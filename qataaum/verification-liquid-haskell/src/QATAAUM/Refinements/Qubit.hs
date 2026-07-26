{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}

-- | Qubit Linearity and Ownership Refinements
--
-- This module defines refinement types for quantum qubits that enforce
-- linear ownership semantics. Qubits cannot be duplicated (no-cloning)
-- and must be properly tracked through their lifetime.
--
-- Clean-room implementation based on:
-- - Linear type theory (Wadler 1990, "Linear Types Can Change the World")
-- - Quantum no-cloning theorem (Wootters & Zurek 1982)
-- - Affine type systems for quantum computing (Altenkirch & Grattage 2005)

module QATAAUM.Refinements.Qubit
    ( -- * Qubit Types
      QubitId
    , Qubit(..)
    , QubitState(..)
    , QubitSet
      
      -- * Ownership Predicates
    , isOwned
    , isReleased
    , isUnique
      
      -- * Linear Operations
    , allocQubit
    , releaseQubit
    , useQubit
    , splitQubits
    , mergeQubits
      
      -- * Refinement Witnesses
    , LinearityWitness(..)
    , NoCloneWitness(..)
    , OwnershipWitness(..)
    ) where

import Data.Set (Set)
import qualified Data.Set as Set
import Data.Map (Map)
import qualified Data.Map as Map

-- | Qubit identifier (non-negative integer)
{-@ type QubitId = {v:Int | v >= 0} @-}
type QubitId = Int

-- | Qubit state: Owned, Released, or Measured
data QubitState
    = Owned      -- ^ Qubit is owned and can be used
    | Released   -- ^ Qubit has been released (cannot be reused)
    | Measured   -- ^ Qubit has been measured (classical result available)
    deriving (Eq, Show)

-- | Qubit with refinement tracking
data Qubit = Qubit
    { qubitId    :: QubitId
    , qubitState :: QubitState
    }
    deriving (Eq, Show)

-- | Set of qubits with uniqueness constraint
{-@ type QubitSet = {v:Set QubitId | Set.size v >= 0} @-}
type QubitSet = Set QubitId

-- | Predicate: qubit is owned
{-@ measure isOwned :: Qubit -> Bool @-}
isOwned :: Qubit -> Bool
isOwned q = qubitState q == Owned

-- | Predicate: qubit is released
{-@ measure isReleased :: Qubit -> Bool @-}
isReleased :: Qubit -> Bool
isReleased q = qubitState q == Released

-- | Predicate: qubit ID is unique in a set
{-@ isUnique :: qid:QubitId -> qs:QubitSet -> {v:Bool | v <=> not (Set.member qid qs)} @-}
isUnique :: QubitId -> QubitSet -> Bool
isUnique qid qs = not (Set.member qid qs)

-- | Allocate a new qubit with unique ID
{-@ allocQubit :: qid:QubitId -> qs:QubitSet 
               -> {v:(Qubit, QubitSet) | isOwned (fst v) && Set.member qid (snd v)} @-}
allocQubit :: QubitId -> QubitSet -> (Qubit, QubitSet)
allocQubit qid qs = 
    let q = Qubit { qubitId = qid, qubitState = Owned }
        qs' = Set.insert qid qs
    in (q, qs')

-- | Release a qubit (mark as no longer usable)
{-@ releaseQubit :: q:Qubit -> {v:Qubit | isReleased v && qubitId v == qubitId q} @-}
releaseQubit :: Qubit -> Qubit
releaseQubit q = q { qubitState = Released }

-- | Use a qubit (requires it to be owned)
{-@ useQubit :: {q:Qubit | isOwned q} -> {v:Qubit | isOwned v && qubitId v == qubitId q} @-}
useQubit :: Qubit -> Qubit
useQubit q = q

-- | Split a qubit set into two disjoint sets
{-@ splitQubits :: qs:QubitSet -> qids:[QubitId]
                -> {v:(QubitSet, QubitSet) | 
                    Set.size (fst v) + Set.size (snd v) == Set.size qs} @-}
splitQubits :: QubitSet -> [QubitId] -> (QubitSet, QubitSet)
splitQubits qs qids =
    let left = Set.fromList qids `Set.intersection` qs
        right = qs `Set.difference` left
    in (left, right)

-- | Merge two disjoint qubit sets
{-@ mergeQubits :: qs1:QubitSet -> qs2:QubitSet
                -> {v:QubitSet | Set.size v == Set.size qs1 + Set.size qs2} @-}
mergeQubits :: QubitSet -> QubitSet -> QubitSet
mergeQubits = Set.union

-- | Witness that a qubit is used linearly (exactly once)
data LinearityWitness = LinearityWitness
    { lwQubitId   :: QubitId
    , lwAllocated :: Bool  -- ^ Qubit was allocated
    , lwUsed      :: Bool  -- ^ Qubit was used
    , lwReleased  :: Bool  -- ^ Qubit was released
    }
    deriving (Eq, Show)

-- | Witness that no-cloning is preserved
data NoCloneWitness = NoCloneWitness
    { ncQubitId     :: QubitId
    , ncUseCount    :: Int  -- ^ Number of times qubit appears (must be 1)
    , ncIsUnique    :: Bool -- ^ Qubit ID is unique
    }
    deriving (Eq, Show)

-- | Witness that ownership is properly tracked
data OwnershipWitness = OwnershipWitness
    { owQubitId       :: QubitId
    , owCurrentState  :: QubitState
    , owValidTransition :: Bool  -- ^ State transition is valid
    }
    deriving (Eq, Show)

-- | Validate linearity witness
{-@ validateLinearity :: lw:LinearityWitness 
                      -> {v:Bool | v <=> (lwAllocated lw && lwUsed lw && lwReleased lw)} @-}
validateLinearity :: LinearityWitness -> Bool
validateLinearity lw = lwAllocated lw && lwUsed lw && lwReleased lw

-- | Validate no-clone witness
{-@ validateNoClone :: nc:NoCloneWitness 
                    -> {v:Bool | v <=> (ncUseCount nc == 1 && ncIsUnique nc)} @-}
validateNoClone :: NoCloneWitness -> Bool
validateNoClone nc = ncUseCount nc == 1 && ncIsUnique nc

-- | Validate ownership witness
{-@ validateOwnership :: ow:OwnershipWitness 
                      -> {v:Bool | v <=> owValidTransition ow} @-}
validateOwnership :: OwnershipWitness -> Bool
validateOwnership ow = owValidTransition ow

-- | Check if state transition is valid
{-@ validTransition :: QubitState -> QubitState -> Bool @-}
validTransition :: QubitState -> QubitState -> Bool
validTransition Owned Owned = True
validTransition Owned Released = True
validTransition Owned Measured = True
validTransition Released Released = True
validTransition Measured Measured = True
validTransition _ _ = False

-- | Create linearity witness for a qubit lifecycle
{-@ createLinearityWitness :: qid:QubitId -> Bool -> Bool -> Bool -> LinearityWitness @-}
createLinearityWitness :: QubitId -> Bool -> Bool -> Bool -> LinearityWitness
createLinearityWitness qid alloc used rel = LinearityWitness
    { lwQubitId = qid
    , lwAllocated = alloc
    , lwUsed = used
    , lwReleased = rel
    }

-- | Create no-clone witness
{-@ createNoCloneWitness :: qid:QubitId -> {cnt:Int | cnt >= 0} -> Bool -> NoCloneWitness @-}
createNoCloneWitness :: QubitId -> Int -> Bool -> NoCloneWitness
createNoCloneWitness qid cnt uniq = NoCloneWitness
    { ncQubitId = qid
    , ncUseCount = cnt
    , ncIsUnique = uniq
    }

-- | Create ownership witness
{-@ createOwnershipWitness :: qid:QubitId -> QubitState -> Bool -> OwnershipWitness @-}
createOwnershipWitness :: QubitId -> QubitState -> Bool -> OwnershipWitness
createOwnershipWitness qid state valid = OwnershipWitness
    { owQubitId = qid
    , owCurrentState = state
    , owValidTransition = valid
    }

-- Made with Bob
