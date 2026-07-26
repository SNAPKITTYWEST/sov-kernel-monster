-- Hamiltonian Operator Type and Properties
-- Phase 2: Loop Invariant Formalization
-- Status: Immutable operator definition (no physics—just structure metadata)

module Core.Hamiltonian where

open import Data.Nat using (ℕ)
open import Data.Real using (ℝ)
open import Relation.Binary.PropositionalEquality using (_≡_)
open import Core.QuantumState using (Dimension)

-- Hamiltonian operator (time-independent)
record Hamiltonian : Set where
  field
    dim : Dimension          -- dimensionality (2^n for n qubits)
    is_hermitian : Bool      -- should be true (unverified bookkeeping)
    matrix_entries : ℕ       -- number of matrix entries (dim.dim²)

-- Predicate: Hamiltonian is properly dimensioned
isValidHamiltonian : Hamiltonian → Set
isValidHamiltonian h =
  let d = Dimension.dim (Hamiltonian.dim h)
  in Hamiltonian.matrix_entries h ≡ d * d

-- Predicate: Hamiltonian is Hermitian (bookkeeping—not verified)
claimsHermitian : Hamiltonian → Set
claimsHermitian h =
  Hamiltonian.is_hermitian h ≡ true

-- Immutability property: Hamiltonian unchanged during evolution
hamiltonianImmutable : (h h' : Hamiltonian) → Set
hamiltonianImmutable h h' =
  (Hamiltonian.dim h ≡ Hamiltonian.dim h') ∧
  (Hamiltonian.matrix_entries h ≡ Hamiltonian.matrix_entries h')
