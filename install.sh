#!/bin/bash
# capslight — встановлення одним рухом:
#   ./install.sh
#
# Збирає бінарник, ставить симлінки в ~/.claude/bin, підключає hooks Claude Code
# і проганяє візуальний тест лампочки. Безпечно запускати повторно.

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

# 1. Передумови ---------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "працює лише на macOS"
command -v swiftc >/dev/null 2>&1 || die "не знайдено swiftc — постав Xcode Command Line Tools: xcode-select --install"
command -v python3 >/dev/null 2>&1 || die "не знайдено python3 (йде з Command Line Tools)"
ok "swiftc $(swiftc --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | head -1), python3 на місці"

# 2. Збірка -------------------------------------------------------------------
mkdir -p "$REPO/bin"
swiftc -O -o "$REPO/bin/capsled" "$REPO/src/capsled.swift" || die "збірка не вдалася"
chmod +x "$REPO/bin/capsled" "$REPO/bin/caps-indicator"
ok "зібрано bin/capsled"

# 3. Чи вміє це залізо взагалі світити ----------------------------------------
probe="$("$REPO/bin/capsled" probe 2>/dev/null || true)"
if printf '%s' "$probe" | grep -q "hid:      працює"; then
  ok "HID-backend доступний (Caps Lock не вмикатиметься)"
elif printf '%s' "$probe" | grep -q "modifier: працює"; then
  warn "доступний лише modifier-backend — під час блимання Caps Lock реально вмикається"
else
  die "жоден backend не працює — клавіатура не віддає керування LED"
fi

# 4. Симлінки -----------------------------------------------------------------
mkdir -p "$CLAUDE_BIN"
ln -sf "$REPO/bin/capsled" "$CLAUDE_BIN/capsled"
ln -sf "$REPO/bin/caps-indicator" "$CLAUDE_BIN/caps-indicator"
ok "симлінки в $CLAUDE_BIN"

# 5. Hooks --------------------------------------------------------------------
if [ -f "$SETTINGS" ]; then
  if [ ! -f "$SETTINGS.bak-capslight" ]; then
    cp "$SETTINGS" "$SETTINGS.bak-capslight"
    ok "бекап налаштувань: $SETTINGS.bak-capslight"
  fi
else
  mkdir -p "$CLAUDE_DIR"
  echo '{}' > "$SETTINGS"
  ok "створено $SETTINGS"
fi

python3 "$REPO/install-hooks.py" | sed 's/^/  /'
ok "hooks підключено (наявні hooks не змінені)"

# 6. Візуальна перевірка ------------------------------------------------------
if [ "$SKIP_TEST" -eq 0 ]; then
  echo
  bold "Дивись на клавішу Caps Lock:"
  printf '  повільне блимання — Claude працює '; "$REPO/bin/caps-indicator" working; sleep 4
  printf '\r  швидке блимання — чекає на тебе    '; "$REPO/bin/caps-indicator" waiting; sleep 3
  printf '\r  горить рівно — таску виконано      '; "$REPO/bin/caps-indicator" done;    sleep 2
  printf '\r                                     \r'
  "$REPO/bin/caps-indicator" reset
  ok "тест завершено, лампочку погашено"
fi

echo
bold "Готово."
echo "  Перезапусти сесію Claude Code, щоб hooks підхопились."
echo "  Аварійно погасити: $CLAUDE_BIN/caps-indicator reset"
echo "  Прибрати геть:     make uninstall"
