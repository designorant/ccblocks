#!/usr/bin/env bats

# Meta-tests for the test harness itself.

load test_helper

setup() {
    setup_test_dir
}

teardown() {
    teardown_test_dir
}

@test "teardown_test_dir leaves a pre-existing user config directory alone" {
    fake_home="${TEST_TEMP_DIR}/fake-home"
    mkdir -p "${fake_home}/.config/ccblocks"
    echo "user data" > "${fake_home}/.config/ccblocks/config.json"

    inner_tmp="$(mktemp -d)"
    HOME="$fake_home" TEST_TEMP_DIR="$inner_tmp" teardown_test_dir

    assert [ -f "${fake_home}/.config/ccblocks/config.json" ]
    refute [ -d "$inner_tmp" ]
}

@test "setup_test_dir points CCBLOCKS_CONFIG into the test temp directory" {
    assert [ -n "${CCBLOCKS_CONFIG:-}" ]
    case "$CCBLOCKS_CONFIG" in
    "${TEST_TEMP_DIR}"/*) ;;
    *)
        echo "CCBLOCKS_CONFIG escapes the test sandbox: $CCBLOCKS_CONFIG"
        return 1
        ;;
    esac
}
