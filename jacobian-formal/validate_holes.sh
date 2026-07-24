#!/bin/bash
# Haiku hole validator: check hole structure without Agda compiler

echo "=== PHASE 3 HOLE VALIDATION ==="
echo ""

modules=(
  "src/Invariants/EvolutionLoop.agda"
  "src/Invariants/EulerLoop.agda"
  "src/Invariants/MatrixAccumulationLoop.agda"
  "src/Invariants/GateApplicationLoop.agda"
)

total_holes=0
for module in "${modules[@]}"; do
  count=$(grep -c "?" "$module" 2>/dev/null || echo 0)
  echo "$(basename $module): $count holes"
  total_holes=$((total_holes + count))
  
  # Show hole context (2 lines before, 1 after)
  grep -B2 -A1 "?" "$module" | head -40
  echo "---"
done

echo ""
echo "TOTAL HOLES: $total_holes"
echo ""
echo "Module assignment:"
echo "  • ahmad_bot → EvolutionLoop.agda"
echo "  • forge → EulerLoop.agda"
echo "  • enki → MatrixAccumulationLoop.agda + GateApplicationLoop.agda"
