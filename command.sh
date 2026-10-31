#!/usr/bin/env bash
set -euo pipefail
BASE=/srv/zero-line-audio/sonniss-2026
mkdir -p "$BASE" "$BASE/mp3" "$BASE/tools"
if ! command -v ffmpeg >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ffmpeg
fi
if [ ! -x "$BASE/tools/venv/bin/gdown" ]; then
  python3 -m venv "$BASE/tools/venv"
  "$BASE/tools/venv/bin/pip" install -q --upgrade pip gdown
fi
cat > "$BASE/convert_all.py" <<'PY'
import pathlib, zipfile, subprocess, shutil, json, time, os
BASE=pathlib.Path("/srv/zero-line-audio/sonniss-2026")
OUT=BASE/"mp3"
STATUS=BASE/"status.json"
GDOWN=BASE/"tools/venv/bin/gdown"
FILES={
1:"1ndDWhCoq0NgkrJH6ku5MSA65zinEby9r",
2:"1s9GAn7KBS4jr4NlF_ggTYDrXySCg6HXS",
3:"16PX5T28pQaEs6S8j-m6ArR16JwQCQNNB",
4:"1HqMHc0o9Uxv5SmR3KQzx2nHIyrn3sW6M",
5:"1XL8zDflfC86Asd4D7G1T5N1DJ6hNLQVc",
}
AUDIO={".wav",".aif",".aiff",".flac",".ogg",".mp3",".m4a",".aac",".wma",".caf"}

def read_status():
    try:return json.loads(STATUS.read_text())
    except:return {}

def write_status(**kw):
    d=read_status(); d.update(kw)
    t=STATUS.with_suffix(".tmp")
    t.write_text(json.dumps(d,ensure_ascii=False,indent=2))
    t.replace(STATUS)

done=set(read_status().get("completed_parts",[]))
converted=int(read_status().get("converted",0))
write_status(state="running",completed_parts=sorted(done),converted=converted,parts_total=5,started_at=read_status().get("started_at") or time.strftime("%Y-%m-%d %H:%M:%S UTC",time.gmtime()))
for part,fid in FILES.items():
    if part in done:
        continue
    free=shutil.disk_usage(BASE).free
    if free < 10_000_000_000:
        write_status(state="insufficient_space",current_part=part,free_bytes=free)
        raise RuntimeError("Less than 10 GB free")
    archive=BASE/f"part-{part}.zip"
    partial=BASE/f"part-{part}.partial"
    partial.unlink(missing_ok=True)
    write_status(state="downloading",current_part=part,free_bytes=free)
    subprocess.run([str(GDOWN),"--id",fid,"-O",str(partial)],check=True)
    if not zipfile.is_zipfile(partial):
        raise RuntimeError(f"Downloaded part {part} is not a ZIP")
    partial.rename(archive)
    write_status(state="converting",current_part=part)
    with zipfile.ZipFile(archive) as z:
        entries=[n for n in z.namelist() if pathlib.PurePosixPath(n).suffix.lower() in AUDIO]
        write_status(files_in_current_part=len(entries))
        for idx,name in enumerate(entries,1):
            p=pathlib.PurePosixPath(name)
            if p.is_absolute() or ".." in p.parts:
                continue
            dest=(OUT/f"part-{part}").joinpath(*p.parts).with_suffix(".mp3")
            if dest.exists() and dest.stat().st_size>0:
                continue
            dest.parent.mkdir(parents=True,exist_ok=True)
            tmp=dest.with_suffix(".tmp.mp3")
            tmp.unlink(missing_ok=True)
            suffix=p.suffix.lower()
            if suffix==".mp3":
                with z.open(name) as src, tmp.open("wb") as dst:
                    shutil.copyfileobj(src,dst)
            else:
                proc=subprocess.Popen([
                    "ffmpeg","-hide_banner","-loglevel","error","-nostdin","-y",
                    "-i","pipe:0","-map","0:a:0","-vn",
                    "-codec:a","libmp3lame","-b:a","192k",str(tmp)
                ],stdin=subprocess.PIPE)
                with z.open(name) as src:
                    try:
                        while True:
                            chunk=src.read(1024*1024)
                            if not chunk: break
                            proc.stdin.write(chunk)
                    except BrokenPipeError:
                        pass
                proc.stdin.close()
                rc=proc.wait()
                if rc:
                    tmp.unlink(missing_ok=True)
                    raise RuntimeError(f"ffmpeg failed: {name}")
            tmp.rename(dest)
            converted+=1
            if converted % 5 == 0:
                write_status(converted=converted,current_file=name,current_index=idx)
    archive.unlink(missing_ok=True)
    done.add(part)
    write_status(completed_parts=sorted(done),converted=converted,state="running")
write_status(state="completed",converted=converted,completed_parts=sorted(done),finished_at=time.strftime("%Y-%m-%d %H:%M:%S UTC",time.gmtime()),free_bytes=shutil.disk_usage(BASE).free)
PY
systemctl stop zeroline-sonniss.service 2>/dev/null || true
systemctl reset-failed zeroline-sonniss.service 2>/dev/null || true
systemd-run --unit=zeroline-sonniss --description="Sonniss 2026 all 5 parts to MP3" --property=WorkingDirectory="$BASE" /usr/bin/python3 "$BASE/convert_all.py"
echo "SERVICE=$(systemctl is-active zeroline-sonniss.service || true)"
echo "STATUS=$BASE/status.json"
echo "OUTPUT=$BASE/mp3"
df -h "$BASE"
