#!/usr/bin/env bats

# Tests for lib/common.sh - Config management and validation

load test_helper

setup() {
    setup_test_dir
    export SCRIPT_DIR="$PROJECT_ROOT"

    # Override config directory to test directory
    export CCBLOCKS_CONFIG="${TEST_TEMP_DIR}/.config/ccblocks"
    mkdir -p "$CCBLOCKS_CONFIG"

    # Source common library
    source "$PROJECT_LIB_DIR/common.sh"
}

teardown() {
    teardown_test_dir
}

# validate_custom_hours tests

@test "validate_custom_hours: accepts valid 4-trigger schedule" {
    run validate_custom_hours "0,6,12,18"
    assert_success
}

@test "validate_custom_hours: accepts valid 2-trigger schedule" {
    run validate_custom_hours "9,14"
    assert_success
}

@test "validate_custom_hours: accepts valid 3-trigger schedule" {
    run validate_custom_hours "0,8,16"
    assert_success
}

@test "validate_custom_hours: accepts hours with spaces" {
    run validate_custom_hours "0, 6, 12, 18"
    assert_success
}

@test "validate_custom_hours: rejects more than 4 triggers" {
    run validate_custom_hours "0,5,10,15,20"
    assert_failure
    assert_output --partial "Maximum 4 triggers"
}

@test "validate_custom_hours: rejects single trigger" {
    run validate_custom_hours "12"
    assert_failure
    assert_output --partial "At least 2 triggers required"
}

@test "validate_custom_hours: rejects hour out of range (negative)" {
    run validate_custom_hours "-1,6,12,18"
    assert_failure
    assert_output --partial "Invalid hour"
}

@test "validate_custom_hours: rejects hour out of range (>23)" {
    run validate_custom_hours "0,6,12,24"
    assert_failure
    assert_output --partial "Invalid hour: 24"
}

@test "validate_custom_hours: rejects non-numeric input" {
    run validate_custom_hours "0,abc,12,18"
    assert_failure
    assert_output --partial "Invalid hour"
}

@test "validate_custom_hours: rejects duplicate hours" {
    run validate_custom_hours "0,6,6,12"
    assert_failure
    assert_output --partial "Duplicate hour: 6"
}

@test "validate_custom_hours: rejects spacing < 5 hours" {
    run validate_custom_hours "0,4,8,12"
    assert_failure
    assert_output --partial "Insufficient spacing"
    assert_output --partial "4h"
}

@test "validate_custom_hours: rejects spacing < 5 hours (consecutive)" {
    run validate_custom_hours "0,6,9,15"
    assert_failure
    assert_output --partial "Insufficient spacing"
    assert_output --partial "3h"
}

@test "validate_custom_hours: rejects wraparound spacing < 5 hours" {
    run validate_custom_hours "0,6,12,22"
    assert_failure
    assert_output --partial "Insufficient spacing"
    assert_output --partial "next day"
}

@test "validate_custom_hours: accepts exactly 5-hour spacing" {
    run validate_custom_hours "0,5,10,15"
    assert_success
}

# calculate_coverage tests

@test "calculate_coverage: calculates 4-trigger coverage correctly" {
    run calculate_coverage "0,6,12,18"
    assert_success
    assert_output --partial "coverage=20"
    assert_output --partial "gaps=4"
}

@test "calculate_coverage: calculates 2-trigger coverage correctly" {
    run calculate_coverage "9,14"
    assert_success
    assert_output --partial "coverage=10"
    assert_output --partial "gaps=14"
}

@test "calculate_coverage: calculates 3-trigger coverage correctly" {
    run calculate_coverage "0,8,16"
    assert_success
    assert_output --partial "coverage=15"
    assert_output --partial "gaps=9"
}

# write_schedule_config and read_schedule_config tests

@test "write_schedule_config: creates preset config" {
    run write_schedule_config "preset" "247"
    assert_success

    # Verify file was created
    [[ -f "$CCBLOCKS_CONFIG/config.json" ]]

    # Verify content
    run cat "$CCBLOCKS_CONFIG/config.json"
    assert_output --partial '"type": "preset"'
    assert_output --partial '"preset": "247"'
}

@test "write_schedule_config: creates custom config" {
    run write_schedule_config "custom" "" "0,6,12,18"
    assert_success

    # Verify file was created
    [[ -f "$CCBLOCKS_CONFIG/config.json" ]]

    # Verify content
    run cat "$CCBLOCKS_CONFIG/config.json"
    assert_output --partial '"type": "custom"'
    assert_output --partial '"custom_hours"'
    assert_output --partial '"coverage_hours": 20'
}

@test "read_schedule_config: reads preset config" {
    write_schedule_config "preset" "work"

    run read_schedule_config
    assert_success
    assert_output --partial "type=preset"
    assert_output --partial "preset=work"
}

@test "read_schedule_config: reads custom config" {
    write_schedule_config "custom" "" "0,6,12,18"

    run read_schedule_config
    assert_success
    assert_output --partial "type=custom"
    assert_output --partial "custom_hours=0,6,12,18"
    assert_output --partial "coverage_hours=20"
}

@test "read_schedule_config: returns error if config doesn't exist" {
    run read_schedule_config
    assert_failure
}

@test "write_schedule_config: sorts custom hours" {
    run write_schedule_config "custom" "" "18,0,12,6"
    assert_success

    run read_schedule_config
    assert_output --partial "custom_hours=0,6,12,18"
}
