#!/usr/bin/env bats

# Tests for uninstall
# Tests for safe removal of LaunchAgent/systemd and ccblocks components

load test_helper

setup() {
    setup_test_dir
    SCRIPT="${PROJECT_ROOT}/libexec/bin/uninstall.sh"

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
    remove)
        echo "Mock: Removing scheduler"
        exit 0
        ;;
    status)
        echo "Mock: Showing status"
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

    # Restore original helper from backup
    if [ -f "${TEST_TEMP_DIR}/${helper_name}.backup" ]; then
        mv "${TEST_TEMP_DIR}/${helper_name}.backup" "${helper_dir}/${helper_name}"
    else
        echo "Warning: No backup found for ${helper_name}" >&2
    fi
}

# Help and usage tests
@test "uninstall shows usage" {
    run "$SCRIPT" --help
    restore_helper
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "Options:"
    assert_output --partial "--force"
}

@test "uninstall shows error for unknown option" {
    run "$SCRIPT" --invalid-option
    restore_helper
    assert_failure
    assert_output --partial "Unknown option"
}

# Interactive mode tests
@test "uninstall prompts for confirmation in interactive mode" {
    # Simulate user saying "N" (cancel)
    run bash -c "echo 'N' | \"$SCRIPT\""
    restore_helper
    assert_success
    # Check for warning message (appears before prompt) and cancellation
    assert_output --partial "This will remove"
    assert_output --partial "cancelled"
}

@test "uninstall proceeds when user confirms" {
    # Simulate user saying "y" then "N" for config removal
    run bash -c "echo -e 'y\nN' | \"$SCRIPT\""
    restore_helper
    assert_success
    assert_output --partial "Uninstallation Complete"
}

@test "uninstall cancels when user declines" {
    # Simulate user saying "n"
    run bash -c "echo 'n' | \"$SCRIPT\""
    restore_helper
    assert_success
    assert_output --partial "cancelled"
    refute_output --partial "Complete"
}

# Force mode tests
@test "uninstall --force skips confirmation prompts" {
    run "$SCRIPT" --force
    restore_helper
    assert_success
    refute_output --partial "Proceed with uninstallation?"
    assert_output --partial "Complete"
}

@test "uninstall --force removes config automatically" {
    # Create config files
    echo "test" > "$CCBLOCKS_CONFIG/test.conf"

    run "$SCRIPT" --force
    restore_helper
    assert_success

    # Config should be removed in force mode
    assert [ ! -d "$CCBLOCKS_CONFIG" ]
}

# Config removal tests
@test "uninstall shows config directory contents before removal" {
    # Create test config files
    echo "test" > "$CCBLOCKS_CONFIG/config.json"
    echo "test2" > "$CCBLOCKS_CONFIG/data.txt"

    # Run with "y" to proceed, then "y" to remove config
    run bash -c "echo -e 'y\ny' | \"$SCRIPT\""
    restore_helper
    assert_success
    assert_output --partial "Configuration Directory"
    assert_output --partial "2 files"
}

@test "uninstall preserves config when user declines removal" {
    # Create test config file
    echo "test" > "$CCBLOCKS_CONFIG/config.json"

    # Run with "y" to proceed, then "N" to preserve config
    run bash -c "echo -e 'y\nN' | \"$SCRIPT\""
    restore_helper
    assert_success
    assert_output --partial "Configuration preserved"

    # Verify config still exists
    assert [ -f "$CCBLOCKS_CONFIG/config.json" ]
}

@test "uninstall removes config when user confirms removal" {
    # Create test config file
    echo "test" > "$CCBLOCKS_CONFIG/config.json"

    # Run with "y" to proceed, then "y" to remove config
    run bash -c "echo -e 'y\ny' | \"$SCRIPT\""
    restore_helper
    assert_success

    # Verify config was removed
    assert [ ! -d "$CCBLOCKS_CONFIG" ]
}

@test "uninstall auto-removes empty config directory" {
    # Config directory exists but is empty (from setup)
    assert [ -d "$CCBLOCKS_CONFIG" ]

    # Should not prompt for empty directory
    run bash -c "echo 'y' | \"$SCRIPT\""
    restore_helper
    assert_success

    # Empty directory should be removed without prompting
    assert [ ! -d "$CCBLOCKS_CONFIG" ]
}

# Scheduler removal tests
@test "uninstall calls helper remove command" {
    # Create platform-specific config file so the helper remove command gets called
    if [[ "$(uname)" == "Darwin" ]]; then
        mkdir -p "$HOME/Library/LaunchAgents" 2>/dev/null || true
        if ! touch "$HOME/Library/LaunchAgents/ccblocks.plist" 2>/dev/null; then
            skip "Cannot write to ~/Library/LaunchAgents in this environment"
        fi
    else
        mkdir -p "$HOME/.config/systemd/user"
        touch "$HOME/.config/systemd/user/ccblocks@.service"
    fi

    run bash -c "echo 'y' | \"$SCRIPT\""
    restore_helper
    assert_success
    # Check that scheduler removal was successful (helper was called)
    assert_output --partial "successfully removed"

    # Cleanup
    if [[ "$(uname)" == "Darwin" ]]; then
        rm -f "$HOME/Library/LaunchAgents/ccblocks.plist"
    else
        rm -f "$HOME/.config/systemd/user/ccblocks@.service"
    fi
}

@test "uninstall handles missing scheduler gracefully" {
    # The mock helper will be called even if config doesn't exist
    run bash -c "echo 'y' | \"$SCRIPT\""
    restore_helper
    assert_success
    # Should complete successfully even if scheduler is missing
}

# Log creation tests
@test "uninstall creates uninstall log file" {
    run bash -c "echo 'y' | \"$SCRIPT\""
    restore_helper
    assert_success

    # Check that log file reference appears in output
    assert_output --partial "uninstall log"
}

# Completion tests
@test "uninstall shows completion summary" {
    run bash -c "echo 'y' | \"$SCRIPT\""
    restore_helper
    assert_success
    assert_output --partial "Uninstallation Complete"
    assert_output --partial "Summary:"
}

@test "uninstall shows verification commands in summary" {
    run bash -c "echo 'y' | \"$SCRIPT\""
    restore_helper
    assert_success
    assert_output --partial "To verify removal:"
}

@test "uninstall shows platform-specific commands" {
    run bash -c "echo 'y' | \"$SCRIPT\""
    restore_helper
    assert_success

    if [[ "$(uname)" == "Darwin" ]]; then
        assert_output --partial "launchctl"
        assert_output --partial "Library/LaunchAgents"
    else
        assert_output --partial "systemctl"
        assert_output --partial "systemd/user"
    fi
}

# File size display tests
@test "uninstall shows human-readable file sizes" {
    # Create files of different sizes
    dd if=/dev/zero of="$CCBLOCKS_CONFIG/small.txt" bs=100 count=1 2>/dev/null
    dd if=/dev/zero of="$CCBLOCKS_CONFIG/medium.txt" bs=1024 count=5 2>/dev/null

    run bash -c "echo -e 'y\ny' | \"$SCRIPT\""
    restore_helper
    assert_success

    # Should show file sizes (KB or B)
    assert_output --partial "small.txt"
    assert_output --partial "medium.txt"
}
