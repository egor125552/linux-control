#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/orca-51/lib/python3/dist-packages/orca
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=/root/orca51-backup-$STAMP
mkdir -p "$BACKUP"
cp -a "$BASE/event_manager.py" "$BACKUP/"
cp -a "$BASE/script_manager.py" "$BACKUP/"

python3 - <<'PY'
from pathlib import Path

base = Path('/opt/orca-51/lib/python3/dist-packages/orca')

# 1. Event spam filtering is on a frequent path. Compute time and app hash once.
p = base / 'event_manager.py'
s = p.read_text()
old = '''        event_type = event.type
        last_app, last_time = self._event_history.get(event_type, (None, 0))
        app = AXUtilities.get_application(event.source)
        ignore = last_app == hash(app) and time.time() - last_time < 0.1
        self._event_history[event_type] = hash(app), time.time()
'''
new = '''        event_type = event.type
        last_app, last_time = self._event_history.get(event_type, (None, 0))
        app = AXUtilities.get_application(event.source)
        app_hash = hash(app)
        now = time.monotonic()
        ignore = last_app == app_hash and now - last_time < 0.1
        self._event_history[event_type] = app_hash, now
'''
if old not in s:
    raise SystemExit('event_manager.py expected block not found; refusing blind patch')
p.write_text(s.replace(old, new, 1))

# 2. Script-name/toolkit maps are immutable. Do not rebuild temporary dict/list objects per lookup.
p = base / 'script_manager.py'
s = p.read_text()
class_marker = '''class ScriptManager:
    """Manages Orca's scripts."""
'''
class_repl = '''class ScriptManager:
    """Manages Orca's scripts."""

    _APP_NAME_MAP = {
        "gtk-window-decorator": "switcher",
        "marco": "switcher",
        "mate-notification-daemon": "notification-daemon",
        "metacity": "switcher",
        "budgie-daemon": "switcher",
        "xfce4-notifyd": "notification-daemon",
    }
    _APP_NAME_MAP_CASEFOLD = {key.casefold(): value for key, value in _APP_NAME_MAP.items()}
    _TOOLKIT_NAME_MAP = {"GTK": "gtk", "GAIL": "gtk", "WPEWebKit": "WebKitGTK"}
'''
if class_marker not in s:
    raise SystemExit('script_manager.py class marker not found; refusing blind patch')
s = s.replace(class_marker, class_repl, 1)
old = '''        app_names = {
            "gtk-window-decorator": "switcher",
            "marco": "switcher",
            "mate-notification-daemon": "notification-daemon",
            "metacity": "switcher",
            "budgie-daemon": "switcher",
            "xfce4-notifyd": "notification-daemon",
        }
        alt_names = list(app_names.keys())
        if name.endswith((".py", ".bin")):
            name = name.split(".")[0]
        elif name.startswith(("org.", "com.")):
            name = name.split(".")[-1]

        names = [n for n in alt_names if n.lower() == name.lower()]
        if names:
            name = app_names.get(names[0], "")
        else:
            for name_list in (apps.__all__, toolkits.__all__):
                names = [n for n in name_list if n.lower() == name.lower()]
                if names:
                    name = names[0]
                    break
'''
new = '''        if name.endswith((".py", ".bin")):
            name = name.split(".")[0]
        elif name.startswith(("org.", "com.")):
            name = name.split(".")[-1]

        folded_name = name.casefold()
        mapped_name = self._APP_NAME_MAP_CASEFOLD.get(folded_name)
        if mapped_name:
            name = mapped_name
        else:
            for name_list in (apps.__all__, toolkits.__all__):
                match = next((candidate for candidate in name_list if candidate.casefold() == folded_name), None)
                if match:
                    name = match
                    break
'''
if old not in s:
    raise SystemExit('script_manager.py name mapping block not found; refusing blind patch')
s = s.replace(old, new, 1)
old2 = '''        names = {"GTK": "gtk", "GAIL": "gtk", "WPEWebKit": "WebKitGTK"}
        name = AXObject.get_attribute(obj, "toolkit")
        return names.get(name, name)
'''
new2 = '''        name = AXObject.get_attribute(obj, "toolkit")
        return self._TOOLKIT_NAME_MAP.get(name, name)
'''
if old2 not in s:
    raise SystemExit('script_manager.py toolkit mapping block not found; refusing blind patch')
s = s.replace(old2, new2, 1)
p.write_text(s)
PY

echo '===== DIFF ====='
diff -u "$BACKUP/event_manager.py" "$BASE/event_manager.py" || true
diff -u "$BACKUP/script_manager.py" "$BASE/script_manager.py" || true

echo '===== SYNTAX ====='
python3 -m py_compile "$BASE/event_manager.py" "$BASE/script_manager.py"
python3 -m compileall -q "$BASE"
echo 'compile: OK'

echo '===== RESTART ORCA DESKTOP ====='
systemctl restart egor-desktop.service
sleep 4
systemctl is-active egor-desktop.service

echo '===== ORCA AFTER RESTART ====='
pid=$(pgrep -n -x orca || true)
if [ -z "$pid" ]; then
  echo 'ERROR: Orca process did not return' >&2
  systemctl status egor-desktop.service --no-pager -l || true
  exit 3
fi
ps -p "$pid" -o pid,ppid,user,%cpu,%mem,rss,vsz,nlwp,etime,cmd

echo '===== AUDIO REMOTE ====='
systemctl is-active audio-remote.service

echo '===== BACKUP ====='
echo "$BACKUP"
