#!/bin/bash
# SEB Codegen Master Script
# Generated from: SEB_SOVEREIGN_EVENT_BUS_MASTER_SPECIFICATION.xml
# Version: 1.0.0
# Purpose: Generate all codegen targets from contract templates

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTRACTS_DIR="$SEB_ROOT/contracts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if contract templates exist
check_templates() {
    log_info "Checking contract templates..."
    
    local templates=(
        "rust.template"
        "typescript.template"
        "python.template"
        "lean4.template"
        "openapi.template"
    )
    
    local missing=0
    for template in "${templates[@]}"; do
        if [[ ! -f "$CONTRACTS_DIR/$template" ]]; then
            log_error "Missing template: $template"
            missing=$((missing + 1))
        fi
    done
    
    if [[ $missing -gt 0 ]]; then
        log_error "Missing $missing template(s). Cannot proceed."
        exit 1
    fi
    
    log_info "All templates present ✓"
}

# Generate Rust code
generate_rust() {
    log_info "Generating Rust code..."
    bash "$SCRIPT_DIR/generate_rust.sh"
}

# Generate TypeScript code
generate_typescript() {
    log_info "Generating TypeScript code..."
    bash "$SCRIPT_DIR/generate_typescript.sh"
}

# Generate Python code
generate_python() {
    log_info "Generating Python code..."
    bash "$SCRIPT_DIR/generate_python.sh"
}

# Generate Lean4 code
generate_lean4() {
    log_info "Generating Lean4 code..."
    bash "$SCRIPT_DIR/generate_lean4.sh"
}

# Generate OpenAPI spec
generate_openapi() {
    log_info "Generating OpenAPI specification..."
    bash "$SCRIPT_DIR/generate_openapi.sh"
}

# Main execution
main() {
    log_info "SEB Codegen - Generating all targets"
    log_info "Root: $SEB_ROOT"
    
    check_templates
    
    # Generate all targets
    generate_rust
    generate_typescript
    generate_python
    generate_lean4
    generate_openapi
    
    log_info "All codegen targets generated successfully ✓"
    log_info "Next steps:"
    log_info "  1. Review generated code in respective directories"
    log_info "  2. Run 'make scaffold-verify' to validate"
    log_info "  3. Commit changes to version control"
}

main "$@"

# Made with Bob
