#!/usr/bin/env bash

# ccblocks Trigger Script
# Triggers a new Claude Code block via LaunchAgent (macOS) or systemd (Linux)
# Runs in user session with full authentication access

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Ensure config directory exists
mkdir -p "$CCBLOCKS_CONFIG" 2>/dev/null || true

# Find Claude CLI (prefer PATH, fallback to common locations)
CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
if [ -z "$CLAUDE_BIN" ]; then
	CLAUDE_BIN=$(find "$HOME/.local" -name claude -type f -executable 2>/dev/null | head -1 || true)
fi

if [ -z "$CLAUDE_BIN" ]; then
	print_error "Claude CLI not found"
	echo "Tried:"
	echo "  - PATH ($PATH)"
	echo "  - $HOME/.local/ (recursive search)"
	echo ""
	echo "To install Claude CLI, visit: https://claude.ai"
	log_to_system "Failed to locate Claude CLI"
	exit 1
fi

# Trigger new 5-hour block
timestamp=$(date '+%Y-%m-%d %H:%M:%S')

if run_with_timeout 15 "$CLAUDE_BIN" < <(printf '.') >/dev/null 2>&1; then
	# Save last activity timestamp
	echo "$timestamp" >"$CCBLOCKS_CONFIG/.last-activity" 2>/dev/null || true

	# Log to system
	log_to_system "Successfully triggered new 5-hour block at $timestamp"
	exit 0
else
	# Log failure to system
	log_to_system "Failed to trigger block at $timestamp"
	exit 1
fi
