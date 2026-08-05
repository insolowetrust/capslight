#!/bin/bash
# capslight — one-shot install:
#   ./install.sh
#
# Builds the binary, symlinks it into ~/.claude/bin, wires up Claude Code hooks
# and runs a visual test of the LED. Safe to re-run.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_BIN="$CLAUDE_DIR/bin"
SETTINGS="$CLAUDE_DIR/settings.json"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

SKIP_TEST=0
[ "${1:-}" = "--no-test" ] && SKIP_TEST=1

bold "capslight"

# 1. Prerequisites ------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "macOS only"
command -v swiftc >/dev/null 2>&1 || die "swiftc not found — install Xcode Command Line Tools: xcode-select --install"
command -v python3 >/dev/null 2>&1 || die "python3 not found (ships with the Command Line Tools)"
ok "swiftc $(swiftc --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | head -1) and python3 present"

# 2. Build --------------------------------------------------------------------
mkdir -p "$REPO/bin"
swiftc -O -o "$REPO/bin/capsled" "$REPO/src/capsled.swift" || die "build failed"
chmod +x "$REPO/bin/capsled" "$REPO/bin/caps-indicator"
ok "built bin/capsled"

# 3. Can this hardware light up at all? ---------------------------------------
probe="$("$REPO/bin/capsled" probe 2>/dev/null || true)"
if printf '%s' "$probe" | grep -q "^hid:.*works"; then
  ok "HID backend available (Caps Lock itself stays off)"
elif printf '%s' "$probe" | grep -q "^modifier:.*works"; then
  warn "only the modifier backend is available — Caps Lock will actually toggle while blinking"
else
  die "no backend works — this keyboard won't hand over its LED"
fi

# 4. Symlinks -----------------------------------------------------------------
mkdir -p "$CLAUDE_BIN"
ln -sf "$REPO/bin/capsled" "$CLAUDE_BIN/capsled"
ln -sf "$REPO/bin/caps-indicator" "$CLAUDE_BIN/caps-indicator"
ok "symlinked into $CLAUDE_BIN"

# 5. Hooks --------------------------------------------------------------------
if [ -f "$SETTINGS" ]; then
  if [ ! -f "$SETTINGS.bak-capslight" ]; then
    cp "$SETTINGS" "$SETTINGS.bak-capslight"
    ok "settings backed up to $SETTINGS.bak-capslight"
  fi
else
  mkdir -p "$CLAUDE_DIR"
  echo '{}' > "$SETTINGS"
  ok "created $SETTINGS"
fi

python3 "$REPO/install-hooks.py" | sed 's/^/  /'
ok "hooks wired up (existing hooks left untouched)"

# 6. Visual check -------------------------------------------------------------
if [ "$SKIP_TEST" -eq 0 ]; then
  echo
  bold "Watch the Caps Lock key:"
  printf '  slow blink — Claude is working '; "$REPO/bin/caps-indicator" working; sleep 4
  printf '\r  fast blink — it needs you      '; "$REPO/bin/caps-indicator" waiting; sleep 3
  printf '\r  solid — task finished          '; "$REPO/bin/caps-indicator" done;    sleep 2
  printf '\r                                 \r'
  "$REPO/bin/caps-indicator" reset
  ok "test done, LED off"
fi

echo
bold "Done."
echo "  Restart your Claude Code session so the hooks are picked up."
echo "  Kill the light:  $CLAUDE_BIN/caps-indicator reset"
echo "  Remove it all:   make uninstall"
