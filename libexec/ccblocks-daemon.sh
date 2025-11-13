#!/usr/bin/env bash

# ccblocks Trigger Script
# Triggers a new Claude Code block via LaunchAgent (macOS) or systemd (Linux)
# Runs in user session with full authentication access

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Ensure config directory exists
mkdir -p "$CCBLOCKS_CONFIG" 2>/dev/null || true

# No runtime PATH bootstrap. The scheduler injects PATH at start time.

# Find Claude CLI (prefer PATH, then common install locations)
# Support test mode to simulate Claude not found
if [ "${CCBLOCKS_TEST_NO_CLAUDE:-0}" -eq 1 ]; then
	CLAUDE_BIN=""
else
	CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
	if [ -z "$CLAUDE_BIN" ]; then
		for candidate in \
			"$HOME/.local/share/mise/shims/claude" \
			"/opt/homebrew/bin/claude" \
			"/usr/local/bin/claude" \
			"/home/linuxbrew/.linuxbrew/bin/claude"; do
			if [ -x "$candidate" ]; then
				CLAUDE_BIN="$candidate"
				break
			fi
		done
	fi

	# Last-resort recursive search under ~/.local (may be a shim)
	if [ -z "$CLAUDE_BIN" ]; then
		CLAUDE_BIN=$(find "$HOME/.local" -name claude -type f -executable 2>/dev/null | head -1 || true)
	fi
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

# Run claude: default silences stdout but preserves stderr so errors land in logs.
# Set CCBLOCKS_DEBUG=1 to keep stdout as well.
if [ "${CCBLOCKS_DEBUG:-0}" -ne 0 ]; then
	echo "." | run_with_timeout 15 "$CLAUDE_BIN"
	rc=$?
else
	echo "." | run_with_timeout 15 "$CLAUDE_BIN" >/dev/null
	rc=$?
fi

if [ $rc -eq 0 ]; then
	# Optional verification using ccusage if available
	verify_fail=0
	if command_exists ccusage; then
		# Give Claude a brief moment to update backend state
		sleep 1
		usage_out="$(ccusage 2>/dev/null || true)"

		# Trim whitespace for more robust matching
		usage_out_trimmed="$(echo "$usage_out" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

		# Debug logging when CCBLOCKS_DEBUG=1
		if [ "${CCBLOCKS_DEBUG:-0}" -ne 0 ]; then
			echo "[DEBUG] ccusage output: '$usage_out_trimmed'"
		fi

		# Check for empty output
		if [ -z "$usage_out_trimmed" ]; then
			verify_fail=0
			print_warning "Trigger verification inconclusive (ccusage returned empty output)"
			if [ "${CCBLOCKS_DEBUG:-0}" -ne 0 ]; then
				echo "[DEBUG] Empty output may indicate ccusage command succeeded but no data available"
			fi
		# Check for failure indicators
		elif echo "$usage_out_trimmed" | grep -qiE "No active blocks|Session expired|No active session"; then
			verify_fail=1
		# Check for success indicators (more flexible patterns)
		elif echo "$usage_out_trimmed" | grep -qiE "Time remaining|Current session|Block [0-9]+ \(Current\)|[0-9]+h [0-9]+m|Active block"; then
			verify_fail=0
		else
			# Unknown output; do not fail hard, just warn with details
			verify_fail=0
			print_warning "Trigger verification inconclusive (ccusage output unrecognised)"
			if [ "${CCBLOCKS_DEBUG:-0}" -ne 0 ]; then
				echo "[DEBUG] Unrecognised output: '$usage_out_trimmed'"
			else
				# In non-debug mode, log to system for troubleshooting
				log_to_system "ccusage verification inconclusive. Output: ${usage_out_trimmed:0:100}"
			fi
		fi
	else
		print_warning "ccusage not found; skipping trigger verification"
	fi

	if [ "$verify_fail" -eq 1 ]; then
		log_to_system "Trigger completed but no active block detected"
		if [ "${CCBLOCKS_STRICT_VERIFY:-0}" -ne 0 ]; then
			exit 1
		fi
	fi

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
