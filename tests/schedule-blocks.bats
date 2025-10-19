#!/usr/bin/env bats

# Tests for schedule.sh (schedule management)

load test_helper

setup() {
    setup_test_dir
    SCRIPT="${PROJECT_ROOT}/libexec/bin/schedule.sh"

    # Create mock helper for integration tests
    create_mock_helper
}

teardown() {
    restore_mock_helper
    teardown_test_dir
}

# Helper functions for mocking
create_mock_helper() {
    local helper_dir="${PROJECT_ROOT}/libexec/lib"
    local helper_name

    if [[ "$(uname)" == "Darwin" ]]; then
        helper_name="launchagent-helper.sh"
    else
        helper_name="systemd-helper.sh"
    fi

    # Backup original if exists
    if [ -f "${helper_dir}/${helper_name}" ]; then
        cp "${helper_dir}/${helper_name}" "${TEST_TEMP_DIR}/${helper_name}.backup"
    fi

    # Create mock that handles schedule commands
    cat > "${helper_dir}/${helper_name}" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

case "$1" in
    status)
        echo "Mock: Current schedule active"
        exit 0
        ;;
    create)
        echo "Mock: Created schedule $2"
        exit 0
        ;;
    create_custom)
        echo "Mock: Created custom schedule $2"
        exit 0
        ;;
    reload)
        echo "Mock: Reloaded schedule"
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

restore_mock_helper() {
    local helper_dir="${PROJECT_ROOT}/libexec/lib"
    local helper_name

    if [[ "$(uname)" == "Darwin" ]]; then
        helper_name="launchagent-helper.sh"
    else
        helper_name="systemd-helper.sh"
    fi

    # Restore from backup
    if [ -f "${TEST_TEMP_DIR}/${helper_name}.backup" ]; then
        mv "${TEST_TEMP_DIR}/${helper_name}.backup" "${helper_dir}/${helper_name}"
    fi
}

# Help and usage tests
@test "schedule-blocks shows help" {
    run "$SCRIPT" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "Commands:"
}

@test "schedule-blocks shows error for unknown command" {
    run "$SCRIPT" invalid-command
    assert_failure
    assert_output --partial "Unknown command"
}

# List schedules tests
@test "schedule-blocks list shows all available schedules" {
    run "$SCRIPT" list
    assert_success
    assert_output --partial "247"
    assert_output --partial "work"
    assert_output --partial "night"
}

@test "schedule-blocks list shows schedule details" {
    run "$SCRIPT" list
    assert_success
    assert_output --partial "Maximum Coverage"
    assert_output --partial "Work Hours"
    assert_output --partial "Night Owl"
}

# Current schedule tests
@test "schedule-blocks current calls helper status" {
    # Test command routing with mock helper
    run "$SCRIPT" current
    assert_success
    assert_output --partial "Mock: Current schedule active"
}

# Apply schedule tests
@test "schedule-blocks apply requires schedule name" {
    run "$SCRIPT" apply
    assert_failure
    assert_output --partial "specify a schedule"
}

# Schedule name recognition tests
@test "schedule-blocks recognizes 247 schedule name" {
    run "$SCRIPT" apply 247
    assert_success
    assert_output --partial "Applied '247' schedule"
}

@test "schedule-blocks recognizes work schedule" {
    run "$SCRIPT" apply work
    assert_success
    assert_output --partial "Applied 'work' schedule"
}

@test "schedule-blocks recognizes night schedule" {
    run "$SCRIPT" apply night
    assert_success
    assert_output --partial "Applied 'night' schedule"
}

# Help content validation
@test "schedule-blocks help lists all schedule names" {
    run "$SCRIPT" help
    assert_success
    assert_output --partial "247"
    assert_output --partial "work"
    assert_output --partial "night"
}

@test "schedule-blocks help shows examples" {
    run "$SCRIPT" --help
    assert_success
    assert_output --partial "Examples:"
}

# Custom schedule tests
@test "schedule-blocks apply custom with valid hours succeeds" {
    run "$SCRIPT" apply custom "0,8,16"
    assert_success
    assert_output --partial "Applied custom schedule"
    assert_output --partial "0,8,16"
}

@test "schedule-blocks apply custom rejects hour 24" {
    run "$SCRIPT" apply custom "0,8,16,24"
    assert_failure
    assert_output --partial "Invalid hour: 24"
    assert_output --partial "must be 0-23"
}

@test "schedule-blocks apply custom rejects hour 25" {
    run "$SCRIPT" apply custom "0,12,25"
    assert_failure
    assert_output --partial "Invalid hour: 25"
}

@test "schedule-blocks apply custom rejects hour 30" {
    run "$SCRIPT" apply custom "6,18,30"
    assert_failure
    assert_output --partial "Invalid hour: 30"
}

@test "schedule-blocks apply custom rejects negative hour" {
    run "$SCRIPT" apply custom "-1,8,16"
    assert_failure
    assert_output --partial "Invalid hour"
}

@test "schedule-blocks apply custom rejects non-numeric input" {
    run "$SCRIPT" apply custom "0,abc,16"
    assert_failure
    assert_output --partial "Invalid hour: 'abc'"
}

@test "schedule-blocks apply custom rejects alphabetic input" {
    run "$SCRIPT" apply custom "foo,bar"
    assert_failure
    assert_output --partial "Invalid hour"
}

@test "schedule-blocks apply custom rejects duplicate hours" {
    run "$SCRIPT" apply custom "0,8,8,16"
    assert_failure
    assert_output --partial "Duplicate hour: 8"
}

@test "schedule-blocks apply custom rejects single trigger" {
    run "$SCRIPT" apply custom "12"
    assert_failure
    assert_output --partial "At least 2 triggers required"
}

@test "schedule-blocks apply custom rejects more than 4 triggers" {
    run "$SCRIPT" apply custom "0,5,10,15,20"
    assert_failure
    assert_output --partial "Maximum 4 triggers allowed"
}

@test "schedule-blocks apply custom rejects insufficient spacing" {
    run "$SCRIPT" apply custom "0,3,8,16"
    assert_failure
    assert_output --partial "Insufficient spacing"
    assert_output --partial "minimum 5h required"
}

@test "schedule-blocks apply custom rejects consecutive hours" {
    run "$SCRIPT" apply custom "8,9"
    assert_failure
    assert_output --partial "Insufficient spacing"
}

@test "schedule-blocks apply custom accepts exactly 5-hour spacing" {
    run "$SCRIPT" apply custom "0,5,10,15"
    assert_success
    assert_output --partial "Applied custom schedule"
}

@test "schedule-blocks apply custom handles whitespace in hours" {
    run "$SCRIPT" apply custom "0, 8, 16"
    assert_success
    assert_output --partial "Applied custom schedule"
}

@test "schedule-blocks apply custom with 2 triggers succeeds" {
    run "$SCRIPT" apply custom "0,12"
    assert_success
    assert_output --partial "Applied custom schedule"
}

@test "schedule-blocks apply custom with 3 triggers succeeds" {
    run "$SCRIPT" apply custom "0,8,16"
    assert_success
    assert_output --partial "Applied custom schedule"
}

@test "schedule-blocks apply custom with 4 triggers succeeds" {
    run "$SCRIPT" apply custom "0,6,12,18"
    assert_success
    assert_output --partial "Applied custom schedule"
}

@test "schedule-blocks apply custom rejects wraparound spacing violation" {
    run "$SCRIPT" apply custom "0,8,16,22"
    assert_failure
    assert_output --partial "Insufficient spacing"
    assert_output --partial "to 0:00 (next day)"
}

@test "schedule-blocks apply custom requires hours argument" {
    # Test that empty hours is rejected
    run bash -c "echo '' | \"$SCRIPT\" apply custom"
    assert_failure
    assert_output --partial "No hours specified"
}
