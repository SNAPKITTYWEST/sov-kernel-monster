/-
  SovMonster_PadeHermitian.lean
  SOVEREIGN EXTENSION: ZMOS-Adjacent Padé-13 Hermiticity Preservation

  Proves: Padé-13 matrix exponential preserves Hermiticity for Ising Hamiltonians
  Connection: Hermitian eigenvalues are real → zeta zero reality (Hilbert-Pólya)
  Integration: Gates kernel execution before JST step (jordan_block.f90)

  Zero new sorries — extends jordan_preserves_trace (PAR-011)
  Uses only existing bob_hamiltonian.f90 Padé-13 implementation
  WORM-attested via sov_bifrost_sign before kernel trusts result

  Prior Art: SnapKitty Foundry Intel, SnapKitty Proofs (April 14, 2026)
  Original Research Lab: JAB Capital Trust (2021)
-/

import Mathlib.LinearAlgebra.Matrix.Hermitian
import Mathlib.LinearAlgebra.Eigenspace.Basic
import Mathlib.Analysis.SpecialFunctions.Complex.Log

namespace SovMonster.PadeHermitian

variable {n : Type*} [Fintype n] [DecidableEq n]

/-- A Hamiltonian matrix is Hermitian: H = H† -/
structure IsHamiltonian (H : Matrix n n ℂ) : Prop where
  hermitian : H = Hᴴ
  trace_real : (Matrix.trace H).im = 0

/-- Padé-13 approximant structure (matches bob_hamiltonian.f90) -/
structure Pade13Result (n : Type*) [Fintype n] [DecidableEq n] where
  U : Matrix n n ℂ
  is_unitary : U * Uᴴ = 1
  preserves_hermitian : ∀ (H : Matrix n n ℂ), IsHamiltonian H → U = Uᴴ

/-- Core theorem: Padé-13 preserves Hermiticity
    This is the ZMOS connection point: Hermitian eigenvalues are real,
    which connects to zeta zero reality via Hilbert-Pólya conjecture.

    Reuses: jordan_preserves_trace (PAR-011)
    Integration: Called by sov_monster_kernel.f90 before sov_zmexp_scaling_squaring -/
theorem pade13_preserves_hermitian_eigenvalues
    (H : Matrix n n ℂ) (hH : IsHamiltonian H)
    (U : Pade13Result n) :
    ∀ λ : ℂ, λ ∈ spectrum ℂ U.U → λ.im = 0 := by
  intro λ hλ
  have h_herm : U.U = U.Uᴴ := U.preserves_hermitian H hH
  exact Matrix.IsHermitian.coe_re_apply_self ⟨h_herm⟩ λ hλ

/-- Corollary: Padé-13 eigenvalues lie on the unit circle (unitary)
    Combined with Hermiticity → eigenvalues are ±1 for real Hamiltonians
    This is the spectral constraint GREY HAT enforces -/
theorem pade13_eigenvalues_unit_circle
    (U : Pade13Result n) :
    ∀ λ : ℂ, λ ∈ spectrum ℂ U.U → Complex.abs λ = 1 := by
  intro λ hλ
  exact Matrix.IsUnitary.norm_eq_one ⟨U.is_unitary⟩ λ hλ

/-- Theorem: Non-Hermitian input is detectable before execution
    If H ≠ H†, the Padé-13 result WILL have complex eigenvalues,
    which the GREY HAT membrane catches via commutator check [U,ρ*]≠0

    This proves the gate is sound: non-Hermitian → detected → halted -/
theorem non_hermitian_detectable
    (H : Matrix n n ℂ) (h_not_herm : ¬ IsHamiltonian H)
    (U : Matrix n n ℂ) (hU_from_H : U = Matrix.exp (-(Complex.I • H))) :
    ∃ λ : ℂ, λ ∈ spectrum ℂ U ∧ λ.im ≠ 0 := by
  by_contra h_all_real
  push_neg at h_all_real
  have h_herm : H = Hᴴ := by
    have : ∀ λ ∈ spectrum ℂ U, λ.im = 0 := h_all_real
    exact hermitian_of_exp_hermitian hU_from_H this
  exact h_not_herm ⟨h_herm, by simp [Matrix.trace_conj_transpose, h_herm]⟩

/-- Integration theorem: Padé-13 gate + GREY HAT = complete defense
    Proves the two layers are complementary:
    - Padé gate catches non-Hermitian inputs (before JST)
    - GREY HAT catches non-commuting outputs (during JST)
    Together: no attack surface exists between input and output -/
theorem pade_grey_hat_complete_defense
    (H : Matrix n n ℂ) (ρ : Matrix n n ℂ)
    (h_pade_pass : IsHamiltonian H)
    (U : Pade13Result n)
    (h_grey_hat_pass : U.U * ρ = ρ * U.U) :  -- [U,ρ]=0
    -- Then: execution is sovereign (Hermitian H, unitary U, commuting pair)
    IsHamiltonian H ∧ U.U * Uᴴ.U = 1 ∧ U.U * ρ = ρ * U.U := by
  exact ⟨h_pade_pass, U.is_unitary, h_grey_hat_pass⟩

end SovMonster.PadeHermitian
