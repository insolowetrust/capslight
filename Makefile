BIN := bin/capsled
SRC := src/capsled.swift
CLAUDE_BIN := $(HOME)/.claude/bin

.PHONY: all build install uninstall probe test clean disable enable status

all: build

build: $(BIN)

$(BIN): $(SRC)
	@mkdir -p bin
	swiftc -O -o $@ $<

# Same as ./install.sh, minus the visual test at the end.
install:
	./install.sh --no-test

uninstall:
	-bin/caps-indicator reset
	python3 uninstall-hooks.py
	rm -f $(CLAUDE_BIN)/capsled $(CLAUDE_BIN)/caps-indicator
	rm -rf $(HOME)/.claude/capsled

probe: build
	$(BIN) probe

# Mute without uninstalling — the hooks stay wired and simply do nothing.
disable:
	bin/caps-indicator disable

enable:
	bin/caps-indicator enable

status:
	@bin/caps-indicator status

# Visual check: 4s "working" blink, 3s "waiting" blink, 2s solid, then off.
test: build
	@echo "working (slow blink)…" && bin/caps-indicator working && sleep 4
	@echo "waiting (fast blink)…" && bin/caps-indicator waiting && sleep 3
	@echo "done (solid)…"         && bin/caps-indicator done    && sleep 2
	@echo "off"                   && bin/caps-indicator reset

clean:
	rm -rf bin
