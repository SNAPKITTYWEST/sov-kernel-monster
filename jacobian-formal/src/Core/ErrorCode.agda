-- BOB Quantum Kernel Error Status (WORM-sealed)
-- Phase 2: Loop Invariant Formalization
-- Status: Observable error codes tied to WORM logs (bookkeeping only)

module Core.ErrorCode where

open import Data.Nat using (ℕ)

-- Error status codes (copied from bob_errors.f90 enum)
data ErrorCode : Set where
  BOB_SUCCESS             : ErrorCode  -- 0 (no error)
  BOB_ERROR_ALLOCATION    : ErrorCode  -- Memory allocation failure
  BOB_ERROR_INVALID_STATE : ErrorCode  -- Invalid quantum state
  BOB_ERROR_INVALID_GATE  : ErrorCode  -- Invalid gate operation
  BOB_ERROR_NOT_UNITARY   : ErrorCode  -- Matrix is not unitary
  BOB_ERROR_INVALID_ARGUMENT : ErrorCode  -- Bad argument
  BOB_ERROR_DIMENSION_MISMATCH : ErrorCode  -- Dimension mismatch
  BOB_ERROR_OTHER         : ErrorCode  -- Other error

-- Decidable equality for error codes
_==ₑ_ : ErrorCode → ErrorCode → Set
BOB_SUCCESS ==ₑ BOB_SUCCESS = Set
BOB_SUCCESS ==ₑ _           = ⊥
BOB_ERROR_ALLOCATION ==ₑ BOB_ERROR_ALLOCATION = Set
BOB_ERROR_ALLOCATION ==ₑ _                     = ⊥
BOB_ERROR_INVALID_STATE ==ₑ BOB_ERROR_INVALID_STATE = Set
BOB_ERROR_INVALID_STATE ==ₑ _                        = ⊥
BOB_ERROR_INVALID_GATE ==ₑ BOB_ERROR_INVALID_GATE = Set
BOB_ERROR_INVALID_GATE ==ₑ _                       = ⊥
BOB_ERROR_NOT_UNITARY ==ₑ BOB_ERROR_NOT_UNITARY = Set
BOB_ERROR_NOT_UNITARY ==ₑ _                      = ⊥
BOB_ERROR_INVALID_ARGUMENT ==ₑ BOB_ERROR_INVALID_ARGUMENT = Set
BOB_ERROR_INVALID_ARGUMENT ==ₑ _                           = ⊥
BOB_ERROR_DIMENSION_MISMATCH ==ₑ BOB_ERROR_DIMENSION_MISMATCH = Set
BOB_ERROR_DIMENSION_MISMATCH ==ₑ _                              = ⊥
BOB_ERROR_OTHER ==ₑ BOB_ERROR_OTHER = Set
BOB_ERROR_OTHER ==ₑ _               = ⊥

-- Predicate: no error occurred
isSuccess : ErrorCode → Set
isSuccess BOB_SUCCESS = Set
isSuccess _           = ⊥
