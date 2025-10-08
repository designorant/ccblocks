# Contributing to ccblocks

Thank you for your interest in contributing to ccblocks! This guide will help you get started with local development.

## Getting Started

```bash
# Clone the repository
git clone git@github.com:designorant/ccblocks.git
cd ccblocks

# Install development dependencies (bats-core, bats-support, bats-assert, shellcheck, shfmt)
make install-deps

# Install git hooks (optional but recommended)
bash dev/install-hooks.sh
```

## Local Testing

### Testing Without Installation

The simplest way to test ccblocks locally is to run it directly from the repository:

```bash
# From project directory
./ccblocks status

# Test other commands
./ccblocks --version
./ccblocks help
```

### Testing with Homebrew

To test the actual Homebrew installation experience from your tap:

```bash
# Test from your tap
brew install --HEAD designorant/tap/ccblocks

# After making changes, reinstall
brew reinstall --HEAD designorant/tap/ccblocks
```

### Development Workflow

1. **Make changes** to the code
2. **Test directly** with `./ccblocks <command>`
3. **Run tests** to verify functionality with `make test`
4. **Commit** your changes

### Testing Installation Paths

If you need to test installation paths (for Homebrew):

```bash
# Check where Homebrew would install
brew --prefix

# The formula installs to:
# - bin/ccblocks → $(brew --prefix)/bin/ccblocks
# - Supporting files → $(brew --prefix)/Cellar/ccblocks/VERSION/libexec/
```

## Running Tests

ccblocks uses [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System) for testing.

```bash
# Run all tests
make test

# Run specific test file
bats tests/ccblocks.bats        # Test main CLI
bats tests/schedule-blocks.bats # Test schedule management

# Analyse test coverage
bash dev/coverage.sh      # Coverage report for all scripts

# Run shellcheck
make lint
```

### Test Structure

- `tests/ccblocks.bats` - Main CLI interface tests
- `tests/schedule-blocks.bats` - Schedule management and custom schedule tests
- `tests/trigger.bats` - Block trigger integration tests
- `tests/uninstall.bats` - Uninstallation and cleanup tests
- `tests/check-status.bats` - Status reporting tests
- `tests/error-scenarios.bats` - Error handling and edge cases
- `tests/test_helper.bash` - Shared test utilities and platform helpers

**Coverage tool:**
- `dev/coverage.sh` - Analyse test coverage across all scripts
- Run with: `bash dev/coverage.sh`
- Tracks script coverage, test counts, and coverage goals

## Project Structure

```
ccblocks/
├── ccblocks                    # Main CLI entry point
├── bin/                        # Executable scripts
│   ├── setup.sh                # Initial setup script
│   ├── schedule.sh             # Schedule management
│   ├── status.sh               # Status reporting
│   └── uninstall.sh            # Cleanup script
├── libexec/                    # Internal executables
│   └── ccblocks-daemon.sh      # Block trigger logic
├── lib/                        # Shared libraries
│   ├── common.sh               # Shared utilities and functions
│   ├── launchagent-helper.sh   # macOS LaunchAgent management
│   └── systemd-helper.sh       # Linux systemd management
├── dev/                        # Development tools
│   └── coverage.sh             # Test coverage analysis
└── tests/                      # Bats test files
    ├── ccblocks.bats           # Main CLI interface tests
    ├── schedule-blocks.bats    # Schedule management tests
    ├── trigger.bats            # Block trigger tests
    ├── uninstall.bats          # Uninstallation tests
    ├── check-status.bats       # Status reporting tests
    ├── error-scenarios.bats    # Error handling tests
    └── test_helper.bash        # Test utilities and helpers
```

### Key Files

- **ccblocks** - Main CLI dispatcher, routes commands to bin/ scripts
- **bin/setup** - Handles initial installation and configuration
- **bin/schedule** - Manages schedule patterns (247, work, night, custom)
- **libexec/ccblocks-daemon.sh** - Executes the Claude CLI trigger (`printf '.' | claude`)
- **bin/status** - Status dashboard with schedule and activity
- **bin/uninstall** - Safe removal with config preservation options
- **dev/coverage.sh** - Test coverage analysis and reporting tool
- **lib/launchagent-helper.sh** / **lib/systemd-helper.sh** - Platform-specific scheduler management
- **lib/common.sh** - Shared functions for OS detection, logging, error handling, validation

## Code Conventions

### Shell Script Standards

- Use `set -euo pipefail` at the top of all scripts
- Follow existing error handling patterns
- Use `shellcheck` to lint scripts
- Keep functions focused and single-purpose
- Add comments for complex logic

### Naming Conventions

- Functions: `snake_case`
- Variables: `UPPER_CASE` for constants, `lower_case` for locals
- Files: `kebab-case.sh`

### Error Handling

Use the utilities from `lib/common.sh`:

```bash
print_error "Error message"
print_success "Success message"
print_warning "Warning message"
```

## Development Workflow

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow the code conventions
   - Add tests for new functionality
   - Update documentation if needed

3. **Test locally**
   ```bash
   ./ccblocks <your-command>  # Test directly
   make test                  # Run tests
   make lint                  # Run shellcheck
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   ```

   Use conventional commit format:
   - `feat:` - New feature
   - `fix:` - Bug fix
   - `docs:` - Documentation changes
   - `test:` - Test changes
   - `refactor:` - Code refactoring

5. **Push and create a pull request**
   ```bash
   git push origin feature/your-feature-name
   ```

   **Automated CI Checks:**
   - All pull requests automatically run tests on both Ubuntu and macOS
   - Shellcheck linting must pass
   - All 111 tests must pass before merge
   - You can view results in the "Actions" tab of your PR

## Release Process

**For maintainers only.**

Releases are **automated via GitHub Actions** when the VERSION file is updated on the master branch.

### Creating a New Release

1. **Test locally:**
   ```bash
   make test  # Run all tests
   make lint  # Run shellcheck
   ```

2. **Update VERSION file:**
   ```bash
   echo "1.0.1" > VERSION
   git add VERSION
   git commit -m "chore: bump version to 1.0.1"
   ```

3. **Push to master:**
   ```bash
   git push origin master
   ```

4. **Automated steps (GitHub Actions):**
   - ✅ Validates tests and shellcheck pass
   - ✅ Checks if version tag already exists (prevents duplicates)
   - ✅ Creates git tag (e.g., `v1.0.1`)
   - ✅ Generates changelog from commit messages
   - ✅ Creates GitHub Release with notes
   - ✅ Updates Homebrew tap automatically

**Note for maintainers:** The workflow requires a `HOMEBREW_TAP_TOKEN` secret (fine-grained GitHub PAT with write access to `designorant/homebrew-tap`) to be configured in the repository settings.

## Testing Before Submission

Before submitting a pull request, ensure:

- [ ] All tests pass (`make test`)
- [ ] Shellcheck passes (`make lint`)
- [ ] Documentation is updated
- [ ] Commit messages follow conventional format

## Platform-Specific Development

### macOS Development

- Test with LaunchAgent: `launchctl list | grep ccblocks`
- View logs: `log show --predicate 'process == "ccblocks"' --last 1h`
- LaunchAgent plist: `~/Library/LaunchAgents/ccblocks.plist`

### Linux Development

- Test with systemd: `systemctl --user list-timers | grep ccblocks`
- View logs: `journalctl --user -t ccblocks -n 50`
- Service files: `~/.config/systemd/user/ccblocks@*.{service,timer}`

## Getting Help

- **Questions**: Ask in [GitHub Discussions](https://github.com/designorant/ccblocks/discussions)
- **Issues**: Report bugs or request features on [GitHub Issues](https://github.com/designorant/ccblocks/issues)
- **Contact**: [@designorant on X](https://x.com/designorant) or [@designorant.com on BlueSky](https://bsky.app/profile/designorant.com)

## Windows Support

Windows is not currently supported. If you're interested in contributing Windows support (Task Scheduler implementation), please open an issue to discuss the approach.

## License

By contributing to ccblocks, you agree that your contributions will be licensed under the Apache License 2.0.
