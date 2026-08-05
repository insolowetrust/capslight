#!/usr/bin/env python3
"""Strip the capslight command hooks from ~/.claude/settings.json, keeping every other hook."""
import json
import os
import sys
import tempfile

SETTINGS = os.path.expanduser("~/.claude/settings.json")
MARKER = "caps-indicator"

if not os.path.exists(SETTINGS):
    print(f"uninstall-hooks: {SETTINGS} does not exist — nothing to do")
    sys.exit(0)

try:
    with open(SETTINGS) as f:
        settings = json.load(f)
except json.JSONDecodeError as e:
    print(
        f"uninstall-hooks: {SETTINGS} is not valid JSON "
        f"(line {e.lineno}, column {e.colno}: {e.msg}).\n"
        "                 Nothing was changed. Remove the caps-indicator entries by hand.",
        file=sys.stderr,
    )
    sys.exit(1)

removed = []
for event, entries in settings.get("hooks", {}).items():
    if not isinstance(entries, list):
        continue
    before = len(entries)
    entries[:] = [
        e for e in entries
        if not any(MARKER in str(h.get("command", "")) for h in e.get("hooks", []))
    ]
    if len(entries) != before:
        removed.append(event)

# same atomic write as install-hooks.py
directory = os.path.dirname(SETTINGS)
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

print("removed from:", ", ".join(removed) or "-")
