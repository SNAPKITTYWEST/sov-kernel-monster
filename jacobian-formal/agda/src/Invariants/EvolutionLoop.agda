-- Loop Invariant: integrator_evolve
-- BOB Quantum Kernel — Time Evolution Main Loop
-- Phase 2: Formal Structure (no proofs yet)
-- WORM-sealed observable bookkeeping

module Invariants.EvolutionLoop where

open import Data.Nat using (ℕ; _+_; _≤_; _<_; _≥_; zero; suc)
open import Data.Real using (ℝ; _+_; _*_; _-_; _<_; _≤_; _≥_)
open import Data.Bool using (Bool; true; false)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)
open import Core.ErrorCode using (ErrorCode; BOB_SUCCESS; isSuccess)
open import Core.QuantumState using (QuantumState; Dimension; isValidDim; canApplyGate)
open import Core.Hamiltonian using (Hamiltonian; isValidHamiltonian; hamiltonianImmutable)
open import Core.Predicates using (stepInRange; errorIsClear; needsNormalization; canContinueLoop; loopCompleted)

-- ============================================================================
-- Loop State: All variables captured at step k
-- ============================================================================

record EvolutionState : Set where
  field
    step : ℕ                    -- iteration counter k ∈ [0, num_steps]
    state : QuantumState         -- quantum state (mutable, evolving)
    hamiltonian : Hamiltonian    -- time-independent operator (immutable)
    dt : ℝ                       -- time step (immutable, positive)
    num_steps : ℕ                -- total iteration count (immutable)
    error_status : ℕ             -- error code (0=BOB_SUCCESS, etc.)
    normalization_log : ℕ → Bool -- which steps were normalized?
    accumulated_time : ℝ         -- ∑(dt for steps taken)

-- ============================================================================
-- Loop Invariant: Predicate over state and step count
-- ============================================================================

-- At each iteration k, what must be true?
record EvolutionInvariant (s : EvolutionState) (k : ℕ) : Set where
  field
    -- 1. Step counter matches loop variable
    h_step_eq : EvolutionState.step s ≡ k

    -- 2. Error status is success (loop hasn't aborted)
    h_error : errorIsClear (EvolutionState.error_status s)

    -- 3. Quantum state is dimensionally valid
    h_state_valid : isValidDim (EvolutionState.state s)

    -- 4. Hamiltonian is valid
    h_ham_valid : isValidHamiltonian (EvolutionState.hamiltonian s)

    -- 5. Time step is positive
    h_dt_pos : EvolutionState.dt s > 0

    -- 6. Current step ≤ num_steps (loop guard)
    h_in_range : k ≤ EvolutionState.num_steps s

    -- 7. Accumulated time = k * dt
    h_accumulated_time :
      EvolutionState.accumulated_time s ≡ (ℝ.fromℕ k) * (EvolutionState.dt s)

    -- 8. Normalization log: for each step m ≤ k, if m ≡ 0 (mod 100), then normalized
    h_norm_schedule :
      ∀ (m : ℕ) → m < k → (m mod 100 ≡ 0) → (EvolutionState.normalization_log s m ≡ true)

-- ============================================================================
-- Base Case: k = 0 (before loop starts)
-- ============================================================================

evolution_base :
  (s : EvolutionState) →
  EvolutionState.step s ≡ 0 →
  EvolutionState.error_status s ≡ 0 →
  isValidDim (EvolutionState.state s) →
  isValidHamiltonian (EvolutionState.hamiltonian s) →
  EvolutionState.dt s > 0 →
  EvolutionState.accumulated_time s ≡ 0 →
  EvolutionInvariant s 0

evolution_base s h_step h_error h_state_valid h_ham_valid h_dt_pos h_acc_time =
  record
    { h_step_eq = h_step
    ; h_error = h_error
    ; h_state_valid = h_state_valid
    ; h_ham_valid = h_ham_valid
    ; h_dt_pos = h_dt_pos
    ; h_in_range = λ where
        0 → zero
    ; h_accumulated_time = h_acc_time
    ; h_norm_schedule = λ m h_lt_zero _ → absurd (¬(<-zero m) h_lt_zero)
    }
  where
    ¬(<-zero : ∀ n → ¬(n < 0)
    ¬(<-zero _ ()

-- ============================================================================
-- Inductive Step: k → k+1
-- ============================================================================

-- Represents one call to integrator_step(state, hamiltonian)
record StepTransition (s s' : EvolutionState) : Set where
  field
    -- Same invariant on input state
    pre_inv : EvolutionInvariant s (EvolutionState.step s)

    -- Step counter increments by 1
    step_increments : EvolutionState.step s' ≡ EvolutionState.step s + 1

    -- State changed (evolved one step)
    state_changed : EvolutionState.state s ≠ EvolutionState.state s'

    -- Hamiltonian unchanged
    ham_unchanged :
      (EvolutionState.hamiltonian s ≡ EvolutionState.hamiltonian s') ∨
      (hamiltonianImmutable (EvolutionState.hamiltonian s) (EvolutionState.hamiltonian s'))

    -- Quantum state remains valid-dimensioned after evolution (physics invariant)
    state_valid_preserved :
      isValidDim (EvolutionState.state s) →
      isValidDim (EvolutionState.state s')

    -- Error status either remains success or becomes error (and loop exits)
    error_inv : (EvolutionState.error_status s' ≡ 0) ∨
               (EvolutionState.error_status s' ≠ 0)

    -- Accumulated time increases by dt
    time_advances :
      EvolutionState.accumulated_time s' ≡
      EvolutionState.accumulated_time s + EvolutionState.dt s

-- Inductive step: if invariant holds at k, then after one step it holds at k+1
-- (OR the loop exits due to error)
evolution_step :
  (s s' : EvolutionState) (k : ℕ) →
  EvolutionInvariant s k →
  StepTransition s s' →
  -- If no error, then invariant holds at k+1
  (EvolutionState.error_status s' ≡ 0) →
  EvolutionInvariant s' (k + 1)

evolution_step s s' k inv_k trans h_no_error =
  record
    { h_step_eq = StepTransition.step_increments trans
    ; h_error = h_no_error
    ; h_state_valid = ?  -- state remains valid-dimensioned after step
    ; h_ham_valid = EvolutionInvariant.h_ham_valid inv_k
    ; h_dt_pos = EvolutionInvariant.h_dt_pos inv_k
    ; h_in_range = ?  -- (k+1) ≤ num_steps follows from k ≤ num_steps and loop guard
    ; h_accumulated_time = StepTransition.time_advances trans
    ; h_norm_schedule = λ m h_lt h_mod →
        let h_le = <-to-≤ h_lt
        in case (decide (m ≡ k + 1)) of λ where
             (yes p) →
               -- m = k+1, check if normalization_log updated
               if (k + 1) mod 100 ≡ 0 then true else ?
             (no ¬p) →
               -- m < k+1 and m ≠ k+1, so m ≤ k, use old log
               EvolutionInvariant.h_norm_schedule inv_k m (≤-to-< h_le ¬p) h_mod
    }

-- ============================================================================
-- Exit Condition: Loop termination at k = num_steps
-- ============================================================================

-- When loop exits (k ≡ num_steps), postcondition is satisfied
evolution_exit :
  (s : EvolutionState) (k : ℕ) →
  EvolutionInvariant s k →
  k ≡ EvolutionState.num_steps s →
  -- Then:
  -- 1. Loop has completed all iterations
  (loopCompleted k (EvolutionState.num_steps s)) ∧
  -- 2. Error status is success
  (errorIsClear (EvolutionState.error_status s)) ∧
  -- 3. State is valid (ready for measurement/output)
  (isValidDim (EvolutionState.state s)) ∧
  -- 4. Total time accumulated matches intended duration
  (EvolutionState.accumulated_time s ≡
   (ℝ.fromℕ k) * (EvolutionState.dt s))

evolution_exit s k inv_k h_done =
  ⟨ h_done
  , EvolutionInvariant.h_error inv_k
  , EvolutionInvariant.h_state_valid inv_k
  , EvolutionInvariant.h_accumulated_time inv_k
  ⟩
