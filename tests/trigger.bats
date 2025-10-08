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
