#!/usr/bin/env bash

# Test helper for ccblocks tests
# Provides mocking utilities and shared setup/teardown

# Load bats-support and bats-assert
# Try multiple locations: Homebrew, system install, or local install
if command -v brew &>/dev/null; then
	BATS_LIB_PREFIX="$(brew --prefix)"
elif [ -d "/usr/local/lib" ]; then
	BATS_LIB_PREFIX="/usr/local"
elif [ -d "/usr/lib" ]; then
	BATS_LIB_PREFIX="/usr"
else
	echo "Error: bats-support and bats-assert not found" >&2
	echo "Install via: make install-deps" >&2
	exit 1
fi

load "${BATS_LIB_PREFIX}/lib/bats-support/load.bash"
load "${BATS_LIB_PREFIX}/lib/bats-assert/load.bash"

# Get the root directory of the project
PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
PROJECT_RUNTIME_DIR="${PROJECT_ROOT}/libexec"
PROJECT_BIN_DIR="${PROJECT_RUNTIME_DIR}/bin"
PROJECT_LIB_DIR="${PROJECT_RUNTIME_DIR}/lib"

# Test-specific temporary directory
setup_test_dir() {
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR
}

teardown_test_dir() {
    if [ -n "${TEST_TEMP_DIR}" ] && [ -d "${TEST_TEMP_DIR}" ]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi

    # Clean up config directory if created during tests
    if [ -d "$HOME/.config/ccblocks" ]; then
        rm -rf "$HOME/.config/ccblocks" 2>/dev/null || true
    fi
}

# Mock commands by creating temporary scripts in PATH
mock_command() {
    local cmd_name="$1"
    local mock_script="$2"

    # Create mock bin directory if it doesn't exist
    if [ -z "${MOCK_BIN_DIR}" ]; then
        MOCK_BIN_DIR="${TEST_TEMP_DIR}/mock_bin"
        mkdir -p "${MOCK_BIN_DIR}"

        # Copy lib directory to mock bin for scripts that need it
        if [ -d "${PROJECT_ROOT}/libexec/lib" ]; then
            cp -r "${PROJECT_ROOT}/libexec/lib" "${MOCK_BIN_DIR}/"
        fi

        export PATH="${MOCK_BIN_DIR}:${PATH}"
    fi

    # Create mock script
    cat > "${MOCK_BIN_DIR}/${cmd_name}" << EOF
#!/usr/bin/env bash
${mock_script}
EOF
    chmod +x "${MOCK_BIN_DIR}/${cmd_name}"
}

# Mock claude command that simulates successful execution
mock_claude_success() {
    mock_command "claude" 'echo "Claude mock: Success"; exit 0'
}

# Mock claude command that fails
mock_claude_failure() {
    mock_command "claude" 'echo "Claude mock: Failed" >&2; exit 1'
}

# Mock claude command with /usage output showing active block
mock_claude_with_active_block() {
    local percent="${1:-50}"
    mock_command "claude" "cat <<'USAGE_EOF'
Current session: ${percent}%
Tokens used: 50000
USAGE_EOF"
}

# Mock claude command with /usage output showing expired block
mock_claude_with_expired_block() {
    mock_command "claude" "cat <<'USAGE_EOF'
Current session: 100%
Session expired
USAGE_EOF"
}

# Mock ccusage command showing active block
mock_ccusage_active_block() {
    mock_command "ccusage" "cat <<'CCUSAGE_EOF'
Block 1 (Current)
Time remaining: 2h 30m
CCUSAGE_EOF"
}

# Mock ccusage command showing no active block
mock_ccusage_no_block() {
    mock_command "ccusage" "echo 'No active blocks'; exit 0"
}

# Mock ccusage not installed
mock_ccusage_not_installed() {
    # Don't create the mock - simulate command not found
    :
}

# Mock ccusage with alternative format (e.g., time format variations)
mock_ccusage_alternative_format() {
    mock_command "ccusage" "cat <<'CCUSAGE_EOF'
Active block
3h 15m remaining
CCUSAGE_EOF"
}

# Mock ccusage with empty output
mock_ccusage_empty_output() {
    mock_command "ccusage" "echo ''; exit 0"
}

# Create a fake activity file with specific timestamp
create_activity_file() {
    local age_seconds="$1"
    local activity_file="${TEST_TEMP_DIR}/.claude-last-activity"

    # Calculate timestamp
    local current_time
    current_time=$(date +%s)
    local activity_time=$((current_time - age_seconds))

    # Create file and set timestamp
    echo "$activity_time" > "$activity_file"

    # On macOS, use touch -t to set modification time
    # On Linux, use touch -d
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch -t "$(date -r "$activity_time" +%Y%m%d%H%M.%S)" "$activity_file" 2>/dev/null || true
    else
        touch -d "@${activity_time}" "$activity_file" 2>/dev/null || true
    fi

    echo "$activity_file"
}

# Mock crontab command
mock_crontab() {
    local crontab_content="$1"

    mock_command "crontab" "
if [ \"\$1\" = '-l' ]; then
    if [ -z '${crontab_content}' ]; then
        echo 'crontab: no crontab for \$(whoami)' >&2
        exit 1
    fi
    cat <<'CRONTAB_EOF'
${crontab_content}
CRONTAB_EOF
    exit 0
elif [ \"\$1\" = '-r' ]; then
    # Remove crontab
    exit 0
else
    # Accept new crontab from stdin
    cat > /dev/null
    exit 0
fi
"
}

# Assert that a file contains a specific pattern
assert_file_contains() {
    local file="$1"
    local pattern="$2"

    assert [ -f "$file" ]
    run grep -q "$pattern" "$file"
    assert_success
}

# Assert that a command is available in PATH
assert_command_exists() {
    local cmd="$1"
    run command -v "$cmd"
    assert_success
}

# Capture and return stderr
run_with_stderr() {
    local stderr_file="${TEST_TEMP_DIR}/stderr.txt"
    "$@" 2> "$stderr_file"
    local exit_code=$?
    STDERR_OUTPUT="$(cat "$stderr_file")"
    return $exit_code
}

# Platform-specific test skip helpers
skip_if_not_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        skip "macOS only test"
    fi
}

skip_if_not_linux() {
    if [[ "$(uname)" != "Linux" ]]; then
        skip "Linux only test"
    fi
}
