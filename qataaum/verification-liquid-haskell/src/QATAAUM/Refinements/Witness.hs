{-# LANGUAGE GADTs #-}

{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}

-- | Proof Witness Aggregation and Export
--
-- This module aggregates all refinement witnesses from the QATAAUM
-- verification layer and provides a unified interface for proof export
-- to the Rust runtime and Lean 4 verification layer.
--
-- Clean-room implementation based on:
-- - Proof-carrying code (Necula 1997)
-- - Certificate translation (Appel 2001)
-- - Witness generation for SMT solvers

module QATAAUM.Refinements.Witness
    ( -- * Unified Witness Type
      UnifiedWitness(..)
    , WitnessBundle(..)
      
      -- * Witness Validation
    , validateWitnessBundle
    , allWitnessesValid
      
      -- * Witness Export
    , exportWitness
    , serializeWitness
      
      -- * Witness Aggregation
    , aggregateWitnesses
    , combineWitnesses
    ) where

import QATAAUM.Refinements.Qubit
import QATAAUM.Refinements.Circuit
import QATAAUM.Refinements.Schedule
import QATAAUM.Refinements.Pulse
import QATAAUM.Refinements.Passes
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Unified witness type encompassing all verification layers
data UnifiedWitness
    = WLinear LinearityWitness
    | WNoClone NoCloneWitness
    | WOwnership OwnershipWitness
    | WCircuit CircuitWitness
    | WPreservation PreservationWitness
    | WSchedule ScheduleWitness
    | WTiming TimingWitness
    | WPulse PulseWitness
    | WFrame FrameWitness
    | WPass PassWitness
    | WOptimization OptimizationWitness
    deriving (Eq, Show)

-- | Bundle of witnesses for a complete compilation
data WitnessBundle = WitnessBundle
    { wbWitnesses     :: [UnifiedWitness]
    , wbValid         :: Bool  -- ^ All witnesses valid
    , wbCompilationId :: String  -- ^ Unique compilation identifier
    , wbTimestamp     :: String  -- ^ ISO 8601 timestamp
    }
    deriving (Eq, Show)

-- | Validate a single unified witness
{-@ validateUnifiedWitness :: w:UnifiedWitness -> Bool @-}
validateUnifiedWitness :: UnifiedWitness -> Bool
validateUnifiedWitness (WLinear lw) = validateLinearity lw
validateUnifiedWitness (WNoClone nc) = validateNoClone nc
validateUnifiedWitness (WOwnership ow) = validateOwnership ow
validateUnifiedWitness (WCircuit cw) = validateCircuitWitness cw
validateUnifiedWitness (WPreservation pw) = validatePreservationWitness pw
validateUnifiedWitness (WSchedule sw) = validateScheduleWitness sw
validateUnifiedWitness (WTiming tw) = validateTimingWitness tw
validateUnifiedWitness (WPulse pw) = validatePulseWitness pw
validateUnifiedWitness (WFrame fw) = validateFrameWitness fw
validateUnifiedWitness (WPass pw) = validatePass pw
validateUnifiedWitness (WOptimization ow) = validateOptimization ow

-- | Validate entire witness bundle
{-@ validateWitnessBundle :: wb:WitnessBundle -> Bool @-}
validateWitnessBundle :: WitnessBundle -> Bool
validateWitnessBundle wb = wbValid wb && allWitnessesValid (wbWitnesses wb)

-- | Check if all witnesses in list are valid
{-@ allWitnessesValid :: [UnifiedWitness] -> Bool @-}
allWitnessesValid :: [UnifiedWitness] -> Bool
allWitnessesValid = all validateUnifiedWitness

-- | Export witness to string format (JSON-like)
{-@ exportWitness :: UnifiedWitness -> String @-}
exportWitness :: UnifiedWitness -> String
exportWitness (WLinear lw) = 
    "LinearityWitness{qid=" ++ show (lwQubitId lw) ++ 
    ",alloc=" ++ show (lwAllocated lw) ++
    ",used=" ++ show (lwUsed lw) ++
    ",released=" ++ show (lwReleased lw) ++ "}"
exportWitness (WNoClone nc) =
    "NoCloneWitness{qid=" ++ show (ncQubitId nc) ++
    ",count=" ++ show (ncUseCount nc) ++
    ",unique=" ++ show (ncIsUnique nc) ++ "}"
exportWitness (WOwnership ow) =
    "OwnershipWitness{qid=" ++ show (owQubitId ow) ++
    ",state=" ++ show (owCurrentState ow) ++
    ",valid=" ++ show (owValidTransition ow) ++ "}"
exportWitness (WCircuit cw) =
    "CircuitWitness{arity=" ++ show (cwValidArity cw) ++
    ",qubits=" ++ show (cwValidQubits cw) ++
    ",noclone=" ++ show (cwNoClone cw) ++ "}"
exportWitness (WPreservation pw) =
    "PreservationWitness{qubits=" ++ show (pwSameQubits pw) ++
    ",depth=" ++ show (pwSameDepth pw) ++
    ",equiv=" ++ show (pwEquivalent pw) ++ "}"
exportWitness (WSchedule sw) =
    "ScheduleWitness{noconf=" ++ show (swNoConflicts sw) ++
    ",timing=" ++ show (swValidTiming sw) ++
    ",deps=" ++ show (swRespectsDeps sw) ++ "}"
exportWitness (WTiming tw) =
    "TimingWitness{start=" ++ show (twStartValid tw) ++
    ",dur=" ++ show (twDurationValid tw) ++
    ",noconf=" ++ show (twNoConflict tw) ++ "}"
exportWitness (WPulse pw) =
    "PulseWitness{frames=" ++ show (pwValidFrames pw) ++
    ",noconf=" ++ show (pwNoConflicts pw) ++
    ",dur=" ++ show (pwValidDuration pw) ++ "}"
exportWitness (WFrame fw) =
    "FrameWitness{id=" ++ show (fwFrameId fw) ++
    ",valid=" ++ show (fwValidId fw) ++
    ",cons=" ++ show (fwConsistent fw) ++
    ",noover=" ++ show (fwNoOverlap fw) ++ "}"
exportWitness (WPass pw) =
    "PassWitness{pass=" ++ show (pwPass pw) ++
    ",qubits=" ++ show (pwPreservesQubits pw) ++
    ",depth=" ++ show (pwPreservesDepth pw) ++
    ",sem=" ++ show (pwPreservesSem pw) ++ "}"
exportWitness (WOptimization ow) =
    "OptimizationWitness{pass=" ++ show (owPass ow) ++
    ",gates=" ++ show (owGateReduction ow) ++
    ",depth=" ++ show (owDepthReduction ow) ++
    ",correct=" ++ show (owCorrect ow) ++ "}"

-- | Serialize witness bundle to string
{-@ serializeWitness :: wb:WitnessBundle -> String @-}
serializeWitness :: WitnessBundle -> String
serializeWitness wb =
    "WitnessBundle{\n" ++
    "  id=" ++ wbCompilationId wb ++ ",\n" ++
    "  timestamp=" ++ wbTimestamp wb ++ ",\n" ++
    "  valid=" ++ show (wbValid wb) ++ ",\n" ++
    "  witnesses=[\n" ++
    unlines (map (("    " ++) . exportWitness) (wbWitnesses wb)) ++
    "  ]\n}"

-- | Aggregate multiple witness bundles
{-@ aggregateWitnesses :: [WitnessBundle] -> {v:Int | v >= 0} @-}
aggregateWitnesses :: [WitnessBundle] -> Int
aggregateWitnesses = sum . map (length . wbWitnesses)

-- | Combine two witness bundles
{-@ combineWitnesses :: wb1:WitnessBundle -> wb2:WitnessBundle 
                     -> {v:WitnessBundle | length (wbWitnesses v) == 
                         length (wbWitnesses wb1) + length (wbWitnesses wb2)} @-}
combineWitnesses :: WitnessBundle -> WitnessBundle -> WitnessBundle
combineWitnesses wb1 wb2 = WitnessBundle
    { wbWitnesses = wbWitnesses wb1 ++ wbWitnesses wb2
    , wbValid = wbValid wb1 && wbValid wb2
    , wbCompilationId = wbCompilationId wb1 ++ "+" ++ wbCompilationId wb2
    , wbTimestamp = wbTimestamp wb2  -- Use later timestamp
    }

-- | Create empty witness bundle
{-@ emptyWitnessBundle :: String -> String -> {v:WitnessBundle | length (wbWitnesses v) == 0} @-}
emptyWitnessBundle :: String -> String -> WitnessBundle
emptyWitnessBundle compId ts = WitnessBundle
    { wbWitnesses = []
    , wbValid = True
    , wbCompilationId = compId
    , wbTimestamp = ts
    }

-- | Add witness to bundle
{-@ addWitness :: wb:WitnessBundle -> w:UnifiedWitness 
               -> {v:WitnessBundle | length (wbWitnesses v) == length (wbWitnesses wb) + 1} @-}
addWitness :: WitnessBundle -> UnifiedWitness -> WitnessBundle
addWitness wb w = wb
    { wbWitnesses = wbWitnesses wb ++ [w]
    , wbValid = wbValid wb && validateUnifiedWitness w
    }

-- | Count witnesses by type
{-@ countWitnessesByType :: [UnifiedWitness] -> Map String Int @-}
countWitnessesByType :: [UnifiedWitness] -> Map String Int
countWitnessesByType ws = foldr increment Map.empty ws
  where
    increment w m = Map.insertWith (+) (witnessType w) 1 m
    witnessType (WLinear _) = "Linearity"
    witnessType (WNoClone _) = "NoClone"
    witnessType (WOwnership _) = "Ownership"
    witnessType (WCircuit _) = "Circuit"
    witnessType (WPreservation _) = "Preservation"
    witnessType (WSchedule _) = "Schedule"
    witnessType (WTiming _) = "Timing"
    witnessType (WPulse _) = "Pulse"
    witnessType (WFrame _) = "Frame"
    witnessType (WPass _) = "Pass"
    witnessType (WOptimization _) = "Optimization"

-- | Check if bundle contains any invalid witnesses
{-@ hasInvalidWitnesses :: wb:WitnessBundle -> Bool @-}
hasInvalidWitnesses :: WitnessBundle -> Bool
hasInvalidWitnesses wb = not (allWitnessesValid (wbWitnesses wb))

-- | Get count of witnesses in bundle
{-@ witnessCount :: wb:WitnessBundle -> {v:Int | v >= 0} @-}
witnessCount :: WitnessBundle -> Int
witnessCount = length . wbWitnesses

-- | Filter valid witnesses from bundle
{-@ validWitnesses :: wb:WitnessBundle -> [UnifiedWitness] @-}
validWitnesses :: WitnessBundle -> [UnifiedWitness]
validWitnesses = filter validateUnifiedWitness . wbWitnesses

-- | Filter invalid witnesses from bundle
{-@ invalidWitnesses :: wb:WitnessBundle -> [UnifiedWitness] @-}
invalidWitnesses :: WitnessBundle -> [UnifiedWitness]
invalidWitnesses = filter (not . validateUnifiedWitness) . wbWitnesses

-- Made with Bob
