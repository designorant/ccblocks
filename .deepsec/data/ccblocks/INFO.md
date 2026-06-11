# ccblocks

## What this codebase does

ccblocks is a Bash CLI for macOS and Linux that schedules tiny Claude CLI
triggers (a fixed one-turn `claude -p --model haiku` prompt) so a user's
5-hour Claude usage windows start at useful times. It installs user-level
schedulers via LaunchAgent or systemd, stores state under
`~/.config/ccblocks`, and has Bats tests for CLI, schedule validation,
setup/status, trigger, and uninstall flows.

## Auth shape

- There is no web auth layer; the trust boundary is the local user account and
  the already-authenticated `claude` CLI available in that user's session.
- `detect_os` and `init_os_vars` choose the platform helper and user-owned
  scheduler paths; callers should run them before helper actions.
- `check_claude_cli`, `command_exists`, and `run_with_timeout` gate external
  command execution for `claude`, `timeout`/`gtimeout`, `ccusage`, and system
  scheduler tools.
- `require_subscription_auth` gates every trigger: it refuses API/provider
  env credentials and verifies `claude auth status --json` reports a
  logged-in first-party subscription before the fixed haiku trigger fires.
- `validate_custom_hours` is the main validation primitive for user-supplied
  schedule hours before `create_plist_custom` or `create_service_custom`.
- `read_schedule_config` and `write_schedule_config` use Python JSON parsing
  for `~/.config/ccblocks/config.json`; avoid replacing that with ad hoc text
  parsing for trusted state.

## Threat model

The highest-impact issue is turning a user-level scheduler into arbitrary
command execution by corrupting generated LaunchAgent/systemd files, PATH, or
the trigger script path. A local attacker or malicious wrapper could also try
to steer writes/removals through `HOME`, `CCBLOCKS_CONFIG`, or scheduler state
paths. Network-facing attacks are out of scope because ccblocks has no server,
API, or browser surface.

## Project-specific patterns to flag

- Generated scheduler files: review any new interpolation into
  `ccblocks.plist`, `ccblocks@.service`, or `ccblocks@.timer`, especially
  `PATH`, `TRIGGER_SCRIPT`, custom hours, and values derived from `HOME`.
- Command execution paths: new `exec`, `systemctl`, `launchctl`, `logger`,
  `claude`, or `ccusage` calls should use fixed command shapes or strict
  whitelists like the main command dispatcher and schedule preset `case` blocks.
- Path-scoped writes/removals: writes should stay under
  `~/Library/LaunchAgents`, `~/.config/systemd/user`, or `CCBLOCKS_CONFIG`;
  uninstall cleanup should not broaden beyond those paths.
- Schedule input: custom hour strings must pass `validate_custom_hours` before
  helper creation; do not duplicate looser validation in platform helpers.
- Install path normalization: Homebrew Cellar paths are intentionally rewritten
  to the stable `opt/ccblocks` symlink before scheduler generation; regressions
  can break upgrades or point schedulers at stale scripts.

## Known false-positives

- `libexec/ccblocks-daemon.sh` intentionally runs the external `claude` CLI and
  optionally `ccusage`; that is the product trigger mechanism, not a bug by
  itself.
- `libexec/lib/launchagent-helper.sh` and `libexec/lib/systemd-helper.sh`
  intentionally write scheduler files with heredocs to user-owned locations.
- `libexec/bin/uninstall.sh` intentionally unloads schedulers and may remove
  `CCBLOCKS_CONFIG`; destructive findings are only meaningful if paths escape
  the documented user-owned locations.
- `tests/*.bats` and `tests/test_helper.bash` intentionally create mock shell
  commands, overwrite helper scripts, and remove temp/config directories.
- `.deepsec/` is scanner configuration and generated scan state, not ccblocks
  runtime code.
