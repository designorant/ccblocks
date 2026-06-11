#!/usr/bin/env bats

# Static checks for GitHub Actions workflow security invariants.

load test_helper

setup() {
	setup_test_dir
	TEST_WORKFLOW="${PROJECT_ROOT}/.github/workflows/test.yml"
	PUBLISH_WORKFLOW="${PROJECT_ROOT}/.github/workflows/publish.yml"
}

teardown() {
	teardown_test_dir
}

@test "test workflow uses least-privilege read permissions" {
	run grep -Eq '^permissions:[[:space:]]*\{\}[[:space:]]*$|^permissions:[[:space:]]*$' "$TEST_WORKFLOW"
	assert_success

	run grep -Eq '^[[:space:]]+contents:[[:space:]]+read[[:space:]]*$' "$TEST_WORKFLOW"
	assert_success
}

@test "workflows do not expose untrusted event text in run names" {
	run grep -R "github.event.*message\\|github.event.*title" "${PROJECT_ROOT}/.github/workflows"
	assert_failure
}

@test "workflow actions are pinned to commit SHAs" {
	run grep -RhoE 'uses:[[:space:]]+[^[:space:]]+@[A-Za-z0-9._/-]+' "${PROJECT_ROOT}/.github/workflows"
	assert_success

	while IFS= read -r uses_line; do
		ref="${uses_line##*@}"
		[[ "$ref" =~ ^[0-9a-f]{40}$ ]] || {
			echo "Mutable action ref: $uses_line"
			return 1
		}
	done <<<"$output"
}

@test "test workflow pins and verifies the Homebrew installer" {
	run grep -Eq 'raw.githubusercontent.com/Homebrew/install/[0-9a-f]{40}/install\.sh' "$TEST_WORKFLOW"
	assert_success

	run grep -Eq 'sha256sum[[:space:]]+-c' "$TEST_WORKFLOW"
	assert_success
}

@test "publish workflow only runs for successful push-triggered test runs" {
	run grep -F "github.event.workflow_run.conclusion == 'success'" "$PUBLISH_WORKFLOW"
	assert_success

	run grep -F "github.event.workflow_run.event == 'push'" "$PUBLISH_WORKFLOW"
	assert_success
}

@test "publish workflow checks out the tested commit in privileged jobs" {
	run grep -F 'ref: ${{ github.event.workflow_run.head_sha }}' "$PUBLISH_WORKFLOW"
	assert_success
	assert_line --index 0 --partial 'ref: ${{ github.event.workflow_run.head_sha }}'
	assert_line --index 1 --partial 'ref: ${{ github.event.workflow_run.head_sha }}'
}

@test "publish workflow validates VERSION before publishing" {
	run grep -Eq '^[[:space:]]+VERSION_REGEX=' "$PUBLISH_WORKFLOW"
	assert_success

	run grep -Eq 'Version must match' "$PUBLISH_WORKFLOW"
	assert_success
}

@test "publish workflow does not inline version outputs inside shell scripts" {
	run grep -nE 'run:[[:space:]]*\||run:[[:space:]]*$' "$PUBLISH_WORKFLOW"
	assert_success

	run grep -nF '${{ needs.validate.outputs.version }}' "$PUBLISH_WORKFLOW"
	assert_success

	while IFS= read -r expression_line; do
		line_no="${expression_line%%:*}"
		[ "$line_no" -le 1 ] && continue
		start_line=$(((line_no > 5) ? line_no - 5 : 1))
		previous_five="$(sed -n "${start_line},$((line_no - 1))p" "$PUBLISH_WORKFLOW")"
		if echo "$previous_five" | grep -Eq 'run:[[:space:]]*\||run:[[:space:]]*$'; then
			echo "Version output is inlined in a shell run block at line $line_no"
			return 1
		fi
	done <<<"$output"
}
