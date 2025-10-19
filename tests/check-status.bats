#!/usr/bin/env bats

# Tests for status.sh (status reporting and dashboard display)

load test_helper

setup() {
    setup_test_dir
    SCRIPT="${PROJECT_ROOT}/libexec/bin/status.sh"

    # Override config directory to test directory
    export CCBLOCKS_CONFIG="${TEST_TEMP_DIR}/.config/ccblocks"
    mkdir -p "$CCBLOCKS_CONFIG"

    # Create mock helper script
    create_mock_helper
}

teardown() {
    restore_helper
    teardown_test_dir
}

# Helper function to create mock helper script
create_mock_helper() {
    local helper_dir="${PROJECT_ROOT}/libexec/lib"
    local helper_name

    # Determine which helper based on OS
    if [[ "$(uname)" == "Darwin" ]]; then
        helper_name="launchagent-helper.sh"
    else
        helper_name="systemd-helper.sh"
    fi

    # Backup original helper if exists
    if [ -f "${helper_dir}/${helper_name}" ]; then
        cp "${helper_dir}/${helper_name}" "${TEST_TEMP_DIR}/${helper_name}.backup"
    fi

    # Create mock helper
    cat > "${helper_dir}/${helper_name}" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

case "$1" in
    status)
        echo "Mock Status: Scheduler active"
        echo "Next run: in 5 minutes"
        exit 0
        ;;
    *)
        echo "Mock helper: Unknown command $1" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "${helper_dir}/${helper_name}"
}

restore_helper() {
    local helper_dir="${PROJECT_ROOT}/libexec/lib"
    local helper_name

    if [[ "$(uname)" == "Darwin" ]]; then
        helper_name="launchagent-helper.sh"
    else
        helper_name="systemd-helper.sh"
    fi

    # Restore original helper if backup exists
    if [ -f "${TEST_TEMP_DIR}/${helper_name}.backup" ]; then
        mv "${TEST_TEMP_DIR}/${helper_name}.backup" "${helper_dir}/${helper_name}"
    fi
}

# Basic functionality tests
@test "check-status shows status dashboard header" {
    run "$SCRIPT"
    assert_success
    assert_output --partial "Status Dashboard"
}

@test "check-status calls helper status command" {
    run "$SCRIPT"
    assert_success
    assert_output --partial "Mock Status: Scheduler active"
}

@test "check-status shows quick commands section" {
    run "$SCRIPT"
    assert_success
    assert_output --partial "Quick Commands"
}

# Last activity tests
@test "check-status shows last activity when file exists" {
    # Create activity file
    echo "2025-10-07 14:30:00" > "$CCBLOCKS_CONFIG/.last-activity"

    run "$SCRIPT"
    assert_success
    assert_output --partial "Last Activity"
    assert_output --partial "Last triggered: 2025-10-07 14:30:00"
}

@test "check-status handles missing .last-activity file gracefully" {
    # Don't create activity file
    assert [ ! -f "$CCBLOCKS_CONFIG/.last-activity" ]

    run "$SCRIPT"
    assert_success
    # Should not show Last Activity section if file doesn't exist
    refute_output --partial "Last triggered:"
}

@test "check-status shows last activity with timestamp" {
    # Create activity file with specific timestamp
    local timestamp="2025-10-06 09:15:42"
    echo "$timestamp" > "$CCBLOCKS_CONFIG/.last-activity"

    run "$SCRIPT"
    assert_success
    assert_output --partial "$timestamp"
}

# Platform-specific command tests
@test "check-status shows platform-specific log command (macOS)" {
    skip_if_not_macos

    run "$SCRIPT"
    assert_success
    assert_output --partial "log show"
    assert_output --partial "predicate"
}

@test "check-status shows platform-specific log command (Linux)" {
    skip_if_not_linux

    run "$SCRIPT"
    assert_success
    assert_output --partial "journalctl"
    assert_output --partial "--user"
}

# Quick commands tests
@test "check-status shows trigger command" {
    run "$SCRIPT"
    assert_success
    assert_output --partial "ccblocks trigger"
}

@test "check-status shows schedule command" {
    run "$SCRIPT"
    assert_success
    assert_output --partial "ccblocks schedule"
}

@test "check-status shows uninstall command" {
    run "$SCRIPT"
    assert_success
    assert_output --partial "ccblocks uninstall"
}
