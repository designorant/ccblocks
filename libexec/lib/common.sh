#!/usr/bin/env bash

# ccblocks Common Library
# Shared utilities used across all ccblocks scripts

# Colour definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

# Project paths
: "${CCBLOCKS_INSTALL:=${SCRIPT_DIR:-$(pwd)}}"
: "${CCBLOCKS_CONFIG:=${HOME}/.config/ccblocks}"

# Utility helpers
command_exists() {
	command -v "$1" >/dev/null 2>&1
}

# Timeout handling (timeout or gtimeout required)
run_with_timeout() {
	local duration="$1"
	shift

	if command_exists timeout; then
		timeout "$duration" "$@"
	elif command_exists gtimeout; then
		gtimeout "$duration" "$@"
	else
		# No timeout available - run without timeout control
		# This is acceptable for most use cases
		"$@"
	fi
}

# Print functions
print_status() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
	echo -e "${BLUE}${BOLD}$1${NC}"
}

show_logo() {
	echo "░░      ░░░      ░░       ░░  ░░░░░░░      ░░░      ░░  ░░░░  ░░      ░░"
	echo "▒  ▒▒▒▒  ▒  ▒▒▒▒  ▒  ▒▒▒▒  ▒  ▒▒▒▒▒▒  ▒▒▒▒  ▒  ▒▒▒▒  ▒  ▒▒▒  ▒▒  ▒▒▒▒▒▒▒"
	echo "▓  ▓▓▓▓▓▓▓  ▓▓▓▓▓▓▓       ▓▓  ▓▓▓▓▓▓  ▓▓▓▓  ▓  ▓▓▓▓▓▓▓     ▓▓▓▓▓      ▓▓"
	echo "█  ████  █  ████  █  ████  █  ██████  ████  █  ████  █  ███  ████████  █"
	echo "██      ███      ██       ██       ██      ███      ██  ████  ██      ██"
	echo "                                                         by @designorant"
	echo ""
	echo "Time-shift Claude sessions to match your working hours"
}

# Get script directory (must be set by calling script before sourcing this)
# Usage: SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#        source "$SCRIPT_DIR/lib/common.sh"

# Detect OS and set appropriate helper script
detect_os() {
	OS_TYPE="$(uname)"

	if [[ "$OS_TYPE" == "Darwin" ]]; then
		SCHEDULER_NAME="LaunchAgent"
		export OS_TYPE SCHEDULER_NAME
		return 0
	elif [[ "$OS_TYPE" == "Linux" ]]; then
		SCHEDULER_NAME="systemd user service"
		export OS_TYPE SCHEDULER_NAME
		return 0
	else
		print_error "Unsupported OS: $OS_TYPE"
		echo "ccblocks supports macOS (Darwin) and Linux only"
		return 1
	fi
}

# Constants
export BLOCK_DURATION_SECONDS=18000 # 5 hours in seconds

# Logging helpers
log_to_system() {
	local message="$1"
	logger -t ccblocks "$message" 2>/dev/null || true
}

# Get helper script path based on OS
get_helper_script() {
	local script_dir="${1:-}"

	if [[ -z "$script_dir" ]]; then
		print_error "get_helper_script: script_dir parameter required"
		return 1
	fi

	if [[ "$OS_TYPE" == "Darwin" ]]; then
		echo "$script_dir/lib/launchagent-helper.sh"
	elif [[ "$OS_TYPE" == "Linux" ]]; then
		echo "$script_dir/lib/systemd-helper.sh"
	else
		return 1
	fi
}

# Initialize OS-specific variables (sets HELPER, CONFIG_PATH, etc.)
# Usage: init_os_vars "$SCRIPT_DIR"
init_os_vars() {
	local script_dir="${1:-}"

	if [[ -z "$script_dir" ]]; then
		print_error "init_os_vars: script_dir parameter required"
		return 1
	fi

	# Ensure OS is detected
	if [[ -z "$OS_TYPE" ]]; then
		print_error "init_os_vars: OS_TYPE not set. Call detect_os first."
		return 1
	fi

	# Ensure config directory exists
	mkdir -p "$CCBLOCKS_CONFIG" 2>/dev/null || true

	# Set common variables based on OS
	if [[ "$OS_TYPE" == "Darwin" ]]; then
		export HELPER="$script_dir/lib/launchagent-helper.sh"
		export CONFIG_PATH="$HOME/Library/LaunchAgents/ccblocks.plist"
		export LOAD_CMD="load"
		export UNLOAD_CMD="unload"
	elif [[ "$OS_TYPE" == "Linux" ]]; then
		export HELPER="$script_dir/lib/systemd-helper.sh"
		export CONFIG_PATH="$HOME/.config/systemd/user/ccblocks@.service"
		export LOAD_CMD="enable"
		export UNLOAD_CMD="disable"
	else
		return 1
	fi

	return 0
}

# Config file paths
CONFIG_FILE="$CCBLOCKS_CONFIG/config.json"

# Config schema management
read_schedule_config() {
	if [[ ! -f "$CONFIG_FILE" ]]; then
		return 1
	fi

	# Read config using python3 for JSON parsing
	if command_exists python3; then
		python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        config = json.load(f)
        if 'schedule' in config:
            sched = config['schedule']
            print(f"type={sched.get('type', 'preset')}")
            print(f"preset={sched.get('preset', '247')}")
            if 'custom_hours' in sched:
                print(f"custom_hours={','.join(map(str, sched['custom_hours']))}")
            if 'coverage_hours' in sched:
                print(f"coverage_hours={sched['coverage_hours']}")
except Exception as e:
    sys.exit(1)
PY
	else
		print_error "python3 required for config management"
		return 1
	fi
}

write_schedule_config() {
	local schedule_type="$1"
	local preset="${2:-}"
	local custom_hours="${3:-}"

	mkdir -p "$CCBLOCKS_CONFIG" 2>/dev/null || true

	if command_exists python3; then
		python3 - "$CONFIG_FILE" "$schedule_type" "$preset" "$custom_hours" <<'PY'
import json
import sys
from pathlib import Path

config_file = sys.argv[1]
schedule_type = sys.argv[2]
preset = sys.argv[3] if len(sys.argv) > 3 else ""
custom_hours = sys.argv[4] if len(sys.argv) > 4 else ""

config = {}
if Path(config_file).exists():
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
    except:
        config = {}

config['schedule'] = {'type': schedule_type}

if schedule_type == 'preset' and preset:
    config['schedule']['preset'] = preset
elif schedule_type == 'custom' and custom_hours:
    hours = [int(h.strip()) for h in custom_hours.split(',') if h.strip()]
    config['schedule']['custom_hours'] = sorted(hours)
    # Calculate coverage
    coverage = len(hours) * 5
    config['schedule']['coverage_hours'] = coverage

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
PY
	else
		print_error "python3 required for config management"
		return 1
	fi
}

# Validate custom schedule hours
# Returns 0 if valid, 1 if invalid
validate_custom_hours() {
	local hours_str="$1"
	local hours

	# Convert comma-separated string to array
	IFS=',' read -ra hours <<<"$hours_str"

	# Remove whitespace and validate each hour
	local cleaned_hours=()
	for h in "${hours[@]}"; do
		h=$(echo "$h" | tr -d ' ')
		if ! [[ "$h" =~ ^[0-9]+$ ]]; then
			print_error "Invalid hour: '$h' (must be a number)"
			return 1
		fi
		if [[ "$h" -lt 0 || "$h" -gt 23 ]]; then
			print_error "Invalid hour: $h (must be 0-23)"
			return 1
		fi
		cleaned_hours+=("$h")
	done

	# Check minimum triggers
	if [[ ${#cleaned_hours[@]} -lt 2 ]]; then
		print_error "At least 2 triggers required"
		return 1
	fi

	# Check maximum triggers (4 per day for 5-hour blocks)
	if [[ ${#cleaned_hours[@]} -gt 4 ]]; then
		print_error "Maximum 4 triggers allowed (24h ÷ 5h = 4.8)"
		echo "  More triggers don't increase coverage - they overlap existing 5-hour windows"
		return 1
	fi

	# Sort hours (bash 3.2 compatible)
	sorted_hours=()
	while IFS= read -r hour; do
		sorted_hours+=("$hour")
	done < <(printf '%s\n' "${cleaned_hours[@]}" | sort -n)

	# Check for duplicates
	for ((i = 0; i < ${#sorted_hours[@]} - 1; i++)); do
		if [[ "${sorted_hours[$i]}" -eq "${sorted_hours[$((i + 1))]}" ]]; then
			print_error "Duplicate hour: ${sorted_hours[$i]}"
			return 1
		fi
	done

	# Check minimum 5-hour spacing
	for ((i = 0; i < ${#sorted_hours[@]} - 1; i++)); do
		local current="${sorted_hours[$i]}"
		local next="${sorted_hours[$((i + 1))]}"
		local spacing=$((next - current))

		if [[ $spacing -lt 5 ]]; then
			print_error "Insufficient spacing: ${current}:00 to ${next}:00 is only ${spacing}h (minimum 5h required)"
			echo "  Claude blocks are 5 hours long - triggers must be ≥5h apart"
			return 1
		fi
	done

	# Check wraparound (last to first)
	local first="${sorted_hours[0]}"
	local last="${sorted_hours[$((${#sorted_hours[@]} - 1))]}"
	local wraparound_spacing=$((24 - last + first))

	if [[ $wraparound_spacing -lt 5 ]]; then
		print_error "Insufficient spacing: ${last}:00 to ${first}:00 (next day) is only ${wraparound_spacing}h (minimum 5h required)"
		echo "  Claude blocks are 5 hours long - triggers must be ≥5h apart"
		return 1
	fi

	return 0
}

# Calculate coverage hours and gaps
calculate_coverage() {
	local hours_str="$1"

	IFS=',' read -ra hours <<<"$hours_str"
	local coverage=$((${#hours[@]} * 5))
	local gaps=$((24 - coverage))

	echo "coverage=$coverage"
	echo "gaps=$gaps"
}

# Export functions so they can be used in subshells if needed
export -f print_status print_error print_warning print_header show_logo run_with_timeout log_to_system command_exists
export -f read_schedule_config write_schedule_config validate_custom_hours calculate_coverage
