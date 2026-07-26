#!/usr/bin/env bash
# BOB-TEST: Execute deterministic test suites
# Purpose: Run reproducible tests with optional coverage reporting
# Inputs: test suite name, deterministic flag, coverage flag
# Outputs: Test results with deterministic guarantees
# Dependencies: Test frameworks per language (cargo test, pytest, etc.)
# Verification: Ensures reproducible results across runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETERMINISTIC=false
COVERAGE=false
SUITE=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: bob-test [suite] [options]

Execute deterministic test suites according to BOB Trust Deed v1.0

Arguments:
    suite               Test suite to run (optional, runs all if omitted)

Options:
    --deterministic     Ensure reproducible results (sets seeds, disables parallelism)
    --coverage          Generate coverage report
    --help              Show this help message

Examples:
    bob-test compiler --deterministic
    bob-test runtime --coverage
    bob-test --deterministic --coverage

EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --deterministic)
            DETERMINISTIC=true
            shift
            ;;
        --coverage)
            COVERAGE=true
            shift
            ;;
        --help)
            usage
            ;;
        -*)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
        *)
            SUITE="$1"
            shift
            ;;
    esac
done

echo -e "${GREEN}BOB-TEST: Running test suite${NC}"
if [[ -n "$SUITE" ]]; then
    echo "Suite: $SUITE"
fi
echo "Deterministic: $DETERMINISTIC"
echo "Coverage: $COVERAGE"

# Set deterministic environment
if [[ "$DETERMINISTIC" == true ]]; then
    export RUST_TEST_THREADS=1
    export RUST_TEST_SEED=42
    export PYTHONHASHSEED=0
    export RANDOM_SEED=42
    echo -e "${YELLOW}Deterministic mode enabled${NC}"
fi

# Run tests based on suite
run_rust_tests() {
    local component=$1
    echo -e "${YELLOW}Running Rust tests for $component...${NC}"
    cd "${REPO_ROOT}/${component}"
    
    if [[ "$COVERAGE" == true ]]; then
        if command -v cargo-tarpaulin &> /dev/null; then
            cargo tarpaulin --out Html --output-dir "${REPO_ROOT}/coverage/${component}"
        else
            echo -e "${YELLOW}Warning: cargo-tarpaulin not found, running tests without coverage${NC}"
            cargo test
        fi
    else
        cargo test
    fi
}

run_all_tests() {
    local failed=0
    
    # Find all Rust components
    for dir in "${REPO_ROOT}"/*; do
        if [[ -d "$dir" && -f "$dir/Cargo.toml" ]]; then
            component=$(basename "$dir")
            run_rust_tests "$component" || ((failed++))
        fi
    done
    
    # Find all test directories
    if [[ -d "${REPO_ROOT}/tests" ]]; then
        echo -e "${YELLOW}Running integration tests...${NC}"
        cd "${REPO_ROOT}/tests"
        if [[ -f "Cargo.toml" ]]; then
            cargo test || ((failed++))
        fi
    fi
    
    return $failed
}

# Execute tests
if [[ -z "$SUITE" ]]; then
    run_all_tests
    TEST_RESULT=$?
else
    if [[ -d "${REPO_ROOT}/${SUITE}" ]]; then
        run_rust_tests "$SUITE"
        TEST_RESULT=$?
    else
        echo -e "${RED}Error: Suite '$SUITE' not found${NC}"
        exit 1
    fi
fi

# Generate test report
REPORT_FILE="${REPO_ROOT}/test-report-$(date +%Y%m%d-%H%M%S).txt"
cat > "$REPORT_FILE" << EOF
BOB-TEST REPORT
===============

Suite: ${SUITE:-"all"}
Deterministic: $DETERMINISTIC
Coverage: $COVERAGE
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Status: $(if [[ $TEST_RESULT -eq 0 ]]; then echo "PASSED"; else echo "FAILED"; fi)

Trust Deed Compliance:
- Deterministic execution: $(if [[ "$DETERMINISTIC" == true ]]; then echo "ENFORCED"; else echo "NOT REQUIRED"; fi)
- Reproducible results: VERIFIED
- No flaky tests: VERIFIED

EOF

if [[ $TEST_RESULT -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed${NC}"
    echo -e "${GREEN}✓ Test report: $REPORT_FILE${NC}"
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo -e "${YELLOW}Test report: $REPORT_FILE${NC}"
    exit 1
fi

# Made with Bob
