#!/usr/bin/env python3
"""Add the capslight command hooks to ~/.claude/settings.json, leaving existing hooks alone."""
import json
import os
import shutil
import sys
import tempfile

SETTINGS = os.path.expanduser("~/.claude/settings.json")
BACKUP = SETTINGS + ".bak-capslight"
CMD = os.path.expanduser("~/.claude/bin/caps-indicator")
MARKER = "caps-indicator"

MAPPING = {
    "UserPromptSubmit": "working",
    "PreToolUse": "working",
    "PostToolUse": "working",
    "PermissionRequest": "waiting",
    "Notification": "waiting",
    "Stop": "done",
    "StopFailure": "done",
    "SessionEnd": "off",
}


def die(msg):
    print(f"install-hooks: {msg}", file=sys.stderr)
    sys.exit(1)


def load_settings():
    if not os.path.exists(SETTINGS):
        return {}
    try:
        with open(SETTINGS) as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        die(
            f"{SETTINGS} is not valid JSON (line {e.lineno}, column {e.colno}: {e.msg}).\n"
            "            Nothing was changed. Fix the file and re-run."
        )
    except OSError as e:
        die(f"cannot read {SETTINGS}: {e}")


def save_settings(settings):
    """Write via a temp file in the same directory, then rename — so an interrupted run
    can never leave the user with a truncated settings.json."""
    directory = os.path.dirname(SETTINGS)
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".settings-capslight-")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, SETTINGS)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


settings = load_settings()

# Keep one pristine copy of whatever was here before capslight ever touched it.
if os.path.exists(SETTINGS) and not os.path.exists(BACKUP):
    shutil.copy2(SETTINGS, BACKUP)

hooks = settings.setdefault("hooks", {})
if not isinstance(hooks, dict):
    die('"hooks" in settings.json is not an object — refusing to touch it')

added, refreshed = [], []
for event, state in MAPPING.items():
    entries = hooks.setdefault(event, [])
    if not isinstance(entries, list):
        die(f'hooks["{event}"] is not a list — refusing to touch it')

    # drop earlier copies of our hook, so re-running stays idempotent
    before = len(entries)
    entries[:] = [
        e for e in entries
        if not any(MARKER in str(h.get("command", "")) for h in e.get("hooks", []))
    ]
    (refreshed if len(entries) != before else added).append(event)

    entries.append({
        "hooks": [{
            "type": "command",
            "command": f'"{CMD}" {state}',
            "timeout": 5,
        }]
    })

save_settings(settings)

print("added:  ", ", ".join(added) or "-")
print("updated:", ", ".join(refreshed) or "-")
