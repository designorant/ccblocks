#!/usr/bin/env bats

# Tests for error scenarios and edge cases
# Tests error handling across ccblocks components

load test_helper

setup() {
    setup_test_dir
}

teardown() {
    # Restore helper files if they were mocked
    restore_helper_for_status 2>/dev/null || true
    restore_helper_for_uninstall 2>/dev/null || true

    # Clean up symlink created for lib sourcing
    if [ -L "${TEST_TEMP_DIR}/../lib" ]; then
        rm -f "${TEST_TEMP_DIR}/../lib"
    fi
    teardown_test_dir
}

# OS detection error tests
@test "common.sh detect_os fails on unsupported OS" {
    # Create a test script that sources common.sh
    cat > "${TEST_TEMP_DIR}/test_os_detect.sh" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mock uname to return unsupported OS
uname() {
    echo "FreeBSD"
}
export -f uname

source "${SCRIPT_DIR}/../lib/common.sh"
detect_os
EOF
    chmod +x "${TEST_TEMP_DIR}/test_os_detect.sh"

    # Link to lib directory for sourcing
    ln -s "${PROJECT_ROOT}/lib" "${TEST_TEMP_DIR}/../lib" 2>/dev/null || true

    run "${TEST_TEMP_DIR}/test_os_detect.sh"
    assert_failure
    assert_output --partial "Unsupported OS"
}

# Helper initialization error tests
@test "common.sh init_os_vars fails when OS_TYPE not set" {
    cat > "${TEST_TEMP_DIR}/test_init_no_os.sh" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Don't call detect_os, so OS_TYPE is not set
unset OS_TYPE
init_os_vars "$SCRIPT_DIR"
EOF
    chmod +x "${TEST_TEMP_DIR}/test_init_no_os.sh"

    ln -s "${PROJECT_ROOT}/lib" "${TEST_TEMP_DIR}/../lib" 2>/dev/null || true

    run "${TEST_TEMP_DIR}/test_init_no_os.sh"
    assert_failure
    assert_output --partial "OS_TYPE not set"
}

@test "common.sh init_os_vars fails when script_dir parameter missing" {
    cat > "${TEST_TEMP_DIR}/test_init_no_param.sh" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Set OS_TYPE but don't pass script_dir parameter
export OS_TYPE="Darwin"
init_os_vars
EOF
    chmod +x "${TEST_TEMP_DIR}/test_init_no_param.sh"

    ln -s "${PROJECT_ROOT}/lib" "${TEST_TEMP_DIR}/../lib" 2>/dev/null || true

    run "${TEST_TEMP_DIR}/test_init_no_param.sh"
    assert_failure
    assert_output --partial "script_dir parameter required"
}

# Timeout fallback tests
@test "common.sh run_with_timeout falls back to perl when timeout unavailable" {
    cat > "${TEST_TEMP_DIR}/test_timeout_perl.sh" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Mock timeout/gtimeout as not available
command_exists() {
    case "$1" in
        timeout|gtimeout) return 1 ;;
        perl) return 0 ;;
        *) command -v "$1" >/dev/null 2>&1 ;;
    esac
}
export -f command_exists

# Ensure TIMEOUT_CMD is empty
TIMEOUT_CMD=""

# Test that perl fallback works
run_with_timeout 1 echo "perl fallback works"
EOF
    chmod +x "${TEST_TEMP_DIR}/test_timeout_perl.sh"

    ln -s "${PROJECT_ROOT}/lib" "${TEST_TEMP_DIR}/../lib" 2>/dev/null || true

    run "${TEST_TEMP_DIR}/test_timeout_perl.sh"
    assert_success
    assert_output --partial "perl fallback works"
}

@test "common.sh run_with_timeout falls back to python3 when perl unavailable" {
    cat > "${TEST_TEMP_DIR}/test_timeout_python.sh" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Mock timeout/gtimeout/perl as not available
command_exists() {
    case "$1" in
        timeout|gtimeout|perl) return 1 ;;
        python3) return 0 ;;
        *) command -v "$1" >/dev/null 2>&1 ;;
    esac
}
export -f command_exists

# Ensure TIMEOUT_CMD is empty
TIMEOUT_CMD=""

# Test that python3 fallback works
run_with_timeout 1 echo "python3 fallback works"
EOF
    chmod +x "${TEST_TEMP_DIR}/test_timeout_python.sh"

    ln -s "${PROJECT_ROOT}/lib" "${TEST_TEMP_DIR}/../lib" 2>/dev/null || true

    run "${TEST_TEMP_DIR}/test_timeout_python.sh"
    assert_success
    assert_output --partial "python3 fallback works"
}

@test "common.sh run_with_timeout runs without timeout when no utility available" {
    cat > "${TEST_TEMP_DIR}/test_timeout_none.sh" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Mock all timeout utilities as unavailable
command_exists() {
    case "$1" in
        timeout|gtimeout|perl|python3) return 1 ;;
        *) command -v "$1" >/dev/null 2>&1 ;;
    esac
}
export -f command_exists

# Ensure TIMEOUT_CMD is empty
TIMEOUT_CMD=""

# Test that command runs without timeout
run_with_timeout 1 echo "no timeout available"
EOF
    chmod +x "${TEST_TEMP_DIR}/test_timeout_none.sh"

    ln -s "${PROJECT_ROOT}/lib" "${TEST_TEMP_DIR}/../lib" 2>/dev/null || true

    run "${TEST_TEMP_DIR}/test_timeout_none.sh"
    assert_success
    assert_output --partial "no timeout available"
    # Should also show warning about no timeout utility
}

# Empty/missing file scenarios
@test "check-status handles empty .last-activity file" {
    export CCBLOCKS_CONFIG="${TEST_TEMP_DIR}/.config/ccblocks"
    mkdir -p "$CCBLOCKS_CONFIG"

    # Create empty activity file
    touch "$CCBLOCKS_CONFIG/.last-activity"

    # Create mock helper
    create_mock_helper_for_status

    run "${PROJECT_ROOT}/bin/status.sh"
    restore_helper_for_status
    assert_success
    # Should handle empty file gracefully
}

# Command not found scenarios
@test "ccblocks-daemon provides helpful error when claude not found" {
    export CCBLOCKS_CONFIG="${TEST_TEMP_DIR}/.config/ccblocks"
    mkdir -p "$CCBLOCKS_CONFIG"

    # Override HOME to empty directory and restrict PATH
    export HOME="${TEST_TEMP_DIR}/fake_home"
    mkdir -p "$HOME"

    PATH="/usr/bin:/bin" run "${PROJECT_ROOT}/libexec/ccblocks-daemon.sh"
    assert_failure
    assert_output --partial "Claude CLI not found"
    assert_output --partial "Tried:"
}

# Invalid input scenarios
@test "ccblocks shows error for empty command" {
    run "${PROJECT_ROOT}/ccblocks" ""
    assert_success
    # Empty command should show help
    assert_output --partial "Usage:"
}

@test "schedule-blocks apply rejects invalid schedule name" {
    run "${PROJECT_ROOT}/bin/schedule.sh" apply invalid-schedule-name
    # Should fail with error or show available schedules
    assert_failure
    # Should mention the invalid schedule or show help
    assert_output --regexp "(invalid|Unknown|available|247|work|night)"
}

# Helper function to create mock helper for check-status tests
create_mock_helper_for_status() {
    local helper_dir="${PROJECT_ROOT}/lib"
    local helper_name

    if [[ "$(uname)" == "Darwin" ]]; then
        helper_name="launchagent-helper.sh"
    else
        helper_name="systemd-helper.sh"
    fi

    if [ -f "${helper_dir}/${helper_name}" ]; then
        cp "${helper_dir}/${helper_name}" "${TEST_TEMP_DIR}/${helper_name}.backup"
    fi

    cat > "${helper_dir}/${helper_name}" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

case "$1" in
    status)
        echo "Mock status output"
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "${helper_dir}/${helper_name}"
}

restore_helper_for_status() {
    local helper_dir="${PROJECT_ROOT}/lib"
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

# Logger failure scenarios
@test "ccblocks-daemon continues when logger fails" {
    export CCBLOCKS_CONFIG="${TEST_TEMP_DIR}/.config/ccblocks"
    mkdir -p "$CCBLOCKS_CONFIG"

    # Create a simple mock claude in a new mock bin directory
    local mock_bin="${TEST_TEMP_DIR}/mock_bin"
    mkdir -p "$mock_bin"
    cat > "$mock_bin/claude" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$mock_bin/claude"

    # Mock logger to fail
    cat > "$mock_bin/logger" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$mock_bin/logger"

    # Run with mocked commands in PATH
    PATH="$mock_bin:$PATH" run "${PROJECT_ROOT}/libexec/ccblocks-daemon.sh"
    # Should still succeed even if logger fails
    assert_success
}

# Filesystem edge cases
@test "uninstall handles config directory with special characters in filenames" {
    export CCBLOCKS_CONFIG="${TEST_TEMP_DIR}/.config/ccblocks"
    mkdir -p "$CCBLOCKS_CONFIG"

    # Create files with special characters
    touch "$CCBLOCKS_CONFIG/file with spaces.conf"
    touch "$CCBLOCKS_CONFIG/file-with-dashes.conf"
    touch "$CCBLOCKS_CONFIG/.hidden-file"

    create_mock_helper_for_uninstall

    # Run with force mode to skip prompts
    run "${PROJECT_ROOT}/bin/uninstall.sh" --force
    restore_helper_for_uninstall

    # Should complete successfully
    assert_success
}

create_mock_helper_for_uninstall() {
    local helper_dir="${PROJECT_ROOT}/lib"
    local helper_name

    if [[ "$(uname)" == "Darwin" ]]; then
        helper_name="launchagent-helper.sh"
    else
        helper_name="systemd-helper.sh"
    fi

    if [ -f "${helper_dir}/${helper_name}" ]; then
        cp "${helper_dir}/${helper_name}" "${TEST_TEMP_DIR}/${helper_name}.backup"
    fi

    cat > "${helper_dir}/${helper_name}" << 'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

case "$1" in
    remove)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
    chmod +x "${helper_dir}/${helper_name}"
}

restore_helper_for_uninstall() {
    local helper_dir="${PROJECT_ROOT}/lib"
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
