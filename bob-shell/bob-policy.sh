#!/usr/bin/env bash
# BOB-POLICY: Query Prolog/Datalog policy rules
# Purpose: Query and explain policy decisions
# Inputs: rule query, explain flag
# Outputs: Policy decision with optional reasoning trace
# Dependencies: SWI-Prolog or compatible Prolog interpreter
# Verification: Provides explainable policy decisions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_DIR="${REPO_ROOT}/governance/prolog"
EXPLAIN=false
QUERY=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: bob-policy query <rule> [options]

Query Prolog/Datalog policy rules according to BOB Trust Deed v1.0

Arguments:
    query <rule>        Prolog query to execute (required)

Options:
    --explain           Provide reasoning trace
    --help              Show this help message

Examples:
    bob-policy query "agent_class(oracle, X)"
    bob-policy query "route_task(compile, Agent, Priority)" --explain
    bob-policy query "verify_deed(deploy_production, Verdict)"

EOF
    exit 1
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    usage
fi

if [[ "$1" != "query" ]]; then
    echo -e "${RED}Error: First argument must be 'query'${NC}"
    usage
fi
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --explain)
            EXPLAIN=true
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
            QUERY="$1"
            shift
            ;;
    esac
done

if [[ -z "$QUERY" ]]; then
    echo -e "${RED}Error: Query required${NC}"
    usage
fi

echo -e "${GREEN}BOB-POLICY: Querying policy rules${NC}"
echo "Query: $QUERY"
echo "Explain: $EXPLAIN"

# Check for Prolog interpreter
if ! command -v swipl &> /dev/null; then
    echo -e "${RED}Error: SWI-Prolog not found. Install with: apt-get install swi-prolog${NC}"
    exit 1
fi

# Check for policy files
if [[ ! -d "$POLICY_DIR" ]]; then
    echo -e "${YELLOW}Warning: Policy directory not found at $POLICY_DIR${NC}"
    echo "Creating default policy structure..."
    mkdir -p "$POLICY_DIR"
    
    # Create default policy file
    cat > "${POLICY_DIR}/sovereign_kernel.pl" << 'EOF'
:- module(sovereign_kernel, [
    agent_class/2,
    route_task/3,
    verify_deed/2,
    language_approved/1,
    build_phase_valid/2
]).

% Agent classification
agent_class(oracle, quantum).
agent_class(archivist, worm).
agent_class(sentinel, gate).
agent_class(bob, orchestrator).

% Task routing
route_task(Task, Agent, Priority) :-
    task_pattern(Task, Pattern),
    agent_class(Agent, Pattern),
    priority_score(Task, Priority).

task_pattern(compile, orchestrator).
task_pattern(verify, orchestrator).
task_pattern(deploy, orchestrator).
task_pattern(audit, archivist).
task_pattern(measure, quantum).

priority_score(compile, 8).
priority_score(verify, 9).
priority_score(deploy, 10).
priority_score(audit, 7).
priority_score(measure, 6).

% Trust Deed verification
verify_deed(Action, Verdict) :-
    deed_article(Action, Article),
    article_permits(Article, Action),
    Verdict = allowed.

verify_deed(Action, Verdict) :-
    \+ deed_article(Action, _),
    Verdict = denied.

deed_article(compile, 'BUILD_PROTOCOL').
deed_article(verify, 'BUILD_PROTOCOL').
deed_article(deploy, 'BUILD_PROTOCOL').
deed_article(use_python_runtime, 'NO_PYTHON_RUNTIME').

article_permits('BUILD_PROTOCOL', compile).
article_permits('BUILD_PROTOCOL', verify).
article_permits('BUILD_PROTOCOL', deploy).

% Approved languages
language_approved(rexx).
language_approved(rpg).
language_approved(wazi).
language_approved(ada).
language_approved(spark).
language_approved(rust).
language_approved(prolog).
language_approved(datalog).
language_approved(bash).

% Build phase validation
build_phase_valid(1, analysis).
build_phase_valid(2, architecture).
build_phase_valid(3, implementation).
build_phase_valid(4, verification).
build_phase_valid(5, delivery).

EOF
    echo -e "${GREEN}✓ Default policy created${NC}"
fi

# Create temporary query file
TEMP_QUERY=$(mktemp)
cat > "$TEMP_QUERY" << EOF
:- consult('${POLICY_DIR}/sovereign_kernel.pl').
:- initialization(main, main).

main :-
    $(if [[ "$EXPLAIN" == true ]]; then echo "trace,"; fi)
    (   ${QUERY}
    ->  writeln('SUCCESS: Query succeeded'),
        (   ${QUERY}
        ->  write('Result: '), writeln(${QUERY})
        ;   true
        ),
        halt(0)
    ;   writeln('FAILURE: Query failed'),
        halt(1)
    ).
EOF

# Execute query
echo -e "${YELLOW}Executing Prolog query...${NC}"
if swipl -q -t halt -s "$TEMP_QUERY" 2>&1; then
    RESULT=$?
    rm -f "$TEMP_QUERY"
    
    if [[ $RESULT -eq 0 ]]; then
        echo -e "${GREEN}✓ Policy query succeeded${NC}"
        exit 0
    else
        echo -e "${RED}✗ Policy query failed${NC}"
        exit 1
    fi
else
    RESULT=$?
    rm -f "$TEMP_QUERY"
    echo -e "${RED}✗ Prolog execution error${NC}"
    exit $RESULT
fi

# Made with Bob
