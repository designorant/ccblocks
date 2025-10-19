#!/usr/bin/env bash

# ccblocks LaunchAgent Helper (Internal)
# Platform-specific macOS LaunchAgent management
# Note: This is an internal helper script called by main CLI commands

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

LABEL="ccblocks"
PLIST_PATH="$HOME/Library/LaunchAgents/ccblocks.plist"

# Resolve TRIGGER_SCRIPT path - use version-independent path for Homebrew
# If installed via Homebrew, paths contain /Cellar/ccblocks/VERSION/ which breaks on upgrade
# Replace with /opt/ccblocks/ symlink which always points to current version
TRIGGER_SCRIPT="$SCRIPT_DIR/../libexec/ccblocks-daemon.sh"
if [ ! -f "$TRIGGER_SCRIPT" ]; then
	TRIGGER_SCRIPT="$SCRIPT_DIR/../ccblocks-daemon.sh"
fi
if [[ "$TRIGGER_SCRIPT" == */Cellar/ccblocks/* ]]; then
	# Extract brew prefix (everything before /Cellar/)
	BREW_PREFIX="${TRIGGER_SCRIPT%%/Cellar/ccblocks/*}"
	# Preserve relative path after the versioned Cellar segment
	RELATIVE_PATH="${TRIGGER_SCRIPT#${BREW_PREFIX}/Cellar/ccblocks/}"
	RELATIVE_PATH="${RELATIVE_PATH#*/}" # drop version component
	# Use opt symlink instead of versioned Cellar path
	TRIGGER_SCRIPT="$BREW_PREFIX/opt/ccblocks/${RELATIVE_PATH}"
fi

# Check if LaunchAgent exists
agent_exists() {
	[ -f "$PLIST_PATH" ]
}

# Check if LaunchAgent is loaded
agent_loaded() {
	launchctl list | grep -w "$LABEL" >/dev/null
}

# Create LaunchAgent plist
create_plist() {
	local schedule="${1:-247}"

	# Define schedule intervals
	local intervals
	case "$schedule" in
	"247")
		intervals='
        <dict>
            <key>Hour</key>
            <integer>0</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>6</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>12</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>18</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>'
		;;
	"work")
		# Generate weekday entries (Mon=2 through Fri=6) at 9 AM and 2 PM
		intervals=""
		for weekday in 2 3 4 5 6; do
			for hour in 9 14; do
				intervals+="
        <dict>
            <key>Hour</key>
            <integer>$hour</integer>
            <key>Minute</key>
            <integer>0</integer>
            <key>Weekday</key>
            <integer>$weekday</integer>
        </dict>"
			done
		done
		;;
	"night")
		intervals='
        <dict>
            <key>Hour</key>
            <integer>18</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>23</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>'
		;;
	*)
		print_error "Unknown schedule: $schedule"
		return 1
		;;
	esac

	cat >"$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$TRIGGER_SCRIPT</string>
    </array>

    <key>StartCalendarInterval</key>
    <array>$intervals
    </array>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

	print_status "Created LaunchAgent plist at: $PLIST_PATH"
}

# Create LaunchAgent plist with custom hours
create_plist_custom() {
	local hours_str="$1"

	# Convert comma-separated hours to array
	IFS=',' read -ra hours_array <<<"$hours_str"

	# Build intervals XML
	local intervals=""
	for hour in "${hours_array[@]}"; do
		hour=$(echo "$hour" | tr -d ' ')
		intervals+="
        <dict>
            <key>Hour</key>
            <integer>$hour</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>"
	done

	cat >"$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$TRIGGER_SCRIPT</string>
    </array>

    <key>StartCalendarInterval</key>
    <array>$intervals
    </array>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

	print_status "Created custom LaunchAgent plist at: $PLIST_PATH"
	print_status "Triggers at: ${hours_str}"
}

# Load LaunchAgent
load_agent() {
	if ! agent_exists; then
		print_error "LaunchAgent plist not found. Run 'setup' first."
		return 1
	fi

	if agent_loaded; then
		print_warning "LaunchAgent already loaded"
		return 0
	fi

	# Use bootstrap for modern macOS (bootout/bootstrap is more reliable than load/unload)
	local uid
	uid=$(id -u)
	if launchctl bootstrap "gui/$uid" "$PLIST_PATH" 2>&1; then
		print_status "LaunchAgent loaded"
	else
		print_error "Failed to load LaunchAgent"
		return 1
	fi
}

# Unload LaunchAgent
unload_agent() {
	if ! agent_loaded; then
		print_warning "LaunchAgent not loaded"
		return 0
	fi

	# Use bootout for modern macOS (bootout/bootstrap is more reliable than load/unload)
	local uid
	uid=$(id -u)
	if launchctl bootout "gui/$uid/$LABEL" 2>&1; then
		print_status "LaunchAgent unloaded"
	else
		print_error "Failed to unload LaunchAgent"
		return 1
	fi
}

# Start LaunchAgent immediately
start_agent() {
	if ! agent_loaded; then
		print_error "LaunchAgent not loaded. Run 'load' first."
		return 1
	fi

	launchctl start "$LABEL"
	print_status "LaunchAgent started (triggered manually)"
}

# Check LaunchAgent status
status_agent() {
	echo "ccblocks LaunchAgent Status"
	echo "============================"
	echo ""

	if agent_exists; then
		echo "Plist: ✅ Found at $PLIST_PATH"
	else
		echo "Plist: ❌ Not found"
		return 1
	fi

	if agent_loaded; then
		echo "Status: ✅ Loaded and active"
		echo ""

		# Show schedule
		echo "Schedule:"
		if [ -f "$PLIST_PATH" ]; then
			plutil -p "$PLIST_PATH" | awk '
                /"Hour" =>/ { h = $NF }
                /"Minute" =>/ { m = $NF }
                /"Weekday" =>/ { w = $NF }
                /}/ && h != "" && m != "" {
                    wd = ""
                    if (w == "1") wd = " (Sun)"
                    else if (w == "2") wd = " (Mon)"
                    else if (w == "3") wd = " (Tue)"
                    else if (w == "4") wd = " (Wed)"
                    else if (w == "5") wd = " (Thu)"
                    else if (w == "6") wd = " (Fri)"
                    else if (w == "7") wd = " (Sat)"
                    printf "  %02d:%02d%s\n", h, m, wd
                    h = m = w = ""
                }
            '
		fi
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
		echo "Status: ❌ Not loaded"
	fi

	echo ""
	echo "View Logs:"
	echo "  log show --predicate 'process == \"ccblocks\"' --last 1d"
}

# Remove LaunchAgent completely
remove_agent() {
	if agent_loaded; then
		unload_agent
	fi

	if agent_exists; then
		rm "$PLIST_PATH"
		print_status "Removed LaunchAgent plist"
	fi
}

# Show usage
show_usage() {
	echo "ccblocks LaunchAgent Helper (internal)"
	echo ""
	echo "Usage: $0 <command> [options]"
	echo "Note: This is an internal helper. Use 'ccblocks' command instead."
	echo ""
	echo "Commands:"
	echo "  create [schedule]  - Create LaunchAgent plist (schedules: 247, work, night)"
	echo "  load              - Load LaunchAgent"
	echo "  unload            - Unload LaunchAgent"
	echo "  reload            - Reload LaunchAgent (unload + load)"
	echo "  start             - Trigger LaunchAgent manually"
	echo "  status            - Show LaunchAgent status"
	echo "  remove            - Remove LaunchAgent completely"
	echo "  logs              - Show recent logs"
	echo ""
	echo "Examples:"
	echo "  $0 create 247    # Create with 24/7 schedule"
	echo "  $0 load           # Load the LaunchAgent"
	echo "  $0 status         # Check status"
	echo "  $0 start          # Trigger immediately"
}

# Main command handler
main() {
	local command="${1:-}"

	case "$command" in
	create)
		local schedule="${2:-247}"
		create_plist "$schedule"
		;;
	create_custom)
		local hours="${2:-}"
		if [ -z "$hours" ]; then
			print_error "Custom hours required"
			return 1
		fi
		create_plist_custom "$hours"
		;;
	load)
		load_agent
		;;
	unload)
		unload_agent
		;;
	reload)
		unload_agent
		load_agent
		;;
	start)
		start_agent
		;;
	status)
		status_agent
		;;
	remove)
		remove_agent
		;;
	logs)
		echo "Showing ccblocks logs from system log (last 24 hours):"
		log show --predicate 'process == "ccblocks"' --last 1d --style compact
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
