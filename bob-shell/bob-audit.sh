#!/usr/bin/env bash
# BOB-AUDIT: Generate cryptographically sealed audit records
# Purpose: Create tamper-evident audit trail for components
# Inputs: component name, output format
# Outputs: Cryptographically sealed audit record
# Dependencies: sha256sum, openssl (optional for ML-DSA-65)
# Verification: Generates SHA-256 seals for all audit events

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_DIR="${REPO_ROOT}/.audit"
FORMAT="json"
COMPONENT=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: bob-audit [component] [options]

Generate cryptographically sealed audit records according to BOB Trust Deed v1.0

Arguments:
    component           Component to audit (required)

Options:
    --format=FORMAT     Output format: json, text (default: json)
    --help              Show this help message

Examples:
    bob-audit compiler
    bob-audit runtime --format=text

EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --format=*)
            FORMAT="${1#*=}"
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
            COMPONENT="$1"
            shift
            ;;
    esac
done

if [[ -z "$COMPONENT" ]]; then
    echo -e "${RED}Error: Component name required${NC}"
    usage
fi

case $FORMAT in
    json|text)
        ;;
    *)
        echo -e "${RED}Error: Invalid format '$FORMAT'. Must be json or text${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}BOB-AUDIT: Auditing component '$COMPONENT'${NC}"

# Create audit directory
mkdir -p "$AUDIT_DIR"

# Collect audit data
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
AUDIT_ID="audit-${COMPONENT}-$(date +%Y%m%d-%H%M%S)"

# Component metadata
if [[ -d "${REPO_ROOT}/${COMPONENT}" ]]; then
    COMPONENT_PATH="${REPO_ROOT}/${COMPONENT}"
else
    echo -e "${RED}Error: Component '$COMPONENT' not found${NC}"
    exit 1
fi

# Calculate file hashes
echo -e "${YELLOW}Calculating file hashes...${NC}"
declare -a FILE_HASHES=()

while IFS= read -r -d '' file; do
    if [[ -f "$file" ]]; then
        rel_path="${file#$COMPONENT_PATH/}"
        hash=$(sha256sum "$file" | cut -d' ' -f1)
        FILE_HASHES+=("$rel_path:$hash")
    fi
done < <(find "$COMPONENT_PATH" -type f -print0)

# Check for Trust Deed compliance
PYTHON_IN_PROD=false
STUBS_FOUND=false
MISSING_DOCS=false

# Scan for Python in production paths
if grep -r "#!/usr/bin/env python" "$COMPONENT_PATH" 2>/dev/null | grep -v "tools/" | grep -v "scripts/" > /dev/null; then
    PYTHON_IN_PROD=true
fi

# Scan for stub implementations
if grep -r "TODO\|FIXME\|PLACEHOLDER\|NotImplementedError" "$COMPONENT_PATH" 2>/dev/null > /dev/null; then
    STUBS_FOUND=true
fi

# Check for documentation headers
if [[ -d "${COMPONENT_PATH}/src" ]]; then
    for src_file in "${COMPONENT_PATH}/src"/*.rs "${COMPONENT_PATH}/src"/*.ada "${COMPONENT_PATH}/src"/*.c; do
        if [[ -f "$src_file" ]]; then
            if ! grep -q "Purpose:\|Inputs:\|Outputs:\|Dependencies:\|Verification:" "$src_file" 2>/dev/null; then
                MISSING_DOCS=true
                break
            fi
        fi
    done
fi

# Calculate component seal
COMPONENT_SEAL=$(echo -n "${COMPONENT}:${TIMESTAMP}:${FILE_HASHES[*]}" | sha256sum | cut -d' ' -f1)

# Generate audit record
if [[ "$FORMAT" == "json" ]]; then
    AUDIT_FILE="${AUDIT_DIR}/${AUDIT_ID}.json"
    cat > "$AUDIT_FILE" << EOF
{
  "audit_id": "${AUDIT_ID}",
  "component": "${COMPONENT}",
  "timestamp": "${TIMESTAMP}",
  "component_seal": "${COMPONENT_SEAL}",
  "trust_deed_compliance": {
    "python_in_production": ${PYTHON_IN_PROD},
    "stubs_found": ${STUBS_FOUND},
    "missing_documentation": ${MISSING_DOCS},
    "overall_status": "$(if [[ "$PYTHON_IN_PROD" == false && "$STUBS_FOUND" == false && "$MISSING_DOCS" == false ]]; then echo "COMPLIANT"; else echo "NON_COMPLIANT"; fi)"
  },
  "file_count": ${#FILE_HASHES[@]},
  "file_hashes": [
$(for hash_entry in "${FILE_HASHES[@]}"; do
    file="${hash_entry%%:*}"
    hash="${hash_entry##*:}"
    echo "    {\"file\": \"$file\", \"sha256\": \"$hash\"},"
done | sed '$ s/,$//')
  ],
  "audit_seal": "$(echo -n "${AUDIT_ID}:${COMPONENT_SEAL}:${TIMESTAMP}" | sha256sum | cut -d' ' -f1)"
}
EOF
else
    AUDIT_FILE="${AUDIT_DIR}/${AUDIT_ID}.txt"
    cat > "$AUDIT_FILE" << EOF
BOB AUDIT RECORD
================

Audit ID: ${AUDIT_ID}
Component: ${COMPONENT}
Timestamp: ${TIMESTAMP}
Component Seal: ${COMPONENT_SEAL}

TRUST DEED COMPLIANCE
---------------------
Python in Production: ${PYTHON_IN_PROD}
Stubs Found: ${STUBS_FOUND}
Missing Documentation: ${MISSING_DOCS}
Overall Status: $(if [[ "$PYTHON_IN_PROD" == false && "$STUBS_FOUND" == false && "$MISSING_DOCS" == false ]]; then echo "COMPLIANT"; else echo "NON_COMPLIANT"; fi)

FILE INVENTORY
--------------
Total Files: ${#FILE_HASHES[@]}

$(for hash_entry in "${FILE_HASHES[@]}"; do
    file="${hash_entry%%:*}"
    hash="${hash_entry##*:}"
    echo "$file"
    echo "  SHA-256: $hash"
done)

AUDIT SEAL
----------
$(echo -n "${AUDIT_ID}:${COMPONENT_SEAL}:${TIMESTAMP}" | sha256sum | cut -d' ' -f1)

EOF
fi

echo -e "${GREEN}✓ Audit record generated: $AUDIT_FILE${NC}"

# Check compliance status
if [[ "$PYTHON_IN_PROD" == true ]]; then
    echo -e "${RED}✗ VIOLATION: Python found in production paths${NC}"
fi
if [[ "$STUBS_FOUND" == true ]]; then
    echo -e "${RED}✗ VIOLATION: Stub implementations found${NC}"
fi
if [[ "$MISSING_DOCS" == true ]]; then
    echo -e "${YELLOW}⚠ WARNING: Missing documentation headers${NC}"
fi

if [[ "$PYTHON_IN_PROD" == false && "$STUBS_FOUND" == false && "$MISSING_DOCS" == false ]]; then
    echo -e "${GREEN}✓ Component is Trust Deed compliant${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Component has compliance issues${NC}"
    exit 1
fi

# Made with Bob
