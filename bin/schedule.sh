#!/usr/bin/env bash

# ccblocks Schedule Management
# Manage scheduling patterns for block triggers

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Initialize OS-specific variables
detect_os || exit 1
init_os_vars "$SCRIPT_DIR/.." || exit 1

# Show available schedules
list_schedules() {
	echo "Available Schedules"
	echo "==================="
	echo ""
	echo "247 - Maximum Coverage (24/7)"
	echo "  Triggers: 12 AM, 6 AM, 12 PM, 6 PM daily (4 triggers)"
	echo "  Coverage: 20 hours/day (optimal)"
	echo "  Gaps: 5-6 AM, 11 AM-12 PM, 5-6 PM, 11 PM-12 AM"
	echo ""
	echo "work - Work Hours Only"
	echo "  Triggers: 9 AM, 2 PM on weekdays (2 triggers)"
	echo "  Coverage: 10 hours/day (9 AM - 7 PM)"
	echo "  Gaps: 7 PM - 9 AM, all weekend"
	echo ""
	echo "night - Night Owl"
	echo "  Triggers: 6 PM, 11 PM daily (2 triggers)"
	echo "  Coverage: 10 hours/day (6 PM - 4 AM)"
	echo "  Gaps: 4 AM - 6 PM"
	echo ""
	echo "custom - Custom Schedule"
	echo "  Interactive: ccblocks schedule apply custom"
	echo "  Direct: ccblocks schedule apply custom 0,8,16"
	echo ""
}

# Show current schedule
show_current() {
	"$HELPER" status
}

# Apply a schedule
apply_schedule() {
	local schedule="${1:-}"

	if [ -z "$schedule" ]; then
		print_error "Please specify a schedule name"
		echo ""
		echo "Usage: ccblocks schedule apply <name> [hours]"
		echo ""
		echo "Available schedules: 247, work, night, custom"
		echo ""
		echo "Examples:"
		echo "  ccblocks schedule apply 247           # Apply 24/7 preset"
		echo "  ccblocks schedule apply work          # Apply work hours"
		echo "  ccblocks schedule apply custom        # Interactive custom"
		echo "  ccblocks schedule apply custom 0,8,16 # Custom with hours"
		return 1
	fi

	# Handle custom schedules
	if [ "$schedule" = "custom" ]; then
		local hours="${2:-}"

		if [ -z "$hours" ]; then
			# Interactive mode
			echo "Custom Schedule Setup"
			echo "====================="
			echo ""
			echo "Enter trigger hours (0-23), separated by commas."
			echo "Example: 0,6,12,18 for four triggers at midnight, 6 AM, noon, and 6 PM"
			echo ""
			read -r -p "Hours: " hours
		fi

		# Validate and apply custom hours
		if [ -z "$hours" ]; then
			print_error "No hours specified"
			return 1
		fi

		# Validate hours format and values
		if ! validate_custom_hours "$hours"; then
			return 1
		fi

		# Apply validated custom schedule
		"$HELPER" create_custom "$hours"
		"$HELPER" reload

		# Persist schedule configuration
		write_schedule_config "custom" "" "$hours"

		print_status "Applied custom schedule with triggers at: $hours"
	else
		# Apply preset schedule
		case "$schedule" in
		247 | work | night)
			"$HELPER" create "$schedule"
			"$HELPER" reload

			# Persist schedule configuration
			write_schedule_config "preset" "$schedule" ""

			print_status "Applied '$schedule' schedule"
			;;
		*)
			print_error "Unknown schedule: $schedule"
			echo ""
			echo "Available schedules: 247, work, night, custom"
			echo "Run 'ccblocks schedule list' to see details"
			return 1
			;;
		esac
	fi
}

# Pause scheduling
pause_schedule() {
	"$HELPER" unload
	print_status "Paused ccblocks scheduling"
	echo ""
	echo "To resume: ccblocks resume"
}

# Resume scheduling
resume_schedule() {
	"$HELPER" load
	print_status "Resumed ccblocks scheduling"
}

# Remove all schedules
remove_schedule() {
	"$HELPER" remove
	print_status "Removed all ccblocks schedules"
}

# Show help
show_help() {
	echo "ccblocks Schedule Management"
	echo "============================"
	echo ""
	echo "Usage: ccblocks schedule <action> [options]"
	echo ""
	echo "Commands:"
	echo "  list                   # List all available schedules"
	echo "  current                # Show current active schedule"
	echo "  apply <name> [hours]   # Apply a schedule (preset or custom)"
	echo "  pause                  # Pause ccblocks"
	echo "  resume                 # Resume after pause"
	echo "  remove                 # Remove all ccblocks schedules"
	echo ""
	echo "Available Schedules:"
	echo "  247     - Maximum coverage (4 triggers: 12 AM, 6 AM, 12 PM, 6 PM)"
	echo "  work    - Work hours only (2 triggers: 9 AM, 2 PM weekdays)"
	echo "  night   - Night owl (2 triggers: 6 PM, 11 PM)"
	echo "  custom  - Custom trigger hours (interactive or direct)"
	echo ""
	echo "Examples:"
	echo "  ccblocks schedule list                  # Show all schedules"
	echo "  ccblocks schedule current               # Show current schedule"
	echo "  ccblocks schedule apply 247             # Apply 24/7 schedule"
	echo "  ccblocks schedule apply work            # Apply work hours"
	echo "  ccblocks schedule apply custom          # Interactive custom"
	echo "  ccblocks schedule apply custom 0,8,16   # Custom hours directly"
	echo "  ccblocks schedule pause                 # Pause for vacation"
	echo "  ccblocks schedule resume                # Resume after pause"
	echo ""
}

# Main command dispatcher
main() {
	local action="${1:-help}"
	shift || true

	case "$action" in
	list)
		list_schedules
		;;
	current)
		show_current
		;;
	apply)
		apply_schedule "$@"
		;;
	pause)
		pause_schedule
		;;
	resume)
		resume_schedule
		;;
	remove)
		remove_schedule
		;;
	help | -h | --help)
		show_help
		;;
	*)
		print_error "Unknown command: $action"
		echo ""
		show_help
		return 1
		;;
	esac
}

main "$@"
