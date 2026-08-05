#!/usr/bin/env python3
"""Додає command-hooks індикатора у ~/.claude/settings.json, не чіпаючи наявні http-hooks."""
import json
import os

SETTINGS = os.path.expanduser("~/.claude/settings.json")
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

with open(SETTINGS) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

added, refreshed = [], []
for event, state in MAPPING.items():
    entries = hooks.setdefault(event, [])
    # прибираємо попередні версії нашого hook'а (щоб скрипт був ідемпотентним)
    before = len(entries)
    entries[:] = [
        e for e in entries
        if not any(MARKER in str(h.get("command", "")) for h in e.get("hooks", []))
    ]
    if len(entries) != before:
        refreshed.append(event)
    else:
        added.append(event)

    entries.append({
        "hooks": [{
            "type": "command",
            "command": f'"{CMD}" {state}',
            "timeout": 5,
        }]
    })

with open(SETTINGS, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("додано:", ", ".join(added) or "-")
print("оновлено:", ", ".join(refreshed) or "-")
