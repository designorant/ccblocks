#!/usr/bin/env bats

# Tests for Homebrew installation structure
# Verifies that the daemon can find its dependencies when installed via Homebrew

load test_helper

setup() {
    setup_test_dir

    # Create a mock Homebrew prefix structure
    BREW_PREFIX="${TEST_TEMP_DIR}/homebrew/opt/ccblocks"
    mkdir -p "${BREW_PREFIX}/bin"
    mkdir -p "${BREW_PREFIX}/lib"
    mkdir -p "${BREW_PREFIX}/libexec/bin"

    export BREW_PREFIX
}

teardown() {
    teardown_test_dir
}

# Simulate Homebrew installation structure
simulate_homebrew_install() {
    # Copy lib to prefix root (as formula should do)
    cp -r "${PROJECT_ROOT}/lib" "${BREW_PREFIX}/"

    # Copy daemon to libexec
    cp "${PROJECT_ROOT}/libexec/ccblocks-daemon.sh" "${BREW_PREFIX}/libexec/"

    # Copy helper scripts to libexec/bin
    cp -r "${PROJECT_ROOT}/bin" "${BREW_PREFIX}/libexec/"

    # Copy VERSION
    cp "${PROJECT_ROOT}/VERSION" "${BREW_PREFIX}/libexec/"
}

@test "homebrew-structure: daemon can source common.sh from ../lib" {
    simulate_homebrew_install

    # Verify lib is at prefix root
    assert [ -f "${BREW_PREFIX}/lib/common.sh" ]

    # Verify daemon is in libexec
    assert [ -f "${BREW_PREFIX}/libexec/ccblocks-daemon.sh" ]

    # Test that daemon can find ../lib/common.sh
    cd "${BREW_PREFIX}/libexec"
    run bash -c 'SCRIPT_DIR="$(pwd)"; source "$SCRIPT_DIR/../lib/common.sh" && echo "success"'
    assert_success
    assert_output --partial "success"
}

@test "homebrew-structure: lib directory exists at correct location" {
    simulate_homebrew_install

    # lib should be at prefix root, not in libexec
    assert [ -d "${BREW_PREFIX}/lib" ]
    assert [ ! -d "${BREW_PREFIX}/libexec/lib" ]
}

@test "homebrew-structure: all required lib files are accessible" {
    simulate_homebrew_install

    # Check all lib files exist at ../lib relative to daemon
    local daemon_dir="${BREW_PREFIX}/libexec"
    assert [ -f "${daemon_dir}/../lib/common.sh" ]
    assert [ -f "${daemon_dir}/../lib/launchagent-helper.sh" ]
    assert [ -f "${daemon_dir}/../lib/systemd-helper.sh" ]
}

@test "homebrew-structure: daemon script path resolution works" {
    simulate_homebrew_install

    # Simulate what daemon does: get SCRIPT_DIR and source common.sh
    cd "${BREW_PREFIX}/libexec"
    run bash -c '
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$SCRIPT_DIR/../lib/common.sh" ]; then
            echo "found"
        else
            echo "not found: $SCRIPT_DIR/../lib/common.sh"
            exit 1
        fi
    '
    assert_success
    assert_output "found"
}

@test "homebrew-structure: daemon can actually execute with mocked claude" {
    simulate_homebrew_install

    # Mock claude CLI
    mock_claude_success

    # Override config directory
    export CCBLOCKS_CONFIG="${TEST_TEMP_DIR}/.config/ccblocks"
    mkdir -p "$CCBLOCKS_CONFIG"

    # Run daemon from its installed location
    run "${BREW_PREFIX}/libexec/ccblocks-daemon.sh"
    assert_success

    # Verify it created activity file
    assert [ -f "$CCBLOCKS_CONFIG/.last-activity" ]
}

@test "homebrew-structure: incorrect structure fails correctly" {
    # Create fresh test environment without calling simulate_homebrew_install
    # Deliberately install lib in wrong location (inside libexec)
    rm -rf "${BREW_PREFIX}/lib"  # Remove if exists from previous tests
    cp -r "${PROJECT_ROOT}/lib" "${BREW_PREFIX}/libexec/"
    cp "${PROJECT_ROOT}/libexec/ccblocks-daemon.sh" "${BREW_PREFIX}/libexec/"

    # lib should NOT be at prefix root in this test
    assert [ ! -d "${BREW_PREFIX}/lib" ]
    assert [ -d "${BREW_PREFIX}/libexec/lib" ]

    # daemon should fail to find ../lib/common.sh
    cd "${BREW_PREFIX}/libexec"
    run bash -c 'SCRIPT_DIR="$(pwd)"; source "$SCRIPT_DIR/../lib/common.sh" 2>&1'
    assert_failure
    assert_output --partial "No such file or directory"
}
