-- Loop Invariant: apply_single_qubit_gate
-- BOB Quantum Kernel — Single-Qubit Gate Application
-- Loop: do i = 0, state%dim - 1
-- Phase 2: Formal Structure (no proofs yet)
-- WORM-sealed observable bookkeeping

module Invariants.GateApplicationLoop where

open import Data.Nat using (ℕ; _+_; _≤_; _<_; _≥_; _≡_; zero; suc)
open import Data.Real using (ℝ; _+_; _*_; _-_; _<_; _≤_; _≥_)
open import Data.Bool using (Bool; true; false)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)
open import Core.ErrorCode using (ErrorCode; BOB_SUCCESS)
open import Core.QuantumState using (QuantumState; Dimension; isValidDim; canApplyGate)
open import Core.Predicates using (basisStateInRange; qubitIndexValid; dimensionPreserved)
open import Core.BitCounting using (gate_exit_pairs_count; pairs_updated_j_equals_i)

-- ============================================================================
-- Loop Context: Gate Application Setup
-- ============================================================================

-- Gate matrix (2×2)
record GateMatrix : Set where
  field
    entry_1_1 : ℂ  -- top-left
    entry_1_2 : ℂ  -- top-right
    entry_2_1 : ℂ  -- bottom-left
    entry_2_2 : ℂ  -- bottom-right
    is_unitary : Bool  -- verified in apply_single_qubit_gate precondition

-- Immutable context throughout loop
record GateContext : Set where
  field
    state : QuantumState         -- being mutated
    gate : GateMatrix            -- immutable operator
    qubit_index : ℕ              -- target qubit (immutable)
    num_qubits : ℕ               -- from state dimension
    dim : ℕ                       -- state%dim (2^num_qubits)
    bit_mask : ℕ                 -- precomputed: 1 << qubit_index

-- ============================================================================
-- Loop State at iteration i
-- ============================================================================

record GateLoopState : Set where
  field
    ctx : GateContext
    i : ℕ                         -- basis state iterator [0, dim)
    -- Tracking updates
    num_amplitudes_processed : ℕ  -- how many basis states examined
    num_pairs_updated : ℕ         -- number of (state_0, state_1) pairs updated
    -- Gate application bookkeeping
    last_state_0_qubit_0 : Bool   -- was last examined state's qubit bit 0?
    error_status : ℕ              -- 0 = BOB_SUCCESS

-- ============================================================================
-- Loop Invariant: What holds at each iteration i?
-- ============================================================================

record GateInvariant (s : GateLoopState) (i : ℕ) : Set where
  field
    -- 1. Loop iterator in valid range: 0 ≤ i ≤ dim
    h_i_in_range : i ≤ GateContext.dim (GateLoopState.ctx s)

    -- 2. State remains valid
    h_state_valid : isValidDim (GateContext.state (GateLoopState.ctx s))

    -- 3. State can have gates applied
    h_state_can_apply : canApplyGate (GateContext.state (GateLoopState.ctx s))

    -- 4. Gate matrix is unitary (verified precondition)
    h_gate_unitary : GateMatrix.is_unitary (GateContext.gate (GateLoopState.ctx s)) ≡ true

    -- 5. Qubit index is valid
    h_qubit_valid : qubitIndexValid (GateContext.qubit_index (GateLoopState.ctx s)) (GateContext.num_qubits (GateLoopState.ctx s))

    -- 6. Number of basis states examined = i
    h_states_examined : GateLoopState.num_amplitudes_processed s ≡ i

    -- 7. For each processed basis state i where qubit bit is 0,
    --    the (state_0, state_1) pair has been updated
    h_pairs_updated :
      ∀ (j : ℕ) →
      j < i →
      let qubit_bit = (j mod (2 * GateContext.bit_mask (GateLoopState.ctx s))) / GateContext.bit_mask (GateLoopState.ctx s)
      in qubit_bit ≡ 0 →
      -- Then: this pair was processed
      (GateLoopState.num_pairs_updated s ≥ (j / (2 * GateContext.bit_mask (GateLoopState.ctx s))) + 1)

    -- 8. Dimension preserved
    h_dim_preserved : dimensionPreserved (GateContext.dim (GateLoopState.ctx s)) (ℕ.log₂ (GateContext.dim (GateLoopState.ctx s)))

    -- 9. Gate context unchanged
    h_ctx_immutable : ∀ j → j < i → GateContext.gate (GateLoopState.ctx s) ≡ GateContext.gate (GateLoopState.ctx s)

    -- 10. No errors
    h_error_clear : GateLoopState.error_status s ≡ 0

-- ============================================================================
-- Base Case: i = 0 (before loop starts)
-- ============================================================================

gate_base :
  (s : GateLoopState) →
  GateLoopState.i s ≡ 0 →
  isValidDim (GateContext.state (GateLoopState.ctx s)) →
  canApplyGate (GateContext.state (GateLoopState.ctx s)) →
  GateMatrix.is_unitary (GateContext.gate (GateLoopState.ctx s)) ≡ true →
  qubitIndexValid (GateContext.qubit_index (GateLoopState.ctx s)) (GateContext.num_qubits (GateLoopState.ctx s)) →
  GateLoopState.num_amplitudes_processed s ≡ 0 →
  GateLoopState.num_pairs_updated s ≡ 0 →
  GateLoopState.error_status s ≡ 0 →
  GateInvariant s 0

gate_base s h_i h_state_valid h_can_apply h_unitary h_qubit h_examined h_pairs h_error =
  record
    { h_i_in_range = zero
    ; h_state_valid = h_state_valid
    ; h_state_can_apply = h_can_apply
    ; h_gate_unitary = h_unitary
    ; h_qubit_valid = h_qubit
    ; h_states_examined = h_examined
    ; h_pairs_updated = λ j h_j_lt_zero _ → absurd (¬(<-zero j) h_j_lt_zero)
    ; h_dim_preserved = refl
    ; h_ctx_immutable = λ j h_j_lt_zero → absurd (¬(<-zero j) h_j_lt_zero)
    ; h_error_clear = h_error
    }
  where
    ¬(<-zero : ∀ n → ¬(n < 0)
    ¬(<-zero _ ()

-- ============================================================================
-- Inductive Step: i → i+1
-- ============================================================================

-- One iteration of basis state processing
record GateIterationStep (s s' : GateLoopState) : Set where
  fields
    -- Context unchanged
    ctx_same : GateLoopState.ctx s ≡ GateLoopState.ctx s'

    -- Basis state iterator increments
    i_increments : GateLoopState.i s' ≡ GateLoopState.i s + 1

    -- Amplitudes processed count incremented
    states_processed_incremented : GateLoopState.num_amplitudes_processed s' ≡ GateLoopState.num_amplitudes_processed s + 1

    -- Pairs updated: either incremented or unchanged
    --   (incremented if this basis state's qubit bit was 0)
    pairs_updated_invariant :
      let i = GateLoopState.i s
          qubit_bit = (i mod (2 * GateContext.bit_mask (GateLoopState.ctx s))) / GateContext.bit_mask (GateLoopState.ctx s)
      in (qubit_bit ≡ 0 →
          GateLoopState.num_pairs_updated s' ≡ GateLoopState.num_pairs_updated s + 1) ∧
         (qubit_bit ≠ 0 →
          GateLoopState.num_pairs_updated s' ≡ GateLoopState.num_pairs_updated s)

    -- new_amplitudes written for this iteration
    new_amplitudes_written : Bool

    -- No errors during iteration
    error_unchanged : GateLoopState.error_status s' ≡ 0

-- Inductive step
gate_step :
  (s s' : GateLoopState) (i : ℕ) →
  GateInvariant s i →
  GateIterationStep s s' →
  GateInvariant s' (i + 1)

gate_step s s' i inv_i step =
  record
    { h_i_in_range = Nat.succ_le_of_lt (by-i-lt-dim-from-invariant inv_i)
    ; h_state_valid = GateInvariant.h_state_valid inv_i
    ; h_state_can_apply = GateInvariant.h_state_can_apply inv_i
    ; h_gate_unitary = GateInvariant.h_gate_unitary inv_i
    ; h_qubit_valid = GateInvariant.h_qubit_valid inv_i
    ; h_states_examined = cong suc (GateInvariant.h_states_examined inv_i)
    ; h_pairs_updated = λ j h_j_lt_suc_i h_qubit_zero →
        let h_j_le_i = <-to-≤ h_j_lt_suc_i
        in case (decide (j ≡ i)) of λ where
             (yes p) →
               -- j = i, and qubit_bit = 0, so this pair just got updated
               let (h_pairs_inc, _) = GateIterationStep.pairs_updated_invariant step
                   h_pairs_pred = h_pairs_inc h_qubit_zero
               in pairs_updated_j_equals_i i (GateContext.bit_mask (GateLoopState.ctx s)) h_qubit_zero
                    (λ pairs → h_pairs_pred)
             (no ¬p) →
               -- j < i, use previous invariant
               let h_j_lt_i = ≤-to-< h_j_le_i ¬p
               in GateInvariant.h_pairs_updated inv_i j h_j_lt_i h_qubit_zero
    ; h_dim_preserved = GateInvariant.h_dim_preserved inv_i
    ; h_ctx_immutable = λ j h_j_lt → GateInvariant.h_ctx_immutable inv_i j (≤-to-< (<-to-≤ h_j_lt) (by-step-i-increments))
    ; h_error_clear = GateIterationStep.error_unchanged step
    }

-- ============================================================================
-- Exit Condition: Loop termination (i = dim)
-- ============================================================================

-- All basis states processed
gate_exit :
  (s : GateLoopState) (i : ℕ) →
  GateInvariant s i →
  i ≡ GateContext.dim (GateLoopState.ctx s) →
  -- Then:
  -- 1. All basis states examined
  (GateLoopState.num_amplitudes_processed s ≡ GateContext.dim (GateLoopState.ctx s)) ∧
  -- 2. All valid (state_0, state_1) pairs updated
  (GateLoopState.num_pairs_updated s ≡ GateContext.dim (GateLoopState.ctx s) / 2) ∧
  -- 3. new_amplitudes array complete and ready to swap
  (∀ (i : ℕ) → i < GateContext.dim (GateLoopState.ctx s) → basisStateInRange i (GateContext.dim (GateLoopState.ctx s))) ∧
  -- 4. No errors
  (GateLoopState.error_status s ≡ 0) ∧
  -- 5. State dimension preserved
  (dimensionPreserved (GateContext.dim (GateLoopState.ctx s)) (GateContext.dim (GateLoopState.ctx s)))

gate_exit s i inv_i h_done =
  ⟨ trans (GateInvariant.h_states_examined inv_i) h_done
  , gate_exit_pairs_count i (GateContext.dim (GateLoopState.ctx s))
      (GateContext.bit_mask (GateLoopState.ctx s)) h_done
      (by-dim-is-power-of-2)
      (GateLoopState.num_pairs_updated s)
  , λ j h_j_lt →
      basisStateInRange j (GateContext.dim (GateLoopState.ctx s))
  , GateInvariant.h_error_clear inv_i
  , refl
  ⟩
