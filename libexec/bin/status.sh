#!/usr/bin/env bash

# ccblocks Status Checker
# Shows scheduler status (LaunchAgent/systemd) and block information

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Detect OS and initialise OS-specific variables
detect_os || exit 1
init_os_vars "$SCRIPT_DIR/.." || exit 1

# Show scheduler status
echo ""
print_header "ccblocks Status Dashboard"
echo "=========================="
echo ""

# Use helper for basic status
"$HELPER" status

# Show custom schedule details if configured
if [ -f "$CONFIG_FILE" ]; then
	config_output=$(read_schedule_config 2>/dev/null)
	if [ $? -eq 0 ]; then
		schedule_type=$(echo "$config_output" | grep "^type=" | cut -d'=' -f2)

		if [ "$schedule_type" = "custom" ]; then
			echo ""
			print_header "Custom Schedule Details"
			echo "=========================="

			custom_hours=$(echo "$config_output" | grep "^custom_hours=" | cut -d'=' -f2)
			coverage_hours=$(echo "$config_output" | grep "^coverage_hours=" | cut -d'=' -f2)

			if [ -n "$custom_hours" ]; then
				echo "  Triggers: $custom_hours"
				echo "  Coverage: ${coverage_hours}h/day"

				# Calculate gaps
				gap_hours=$((24 - coverage_hours))
				echo "  Gaps: ${gap_hours}h/day"

				# Show optimality
				if [ "$coverage_hours" -eq 20 ]; then
					echo "  Status: ✓ Optimal coverage"
				elif [ "$coverage_hours" -ge 15 ]; then
					echo "  Status: Good coverage"
				else
					echo "  Status: Light coverage"
				fi
			fi
		fi
	fi
fi

echo ""
LAST_ACTIVITY_FILE="$CCBLOCKS_CONFIG/.last-activity"
if [ -f "$LAST_ACTIVITY_FILE" ]; then
	print_header "Last Activity"
	echo "=========================="
	LAST_TRIGGER=$(cat "$LAST_ACTIVITY_FILE" 2>/dev/null || echo "unknown")
	echo "  Last triggered: $LAST_TRIGGER"
	echo ""
fi

print_header "Quick Commands"
echo "=========================="
if [ "$OS_TYPE" = "Darwin" ]; then
	echo "  View logs:       log show --last 1d --info --predicate 'eventMessage CONTAINS[c] \"ccblocks\"'"
else
	echo "  View logs:       journalctl --user -t ccblocks -n 50"
fi
echo "  Trigger now:     ccblocks trigger"
echo "  Change schedule: ccblocks schedule"
echo "  Uninstall:       ccblocks uninstall"
echo ""
