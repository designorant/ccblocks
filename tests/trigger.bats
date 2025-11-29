#!/usr/bin/env bats

# Tests for ccblocks-daemon
# Integration tests for Claude Code block triggering

load test_helper

setup() {
    setup_test_dir
    SCRIPT="${PROJECT_ROOT}/libexec/ccblocks-daemon.sh"

    # Override config directory to test directory
    export CCBLOCKS_CONFIG="${TEST_TEMP_DIR}/.config/ccblocks"
    mkdir -p "$CCBLOCKS_CONFIG"
}

teardown() {
    teardown_test_dir
}

# Claude CLI discovery tests
@test "ccblocks-daemon finds claude in PATH and triggers successfully" {
    mock_claude_success

    run "$SCRIPT"
    assert_success
}

# Activity file tests
@test "ccblocks-daemon creates .last-activity file on success" {
    mock_claude_success

    run "$SCRIPT"
    assert_success
    assert [ -f "$CCBLOCKS_CONFIG/.last-activity" ]
}

@test "ccblocks-daemon writes timestamp to .last-activity file" {
    mock_claude_success

    run "$SCRIPT"
    assert_success

    # Verify file contains a timestamp pattern
    run cat "$CCBLOCKS_CONFIG/.last-activity"
    assert_output --regexp "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"
}

@test "ccblocks-daemon overwrites existing .last-activity file" {
    mock_claude_success

    # Create existing activity file
    echo "2024-01-01 00:00:00" > "$CCBLOCKS_CONFIG/.last-activity"

    run "$SCRIPT"
    assert_success

    # Verify it was overwritten with new timestamp
    run cat "$CCBLOCKS_CONFIG/.last-activity"
    refute_output --partial "2024-01-01"
}

# Timeout tests
@test "ccblocks-daemon handles claude timeout" {
    # Mock claude that takes too long (simulated by returning timeout exit code)
    mock_command "claude" 'sleep 1; exit 124'

    run "$SCRIPT"
    assert_failure
}

@test "ccblocks-daemon handles claude failure" {
    mock_claude_failure

    run "$SCRIPT"
    assert_failure
}

# Config directory tests
@test "ccblocks-daemon creates config directory if missing" {
    # Remove config directory
    rm -rf "$CCBLOCKS_CONFIG"

    mock_claude_success

    run "$SCRIPT"
    assert_success
    assert [ -d "$CCBLOCKS_CONFIG" ]
}

@test "ccblocks-daemon handles existing config directory" {
    # Config directory already exists from setup
    assert [ -d "$CCBLOCKS_CONFIG" ]

    mock_claude_success

    run "$SCRIPT"
    assert_success
}

# Edge cases
@test "ccblocks-daemon doesn't fail if .last-activity write fails" {
    mock_claude_success

    # Make config directory read-only to prevent file creation
    chmod 555 "$CCBLOCKS_CONFIG"

    run "$SCRIPT"
    # Should still succeed even if activity file can't be written
    assert_success

    # Restore permissions for cleanup
    chmod 755 "$CCBLOCKS_CONFIG"
}

# ccusage verification tests
@test "ccblocks-daemon succeeds with standard ccusage active block output" {
    mock_claude_success
    mock_ccusage_active_block

    run "$SCRIPT"
    assert_success
    refute_output --partial "inconclusive"
}

@test "ccblocks-daemon warns when ccusage shows no active block but doesn't fail" {
    mock_claude_success
    mock_ccusage_no_block

    run "$SCRIPT"
    # Should still succeed by default (non-strict mode)
    assert_success
}

@test "ccblocks-daemon handles alternative ccusage output formats" {
    mock_claude_success
    mock_ccusage_alternative_format

    run "$SCRIPT"
    assert_success
    # Should not show inconclusive warning for recognized alternative format
    refute_output --partial "inconclusive"
}

@test "ccblocks-daemon warns on empty ccusage output but continues" {
    mock_claude_success
    mock_ccusage_empty_output

    run "$SCRIPT"
    assert_success
    assert_output --partial "empty output"
}

@test "ccblocks-daemon warns when ccusage is not found" {
    mock_claude_success
    mock_ccusage_not_installed

    run "$SCRIPT"
    assert_success
    assert_output --partial "ccusage not found"
}

@test "ccblocks-daemon logs actual output in debug mode for unrecognised ccusage format" {
    mock_claude_success
    # Mock ccusage with completely unexpected format
    mock_command "ccusage" "echo 'Unexpected format here'; exit 0"

    export CCBLOCKS_DEBUG=1
    run "$SCRIPT"
    assert_success
    assert_output --partial "[DEBUG]"
    assert_output --partial "Unexpected format"
}
