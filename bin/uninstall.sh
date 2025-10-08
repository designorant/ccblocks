#!/usr/bin/env bash

# ccblocks Uninstaller
# Complete and safe removal of scheduler (LaunchAgent/systemd) and components

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Detect OS and initialise OS-specific variables
detect_os || exit 1
init_os_vars "$SCRIPT_DIR/.." || exit 1

# Show what will be removed
show_removal_plan() {
	print_header "ccblocks Uninstallation Plan"
	echo ""

	echo "The following items will be removed:"
	echo ""

	# Check for scheduler
	if [ -f "$CONFIG_PATH" ]; then
		echo "✅ $SCHEDULER_NAME:"
		echo "   Location: $CONFIG_PATH"
		if [[ "$OS_TYPE" == "Darwin" ]] && launchctl list | grep -q "ccblocks"; then
			echo "   Status: Currently loaded (will be unloaded)"
		elif [[ "$OS_TYPE" == "Linux" ]] && systemctl --user is-active ccblocks@default.timer &>/dev/null; then
			echo "   Status: Currently active (will be disabled)"
		else
			echo "   Status: Not active"
		fi
		echo ""
	else
		echo "❌ $SCHEDULER_NAME: Not found"
		echo ""
	fi

	# Check for project directory
	if [ -d "$SCRIPT_DIR" ]; then
		echo "📂 Project Directory:"
		echo "   Location: $SCRIPT_DIR"
		echo "   Action: Keep directory (you can manually delete if desired)"
		echo ""
	fi

	# Check for config directory
	if [ -d "$CCBLOCKS_CONFIG" ]; then
		echo "⚙️  Configuration:"
		echo "   Location: $CCBLOCKS_CONFIG"
		echo "   Action: You will be asked whether to remove or preserve"
		echo ""
	fi

	echo "🔒 What will NOT be removed:"
	echo "   • Claude CLI installation"
	echo "   • Log files (for reference)"
	echo "   • Project directory (manual deletion if desired)"
	echo ""
}

# Remove scheduler
remove_scheduler() {
	print_status "Removing $SCHEDULER_NAME..."

	if ! [ -f "$CONFIG_PATH" ]; then
		print_warning "No $SCHEDULER_NAME found"
		return 0
	fi

	# Use helper to remove
	if ! "$HELPER" remove; then
		print_error "Failed to remove $SCHEDULER_NAME"
		return 1
	fi

	print_status "$SCHEDULER_NAME removed successfully"
}

# Show config directory contents
show_config_contents() {
	if [ ! -d "$CCBLOCKS_CONFIG" ]; then
		return 0
	fi

	echo "📁 Configuration Directory:"
	echo "   Location: $CCBLOCKS_CONFIG"
	echo ""

	# Count files
	local file_count
	file_count=$(find "$CCBLOCKS_CONFIG" -type f 2>/dev/null | wc -l | tr -d ' ')

	if [ "$file_count" -eq 0 ]; then
		echo "   Contents: Empty directory"
		return 0
	fi

	echo "   Contents ($file_count file$([ "$file_count" -ne 1 ] && echo "s")):"

	# Show files with relative paths
	find "$CCBLOCKS_CONFIG" -type f 2>/dev/null | while read -r file; do
		local rel_path="${file#"$CCBLOCKS_CONFIG"/}"
		local size
		if [[ "$OS_TYPE" == "Darwin" ]]; then
			size=$(stat -f "%z" "$file" 2>/dev/null || echo "0")
		else
			size=$(stat -c "%s" "$file" 2>/dev/null || echo "0")
		fi

		# Convert size to human readable
		local human_size
		if [ "$size" -lt 1024 ]; then
			human_size="${size}B"
		elif [ "$size" -lt 1048576 ]; then
			human_size="$((size / 1024))KB"
		else
			human_size="$((size / 1048576))MB"
		fi

		echo "   - $rel_path ($human_size)"
	done

	echo ""
}

# Prompt for config removal
prompt_config_removal() {
	if [ ! -d "$CCBLOCKS_CONFIG" ]; then
		return 0
	fi

	# Count files to decide if it's worth asking
	local file_count
	file_count=$(find "$CCBLOCKS_CONFIG" -type f 2>/dev/null | wc -l | tr -d ' ')

	if [ "$file_count" -eq 0 ]; then
		# Empty directory, just remove it
		print_status "Removing empty config directory..."
		rm -rf "$CCBLOCKS_CONFIG"
		return 0
	fi

	echo ""
	print_header "Configuration Directory"
	echo ""
	show_config_contents

	print_warning "This directory contains your ccblocks configuration"
	echo "If you plan to reinstall ccblocks later, you may want to keep these files."
	echo ""
	read -r -p "Remove configuration directory? [Y/n]: " confirm

	if [[ "$confirm" =~ ^[Nn]$ ]]; then
		print_status "Configuration preserved at: $CCBLOCKS_CONFIG"
		echo "You can manually remove it later with: rm -rf $CCBLOCKS_CONFIG"
		echo ""
		return 0
	else
		remove_config
		return 0
	fi
}

# Remove config directory
remove_config() {
	if [ ! -d "$CCBLOCKS_CONFIG" ]; then
		return 0
	fi

	print_status "Removing configuration directory..."

	if rm -rf "$CCBLOCKS_CONFIG"; then
		print_status "Configuration removed successfully"
	else
		print_error "Failed to remove configuration directory"
		echo "You can manually remove it with: rm -rf $CCBLOCKS_CONFIG"
		return 1
	fi
}

# Create uninstallation log
create_uninstall_log() {
	# Use temp directory for log to avoid polluting source tree during tests
	local log_file
	if [ -n "${CCBLOCKS_CONFIG:-}" ] && [ -d "$(dirname "$CCBLOCKS_CONFIG")" ]; then
		log_file="$(dirname "$CCBLOCKS_CONFIG")/ccblocks-uninstall.log"
	else
		log_file="$(mktemp "${TMPDIR:-/tmp}/ccblocks-uninstall.XXXXXX.log")"
	fi

	local config_status="Preserved"

	if [ ! -d "$CCBLOCKS_CONFIG" ]; then
		config_status="Removed"
	fi

	cat >"$log_file" <<EOF
ccblocks Uninstallation Log
===============================

Date: $(date)
User: $(whoami)
System: $(uname -a)

Actions Performed:
- Removed $SCHEDULER_NAME: $CONFIG_PATH
- Disabled/unloaded $SCHEDULER_NAME
- Configuration directory: $config_status
- Created this log file

Project Directory: $SCRIPT_DIR
(Preserved - delete manually if desired)

Configuration: $config_status
$([ "$config_status" = "Preserved" ] && echo "Location: $CCBLOCKS_CONFIG
To remove: rm -rf $CCBLOCKS_CONFIG" || echo "Configuration was removed from: $CCBLOCKS_CONFIG")

To completely remove ccblocks:
  rm -rf "$SCRIPT_DIR"

To reinstall ccblocks:
  cd "$SCRIPT_DIR"
  ./setup.sh

Uninstallation completed successfully.
EOF

	print_status "Created uninstall log: $log_file"
}

# Show final status
show_completion() {
	local config_status_icon="📂"
	local config_status_text="preserved"

	if [ ! -d "$CCBLOCKS_CONFIG" ]; then
		config_status_icon="✅"
		config_status_text="removed"
	fi

	echo ""
	print_header "[UNINSTALL] Uninstallation Complete! ✅"
	echo ""

	print_status "ccblocks $SCHEDULER_NAME has been successfully removed"
	echo ""

	echo "📋 Summary:"
	echo "   ✅ $SCHEDULER_NAME disabled and removed"
	echo "   $config_status_icon Configuration $config_status_text"
	echo "   ✅ Created uninstall log"
	echo "   📂 Project directory preserved at: $SCRIPT_DIR"
	echo ""

	echo "🔄 To verify removal:"
	if [[ "$OS_TYPE" == "Darwin" ]]; then
		echo "   launchctl list | grep ccblocks    # Should return nothing"
		echo "   ls ~/Library/LaunchAgents/ccblocks.plist  # Should not exist"
	else
		echo "   systemctl --user list-timers | grep ccblocks  # Should return nothing"
		echo "   ls ~/.config/systemd/user/ccblocks*  # Should not exist"
	fi
	echo ""

	echo "🗑️  To completely remove ccblocks:"
	if [ -d "$CCBLOCKS_CONFIG" ]; then
		echo "   rm -rf $SCRIPT_DIR $CCBLOCKS_CONFIG"
	else
		echo "   rm -rf $SCRIPT_DIR"
	fi
	echo ""

	echo "🔧 To reinstall later:"
	echo "   cd $SCRIPT_DIR"
	echo "   ./setup.sh"
	echo ""

	print_status "Thank you for using ccblocks!"
}

# Show usage
show_usage() {
	echo "ccblocks Uninstaller"
	echo ""
	echo "Usage: ccblocks uninstall [options]"
	echo ""
	echo "Options:"
	echo "  --force    # Skip prompts, remove config automatically"
	echo "  -h, --help # Show this help message"
	echo ""
	echo "Examples:"
	echo "  ccblocks uninstall         # Interactive (asks about config)"
	echo "  ccblocks uninstall --force # Uninstall without prompts"
}

# Main uninstallation flow
main() {
	local force=false

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--force)
			force=true
			shift
			;;
		-h | --help)
			show_usage
			exit 0
			;;
		*)
			print_error "Unknown option: $1"
			show_usage
			exit 1
			;;
		esac
	done

	# Show header
	print_header "[UNINSTALL] ccblocks Uninstaller"
	echo "Safe removal of $SCHEDULER_NAME scheduling system"
	echo ""

	# Show what will be removed
	show_removal_plan

	# Confirmation (unless forced)
	if [ "$force" = false ]; then
		echo ""
		print_warning "This will remove the ccblocks $SCHEDULER_NAME"
		read -r -p "Proceed with uninstallation? [Y/n]: " confirm

		if [[ "$confirm" =~ ^[Nn]$ ]]; then
			print_status "Uninstallation cancelled"
			exit 0
		fi
	fi

	echo ""
	print_header "[UNINSTALL] Starting Uninstallation..."

	# Perform removal
	remove_scheduler

	# Handle config removal (with force flag support)
	if [ "$force" = true ]; then
		# Force mode: remove config without prompting
		if [ -d "$CCBLOCKS_CONFIG" ]; then
			remove_config
		fi
	else
		# Interactive mode: ask user
		prompt_config_removal
	fi

	create_uninstall_log
	show_completion
}

# Run main function
main "$@"
