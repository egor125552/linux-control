#!/usr/bin/env bash
set -euo pipefail
pid=$(pgrep -u egor -x mate-session | head -1 || true)
[ -n "$pid" ] || { echo NO_MATE_SESSION; exit 1; }
getv(){ tr '\0' '\n' < "/proc/$pid/environ" | sed -n "s/^$1=//p" | head -1; }
DBUS_VAL=$(getv DBUS_SESSION_BUS_ADDRESS)
DISPLAY_VAL=$(getv DISPLAY); [ -n "$DISPLAY_VAL" ] || DISPLAY_VAL=:100
XDG_VAL=$(getv XDG_RUNTIME_DIR); [ -n "$XDG_VAL" ] || XDG_VAL=/run/egor-desktop
RUNENV=(env HOME=/home/egor DISPLAY="$DISPLAY_VAL" XDG_RUNTIME_DIR="$XDG_VAL" DBUS_SESSION_BUS_ADDRESS="$DBUS_VAL")

ext=/home/egor/.local/share/orca/extensions/egor_desktop_accessibility/__init__.py
stamp=$(date +%Y%m%d-%H%M%S)
backup=/root/egor-orca-extension-before-virtual-cursor-$stamp.py
cp -a "$ext" "$backup"

cat >"$ext" <<'PY'
"""VoiceOver-like resilient desktop navigation for Egor's MATE session."""
from __future__ import annotations

import time
import gi
gi.require_version("Atspi", "2.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Atspi, Gdk, GLib

from orca import debug, extension, focus_manager, presentation_manager
from orca.ax_object import AXObject
from .core import is_semantic_speech, normalize_desktop_speech


def _safe(call, default=None):
    try:
        return call()
    except Exception:
        return default


def _name(obj):
    return (_safe(lambda: obj.get_name(), "") or "").strip() if obj is not None else ""


def _description(obj):
    return (_safe(lambda: obj.get_description(), "") or "").strip() if obj is not None else ""


def _role(obj):
    if obj is None:
        return ""
    return (_safe(lambda: Atspi.role_get_name(obj.get_role()), "") or "").strip()


def _label(obj, depth=0):
    if obj is None or depth > 5:
        return ""
    label = _name(obj) or _description(obj)
    if label:
        return label
    count = min(_safe(lambda: obj.get_child_count(), 0) or 0, 12)
    for i in range(count):
        child = _safe(lambda i=i: obj.get_child_at_index(i))
        label = _label(child, depth + 1)
        if label:
            return label
    return ""


def _has_state(obj, state):
    states = _safe(lambda: obj.get_state_set())
    return bool(states is not None and _safe(lambda: states.contains(state), False))


def _object_signature(obj):
    if obj is None:
        return ("none",)
    app = _safe(lambda: obj.get_application())
    return (
        _safe(lambda: app.get_name(), "") or "",
        _role(obj),
        _label(obj),
        _safe(lambda: obj.get_index_in_parent(), -1),
    )


def _desktop_signature():
    manager = focus_manager.get_manager()
    return (_object_signature(manager.get_active_window()), _object_signature(manager.get_locus_of_focus()))


def _find_focused_anywhere(limit=3000):
    desktop = _safe(lambda: Atspi.get_desktop(0))
    if desktop is None:
        return None
    queue = []
    for i in range(min(_safe(lambda: desktop.get_child_count(), 0) or 0, 64)):
        child = _safe(lambda i=i: desktop.get_child_at_index(i))
        if child is not None:
            queue.append(child)
    seen = 0
    while queue and seen < limit:
        obj = queue.pop(0)
        seen += 1
        if _has_state(obj, Atspi.StateType.FOCUSED):
            return obj
        count = min(_safe(lambda: obj.get_child_count(), 0) or 0, 100)
        for i in range(count):
            child = _safe(lambda i=i, obj=obj: obj.get_child_at_index(i))
            if child is not None:
                queue.append(child)
    return None


def _top_level_candidates():
    desktop = _safe(lambda: Atspi.get_desktop(0))
    if desktop is None:
        return []
    out = []
    app_count = min(_safe(lambda: desktop.get_child_count(), 0) or 0, 64)
    for ai in range(app_count):
        app = _safe(lambda ai=ai: desktop.get_child_at_index(ai))
        if app is None:
            continue
        app_name = _name(app)
        for wi in range(min(_safe(lambda: app.get_child_count(), 0) or 0, 64)):
            win = _safe(lambda wi=wi, app=app: app.get_child_at_index(wi))
            if win is None:
                continue
            score = 0
            if _has_state(win, Atspi.StateType.ACTIVE): score += 1000
            if _has_state(win, Atspi.StateType.FOCUSED): score += 900
            if _has_state(win, Atspi.StateType.SHOWING): score += 120
            if _has_state(win, Atspi.StateType.VISIBLE): score += 80
            n = _name(win).lower()
            if app_name == "caja" and "рабоч" in n: score += 60
            if app_name == "mate-panel": score += 40
            out.append((score, app_name, win))
    out.sort(key=lambda x: x[0], reverse=True)
    return out


_SKIP_ROLES = {
    "application", "window", "frame", "panel", "filler", "separator", "scroll pane",
    "layered pane", "viewport", "root pane", "unknown", "tearoff menu item",
}


def _is_semantic_object(obj):
    role = _role(obj)
    label = _name(obj) or _description(obj)
    if not label or role in _SKIP_ROLES:
        return False
    # Hidden descendants are poor virtual-cursor targets. If SHOWING is reported, require it.
    states = _safe(lambda: obj.get_state_set())
    if states is not None:
        showing = _safe(lambda: states.contains(Atspi.StateType.SHOWING), None)
        visible = _safe(lambda: states.contains(Atspi.StateType.VISIBLE), None)
        if showing is False and visible is False:
            return False
    return True


def _flatten_semantic(root, limit=1600):
    if root is None:
        return []
    out = []
    queue = [root]
    seen = 0
    while queue and seen < limit:
        obj = queue.pop(0)
        seen += 1
        if _is_semantic_object(obj):
            out.append(obj)
        count = min(_safe(lambda: obj.get_child_count(), 0) or 0, 120)
        for i in range(count):
            child = _safe(lambda i=i, obj=obj: obj.get_child_at_index(i))
            if child is not None:
                queue.append(child)
    return out


def _best_surface():
    focused = _find_focused_anywhere()
    if focused is not None:
        cur = focused
        last = focused
        for _ in range(12):
            parent = _safe(lambda cur=cur: cur.get_parent())
            if parent is None:
                break
            last = cur
            cur = parent
            if _role(cur) in {"frame", "window"}:
                return cur
        return last
    candidates = _top_level_candidates()
    return candidates[0][2] if candidates else None


class EgorDesktopAccessibility(extension.Extension):
    """Maintains a virtual accessibility cursor when MATE/Xpra loses real focus."""

    GROUP_LABEL = "Доступность рабочего стола Егора"
    DESCRIPTION = "Сохраняет виртуальный курсор и не оставляет Orca без текущего элемента."
    VERSION = "2.0"
    AUTHOR = "OpenAI"

    _DELAY_MS = 170
    _NAV_KEYS = {"Tab", "ISO_Left_Tab", "Left", "Right", "Up", "Down"}

    def __init__(self):
        super().__init__()
        self._device = None
        self._listener = None
        self._enabled = True
        self._serial = 0
        self._last_semantic_speech_time = 0.0
        self._virtual_items = []
        self._virtual_index = -1
        self._virtual_surface_signature = None
        self._virtual_obj = None

    def on_ready(self):
        self._device = Atspi.Device.new_full("org.gnome.Orca.EgorDesktopAccessibility")
        self._device.add_key_watcher(self._on_key_event)
        self._listener = Atspi.EventListener.new(self._on_focus_event)
        self._listener.register("object:state-changed:focused")
        self._listener.register("object:state-changed:active")
        self._listener.register("window:activate")
        debug.print_message(debug.LEVEL_INFO, "EGOR ACCESSIBILITY: VoiceOver-like virtual cursor active.", True)

    def on_enabled(self):
        self._enabled = True

    def on_disabled(self):
        self._enabled = False

    def on_shutdown(self):
        self._enabled = False
        self._device = None

    def on_speech_output(self, output):
        focus = focus_manager.get_manager().get_locus_of_focus()
        app = _safe(lambda: focus.get_application()) if focus is not None else None
        app_name = _safe(lambda: app.get_name(), "") or ""
        text = normalize_desktop_speech(output.text, app_name)
        if is_semantic_speech(text):
            self._last_semantic_speech_time = time.monotonic()
        if text != output.text:
            return extension.SpeechOutputResult.replace(text)
        return None

    def _on_focus_event(self, event):
        if not self._enabled or not getattr(event, "detail1", True):
            return
        source = getattr(event, "source", None)
        if source is None:
            return
        if event.type.startswith("object:state-changed:focused"):
            self._virtual_obj = source
            self._virtual_items = []
            self._virtual_index = -1
            manager = focus_manager.get_manager()
            if manager.get_locus_of_focus() is None:
                manager.set_locus_of_focus(None, source, notify_script=True)
                debug.print_message(debug.LEVEL_INFO, "EGOR ACCESSIBILITY: Adopted real AT-SPI focus.", True)

    def _on_key_event(self, _device, pressed, _keycode, keysym, modifiers, _text):
        if not self._enabled or not pressed:
            return False
        key_name = Gdk.keyval_name(keysym) or ""
        if key_name not in self._NAV_KEYS:
            return False
        self._serial += 1
        serial = self._serial
        before = _desktop_signature()
        key_time = time.monotonic()
        GLib.timeout_add(self._DELAY_MS, self._check_navigation_result, serial, key_name, before, key_time, modifiers)
        return False

    def _rebuild_virtual_items(self):
        surface = _best_surface()
        if surface is None:
            self._virtual_items = []
            self._virtual_index = -1
            return None
        signature = _object_signature(surface)
        items = _flatten_semantic(surface)
        if not items:
            # Last-resort: combine all visible top levels, so there is still something to land on.
            combined = []
            for _score, _app, win in _top_level_candidates()[:6]:
                combined.extend(_flatten_semantic(win, 700))
            items = combined
        self._virtual_items = items
        self._virtual_surface_signature = signature
        self._virtual_index = -1
        if self._virtual_obj is not None:
            for i, item in enumerate(items):
                if item == self._virtual_obj:
                    self._virtual_index = i
                    break
        return surface

    def _move_virtual_cursor(self, key_name, modifiers):
        if not self._virtual_items:
            self._rebuild_virtual_items()
        if not self._virtual_items:
            return False

        backwards = key_name in {"ISO_Left_Tab", "Left", "Up"}
        # Shift+Tab sometimes arrives as Tab with the shift modifier rather than ISO_Left_Tab.
        try:
            if key_name == "Tab" and modifiers & int(Gdk.ModifierType.SHIFT_MASK):
                backwards = True
        except Exception:
            pass

        if self._virtual_index < 0:
            self._virtual_index = len(self._virtual_items) - 1 if backwards else 0
        else:
            step = -1 if backwards else 1
            self._virtual_index = max(0, min(len(self._virtual_items) - 1, self._virtual_index + step))

        obj = self._virtual_items[self._virtual_index]
        self._virtual_obj = obj
        manager = focus_manager.get_manager()
        manager.set_locus_of_focus(None, obj, notify_script=False)

        label = _name(obj) or _description(obj) or _label(obj)
        role = _role(obj)
        if label:
            message = f"{label}, {role}" if role else label
            presentation_manager.get_manager().speak_message(message)
            self._last_semantic_speech_time = time.monotonic()
            debug.print_message(
                debug.LEVEL_INFO,
                f"EGOR ACCESSIBILITY: Virtual cursor -> {label!r} ({role}).",
                True,
            )
            return True
        return False

    def _repair_missing_focus(self):
        manager = focus_manager.get_manager()
        real = _find_focused_anywhere()
        if real is not None:
            manager.set_locus_of_focus(None, real, notify_script=True)
            self._virtual_obj = real
            return True
        return False

    def _check_navigation_result(self, serial, key_name, before, key_time, modifiers):
        if not self._enabled or serial != self._serial:
            return GLib.SOURCE_REMOVE
        after = _desktop_signature()
        manager = focus_manager.get_manager()
        focus = manager.get_locus_of_focus()
        active = manager.get_active_window()

        # Native navigation worked. Remember its object and leave it alone.
        if after != before and focus is not None:
            self._virtual_obj = focus
            self._virtual_items = []
            self._virtual_index = -1
            return GLib.SOURCE_REMOVE

        # If a real AT-SPI focus exists but Orca lost it, adopt it first.
        if focus is None and self._repair_missing_focus():
            return GLib.SOURCE_REMOVE

        # MATE/Xpra can expose no active window and no focused object at all.
        # Instead of saying "пусто", move an independent virtual cursor over
        # meaningful visible AT-SPI objects, similar in spirit to VoiceOver's cursor.
        if focus is None or active is None or after == before:
            self._move_virtual_cursor(key_name, modifiers)

        return GLib.SOURCE_REMOVE
PY

chown egor:egor "$ext"
chmod 0644 "$ext"
python3 -m py_compile "$ext"

echo '===== RESTART ONLY ORCA ====='
old=$(pgrep -u egor -x orca || true)
[ -z "$old" ] || kill $old || true
sleep 0.5
sudo -u egor "${RUNENV[@]}" bash -c '
  export RUNNER_TRACKING_ID=
  mkdir -p "$HOME/.local/state/orca"
  setsid -f /usr/local/bin/orca-egor-launcher >"$HOME/.local/state/orca/manual-restart.log" 2>&1
'
for i in $(seq 1 40); do
  pgrep -u egor -x orca >/dev/null 2>&1 && break
  sleep 0.25
done

if ! pgrep -u egor -x orca >/dev/null 2>&1; then
  echo ORCA_RESTART_FAILED
  cp -a "$backup" "$ext"
  python3 -m py_compile "$ext"
  exit 1
fi
sleep 1

echo '===== VERIFY ====='
pgrep -a -u egor -x orca
grep -nE 'VoiceOver-like|Virtual cursor|пусто' "$ext" || true
tail -n 80 /home/egor/.local/state/orca/orca-debug.log | grep -E 'EGOR ACCESSIBILITY|Traceback|ERROR|CRITICAL' || true

echo "BACKUP=$backup"
echo ORCA_VIRTUAL_CURSOR_INSTALLED=yes
