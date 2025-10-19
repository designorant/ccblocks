#!/usr/bin/env bash

# ccblocks Test Coverage Analyzer
# Analyzes test coverage across shell scripts

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$PROJECT_ROOT/libexec"
BIN_DIR="$RUNTIME_DIR/bin"
LIB_DIR="$RUNTIME_DIR/lib"

# Detect OS for find compatibility
OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" = "Darwin" ]; then
	PERM_FLAG="+111" # macOS BSD find
else
	PERM_FLAG="/111" # GNU find (Linux)
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
	echo -e "${BLUE}${BOLD}$1${NC}"
}

print_success() {
	echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
	echo -e "${RED}✗${NC} $1"
}

# Count total scripts
count_scripts() {
	local script_count=0
	# Count executables in bin/ (no extension) + helpers in lib/ (.sh extension)
	local bin_count lib_count
	bin_count=$(find "$BIN_DIR" -type f -perm "$PERM_FLAG" ! -name "*.log" | wc -l | tr -d ' ')
	lib_count=$(find "$LIB_DIR" -name "*.sh" -type f | wc -l | tr -d ' ')
	script_count=$((bin_count + lib_count))
	echo "$script_count"
}

# Count total lines of shell code
count_lines() {
	local line_count=0
	# Count lines in bin/ executables and lib/ helpers, excluding comments and blank lines
	line_count=$({
		find "$BIN_DIR" -type f -perm "$PERM_FLAG" ! -name "*.log" -exec cat {} \;
		find "$LIB_DIR" -name "*.sh" -type f -exec cat {} \;
	} | grep -v '^\s*#' | grep -v '^\s*$' | wc -l | tr -d ' ')
	echo "$line_count"
}

# Count total functions defined
count_functions() {
	local func_count=0
	# Find function definitions (name() { or function name {)
	func_count=$({
		find "$BIN_DIR" -type f -perm "$PERM_FLAG" ! -name "*.log" -exec grep -h '^\s*[a-z_][a-z0-9_]*\s*()' {} \;
		find "$LIB_DIR" -name "*.sh" -type f -exec grep -h '^\s*[a-z_][a-z0-9_]*\s*()' {} \;
	} | sed 's/\s*().*$//' | sed 's/^\s*//' | sort -u | wc -l | tr -d ' ')
	echo "$func_count"
}

# List all function names
list_functions() {
	{
		find "$BIN_DIR" -type f -perm "$PERM_FLAG" ! -name "*.log" -exec grep -h '^\s*[a-z_][a-z0-9_]*\s*()' {} \;
		find "$LIB_DIR" -name "*.sh" -type f -exec grep -h '^\s*[a-z_][a-z0-9_]*\s*()' {} \;
	} | sed 's/\s*().*$//' | sed 's/^\s*//' | sort -u
}

# Count test files
count_test_files() {
	local test_count=0
	test_count=$(find "$PROJECT_ROOT/tests" -name "*.bats" -type f | wc -l | tr -d ' ')
	echo "$test_count"
}

# Count total test cases
count_tests() {
	local test_count=0
	test_count=$(find "$PROJECT_ROOT/tests" -name "*.bats" -type f -exec grep -h '@test' {} \; | wc -l | tr -d ' ')
	echo "$test_count"
}

# Analyze which scripts have tests
analyze_script_coverage() {
	local script_name
	local covered=0
	local total=0

	echo ""
	print_header "Script Test Coverage"
	echo "===================="

	# Analyze bin/ executables (no extension)
	while IFS= read -r script; do
		script_name=$(basename "$script")
		total=$((total + 1))

		# Check if there's a corresponding test file
		if [ -f "$PROJECT_ROOT/tests/${script_name}.bats" ]; then
			covered=$((covered + 1))
			print_success "$script_name (tests/${script_name}.bats)"
		else
			print_warning "$script_name (no test file)"
		fi
	done < <(find "$BIN_DIR" -type f -perm "$PERM_FLAG" ! -name "*.log" | sort)

	echo ""
	local coverage_pct=0
	if [ "$total" -gt 0 ]; then
		coverage_pct=$((covered * 100 / total))
	fi

	if [ "$coverage_pct" -ge 80 ]; then
		print_success "Script coverage: $covered/$total ($coverage_pct%)"
	elif [ "$coverage_pct" -ge 60 ]; then
		print_warning "Script coverage: $covered/$total ($coverage_pct%)"
	else
		print_error "Script coverage: $covered/$total ($coverage_pct%)"
	fi
}

# Show coverage summary
show_summary() {
	local scripts
	local lines
	local functions
	local test_files
	local tests

	scripts=$(count_scripts)
	lines=$(count_lines)
	functions=$(count_functions)
	test_files=$(count_test_files)
	tests=$(count_tests)

	echo ""
	print_header "ccblocks Test Coverage Report"
	echo "=============================="
	echo ""

	print_header "Codebase Statistics"
	echo "  Shell scripts:    $scripts files"
	echo "  Lines of code:    $lines (excluding comments/blanks)"
	echo "  Functions:        $functions unique functions"
	echo ""

	print_header "Test Statistics"
	echo "  Test files:       $test_files files"
	echo "  Test cases:       $tests tests"
	echo ""

	# Show average tests per script
	local avg_tests_per_script=0
	if [ "$scripts" -gt 0 ]; then
		avg_tests_per_script=$((tests / scripts))
	fi
	echo "  Avg tests/script: $avg_tests_per_script"
}

# Main coverage analysis
main() {
	show_summary
	analyze_script_coverage

	echo ""
	print_header "Coverage Goals"
	echo "=============="
	local current_tests
	current_tests=$(count_tests)

	local script_count
	script_count=$(count_scripts)

	local target_tests=$((script_count * 10)) # Target: 10 tests per script

	if [ "$current_tests" -ge "$target_tests" ]; then
		print_success "Coverage goal achieved: $current_tests/$target_tests tests"
	else
		local needed=$((target_tests - current_tests))
		print_warning "Coverage goal: $current_tests/$target_tests tests ($needed needed)"
	fi

	echo ""
	print_header "Next Steps"
	echo "=========="
	echo "  1. Maintain >80% script coverage (all bin/* executables have tests)"
	echo "  2. Add integration tests for lib/*.sh helper functions"
	echo "  3. Increase test cases to >10 per script for complex scripts"
	echo "  4. Run 'make test' regularly to verify coverage"
	echo ""
}

# Run main
main
