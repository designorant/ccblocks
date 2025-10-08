#!/usr/bin/env bash

# ccblocks Systemd Helper (Internal)
# Platform-specific Linux systemd service/timer management
# Note: This is an internal helper script called by main CLI commands

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

SERVICE_NAME="ccblocks"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}@.service"
TIMER_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}@.timer"
TRIGGER_SCRIPT="$SCRIPT_DIR/../libexec/ccblocks-daemon.sh"

# Check if service exists
service_exists() {
	[ -f "$SERVICE_FILE" ]
}

# Check if timer is active
timer_active() {
	systemctl --user is-active "${SERVICE_NAME}@*.timer" &>/dev/null
}

# Create systemd service and timer files
create_service() {
	local schedule="${1:-247}"

	# Create systemd user directory if it doesn't exist
	mkdir -p "$HOME/.config/systemd/user"

	# Create service file (template)
	cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=ccblocks Claude Code Block Trigger (%i)
After=network.target

[Service]
Type=oneshot
ExecStart=$TRIGGER_SCRIPT
SyslogIdentifier=ccblocks

[Install]
WantedBy=default.target
EOF

	# Define timer schedules
	local oncalendar
	case "$schedule" in
	"247")
		oncalendar="*-*-* 00,06,12,18:00:00"
		;;
	"work")
		oncalendar="Mon-Fri *-*-* 09,14:00:00"
		;;
	"night")
		oncalendar="*-*-* 18,23:00:00"
		;;
	*)
		print_error "Unknown schedule: $schedule"
		return 1
		;;
	esac

	# Create timer file (template)
	cat >"$TIMER_FILE" <<EOF
[Unit]
Description=ccblocks Scheduling Timer (%i)

[Timer]
OnCalendar=$oncalendar
Persistent=true

[Install]
WantedBy=timers.target
EOF

	print_status "Created systemd service and timer files"
}

# Create systemd service and timer files with custom hours
create_service_custom() {
	local hours_str="$1"

	# Create systemd user directory if it doesn't exist
	mkdir -p "$HOME/.config/systemd/user"

	# Create service file (template)
	cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=ccblocks Claude Code Block Trigger (%i)
After=network.target

[Service]
Type=oneshot
ExecStart=$TRIGGER_SCRIPT
SyslogIdentifier=ccblocks

[Install]
WantedBy=default.target
EOF

	# Convert comma-separated hours to systemd OnCalendar format
	# E.g., "0,6,12,18" becomes "*-*-* 00,06,12,18:00:00"
	local formatted_hours
	formatted_hours=$(echo "$hours_str" | tr ',' ' ' | awk '{for(i=1;i<=NF;i++) printf "%02d,", $i}' | sed 's/,$//')
	local oncalendar="*-*-* ${formatted_hours}:00:00"

	# Create timer file (template)
	cat >"$TIMER_FILE" <<EOF
[Unit]
Description=ccblocks Scheduling Timer (%i)

[Timer]
OnCalendar=$oncalendar
Persistent=true

[Install]
WantedBy=timers.target
EOF

	print_status "Created custom systemd service and timer files"
	print_status "Triggers at: ${hours_str}"
}

# Enable and start timer
enable_timer() {
	if ! service_exists; then
		print_error "Service files not found. Run 'create' first."
		return 1
	fi

	# Reload systemd to pick up new files
	systemctl --user daemon-reload

	# Enable and start timer
	systemctl --user enable "${SERVICE_NAME}@default.timer"
	systemctl --user start "${SERVICE_NAME}@default.timer"

	print_status "Timer enabled and started"
}

# Disable and stop timer
disable_timer() {
	if systemctl --user is-enabled "${SERVICE_NAME}@default.timer" &>/dev/null; then
		systemctl --user stop "${SERVICE_NAME}@default.timer"
		systemctl --user disable "${SERVICE_NAME}@default.timer"
		print_status "Timer disabled and stopped"
	else
		print_warning "Timer not enabled"
	fi
}

# Start service immediately
start_service() {
	if ! service_exists; then
		print_error "Service files not found. Run 'create' first."
		return 1
	fi

	systemctl --user start "${SERVICE_NAME}@manual.service"
	print_status "Service started (triggered manually)"
}

# Check service/timer status
status_service() {
	echo "ccblocks Systemd Status"
	echo "======================="
	echo ""

	if service_exists; then
		echo "Service: ✅ Found at $SERVICE_FILE"
		echo "Timer:   ✅ Found at $TIMER_FILE"
	else
		echo "Service: ❌ Not found"
		return 1
	fi

	echo ""
	if systemctl --user is-active "${SERVICE_NAME}@default.timer" &>/dev/null; then
		echo "Status: ✅ Timer active"
		echo ""

		# Show timer schedule
		echo "Schedule:"
		systemctl --user cat "${SERVICE_NAME}@default.timer" | grep "OnCalendar" | sed 's/^/  /'
		echo ""

		# Show next trigger
		echo "Next Trigger:"
		systemctl --user list-timers "${SERVICE_NAME}@default.timer" --no-pager | grep -v "^NEXT" | grep "${SERVICE_NAME}" | sed 's/^/  /' || echo "  (calculating...)"
		echo ""

		# Show recent activity from state file
		local last_activity="$CCBLOCKS_CONFIG/.last-activity"
		if [ -f "$last_activity" ]; then
			echo "Recent Activity:"
			echo "  Last trigger: $(cat "$last_activity" 2>/dev/null || echo "unknown")"
		else
			echo "Recent Activity: None yet"
		fi
	else
		echo "Status: ❌ Timer not active"
	fi

	echo ""
	echo "View Logs:"
	echo "  journalctl --user -t ccblocks -n 50"
}

# Remove service/timer completely
remove_service() {
	if systemctl --user is-active "${SERVICE_NAME}@default.timer" &>/dev/null; then
		disable_timer
	fi

	if service_exists; then
		rm "$SERVICE_FILE" "$TIMER_FILE"
		systemctl --user daemon-reload
		print_status "Removed systemd service and timer files"
	fi
}

# Show usage
show_usage() {
	echo "ccblocks Systemd Helper (internal)"
	echo ""
	echo "Usage: $0 <command> [options]"
	echo "Note: This is an internal helper. Use 'ccblocks' command instead."
	echo ""
	echo "Commands:"
	echo "  create [schedule]  - Create systemd service/timer (schedules: 247, work, night)"
	echo "  enable             - Enable and start timer"
	echo "  disable            - Disable and stop timer"
	echo "  reload             - Reload systemd (after manual edits)"
	echo "  start              - Trigger service manually"
	echo "  status             - Show service/timer status"
	echo "  remove             - Remove service/timer completely"
	echo "  logs               - Show recent logs"
	echo ""
	echo "Examples:"
	echo "  $0 create 247     # Create with 24/7 schedule"
	echo "  $0 enable          # Enable the timer"
	echo "  $0 status          # Check status"
	echo "  $0 start           # Trigger immediately"
}

# Main command handler
main() {
	local command="${1:-}"

	case "$command" in
	create)
		local schedule="${2:-247}"
		create_service "$schedule"
		;;
	create_custom)
		local hours="${2:-}"
		if [ -z "$hours" ]; then
			print_error "Custom hours required"
			return 1
		fi
		create_service_custom "$hours"
		;;
	enable)
		enable_timer
		;;
	disable)
		disable_timer
		;;
	load)
		enable_timer
		;;
	unload)
		disable_timer
		;;
	reload)
		systemctl --user daemon-reload
		print_status "Systemd user daemon reloaded"

		# Restart timer if it's enabled to apply changes
		if systemctl --user is-enabled "${SERVICE_NAME}@default.timer" &>/dev/null; then
			systemctl --user restart "${SERVICE_NAME}@default.timer"
			print_status "Timer restarted with new schedule"
		fi
		;;
	start)
		start_service
		;;
	status)
		status_service
		;;
	remove)
		remove_service
		;;
	logs)
		echo "Showing ccblocks logs from journald (last 50 entries):"
		journalctl --user -t ccblocks -n 50 --no-pager
		;;
	-h | --help | help | "")
		show_usage
		;;
	*)
		print_error "Unknown command: $command"
		show_usage
		exit 1
		;;
	esac
}

main "$@"
