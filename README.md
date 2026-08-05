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

https://github.com/user-attachments/assets/49936cdf-c3d8-4f2c-9f6a-aa5b0cba6fc5

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
| `PermissionRequest` | `waiting` |
| `Notification` | `waiting` or `done`, depending on the message |
| `Stop`, `StopFailure` | `done` |
| `SessionEnd` | `off` |

`Notification` needs the extra step because Claude Code uses it for two unrelated things:
a real permission prompt, and the idle "waiting for your input" that fires shortly after
`Stop`. Mapping it straight to `waiting` meant the LED started blinking fast every time
Claude finished a task and sat idle — so the handler reads the message and only treats
permission prompts as "needs you".

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

If the LED lights up but shows the *wrong* thing, turn on the breadcrumb log and watch
what the hooks actually send:

```sh
touch ~/.claude/capsled/debug          # start logging
tail -f ~/.claude/capsled/debug.log    # one line per hook: argument, event, payload
rm ~/.claude/capsled/debug             # stop (the log file stays until you delete it)
```

`CAPSLIGHT_DEBUG=1` does the same for a single run.

## Tuning the blink

Via environment variables (you can set these in `~/.claude/settings.json` under `env`):

```
CAPS_WORKING_INTERVAL=0.7   CAPS_WORKING_DUTY=0.35
CAPS_WAITING_INTERVAL=0.22  CAPS_WAITING_DUTY=0.5
CAPS_BLINK_MAX_SECONDS=900  CAPS_SESSION_TTL_MINUTES=30
```

`DUTY` is the fraction of each cycle the LED stays lit. 0.35 gives short flashes (less
distracting in peripheral vision), 0.5 gives an even blink.

To force a backend: `bin/capsled --backend modifier on`.

## Turning it off

Sometimes you don't want a blinking keyboard — a screen recording, a meeting, a demo.
No need to uninstall:

```sh
caps-indicator disable   # LED goes dark and stays dark
caps-indicator enable    # back to normal on the next hook
caps-indicator status    # muted or active, and the current state
```

The hooks stay wired; they just return immediately and do nothing. The switch is a flag
file at `~/.claude/capsled/disabled`, so it survives restarts and applies to every session
at once. `make disable` / `make enable` / `make status` do the same from the checkout.

To mute a single session instead of all of them, launch Claude with the environment
variable set:

```sh
CAPSLIGHT_DISABLED=1 claude
```

`caps-indicator reset` keeps working while muted — it's the way out if the LED ever gets
stuck.

## Uninstall

```sh
make uninstall
```

Turns the LED off, removes the hooks from `~/.claude/settings.json`, deletes the symlinks
and clears the state directory. Your original settings are still in
`~/.claude/settings.json.bak-capslight`.

### What it touches

Worth knowing before you run a script that edits your config:

- `~/.claude/settings.json` — adds one command hook per event listed above, nothing else.
  A pristine copy is kept as `.bak-capslight` before the first change, and writes go
  through a temp file plus atomic rename, so an interrupted run can't truncate your
  settings. If the file isn't valid JSON, the installer says so and changes nothing.
- `~/.claude/bin/` — two symlinks pointing back at this checkout.
- `~/.claude/capsled/` — the blinker's PID, per-session state and the mute flag.

Nothing runs as root, nothing is downloaded, nothing phones home.

## Known limitations

- Pressing the real Caps Lock key mid-blink makes the system overwrite the LED state. The
  next flash puts it back, but you may see one beat go out of step.
- If Claude is killed with `kill -9`, `SessionEnd` never fires. Two dead-man's switches
  cover that: the blinker gives up after 15 minutes without anyone refreshing it, and a
  session record is dropped after 30 minutes of silence. A live session touches its record
  on every hook, so neither fires in normal use. To clear it immediately, run
  `bin/caps-indicator reset`. Both are tunable via `CAPS_BLINK_MAX_SECONDS` and
  `CAPS_SESSION_TTL_MINUTES`.
- External keyboards are driven too — the command goes to every HID keyboard at once.

## Author

Max Solo — [t.me/aiukraine_wetrust](https://t.me/aiukraine_wetrust)

MIT. Do whatever you like with it.
