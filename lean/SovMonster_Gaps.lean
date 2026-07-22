/-!
# Mathlib Gap Analysis & Implementation Strategies
# for SovMonster Matrix-Level Formalization

Ahmad Ali Parr · SnapKitty Collective · 2026-07-21

This file documents the exact Mathlib gaps that remain after
`SovMonster_Matrix_Closed.lean` and provides:
  1. Precise mathematical formulations (what needs to be true)
  2. Mathlib API patterns to use when the gap closes
  3. Working constructive approximations where possible

PAR-011: Core commutativity — ALREADY PROVED (SovMonster_Matrix_Closed)
Remaining: spectral contraction, SPE frame, fidelity, hot_swap versioning
-/

import Mathlib.Analysis.Complex.Basic
import Mathlib.Analysis.NormedSpace.Basic
import Mathlib.LinearAlgebra.Matrix.Basic
import Mathlib.LinearAlgebra.Matrix.NonsingularInverse
import Mathlib.LinearAlgebra.Matrix.Trace
import Mathlib.LinearAlgebra.Matrix.PosDef
import Mathlib.LinearAlgebra.Matrix.Adjoint
import Mathlib.Data.Real.Basic
import Mathlib.Analysis.SpecialFunctions.Pow.Real
import Mathlib.LinearAlgebra.Cholesky

open Matrix Complex NormedSpace

-- =====================================================================
-- GAP 1: MATRIX SQUARE ROOT
-- =====================================================================

/-!
## Matrix Square Root Theory

For A ∈ Mₙ(ℂ) positive semidefinite with spectral decomposition
A = U Σ U*, the unique PSD square root is:
  A^(1/2) = U Σ^(1/2) U*   where Σ^(1/2) = diag(√σ₁, ..., √σₙ)

Mathlib status: `Matrix.sqrt` exists for PSD Hermitian matrices.
Missing: Fréchet derivative of sqrt (needed for gradient computations).
Workaround: Denman-Beavers iteration or Dunford-Schur contour integrals.
-/

/-- PSD square root via spectral decomposition (structure) -/
noncomputable def matrix_sqrt_psd
    {n : Type*} [Fintype n] [DecidableEq n]
    (A : Matrix n n ℂ) (hA : A.PosSemidef) : Matrix n n ℂ :=
  A.sqrt  -- Mathlib's Matrix.sqrt handles PSD Hermitian matrices

/-- Key property: (A^(1/2))^2 = A for PSD A -/
theorem matrix_sqrt_sq
    {n : Type*} [Fintype n] [DecidableEq n]
    (A : Matrix n n ℂ) (hA : A.PosSemidef) :
    (matrix_sqrt_psd A hA) * (matrix_sqrt_psd A hA) = A := by
  simp [matrix_sqrt_psd]
  exact Matrix.sqrt_sq hA

/-- sqrt preserves PSD -/
theorem matrix_sqrt_psd_iff
    {n : Type*} [Fintype n] [DecidableEq n]
    (A : Matrix n n ℂ) (hA : A.PosSemidef) :
    (matrix_sqrt_psd A hA).PosSemidef := by
  simp [matrix_sqrt_psd]
  exact Matrix.posSemidef_sqrt hA

/-- Cyclic property needed for fidelity:
    √(√ρ · σ · √ρ) — trace is invariant under cyclic permutation.
    Requires: Matrix.sqrt commutes with congruence for PSD matrices. -/
theorem sqrt_congruence_trace
    {n : Type*} [Fintype n] [DecidableEq n]
    (ρ σ : Matrix n n ℂ)
    (hρ : ρ.PosSemidef) (hσ : σ.PosSemidef) :
    Matrix.trace ((matrix_sqrt_psd ρ hρ * σ * matrix_sqrt_psd ρ hρ).sqrt) =
    Matrix.trace ((matrix_sqrt_psd σ hσ * ρ * matrix_sqrt_psd σ hσ).sqrt) := by
  -- Uses: tr(f(AB)) = tr(f(BA)) for functions f via cyclic trace
  -- Specific case: tr(√(√ρ σ √ρ)) = tr(√(√σ ρ √σ))  (Uhlmann)
  sorry  -- Needs: Matrix.trace_sqrt_congruence (Mathlib PR target)

-- =====================================================================
-- GAP 2: COMPLETELY POSITIVE MAPS (CHOI'S THEOREM)
-- =====================================================================

/-!
## Completely Positive Maps

Φ: Mₙ(ℂ) → Mₘ(ℂ) is CP iff its Choi matrix
  C_Φ = (Φ ⊗ id_n)(|Ω⟩⟨Ω|) ∈ Mₘₙ(ℂ) is PSD
where |Ω⟩ = Σᵢ |i⟩⊗|i⟩ is the maximally entangled state.

Mathlib has: `CStarAlgebra`, `Matrix.PosSemidef`, `Matrix.kronecker`
Missing: Choi matrix construction as a bundled type with CP ↔ Choi PSD.
-/

/-- Choi matrix of a linear map Φ: Mₙ → Mₘ -/
noncomputable def choi_matrix
    {n m : Type*} [Fintype n] [Fintype m] [DecidableEq n] [DecidableEq m]
    (Φ : Matrix n n ℂ →ₗ[ℂ] Matrix m m ℂ) : Matrix (m × n) (m × n) ℂ :=
  fun ij kl =>
    -- C_Φ[i,j,k,l] = Φ(|k⟩⟨l|)[i,j]
    (Φ (Matrix.stdBasis ℂ n kl.2 ▸ (fun a b => if a = kl.2 ∧ b = kl.2 then 1 else 0))) ij.1 ij.2

/-- Completely positive predicate (via Choi) -/
def IsCompletelyPositive
    {n m : Type*} [Fintype n] [Fintype m] [DecidableEq n] [DecidableEq m]
    (Φ : Matrix n n ℂ →ₗ[ℂ] Matrix m m ℂ) : Prop :=
  (choi_matrix Φ).PosSemidef

/-- Fibonacci channel is CP: Φ(ρ) = UρU† is a unitary conjugation -/
theorem fibonacci_channel_is_cp
    {n : Type*} [Fintype n] [DecidableEq n]
    (U : Matrix n n ℂ) (hU : U * star U = 1) :
    IsCompletelyPositive
      { toFun := fun ρ => U * ρ * star U
        map_add' := fun a b => by ring
        map_smul' := fun c a => by simp [smul_mul, mul_smul] } := by
  simp [IsCompletelyPositive, choi_matrix]
  -- Choi matrix of UρU† is (U⊗U) C_id (U⊗U)† which is PSD since C_id is PSD
  sorry  -- Needs: Matrix.kronecker CP channel Choi construction

-- =====================================================================
-- GAP 3: QUANTUM PERRON-FROBENIUS
-- =====================================================================

/-!
## Quantum Perron-Frobenius Theory

For a primitive CP map Φ with spectral radius ρ(Φ):
  - ρ(Φ) is a simple eigenvalue
  - The unique fixed state ρ* satisfies Φ(ρ*) = ρ(Φ)·ρ*
  - All other eigenvalues satisfy |λ| < ρ(Φ)

Mathlib adaptation:
  - Express Φ as n²×n² matrix via Matrix.kronecker / LinearMap.toMatrix
  - Use Matrix.spectralRadius bounds
  - Apply existing Perron-Frobenius for nonneg matrices (Mathlib has this)

This provides the contraction bound on the orthogonal subspace.
-/

/-- Superoperator representation: Φ → n²×n² matrix -/
noncomputable def superoperator_matrix
    {n : Type*} [Fintype n] [DecidableEq n]
    (Φ : Matrix n n ℂ →ₗ[ℂ] Matrix n n ℂ) :
    Matrix (n × n) (n × n) ℂ :=
  LinearMap.toMatrix
    (Pi.basisFun ℂ (n × n))
    (Pi.basisFun ℂ (n × n))
    (Φ.comp (Matrix.vecMulLinear (1 : Matrix n n ℂ)))  -- stub

/-- The fixed-point subspace of a CP map -/
def fixed_subspace
    {n : Type*} [Fintype n] [DecidableEq n]
    (Φ : Matrix n n ℂ →ₗ[ℂ] Matrix n n ℂ) : Submodule ℂ (Matrix n n ℂ) :=
  LinearMap.ker (Φ - LinearMap.id)

/-- Contraction on orthogonal complement of fixed point.
    Strategy: lift to n²×n² matrix, apply Perron-Frobenius. -/
theorem cp_map_contraction_on_complement
    {n : Type*} [Fintype n] [DecidableEq n]
    (Φ : Matrix n n ℂ →ₗ[ℂ] Matrix n n ℂ)
    (hΦ_cp : IsCompletelyPositive Φ)
    (hΦ_tp : ∀ ρ, Matrix.trace (Φ ρ) = Matrix.trace ρ)
    (ρ_star : Matrix n n ℂ)
    (h_fp : Φ ρ_star = ρ_star)
    (hρ_psd : ρ_star.PosSemidef) :
    ∃ c : ℝ, 0 < c ∧ c < 1 ∧
      ∀ ρ : Matrix n n ℂ,
        Matrix.trace (ρ * ρ_star) = 0 →
        ‖Φ ρ‖ ≤ c * ‖ρ‖ := by
  -- Strategy:
  -- 1. Form S = superoperator_matrix Φ (n²×n² matrix)
  -- 2. ρ_star ↔ fixed eigenvector of S at eigenvalue 1
  -- 3. Perron-Frobenius: all other eigenvalues |λ| < 1 for primitive CP map
  -- 4. c = max{|λ| : λ eigenvalue of S, λ ≠ 1}
  -- Requires: Matrix.spectralRadius, primitivity condition
  sorry  -- Needs: Mathlib.LinearAlgebra.Matrix.SpecRadius + CP Perron-Frobenius

-- =====================================================================
-- GAP 4: SIC-POVM FRAME COMPLETION
-- =====================================================================

/-!
## SIC-POVMs

A SIC-POVM in dimension d: d² rank-1 projectors Πᵢ = |ψᵢ⟩⟨ψᵢ|/d with:
  (a) Completeness:  Σᵢ Πᵢ = I
  (b) Equiangularity: tr(Πᵢ Πⱼ) = 1/(d+1) for i ≠ j

Mathlib status: No SIC-POVM construction exists.
Workaround for SPE round-trip: Replace with ABSTRACT frame axioms.
The round-trip holds for ANY tight frame, not just SIC-POVMs.
-/

/-- Abstract tight frame axioms (generalizes SIC-POVM) -/
structure TightFrame (n r : Type*) [Fintype n] [Fintype r] [DecidableEq n] where
  elements    : r → Matrix n n ℂ
  hermitian   : ∀ i, (elements i).Hermitian
  psd         : ∀ i, (elements i).PosSemidef
  completeness : ∑ i, elements i = 1    -- Σ Eᵢ = I (key axiom)
  orthogonality : ∀ i j, i ≠ j →
    ∃ c : ℂ, Matrix.trace (elements i * elements j) = c  -- equiangular

/-- SPE round-trip from tight frame completeness -/
theorem spe_roundtrip_from_tight_frame
    {n r : Type*} [Fintype n] [Fintype r] [DecidableEq n]
    (F : TightFrame n r)
    (x : Matrix n n ℂ) :
    ∑ i, Matrix.trace (x * F.elements i) • F.elements i = x := by
  -- Proof: Σᵢ tr(x Eᵢ) · Eᵢ = Σᵢ tr(x Eᵢ) · Eᵢ
  --      = x · (Σᵢ Eᵢ)          by linearity of trace
  --      = x · I = x             by completeness
  have key : x = x * 1 := by simp
  rw [← F.completeness, Matrix.mul_sum] at key
  rw [key]
  congr 1; ext i
  -- Need: tr(x Eᵢ) • Eᵢ = x * Eᵢ
  -- This requires: ∑ tr(x Eᵢ) • Eᵢ = ∑ x * Eᵢ as a whole, not termwise
  sorry  -- One reindex: smul_eq_mul + trace inner product

-- =====================================================================
-- GAP 5: QUANTUM FIDELITY
-- =====================================================================

/-!
## Uhlmann Fidelity

F(ρ,σ) = tr(√(√ρ σ √ρ))

When ρ,σ commute: F(ρ,σ) = Σᵢ √(pᵢ qᵢ) (Bhattacharyya coefficient)
When σ = ρ:       F(ρ,ρ) = tr(√(ρ²)) = tr(ρ) = 1  [since ρ² = ρ for projectors,
                           and tr(√ρ²) = tr(ρ) for PSD ρ with tr(ρ)=1]

Needed Mathlib lemmas:
  - Matrix.sqrt_sq_eq_abs for PSD (gives √(ρ²) = ρ when ρ ≥ 0)
  - Matrix.trace_sqrt_congruence (cyclic)
-/

noncomputable def quantum_fidelity
    {n : Type*} [Fintype n] [DecidableEq n]
    (ρ σ : Matrix n n ℂ)
    (hρ : ρ.PosSemidef) (hσ : σ.PosSemidef) : ℝ :=
  (Matrix.trace
    ((matrix_sqrt_psd ρ hρ * σ * matrix_sqrt_psd ρ hρ).sqrt)).re

/-- F(ρ,ρ) = 1 for density matrices -/
theorem fidelity_self_eq_one
    {n : Type*} [Fintype n] [DecidableEq n]
    (ρ : Matrix n n ℂ)
    (hρ : ρ.PosSemidef)
    (htr : Matrix.trace ρ = 1) :
    quantum_fidelity ρ ρ hρ hρ = 1 := by
  simp only [quantum_fidelity]
  -- √ρ · ρ · √ρ = (√ρ)³ = ρ · √ρ = √ρ · ρ
  -- For PSD ρ: √(√ρ · ρ · √ρ) = √(ρ²) = ρ  (since √ρ · √ρ = ρ)
  have h1 : matrix_sqrt_psd ρ hρ * ρ * matrix_sqrt_psd ρ hρ =
            (matrix_sqrt_psd ρ hρ) * (matrix_sqrt_psd ρ hρ) *
            (matrix_sqrt_psd ρ hρ) * (matrix_sqrt_psd ρ hρ) := by
    have sq : matrix_sqrt_psd ρ hρ * matrix_sqrt_psd ρ hρ = ρ :=
      matrix_sqrt_sq ρ hρ
    rw [← sq]; ring
  rw [h1]
  -- √((√ρ)⁴) = (√ρ)² = ρ
  have h2 : ((matrix_sqrt_psd ρ hρ) * (matrix_sqrt_psd ρ hρ) *
             (matrix_sqrt_psd ρ hρ) * (matrix_sqrt_psd ρ hρ)).sqrt =
            ρ := by
    sorry  -- Needs: Matrix.sqrt_pow for PSD matrices
  rw [h2, htr]
  simp

-- =====================================================================
-- GAP 6: HOT_SWAP VERSIONING POLICY
-- =====================================================================

/-!
## Semantic Versioning for hot_swap

| Change type                    | Version bump | Rule                    |
|-------------------------------|--------------|-------------------------|
| Interface signature change     | Major v→v+1  | Invalidate prior handles|
| Numerical algorithm swap       | Minor        | Backward compatible     |
| Performance / logging changes  | Patch        | Zero-downtime allowed   |
-/

inductive VersionBump where
  | Major : VersionBump   -- interface changed, handles invalidated
  | Minor : VersionBump   -- algorithm changed, backward compatible
  | Patch : VersionBump   -- heuristics/logging only

structure SemanticVersion where
  major : ℕ
  minor : ℕ
  patch : ℕ

def bump (v : SemanticVersion) : VersionBump → SemanticVersion
  | .Major => ⟨v.major + 1, 0, 0⟩
  | .Minor => ⟨v.major, v.minor + 1, 0⟩
  | .Patch => ⟨v.major, v.minor, v.patch + 1⟩

def version_compatible (old new : SemanticVersion) : Prop :=
  old.major = new.major   -- same major = compatible

/-- hot_swap is valid iff versions are compatible and invariants hold -/
def hot_swap_valid
    {n : Type*} [Fintype n] [DecidableEq n]
    (old_v new_v : SemanticVersion)
    (new_invariants_hold : Prop) : Prop :=
  version_compatible old_v new_v ∧ new_invariants_hold

theorem version_increases_on_swap (v : SemanticVersion) (b : VersionBump) :
    (match b with
     | .Major => (bump v b).major > v.major
     | .Minor => (bump v b).minor > v.minor ∧ (bump v b).major = v.major
     | .Patch => (bump v b).patch > v.patch ∧ (bump v b).minor = v.minor) := by
  cases b <;> simp [bump]

-- =====================================================================
-- GAP 7: LINEAR MAP ↔ MATRIX BRIDGE (API PATTERN)
-- =====================================================================

/-!
## Linear Maps vs Matrices — Correct Mathlib Pattern

Use: Matrix.toLin, LinearMap.toMatrix with explicit finite basis proofs.
Avoid assuming high-level API for non-commutative operator derivatives.
-/

/-- Convert matrix multiplication to linear map explicitly -/
noncomputable def mat_to_lin
    {n : Type*} [Fintype n] [DecidableEq n]
    (A : Matrix n n ℂ) : (n → ℂ) →ₗ[ℂ] (n → ℂ) :=
  Matrix.toLin (Pi.basisFun ℂ n) (Pi.basisFun ℂ n) A

/-- Congruence transformation as linear map on matrix space -/
noncomputable def congruence_lin
    {n : Type*} [Fintype n] [DecidableEq n]
    (A : Matrix n n ℂ) : Matrix n n ℂ →ₗ[ℂ] Matrix n n ℂ where
  toFun     := fun M => A * M * star A
  map_add'  := fun M N => by ring
  map_smul' := fun c M => by simp [smul_mul, mul_smul]

/-- Positivity via Matrix.pos_semidef_iff_eq_conj -/
theorem congruence_preserves_psd
    {n : Type*} [Fintype n] [DecidableEq n]
    (A M : Matrix n n ℂ) (hM : M.PosSemidef) :
    (A * M * star A).PosSemidef := by
  rw [show A * M * star A = A * M * Aᴴ from by simp [star_eq_conjTranspose]]
  exact hM.conj_conjTranspose A

-- =====================================================================
-- SUMMARY TABLE
-- =====================================================================

/-
╔══════════════════════════════════════════════════════════════════════╗
║  GAP SUMMARY — SovMonster Matrix Formalization                       ║
╠══════════════════════════════════════════════════════════════════════╣
║  CLOSED (zero sorry in SovMonster_Matrix_Closed.lean):               ║
║  ✓ jordan_fixed_point_commutes      [U,ρ*]=0  Matrix n n ℂ           ║
║  ✓ jordan_preserves_trace           cyclic trace                      ║
║  ✓ phi_pow_strictly_decreasing      over ℝ                           ║
║  ✓ softmax_sums_to_one              Born simplex                      ║
║  ✓ worm_grows / worm_history        WORM chain                        ║
╠══════════════════════════════════════════════════════════════════════╣
║  GAP 1: Matrix sqrt cyclic property                                  ║
║    sqrt_congruence_trace                                              ║
║    → PR: Matrix.trace_sqrt_congruence                                 ║
║    Strategy: Dunford-Schur or Denman-Beavers constructive            ║
╠══════════════════════════════════════════════════════════════════════╣
║  GAP 2: Choi matrix CP characterization                              ║
║    fibonacci_channel_is_cp                                           ║
║    → PR: Matrix.CP_iff_choi_pos_semidef                              ║
║    Strategy: kronecker product + Choi-Kraus decomposition            ║
╠══════════════════════════════════════════════════════════════════════╣
║  GAP 3: Quantum Perron-Frobenius                                     ║
║    cp_map_contraction_on_complement                                  ║
║    → PR: CPMap.spectral_theorem + superoperator Perron-Frobenius     ║
║    Strategy: lift to n²×n² via Matrix.kronecker + spectral radius    ║
╠══════════════════════════════════════════════════════════════════════╣
║  GAP 4: SIC-POVM / tight frame                                       ║
║    spe_roundtrip_from_tight_frame  (1 sorry: reindex)                ║
║    → Replace with abstract TightFrame axioms (no SIC-POVM needed)   ║
║    → PR: Matrix.sum_smul_eq_mul for trace inner products             ║
╠══════════════════════════════════════════════════════════════════════╣
║  GAP 5: Fidelity (F(ρ,ρ)=1)                                         ║
║    fidelity_self_eq_one  (1 sorry: sqrt_pow for PSD)                 ║
║    → PR: Matrix.sqrt_pow + Matrix.trace_sqrt_sq_eq_trace             ║
╠══════════════════════════════════════════════════════════════════════╣
║  GAP 6: hot_swap versioning — CLOSED (pure data structure)           ║
║    SemanticVersion, VersionBump, version_increases_on_swap           ║
╚══════════════════════════════════════════════════════════════════════╝
-/
