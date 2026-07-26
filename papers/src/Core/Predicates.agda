-- Shared Loop Invariant Predicates
-- Phase 2: Loop Invariant Formalization
-- Status: Observable bookkeeping conditions (counters, flags, divisibility)

module Core.Predicates where

open import Data.Nat using (ℕ; _≤_; _<_; _≡_; _mod_; zero; suc)
open import Data.Real using (ℝ; _≤_; _<_; _≥_; _+_; _*_; _-_)
open import Data.Bool using (Bool; true; false)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Data.Vec using (Vec; _[_]; map)

-- Predicate: step counter has reached target
stepCounterAt : (k : ℕ) (target : ℕ) → Set
stepCounterAt k target = k ≡ target

-- Predicate: step counter is within valid range
stepInRange : (k : ℕ) (num_steps : ℕ) → Set
stepInRange k num_steps = k ≤ num_steps

-- Predicate: error status flag is success
errorIsClear : (err : ℕ) → Set  -- 0 = BOB_SUCCESS
errorIsClear err = err ≡ 0

-- Predicate: time value is valid (positive)
timeIsPositive : (t : ℝ) → Set
timeIsPositive t = 0 < t

-- Predicate: time step is positive
dtIsPositive : (dt : ℝ) → Set
dtIsPositive dt = 0 < dt

-- Predicate: step count is exact multiple of normalization period
needsNormalization : (step : ℕ) (period : ℕ) → Set
needsNormalization step period = (step mod period) ≡ 0

-- Predicate: step has NOT exceeded target
canContinueLoop : (step : ℕ) (num_steps : ℕ) → Set
canContinueLoop step num_steps = step < num_steps

-- Predicate: qubit index is valid
qubitIndexValid : (idx : ℕ) (num_qubits : ℕ) → Set
qubitIndexValid idx num_qubits = idx < num_qubits

-- Predicate: basis state iterator in valid range
basisStateInRange : (i : ℕ) (dim : ℕ) → Set
basisStateInRange i dim = i < dim

-- Predicate: Taylor series term index
taylorTermIndex : (k : ℕ) (max_terms : ℕ) → Set
taylorTermIndex k max_terms = k ≤ max_terms

-- Predicate: dimension is power of 2
isPowerOfTwo : (n : ℕ) → Set
data IsPowerOfTwo : ℕ → Set where
  base : IsPowerOfTwo 1
  step : ∀ {n} → IsPowerOfTwo n → IsPowerOfTwo (n * 2)

-- Predicate: vector dimensionality preserved
dimensionPreserved : (dim₁ dim₂ : ℕ) → Set
dimensionPreserved dim₁ dim₂ = dim₁ ≡ dim₂

-- Predicate: all elements processed in loop
loopCompleted : (current : ℕ) (limit : ℕ) → Set
loopCompleted current limit = current ≡ limit
