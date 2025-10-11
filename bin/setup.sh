#!/usr/bin/env bash

# ccblocks Setup Script
# Cross-platform installation using LaunchAgent (macOS) or systemd (Linux)

set -euo pipefail
set -E

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

handle_setup_error() {
	local exit_code=$?
	local failed_command=${BASH_COMMAND:-unknown}

	trap - ERR

	print_error "Setup exited early while running: ${failed_command}"
	print_warning "Common fixes: ensure the Claude CLI is installed, logged in, and reachable."

	exit "$exit_code"
}

trap 'handle_setup_error' ERR

# Detect OS and initialise OS-specific variables
detect_os || exit 1
init_os_vars "$SCRIPT_DIR/.." || exit 1

# Check if Claude CLI is available
check_claude_cli() {
	if ! command_exists claude; then
		print_error "Claude CLI not found. Please install Claude Code first:"
		echo "  Visit: https://claude.ai/code"
		exit 1
	fi

	print_status "Claude CLI found: $(command -v claude)"

	# Test Claude CLI (quick test)
	local test_output=""
	# Use echo with a single dot instead of printf "test" for better compatibility
	# The Claude CLI may hang with certain input methods, so we use a simple dot
	if ! test_output=$(echo "." | run_with_timeout 15 claude 2>&1); then
		if echo "$test_output" | grep -qi "session limit reached"; then
			print_warning "Claude CLI responded with a session limit message. Setup will continue, but scheduled triggers will wait until the limit resets."
		else
			print_error "Claude CLI test failed. Please ensure you're authenticated:"
			echo "  The CLI might not be properly logged in"
			echo "  Try running claude manually first"
			echo "  Captured output:"
			while IFS= read -r line || [[ -n $line ]]; do
				echo "    $line"
			done <<<"$test_output"
			exit 1
		fi
	else
		print_status "Claude CLI test successful"
	fi
}

# Warn about potential block usage
check_current_block() {
	print_warning "Note: Running ccblocks will trigger Claude to start new blocks"
	echo "  If you currently have an active block with remaining time,"
	echo "  you may want to wait until it expires before setting up ccblocks."
	echo ""
}

# Show schedule options
show_schedule_options() {
	echo ""
	print_header "Choose Your Schedule"
	echo ""
	echo "1. 24/7 Maximum Coverage (Recommended)"
	echo "   Triggers: 12 AM, 6 AM, 12 PM, 6 PM daily"
	echo "   Coverage: ~20 hours/day with strategic gaps"
	echo "   Best for: Heavy users, flexible schedules"
	echo ""
	echo "2. Work Hours Only"
	echo "   Triggers: 9 AM, 2 PM on weekdays"
	echo "   Coverage: 9 AM - 7 PM weekdays"
	echo "   Best for: Standard work schedules"
	echo ""
	echo "3. Night Owl"
	echo "   Triggers: 6 PM, 11 PM daily"
	echo "   Coverage: 6 PM - 4 AM"
	echo "   Best for: Evening/night coders"
	echo ""
}

# Get schedule choice
get_schedule_choice() {
	while true; do
		read -r -p "Select schedule [1-3] (default: 1): " choice
		# Default to option 1 if empty
		[[ -z "$choice" ]] && choice=1
		case $choice in
		1)
			SCHEDULE="247"
			SCHEDULE_NAME="24/7 Maximum Coverage"
			break
			;;
		2)
			SCHEDULE="work"
			SCHEDULE_NAME="Work Hours Only"
			break
			;;
		3)
			SCHEDULE="night"
			SCHEDULE_NAME="Night Owl"
			break
			;;
		*)
			echo "Please choose 1, 2, or 3"
			;;
		esac
	done

	print_status "Selected: $SCHEDULE_NAME"
}

# Install scheduler (LaunchAgent or systemd)
install_scheduler() {
	# shellcheck disable=SC2153  # SCHEDULER_NAME is set by detect_os() in common.sh
	print_status "Installing $SCHEDULER_NAME..."

	# Create scheduler config using helper
	if ! "$HELPER" create "$SCHEDULE"; then
		print_error "Failed to create $SCHEDULER_NAME"
		exit 1
	fi

	# Load/enable scheduler
	local load_cmd="load"
	[[ "$OS_TYPE" == "Linux" ]] && load_cmd="enable"

	if ! "$HELPER" "$load_cmd"; then
		print_error "Failed to ${load_cmd} $SCHEDULER_NAME"
		exit 1
	fi

	# Persist schedule configuration
	write_schedule_config "preset" "$SCHEDULE" ""

	print_status "$SCHEDULER_NAME installed and active"
}

# Show completion message
show_completion() {
	echo ""
	print_header "[CCBLOCKS] Setup Complete! 🚀"
	echo ""
	print_status "Schedule: $SCHEDULE_NAME"
	print_status "Scheduler: $SCHEDULER_NAME"
	echo ""
	echo "Your Claude blocks will now start automatically at scheduled times!"
	echo "The $SCHEDULER_NAME runs in your user session with full authentication."
	echo ""
	echo "Next Steps:"
	echo "  • Check status: ccblocks status"
	echo "  • Test trigger: ccblocks trigger"
	echo "  • Change schedule: ccblocks schedule list"
	echo ""
	print_status "Setup completed successfully"
}

# Main setup flow
main() {
	print_header "[CCBLOCKS] ccblocks Setup"
	show_logo
	echo ""

	# Pre-flight checks
	check_claude_cli
	check_current_block

	# Interactive setup
	show_schedule_options
	get_schedule_choice

	# Confirm before proceeding
	echo ""
	print_warning "Ready to install $SCHEDULE_NAME schedule"
	read -r -p "Proceed with installation? [Y/n]: " confirm

	# Default to yes if empty, or if user explicitly said no
	if [[ "$confirm" =~ ^[Nn]$ ]]; then
		print_status "Setup cancelled"
		exit 0
	fi

	# Installation
	install_scheduler
	show_completion
}

# Run main function
main "$@"
