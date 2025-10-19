# ccblocks

[![CI](https://github.com/designorant/ccblocks/actions/workflows/test.yml/badge.svg)](https://github.com/designorant/ccblocks/actions/workflows/test.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)](README.md#platform-support)

```sh
░░      ░░░      ░░       ░░  ░░░░░░░      ░░░      ░░  ░░░░  ░░      ░░
▒  ▒▒▒▒  ▒  ▒▒▒▒  ▒  ▒▒▒▒  ▒  ▒▒▒▒▒▒  ▒▒▒▒  ▒  ▒▒▒▒  ▒  ▒▒▒  ▒▒  ▒▒▒▒▒▒▒
▓  ▓▓▓▓▓▓▓  ▓▓▓▓▓▓▓       ▓▓  ▓▓▓▓▓▓  ▓▓▓▓  ▓  ▓▓▓▓▓▓▓     ▓▓▓▓▓      ▓▓
█  ████  █  ████  █  ████  █  ██████  ████  █  ████  █  ███  ████████  █
██      ███      ██       ██       ██      ███      ██  ████  ██      ██
```

Time-shift Claude sessions to match your working hours

---

## How It Works

**Simple concept:**
- Scheduled trigger: `printf '.' | claude`
- Starts new 5-hour block automatically
- Runs in your user session with full authentication
- Zero maintenance after setup

**Example:**
- **Without ccblocks:** Start coding at 9 AM → hit limits at 10 AM → locked out until 2 PM
- **With ccblocks:** Trigger at 6 AM → start coding at 9 AM → spans multiple blocks → more headroom

**Token cost:** ~44-84 tokens/day

## Understanding the 5-Hour Block System

**Each Claude trigger starts a 5-hour usage window.** This is the fundamental constraint that shapes optimal scheduling:

- **Maximum useful triggers: 4 per day** (24h ÷ 5h = 4.8)
- **Minimum spacing: 5 hours** between triggers
- **Optimal coverage: 20 hours/day** with 4 strategically-placed triggers

**Why not more triggers?** Triggers within an active 5-hour window don't start new blocks—they're wasted. A 5th trigger would overlap an existing window without extending coverage.

**Visualising the 247 Max schedule (optimal):**
```
00:00 ━━━━━ 05:00 (gap) 06:00 ━━━━━ 11:00 (gap) 12:00 ━━━━━ 17:00 (gap) 18:00 ━━━━━ 23:00 (gap)
      5h                      5h                      5h                      5h
```
**Result:** 20 hours of coverage with 4 hours of strategic gaps (5-6 AM, 11 AM-12 PM, 5-6 PM, 11 PM-12 AM).

**Key insight:** More triggers ≠ more coverage. Strategic placement maximises available hours while respecting the 5-hour window constraint.

**Important:** If you use Claude during a scheduled gap, you'll immediately trigger a new 5-hour block regardless of your ccblocks schedule. This is why it's best to align your schedule with your daily routine: plan gaps during lunch, gym, meetings, or quiet time when you won't be coding.

## Quick Start

```bash
# Install via Homebrew
brew install designorant/tap/ccblocks

# Run setup
ccblocks setup
```

**Platform Support:** macOS and Linux only. Windows is not currently supported ([contribute!](https://github.com/designorant/ccblocks/issues)).

## Schedules

**247 Maximum Coverage** (Recommended)
```
Triggers: 12 AM, 6 AM, 12 PM, 6 PM daily (4 triggers)
Coverage: 20 hours/day (optimal)
Gaps: 5-6 AM, 11 AM-12 PM, 5-6 PM, 11 PM-12 AM (4h total)
```

**Work Hours Only**
```
Triggers: 9 AM, 2 PM on weekdays (2 triggers)
Coverage: 10 hours/day (9 AM - 7 PM)
Gaps: 7 PM - 9 AM (14h)
```

**Night Owl**
```
Triggers: 6 PM, 11 PM daily (2 triggers)
Coverage: 10 hours/day (6 PM - 4 AM)
Gaps: 4 AM - 6 PM (14h)
```

## Commands

```bash
ccblocks setup                         # Install and configure
ccblocks status                        # Show schedule and recent activity
ccblocks schedule list                 # List available schedules
ccblocks schedule apply <name>         # Apply preset schedule (247, work, night)
ccblocks schedule apply custom         # Interactive custom schedule
ccblocks schedule apply custom 0,8,16  # Custom schedule with hours
ccblocks pause                         # Vacation mode
ccblocks resume                        # Resume after vacation
ccblocks uninstall                     # Complete removal
```

## FAQ

**Does this bypass Claude's rate limits?**
No. Your subscription limits still apply. This optimizes *when* your 5-hour windows start.

**How much does this cost in tokens?**
Each trigger sends 1 token and receives ~10-20 tokens. At 4 triggers/day ≈ 44-84 tokens/day.

**Can I customise the schedule?**
Yes! See [Configuration](#configuration) for preset schedules and custom schedule options.

**Why not just use cron or a bash loop?**

You *can* - many users successfully schedule triggers with:
- **Cron**: Simple, but limited logging and error handling
- **Bash loop**: Works in tmux/screen, but manual recovery if it dies

ccblocks provides:
- **Reliability**: Automatic restart, survives reboots
- **Management**: Easy schedule changes, pause/resume, status monitoring
- **Best practices**: OS-native service managers (LaunchAgent/systemd)
- **Observability**: System logs, failure notifications

## Technical Details

**Architecture:**
- **macOS**: LaunchAgent (`~/Library/LaunchAgents/ccblocks.plist`)
- **Linux**: systemd user service (`~/.config/systemd/user/ccblocks@.service`)

**Trigger mechanism:**
1. LaunchAgent/systemd timer fires at scheduled time
2. Executes `ccblocks-daemon` in your user session
3. Runs `printf '.' | claude`
4. New 5-hour block starts immediately
5. Logs success/failure to system log

## Status & Monitoring

```bash
# Check scheduler status
ccblocks status

# View system logs
log show --predicate 'process == "ccblocks"' --last 1d    # macOS
journalctl --user -t ccblocks -n 50                       # Linux

# Manual test trigger
ccblocks trigger
```

## Configuration

**Change schedule:**

See [Schedules](#schedules) for available presets (247, work, night).

```bash
ccblocks schedule apply <name>             # Apply preset schedule
ccblocks schedule apply custom             # Interactive custom schedule
ccblocks schedule apply custom 0,8,16      # Custom with specified hours
```

**Custom schedule examples:**
- `0,8,16` → 15 hours/day coverage (midnight, 8 AM, 4 PM)
- `9,15,21` → 15 hours/day coverage (9 AM, 3 PM, 9 PM)
- `0,12` → 10 hours/day coverage (midnight, noon)
- `0,6,12,18` → 20 hours/day coverage (optimal 4 triggers)

**Validation rules:**
- Minimum 2 triggers, maximum 4 triggers per day
- Triggers must be ≥5 hours apart (Claude's block duration)
- Hours in 24-hour format (0-23)

**Vacation mode:**
```bash
ccblocks pause    # Disable all triggers
ccblocks resume   # Re-enable schedule
```

Your schedule is preserved when paused.

## Troubleshooting

**Scheduler not running:**

macOS:
```bash
launchctl list | grep ccblocks           # Should show loaded
ls ~/Library/LaunchAgents/ccblocks.plist # Should exist
ccblocks status                          # Check detailed status
```

Linux:
```bash
systemctl --user list-timers | grep ccblocks # Should show active
systemctl --user daemon-reload               # Reload if needed
ccblocks status                              # Check detailed status
```

**Claude CLI issues:**
```bash
which claude          # Verify installation
echo "test" | claude  # Test authentication
```

ccblocks requires Claude CLI to be installed and authenticated.

**Logs and configuration:**
- Config directory: `~/.config/ccblocks/`
- macOS logs: Use `log show` (see Status & Monitoring above)
- Linux logs: Use `journalctl` (see Status & Monitoring above)

## Uninstallation

Homebrew automatically removes schedulers when uninstalling:

```bash
# Uninstall package (automatically cleans up schedulers)
brew uninstall ccblocks

# Optional: Remove user configuration
rm -rf ~/.config/ccblocks
```

## Getting Help

- **Questions**: Ask in [GitHub Discussions](https://github.com/designorant/ccblocks/discussions)
- **Issues**: Report bugs on [GitHub Issues](https://github.com/designorant/ccblocks/issues)
- **Contact**: [@designorant on X](https://x.com/designorant) or [@designorant.com on BlueSky](https://bsky.app/profile/designorant.com)

## Contributing

Contributions are welcome! For local development, testing, and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache-2.0](LICENSE) © [@designorant](https://github.com/designorant)
