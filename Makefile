.PHONY: test lint format format-check validate install-deps help

help:
	@echo "ccblocks development targets:"
	@echo ""
	@echo "  make test          - Run all bats tests"
	@echo "  make lint          - Run shellcheck on all scripts"
	@echo "  make format        - Format all scripts with shfmt"
	@echo "  make format-check  - Check formatting without modifying"
	@echo "  make validate      - Run lint + tests (pre-commit validation)"
	@echo "  make install-deps  - Install development dependencies"
	@echo "  make help          - Show this help message"

test:
	bats tests/*.bats

lint:
	@shellcheck ccblocks bin/*.sh lib/*.sh libexec/*.sh dev/*.sh

format:
	@shfmt -w -i 0 ccblocks bin/*.sh lib/*.sh libexec/*.sh dev/*.sh

format-check:
	@shfmt -d -i 0 ccblocks bin/*.sh lib/*.sh libexec/*.sh dev/*.sh

validate: lint test

install-deps:
	@command -v brew >/dev/null 2>&1 || { echo "Error: Homebrew not found. Install from https://brew.sh"; exit 1; }
	brew tap bats-core/bats-core
	brew install bats-core bats-support bats-assert shellcheck shfmt
