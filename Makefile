BIN := bin/capsled
SRC := src/capsled.swift
CLAUDE_BIN := $(HOME)/.claude/bin

.PHONY: all build install uninstall probe test clean

all: build

build: $(BIN)

$(BIN): $(SRC)
	@mkdir -p bin
	swiftc -O -o $@ $<

# Те саме, що ./install.sh, лише без візуального тесту наприкінці.
install:
	./install.sh --no-test

uninstall:
	python3 uninstall-hooks.py
	rm -f $(CLAUDE_BIN)/capsled $(CLAUDE_BIN)/caps-indicator
	-bin/capsled off

probe: build
	$(BIN) probe

# Візуальна перевірка: 4с блимання «працює», 2с «увага», 2с «готово», гасне.
test: build
	@echo "working (повільне блимання)…" && bin/caps-indicator working && sleep 4
	@echo "waiting (швидке блимання)…"   && bin/caps-indicator waiting && sleep 3
	@echo "done (горить)…"               && bin/caps-indicator done    && sleep 2
	@echo "off"                          && bin/caps-indicator reset

clean:
	rm -rf bin
