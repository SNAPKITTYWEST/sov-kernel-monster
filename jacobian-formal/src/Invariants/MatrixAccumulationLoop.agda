-- Loop Invariant: step_rk4_matrix_accumulation
-- BOB Quantum Kernel — RK4 Matrix Exponential Computation
-- Loop: do k = 1, MAX_TERMS (Taylor series accumulation)
-- Phase 2: Formal Structure (no proofs yet)
-- WORM-sealed observable bookkeeping

module Invariants.MatrixAccumulationLoop where

open import Data.Nat using (ℕ; _+_; _≤_; _<_; _≥_; zero; suc)
open import Data.Real using (ℝ; _+_; _*_; _-_; _/_;  _<_; _≤_; _≥_)
open import Data.Bool using (Bool; true; false)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)
open import Core.ErrorCode using (ErrorCode; BOB_SUCCESS)
open import Core.QuantumState using (QuantumState; Dimension)
open import Core.Predicates using (taylorTermIndex)

-- ============================================================================
-- Loop Context: RK4 Taylor Series Accumulation
-- ============================================================================

-- Immutable throughout loop
record MatrixAccContext : Set where
  field
    dim : ℕ                  -- state dimension
    state_dim : ℕ            -- matrix is state_dim × state_dim
    dt : ℝ                   -- time step (immutable)
    max_terms : ℕ            -- MAX_TERMS = 20 (or configurable)
    hamiltonian_matrix_entries : ℕ  -- precomputed; should = state_dim²

-- ============================================================================
-- Loop State at iteration k (Taylor coefficient)
-- ============================================================================

record MatrixAccLoopState : Set where
  field
    ctx : MatrixAccContext
    k : ℕ                         -- term index [1, max_terms]
    -- Cumulative state
    exp_matrix_accumulated : ℕ    -- number of matrix elements updated so far
    factorial_k : ℝ               -- k! (recomputed/cached)
    term_coefficient : ℝ          -- (-i*dt)^k / k!
    -- Tracking
    num_hamiltonian_sweeps : ℕ    -- how many i,j sweeps completed
    error_status : ℕ              -- 0 = BOB_SUCCESS

-- ============================================================================
-- Loop Invariant: What holds at each term k?
-- ============================================================================

record MatrixAccInvariant (s : MatrixAccLoopState) (k : ℕ) : Set where
  field
    -- 1. Term index in valid range
    h_k_valid : taylorTermIndex k (MatrixAccContext.max_terms (MatrixAccLoopState.ctx s))

    -- 2. dt is positive
    h_dt_pos : MatrixAccContext.dt (MatrixAccLoopState.ctx s) > 0

    -- 3. State dimension valid
    h_dim_pos : MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) ≥ 1

    -- 4. Factorial k > 0
    h_factorial_pos : MatrixAccLoopState.factorial_k s > 0

    -- 5. Term coefficient is ratio of power and factorial
    --    More precisely: coefficient = (-dt)^k / k!
    h_coefficient_ratio :
      let fact_k = MatrixAccLoopState.factorial_k s
          pow_dt_k = ((MatrixAccContext.dt (MatrixAccLoopState.ctx s)) ^ k)
      in MatrixAccLoopState.term_coefficient s ≡ pow_dt_k / fact_k

    -- 6. Number of matrix sweeps = k - 1
    --    (each term iteration sweeps the entire dim×dim matrix once)
    h_sweeps_count : MatrixAccLoopState.num_hamiltonian_sweeps s ≡ k - 1

    -- 7. Matrix accumulation: number of updated elements = k * (dim²)
    h_matrix_accumulated :
      MatrixAccLoopState.exp_matrix_accumulated s ≡
      k * (MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) * MatrixAccContext.state_dim (MatrixAccLoopState.ctx s))

    -- 8. No errors
    h_error_clear : MatrixAccLoopState.error_status s ≡ 0

-- ============================================================================
-- Base Case: k = 1 (first Taylor term)
-- ============================================================================

matrix_acc_base :
  (s : MatrixAccLoopState) →
  MatrixAccLoopState.k s ≡ 1 →
  MatrixAccContext.dt (MatrixAccLoopState.ctx s) > 0 →
  MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) ≥ 1 →
  MatrixAccContext.max_terms (MatrixAccLoopState.ctx s) ≥ 1 →  -- PRECONDITION: max_terms ≥ 1
  MatrixAccLoopState.factorial_k s ≡ 1 →  -- 1! = 1
  MatrixAccLoopState.term_coefficient s ≡ MatrixAccContext.dt (MatrixAccLoopState.ctx s) →
  MatrixAccLoopState.num_hamiltonian_sweeps s ≡ 0 →
  MatrixAccLoopState.exp_matrix_accumulated s ≡ MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) * MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) →
  MatrixAccLoopState.error_status s ≡ 0 →
  MatrixAccInvariant s 1

matrix_acc_base s h_k h_dt h_dim h_max_terms_pos h_fact h_coeff h_sweeps h_acc h_error =
  record
    { h_k_valid = h_max_terms_pos  -- 1 ≤ max_terms (from precondition)
    ; h_dt_pos = h_dt
    ; h_dim_pos = h_dim
    ; h_factorial_pos = by cong ℝ.fromℕ (Nat.factorial 1) ▸ h_fact ▸ one_pos
    ; h_coefficient_ratio = h_coeff
    ; h_sweeps_count = h_sweeps
    ; h_matrix_accumulated = h_acc
    ; h_error_clear = h_error
    }

-- ============================================================================
-- Inductive Step: k → k+1
-- ============================================================================

-- One iteration of Taylor term addition
record MatrixAccIterationStep (s s' : MatrixAccLoopState) : Set where
  field
    -- Context unchanged
    ctx_same : MatrixAccLoopState.ctx s ≡ MatrixAccLoopState.ctx s'

    -- Term index increments
    k_increments : MatrixAccLoopState.k s' ≡ MatrixAccLoopState.k s + 1

    -- Factorial updated: (k+1)! = k! * (k+1)
    factorial_updated :
      MatrixAccLoopState.factorial_k s' ≡
      (MatrixAccLoopState.factorial_k s) * (ℝ.fromℕ (MatrixAccLoopState.k s + 1))

    -- Term coefficient updated
    coefficient_updated :
      let pow_dt_k_plus_1 = (MatrixAccContext.dt (MatrixAccLoopState.ctx s)) ^ (MatrixAccLoopState.k s + 1)
          fact_k_plus_1 = MatrixAccLoopState.factorial_k s'
      in MatrixAccLoopState.term_coefficient s' ≡ pow_dt_k_plus_1 / fact_k_plus_1

    -- Matrix accumulated: one full (dim × dim) sweep
    matrix_sweep_done :
      MatrixAccLoopState.exp_matrix_accumulated s' ≡
      MatrixAccLoopState.exp_matrix_accumulated s +
      (MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) * MatrixAccContext.state_dim (MatrixAccLoopState.ctx s))

    -- Sweeps incremented
    sweeps_incremented : MatrixAccLoopState.num_hamiltonian_sweeps s' ≡ MatrixAccLoopState.num_hamiltonian_sweeps s + 1

    -- No errors
    error_unchanged : MatrixAccLoopState.error_status s' ≡ 0

-- Inductive step
matrix_acc_step :
  (s s' : MatrixAccLoopState) (k : ℕ) →
  MatrixAccInvariant s k →
  MatrixAccIterationStep s s' →
  MatrixAccInvariant s' (k + 1)

matrix_acc_step s s' k inv_k step =
  record
    { h_k_valid = Nat.succ_le_of_lt (Nat.lt_of_succ_le (Nat.succ_le_succ (MatrixAccInvariant.h_k_valid inv_k)))
    ; h_dt_pos = MatrixAccInvariant.h_dt_pos inv_k
    ; h_dim_pos = MatrixAccInvariant.h_dim_pos inv_k
    ; h_factorial_pos = Nat.cast_pos (Nat.factorial_pos (k + 1))
    ; h_coefficient_ratio =
        -- coefficient = (-dt)^(k+1) / (k+1)!
        MatrixAccIterationStep.coefficient_updated step
    ; h_sweeps_count =
        -- sweeps = k (since k+1 - 1 = k)
        cong pred (MatrixAccIterationStep.sweeps_incremented step)
    ; h_matrix_accumulated =
        -- acc = (k+1) * dim²
        let h_step_k = MatrixAccInvariant.h_matrix_accumulated inv_k
            h_sweep = MatrixAccIterationStep.matrix_sweep_done step
            dim_sq = MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) * MatrixAccContext.state_dim (MatrixAccLoopState.ctx s)
        in trans h_sweep (cong (λ x → x + dim_sq) h_step_k)
    ; h_error_clear = MatrixAccIterationStep.error_unchanged step
    }

-- ============================================================================
-- Exit Condition: Loop termination (k = max_terms + 1)
-- ============================================================================

-- All Taylor terms accumulated
matrix_acc_exit :
  (s : MatrixAccLoopState) (k : ℕ) →
  MatrixAccInvariant s k →
  k ≡ MatrixAccContext.max_terms (MatrixAccLoopState.ctx s) + 1 →
  -- Then:
  -- 1. All MAX_TERMS coefficients processed
  (MatrixAccLoopState.num_hamiltonian_sweeps s ≡ MatrixAccContext.max_terms (MatrixAccLoopState.ctx s)) ∧
  -- 2. Matrix fully accumulated
  (MatrixAccLoopState.exp_matrix_accumulated s ≡
   (MatrixAccContext.max_terms (MatrixAccLoopState.ctx s)) *
   (MatrixAccContext.state_dim (MatrixAccLoopState.ctx s) * MatrixAccContext.state_dim (MatrixAccLoopState.ctx s))) ∧
  -- 3. No errors
  (MatrixAccLoopState.error_status s ≡ 0)

matrix_acc_exit s k inv_k h_done =
  ⟨ ?  -- sweeps = k - 1 = (max_terms + 1) - 1 = max_terms
  , ?  -- acc = k * dim² = (max_terms + 1) * dim² ... wait, need to recalculate
  , MatrixAccInvariant.h_error_clear inv_k
  ⟩
