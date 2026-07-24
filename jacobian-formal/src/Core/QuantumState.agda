-- Quantum State Type and Validity Predicates
-- Phase 2: Loop Invariant Formalization
-- Status: Bookkeeping structures for state tracking (no physics, just accounting)

module Core.QuantumState where

open import Data.Nat using (ℕ; _≤_; _<_; zero; suc)
open import Data.Integer using (ℤ; _+_)
open import Data.Real using (ℝ; _≤_; _<_; _+_; _*_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

-- Dimension type: how many basis states?
record Dimension : Set where
  field
    num_qubits : ℕ  -- n qubits ⟹ 2^n basis states
    dim : ℕ          -- 2^n (computed, cached)

-- Quantum state representation (amplitudes vector)
-- We don't model complex amplitudes themselves—only existence and dimensionality
record QuantumState : Set where
  field
    dim : Dimension
    is_valid : Bool
    is_normalized : Bool
    amplitude_count : ℕ  -- should equal dim.dim

-- Predicate: state is dimensionally valid
isValidDim : QuantumState → Set
isValidDim state =
  QuantumState.amplitude_count state ≡ Dimension.dim (QuantumState.dim state)

-- Predicate: state has been normalized
isNormalized : QuantumState → Set
isNormalized state =
  QuantumState.is_normalized state ≡ true

-- Predicate: state can accept gate operations
canApplyGate : QuantumState → Set
canApplyGate state =
  (QuantumState.is_valid state ≡ true) ∧ isValidDim state

-- Predicate: after gate application, state is marked un-normalized
gateMarksUnnormalized : (s s' : QuantumState) → Set
gateMarksUnnormalized s s' =
  (QuantumState.is_valid s ≡ true) →
  (QuantumState.is_normalized s' ≡ false)

-- Predicate: normalization preserves dimension
normalizationPreserveDim : (s s' : QuantumState) → Set
normalizationPreserveDim s s' =
  Dimension.dim (QuantumState.dim s) ≡ Dimension.dim (QuantumState.dim s')
