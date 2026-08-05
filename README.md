# capslight

The green LED on your Caps Lock key as a live status indicator for Claude Code.

It blinks while Claude is working, goes solid when the task is done, and blinks fast when
Claude is waiting on you. It changes nothing about how your keyboard behaves — Caps Lock
stays off and your typing stays lowercase.

| State | LED | When |
|---|---|---|
| `working` | slow blink (0.7s cycle, short flashes) | Claude is thinking / running tools |
| `waiting` | fast blink (0.22s) | it needs you: permission prompt, question |
| `done` | solid on | task finished |
| `off` | dark | session closed |

## How it works

`bin/capsled` is a small IOKit utility in Swift. It has two ways to light the LED:

1. **`hid`** (default) — writes straight to the keyboard's HID LED element
   (`kHIDPage_LEDs` / `kHIDUsage_LED_CapsLock`). **It does not touch the modifier state**,
   so your typing stays lowercase while the light blinks. That's the whole reason not to
   use the simpler approach below.
2. **`modifier`** — `IOHIDSetModifierLockState`, kept as a fallback. More reliable, but it
   genuinely turns Caps Lock on, so text would jump to CAPS every time the LED flashes.

To see what your hardware supports: `make probe`. On a MacBook's built-in keyboard both
work, with no root and no Input Monitoring permission.

`bin/caps-indicator` is a state machine on top of `capsled`. It owns the background blink
process and its PID, and tracks state **per Claude session** in `~/.claude/capsled/sessions/`.
With several Claude windows open, the LED shows the highest-priority state
(`waiting` > `working` > `done` > `off`) — so one session finishing won't switch off the
indicator for another that's still running.

## Install

All you need is the Xcode Command Line Tools (`swiftc`, `python3`). No other dependencies.

```sh
git clone https://github.com/insolowetrust/capslight.git
cd capslight
./install.sh
```

`install.sh` does the lot: checks prerequisites, builds the binary, probes which backend
your hardware supports, symlinks into `~/.claude/bin/`, wires up the hooks, and finishes
with a visual test of the LED. Pass `--no-test` to skip that last step.

Your existing hooks in `~/.claude/settings.json` are left alone — capslight adds its own
separate entries and the rest of your config stays as it was. A backup is written to
`~/.claude/settings.json.bak-capslight` before the first change. Re-running is safe: it
replaces its own entries rather than duplicating them.

If you prefer make: `make install` does the same thing without the checks and the test.

**The hooks are picked up after you restart your Claude Code session.**

Event mapping:

| Hook | State |
|---|---|
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | `working` |
| `PermissionRequest`, `Notification` | `waiting` |
| `Stop`, `StopFailure` | `done` |
| `SessionEnd` | `off` |

## Checking it

```sh
make test          # walks through every state with pauses — watch your keyboard
make probe         # which backend is available
bin/capsled on     # light it manually
bin/capsled off
bin/caps-indicator reset   # panic button: kill the blinker, turn the LED off
```

If nothing happens, start with `make probe`. If both backends come back `unavailable`,
that keyboard won't hand over its LED (happens on some third-party Bluetooth models).

## Tuning the blink

Via environment variables (you can set these in `~/.claude/settings.json` under `env`):

```
CAPS_WORKING_INTERVAL=0.7   CAPS_WORKING_DUTY=0.35
CAPS_WAITING_INTERVAL=0.22  CAPS_WAITING_DUTY=0.5
```

`DUTY` is the fraction of each cycle the LED stays lit. 0.35 gives short flashes (less
distracting in peripheral vision), 0.5 gives an even blink.

To force a backend: `bin/capsled --backend modifier on`.

## Uninstall

```sh
make uninstall
```

Removes the hooks from `~/.claude/settings.json`, deletes the symlinks and turns the LED
off. Your original settings are still in `~/.claude/settings.json.bak-capslight`.

## Known limitations

- Pressing the real Caps Lock key mid-blink makes the system overwrite the LED state. The
  next flash puts it back, but you may see one beat go out of step.
- If Claude is killed with `kill -9`, `SessionEnd` never fires and the LED stays in its
  last state. Orphaned session records clear themselves after 4 hours; to fix it now, run
  `bin/caps-indicator reset`.
- External keyboards are driven too — the command goes to every HID keyboard at once.

## Author

Max Solo — [t.me/aiukraine_wetrust](https://t.me/aiukraine_wetrust)

MIT. Do whatever you like with it.
