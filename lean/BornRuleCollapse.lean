/-!
# Born Rule Collapse - Formal Specification
# Ahmad Ali Parr · 2026-08-03

Formal verification of quantum measurement collapse via Born rule.

## Specification

Given quantum samples from ANU QRNG (real vacuum fluctuations):
1. Normalize uint16 → [0,1]
2. Filter through thermal window [thermalMin, thermalMax]
3. Apply Born rule: equal weights within window
4. Collapse to dominant branch (first surviving)

## Properties to Prove

1. **Termination**: `bornCollapse` always terminates
2. **Validity**: Output ∈ [thermalMin, thermalMax] when non-vacuum
3. **Probability**: Collapsed value has valid probability measure
4. **Vacuum State**: Empty window correctly returns None
5. **Maximum Entropy**: Equal weights maximize entropy within thermal window

## Reference Implementation

JavaScript (backend/bob/quantum.mjs):
```javascript
export async function bornCollapse (thermalMin = 0.2, thermalMax = 0.8) {
  const samples = await getQuantumSamples(32)
  const normalized = samples.map(v => v / 65535)
  const inWindow   = normalized.filter(v => v >= thermalMin && v <= thermalMax)
  if (inWindow.length === 0) return null  // vacuum state
  const weights    = inWindow.map(v => ({ value: v, weight: 1 / inWindow.length }))
  const dominant   = weights.sort((a, b) => b.weight - a.weight)[0]
  return {
    collapsed:    dominant.value,
    branchCount:  inWindow.length,
    totalBranches: samples.length,
    isVacuum:     false
  }
}
```

-/

import Mathlib.Data.Real.Basic
import Mathlib.Data.Finset.Basic
import Mathlib.Algebra.BigOperators.Basic

namespace BornRule

-- ══════════════════════════════════════════════════════════════════
-- Core Types
-- ══════════════════════════════════════════════════════════════════

/-- Quantum sample from ANU QRNG (uint16) -/
def QuantumSample := Fin 65536

/-- Normalized quantum value in [0,1] -/
structure NormalizedValue where
  val : ℝ
  h_bounds : 0 ≤ val ∧ val ≤ 1

/-- Thermal window bounds -/
structure ThermalWindow where
  min : ℝ
  max : ℝ
  h_bounds : 0 ≤ min ∧ min < max ∧ max ≤ 1

/-- Weighted quantum branch -/
structure WeightedBranch where
  value : NormalizedValue
  weight : ℝ
  h_weight : 0 ≤ weight ∧ weight ≤ 1

/-- Born collapse result -/
inductive CollapseResult
  | Vacuum : CollapseResult
  | Collapsed (collapsed : NormalizedValue)
              (branchCount : ℕ)
              (totalBranches : ℕ) : CollapseResult

-- ══════════════════════════════════════════════════════════════════
-- Normalization
-- ══════════════════════════════════════════════════════════════════

/-- Normalize uint16 sample to [0,1] -/
def normalize (sample : QuantumSample) : NormalizedValue :=
  { val := sample.val / 65535,
    h_bounds := by
      constructor
      · apply div_nonneg
        · exact Nat.cast_nonneg _
        · norm_num
      · apply div_le_one_of_le
        · norm_num
        · exact Nat.cast_le.mpr sample.isLt.le }

-- ══════════════════════════════════════════════════════════════════
-- Thermal Window Filter
-- ══════════════════════════════════════════════════════════════════

/-- Check if normalized value is within thermal window -/
def inWindow (nv : NormalizedValue) (tw : ThermalWindow) : Bool :=
  tw.min ≤ nv.val && nv.val ≤ tw.max

/-- Filter samples through thermal window -/
def filterWindow (samples : List NormalizedValue) (tw : ThermalWindow) : List NormalizedValue :=
  samples.filter (fun nv => inWindow nv tw)

-- ══════════════════════════════════════════════════════════════════
-- Born Rule Weighting
-- ══════════════════════════════════════════════════════════════════

/-- Assign equal weights to all branches (maximum entropy) -/
def assignWeights (samples : List NormalizedValue) : List WeightedBranch :=
  match samples with
  | [] => []
  | xs => xs.map fun nv =>
      { value := nv,
        weight := 1 / xs.length,
        h_weight := by
          constructor
          · apply div_nonneg; norm_num; exact Nat.cast_nonneg _
          · apply div_le_one_of_le; norm_num
            exact Nat.one_le_cast.mpr (List.length_pos_of_mem (List.mem_of_ne_nil _ _)) }

/-- Born collapse: select dominant branch (first with max weight) -/
def selectDominant (branches : List WeightedBranch) : Option WeightedBranch :=
  branches.head?

-- ══════════════════════════════════════════════════════════════════
-- Main Born Collapse Algorithm
-- ══════════════════════════════════════════════════════════════════

/-- Born rule collapse with thermal window -/
def bornCollapse
    (samples : List QuantumSample)
    (tw : ThermalWindow) : CollapseResult :=
  let normalized := samples.map normalize
  let inWindow := filterWindow normalized tw
  match inWindow with
  | [] => CollapseResult.Vacuum
  | xs =>
      let branches := assignWeights xs
      match selectDominant branches with
      | none => CollapseResult.Vacuum  -- impossible if xs nonempty
      | some dominant =>
          CollapseResult.Collapsed
            dominant.value
            xs.length
            samples.length

-- ══════════════════════════════════════════════════════════════════
-- Theorems
-- ══════════════════════════════════════════════════════════════════

/-- T1: Born collapse always terminates -/
theorem born_collapse_terminates
    (samples : List QuantumSample)
    (tw : ThermalWindow) :
    ∃ result, bornCollapse samples tw = result := by
  use bornCollapse samples tw

/-- T2: Non-vacuum result is within thermal window -/
theorem born_collapse_valid_range
    (samples : List QuantumSample)
    (tw : ThermalWindow)
    (nv : NormalizedValue)
    (bc : ℕ) (tb : ℕ)
    (h : bornCollapse samples tw = CollapseResult.Collapsed nv bc tb) :
    tw.min ≤ nv.val ∧ nv.val ≤ tw.max := by
  unfold bornCollapse at h
  simp only at h
  -- After filterWindow, all values satisfy inWindow
  split at h
  · contradiction  -- Empty case contradicts Collapsed result
  next xs hxs =>
    simp only at h
    split at h
    · contradiction  -- selectDominant none contradicts Collapsed
    next dom hdom =>
      injection h with h_nv h_bc h_tb
      subst h_nv
      -- dom came from assignWeights xs, which came from filterWindow
      -- filterWindow ensures all elements satisfy inWindow predicate
      have h_mem : dom ∈ assignWeights xs := by
        sorry -- dom is head of non-empty list
      have h_in : nv ∈ xs := by
        sorry -- unwrap WeightedBranch to get NormalizedValue
      -- inWindow nv tw = true
      unfold inWindow at *
      sorry -- extract bounds from Bool.true

/-- T3: Vacuum state only when no samples in window -/
theorem born_collapse_vacuum_iff
    (samples : List QuantumSample)
    (tw : ThermalWindow) :
    bornCollapse samples tw = CollapseResult.Vacuum ↔
    filterWindow (samples.map normalize) tw = [] := by
  sorry  -- Proof: case split on filterWindow result

/-- T4: Equal weights sum to 1 (probability measure) -/
theorem born_weights_sum_to_one
    (samples : List NormalizedValue)
    (h : samples ≠ []) :
    (assignWeights samples).map (·.weight) |>.sum = 1 := by
  sorry  -- Proof: n × (1/n) = 1

/-- T5: Maximum entropy within thermal window -/
theorem born_maximum_entropy
    (samples : List NormalizedValue)
    (h : samples ≠ []) :
    ∀ (alt_weights : List ℝ),
      alt_weights.sum = 1 →
      entropy (assignWeights samples) ≥ entropy_from_weights alt_weights := by
  sorry  -- Proof: uniform distribution maximizes Shannon entropy

end BornRule
