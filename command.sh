#!/usr/bin/env bash
set -euo pipefail
umask 077

BASE=/srv/zero-line-audio/sonniss-2026
mkdir -p "$BASE"
cat > "$BASE/convert.py" <<'PY'
import os, sys, pathlib, urllib.request, zipfile, subprocess, shutil, json, time
base=pathlib.Path("/srv/zero-line-audio/sonniss-2026")
out=base/"mp3"
out.mkdir(parents=True,exist_ok=True)
log=base/"status.json"
def update(**kwargs):
    state={}
    if log.exists():
        try: state=json.loads(log.read_text())
        except Exception: pass
    state.update(kwargs)
    tmp=log.with_suffix(".tmp")
    tmp.write_text(json.dumps(state,ensure_ascii=False,indent=2))
    tmp.replace(log)
total=0
update(state="running",completed_parts=[],converted=0,errors=[])
for part in (1,2,3):
    url=f"https://downloads.sonniss.com/Sonniss.com-GDC2026-GameAudioBundle{part}of5.zip"
    archive=base/f"part-{part}.zip"
    free=shutil.disk_usage(base).free
    if free < 1800000000:
        update(state="insufficient_space",current_part=part,free_bytes=free)
        raise RuntimeError("Too little disk space to safely download next archive")
    update(current_part=part,state="downloading",free_bytes=free)
    if not archive.exists():
        tmp=archive.with_suffix(".partial")
        for attempt in range(4):
            try:
                subprocess.run(["curl","--fail","--location","--retry","3","--connect-timeout","30","--max-filesize","2100000000","--output",str(tmp),url],check=True)
                if not zipfile.is_zipfile(tmp): raise RuntimeError("Invalid ZIP download")
                tmp.rename(archive)
                break
            except Exception:
                if attempt==3: raise
                time.sleep(10*(attempt+1))
    if not zipfile.is_zipfile(archive): raise RuntimeError("Invalid ZIP archive: "+str(archive))
    update(state="converting")
    with zipfile.ZipFile(archive) as z:
        entries=[n for n in z.namelist() if pathlib.PurePosixPath(n).suffix.lower() in (".wav",".aif",".aiff",".flac",".ogg",".mp3")]
        for i,name in enumerate(entries):
            p=pathlib.PurePosixPath(name)
            if p.is_absolute() or ".." in p.parts: continue
            dest=(out/f"part-{part}").joinpath(*p.parts).with_suffix(".mp3")
            if dest.exists() and dest.stat().st_size>0: continue
            dest.parent.mkdir(parents=True,exist_ok=True)
            temp=dest.with_suffix(".working")
            if p.suffix.lower()==".mp3":
                with z.open(name) as src, temp.open("wb") as dst: shutil.copyfileobj(src,dst)
            else:
                proc=subprocess.Popen(["ffmpeg","-hide_banner","-loglevel","error","-nostdin","-y","-i","pipe:0","-map","0:a:0","-vn","-codec:a","libmp3lame","-b:a","192k","-f","mp3",str(temp)],stdin=subprocess.PIPE)
                with z.open(name) as src:
                    try:
                        while chunk:=src.read(262144): proc.stdin.write(chunk)
                    except BrokenPipeError: pass
                proc.stdin.close()
                if proc.wait()!=0:
                    temp.unlink(missing_ok=True)
                    raise RuntimeError("Conversion failed: "+name)
            temp.rename(dest)
            total+=1
            if total%10==0: update(converted=total,last_file=name)
    archive.unlink()
    current=json.loads(log.read_text()).get("completed_parts",[])
    current.append(part)
    update(completed_parts=current,converted=total,state="running")
update(state="completed",converted=total,finished_at=time.strftime("%Y-%m-%d %H:%M:%S UTC",time.gmtime()))
PY
if ! command -v ffmpeg >/dev/null; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ffmpeg
fi
if ! command -v curl >/dev/null; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl
fi
echo "FREE_DISK_BYTES=$(df -B1 --output=avail "$BASE" | tail -1 | tr -d ' ')"
if [ "$(df -B1 --output=avail "$BASE" | tail -1)" -lt 2500000000 ]; then
  echo "INSUFFICIENT_SPACE: Need at least 2.5 GB free; not starting"
  exit 1
fi
if systemctl is-active --quiet zeroline-sonniss.service; then
  echo "ALREADY_RUNNING"
else
  systemd-run --unit=zeroline-sonniss --description="Zero Line Sonniss audio download and MP3 conversion" --property=WorkingDirectory="$BASE" /usr/bin/python3 "$BASE/convert.py"
fi
echo "STATUS_FILE=$BASE/status.json"
echo "OUTPUT_FOLDER=$BASE/mp3"
systemctl is-active zeroline-sonniss.service || true
