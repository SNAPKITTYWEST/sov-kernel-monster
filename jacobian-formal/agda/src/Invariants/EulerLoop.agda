-- Loop Invariant: step_euler
-- BOB Quantum Kernel — Euler Method Integration
-- Loop: do i = 1, state%dim
-- Phase 2: Formal Structure (no proofs yet)
-- WORM-sealed observable bookkeeping

module Invariants.EulerLoop where

open import Data.Nat using (ℕ; _+_; _≤_; _<_; _≥_; zero; suc)
open import Data.Real using (ℝ; _+_; _*_; _-_; _<_; _≤_; _≥_)
open import Data.Bool using (Bool; true; false)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)
open import Core.ErrorCode using (ErrorCode; BOB_SUCCESS; isSuccess)
open import Core.QuantumState using (QuantumState; Dimension; isValidDim)
open import Core.Hamiltonian using (Hamiltonian; isValidHamiltonian)
open import Core.Predicates using (basisStateInRange; dimensionPreserved; loopCompleted)

-- ============================================================================
-- Loop Context: Euler step pre-conditions
-- ============================================================================

-- Immutable parameters throughout the loop
record EulerContext : Set where
  field
    state : QuantumState           -- being mutated
    hamiltonian : Hamiltonian      -- immutable operator
    dt : ℝ                         -- immutable time step
    dim : ℕ                        -- state dimension (≥ 1)

-- ============================================================================
-- Loop State at iteration i
-- ============================================================================

record EulerLoopState : Set where
  field
    ctx : EulerContext
    i : ℕ                          -- iteration counter [1, dim]
    -- Updated amplitudes accumulated so far
    num_updated : ℕ                -- how many amplitudes updated (≤ i-1)
    -- Tracking computation
    h_psi_computed : Bool          -- H|ψ⟩ computed?
    error_status : ℕ               -- 0 = BOB_SUCCESS

-- ============================================================================
-- Loop Invariant: What holds at each iteration i?
-- ============================================================================

record EulerInvariant (s : EulerLoopState) (i : ℕ) : Set where
  field
    -- 1. Loop iterator is in valid range: 1 ≤ i ≤ dim
    h_i_in_range : (i ≥ 1 ∧ i ≤ EulerContext.dim (EulerLoopState.ctx s)) ∨ (i ≡ EulerContext.dim (EulerLoopState.ctx s) + 1)

    -- 2. State remains valid
    h_state_valid : isValidDim (EulerContext.state (EulerLoopState.ctx s))

    -- 3. Hamiltonian remains valid and unchanged
    h_ham_valid : isValidHamiltonian (EulerContext.hamiltonian (EulerLoopState.ctx s))

    -- 4. Time step is positive
    h_dt_pos : EulerContext.dt (EulerLoopState.ctx s) > 0

    -- 5. H|ψ⟩ has been computed (precondition before loop)
    h_h_psi_ready : EulerLoopState.h_psi_computed s ≡ true

    -- 6. Number of updated amplitudes = i - 1
    --    (after iteration i, amplitude i has been updated)
    h_num_updated : EulerLoopState.num_updated s ≡ i - 1

    -- 7. Error status remains success throughout
    h_error_clear : EulerLoopState.error_status s ≡ 0

    -- 8. All predecessors updated in order
    h_ordered : ∀ (j : ℕ) → j < i → basisStateInRange j (EulerContext.dim (EulerLoopState.ctx s))

-- ============================================================================
-- Base Case: i = 1 (first iteration)
-- ============================================================================

euler_base :
  (s : EulerLoopState) →
  EulerLoopState.i s ≡ 1 →
  isValidDim (EulerContext.state (EulerLoopState.ctx s)) →
  isValidHamiltonian (EulerContext.hamiltonian (EulerLoopState.ctx s)) →
  EulerContext.dt (EulerLoopState.ctx s) > 0 →
  EulerLoopState.h_psi_computed s ≡ true →
  EulerLoopState.num_updated s ≡ 0 →
  EulerLoopState.error_status s ≡ 0 →
  1 ≤ EulerContext.dim (EulerLoopState.ctx s) →
  EulerInvariant s 1

euler_base s h_i h_state_valid h_ham_valid h_dt_pos h_h_psi h_num_updated h_error h_dim_pos =
  record
    { h_i_in_range = inl ⟨ refl , h_dim_pos ⟩
    ; h_state_valid = h_state_valid
    ; h_ham_valid = h_ham_valid
    ; h_dt_pos = h_dt_pos
    ; h_h_psi_ready = h_h_psi
    ; h_num_updated = h_num_updated
    ; h_error_clear = h_error
    ; h_ordered = λ j h_j_lt_one → absurd (¬(<-one j) h_j_lt_one)
    }
  where
    ¬(<-one : ∀ n → ¬(n < 1)
    ¬(<-one 0 ()

-- ============================================================================
-- Inductive Step: i → i+1
-- ============================================================================

-- Represents one iteration of the loop body
record EulerIterationStep (s s' : EulerLoopState) : Set where
  field
    -- Same context
    ctx_same : EulerLoopState.ctx s ≡ EulerLoopState.ctx s'

    -- Iterator increments
    i_increments : EulerLoopState.i s' ≡ EulerLoopState.i s + 1

    -- Amplitude i was updated: new_amplitudes[i] = old[i] - CI * dt * h_psi[i]
    amplitude_updated :
      EulerLoopState.num_updated s' ≡ EulerLoopState.num_updated s + 1

    -- H|ψ⟩ still available
    h_psi_still_ready : EulerLoopState.h_psi_computed s' ≡ true

    -- No errors during iteration
    error_unchanged : EulerLoopState.error_status s' ≡ 0

-- Inductive step
euler_step :
  (s s' : EulerLoopState) (i : ℕ) →
  EulerInvariant s i →
  EulerIterationStep s s' →
  EulerInvariant s' (i + 1)

euler_step s s' i inv_i step =
  record
    { h_i_in_range =
        case (decide (i + 1 ≡ EulerContext.dim (EulerLoopState.ctx s) + 1)) of λ where
          (yes p) → inr p
          (no ¬p) → inl ⟨ ?
            , ?  -- i ≥ 1 implies i+1 ≥ 2; need to show i+1 ≤ dim
            ⟩
    ; h_state_valid = EulerInvariant.h_state_valid inv_i
    ; h_ham_valid = EulerInvariant.h_ham_valid inv_i
    ; h_dt_pos = EulerInvariant.h_dt_pos inv_i
    ; h_h_psi_ready = EulerIterationStep.h_psi_still_ready step
    ; h_num_updated = cong suc (EulerInvariant.h_num_updated inv_i)
    ; h_error_clear = EulerIterationStep.error_unchanged step
    ; h_ordered = λ j h_j_lt →
        let h_j_lt_suc_i = h_j_lt
            h_j_le_i = <-to-≤ h_j_lt_suc_i
        in case (decide (j ≡ i)) of λ where
             (yes p) →
               -- j = i, so j is in range [1, dim]
               let h_i_in = EulerInvariant.h_i_in_range inv_i
               in case h_i_in of λ where
                    (inl ⟨ h_i_ge_1 , h_i_le_dim ⟩) →
                      basisStateInRange i (EulerContext.dim (EulerLoopState.ctx s))
                    (inr p_done) → absurd (¬-all-le-dim i (by-contradiction p_done))
             (no ¬p) →
               -- j < i, use previous invariant
               EulerInvariant.h_ordered inv_i j (≤-to-< h_j_le_i ¬p)
    }

-- ============================================================================
-- Exit Condition: Loop termination (i = dim + 1)
-- ============================================================================

-- All amplitudes have been updated
euler_exit :
  (s : EulerLoopState) (i : ℕ) →
  EulerInvariant s i →
  i ≡ EulerContext.dim (EulerLoopState.ctx s) + 1 →
  -- Then:
  -- 1. All amplitudes updated
  (EulerLoopState.num_updated s ≡ EulerContext.dim (EulerLoopState.ctx s)) ∧
  -- 2. Loop completed
  (loopCompleted i (EulerContext.dim (EulerLoopState.ctx s) + 1)) ∧
  -- 3. No errors
  (EulerLoopState.error_status s ≡ 0) ∧
  -- 4. State still valid
  (isValidDim (EulerContext.state (EulerLoopState.ctx s)))

euler_exit s i inv_i h_done =
  ⟨ ?  -- num_updated = i - 1 = (dim + 1) - 1 = dim
  , h_done
  , EulerInvariant.h_error_clear inv_i
  , EulerInvariant.h_state_valid inv_i
  ⟩
