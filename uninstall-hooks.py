#!/usr/bin/env python3
"""Прибирає command-hooks індикатора з ~/.claude/settings.json, лишаючи решту hooks."""
import json
import os

SETTINGS = os.path.expanduser("~/.claude/settings.json")
MARKER = "caps-indicator"

with open(SETTINGS) as f:
    settings = json.load(f)

removed = []
for event, entries in settings.get("hooks", {}).items():
    before = len(entries)
    entries[:] = [
        e for e in entries
        if not any(MARKER in str(h.get("command", "")) for h in e.get("hooks", []))
    ]
    if len(entries) != before:
        removed.append(event)

with open(SETTINGS, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("прибрано з:", ", ".join(removed) or "-")
