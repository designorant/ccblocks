#!/usr/bin/env bash
# Install git hooks for ccblocks development

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

echo "Installing git hooks..."

# Create pre-commit hook
cat >"$HOOKS_DIR/pre-commit" <<'EOF'
#!/usr/bin/env bash
# Pre-commit hook for ccblocks
# Runs linting and tests before allowing commit

set -e

echo "Running pre-commit checks..."

# Run linting
echo "→ Running shellcheck..."
make lint

# Run tests
echo "→ Running tests..."
make test

echo "✓ All checks passed"
EOF

chmod +x "$HOOKS_DIR/pre-commit"

echo "✓ Pre-commit hook installed"
echo ""
echo "To skip hooks on commit (not recommended):"
echo "  git commit --no-verify"
