-- Quick test of Euler loop hole discharge

module test-discharge where

open import Data.Nat using (ℕ; _+_; _≤_; _<_; zero; suc)
open import Data.Nat.Properties using (n≤n+m)

-- Test: if i ≥ 1, then i + 1 ≥ 1
test_lower_bound : ∀ (i : ℕ) → 1 ≤ i + 1
test_lower_bound i = n≤n+m 1 i
