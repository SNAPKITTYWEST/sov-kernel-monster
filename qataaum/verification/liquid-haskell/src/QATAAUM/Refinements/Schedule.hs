{-# LANGUAGE GADTs #-}

{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}

-- | Scheduling and Timing Refinements
--
-- This module defines refinement types for quantum circuit scheduling
-- that enforce timing constraints, resource conflicts, and dependency ordering.
--
-- Clean-room implementation based on:
-- - List scheduling algorithms (Graham 1966)
-- - Critical path method (Kelley & Walker 1959)
-- - Resource-constrained scheduling theory

module QATAAUM.Refinements.Schedule
    ( -- * Time Types
      Time
    , Duration
    , TimeInterval(..)
      
      -- * Scheduled Operations
    , ScheduledOp(..)
    , Schedule(..)
      
      -- * Timing Constraints
    , validTiming
    , noOverlap
    , respectsDependencies
      
      -- * Schedule Witnesses
    , ScheduleWitness(..)
    , TimingWitness(..)
      
      -- * Schedule Operations
    , addOperation
    , checkConflict
    , computeMakespan
    ) where

import QATAAUM.Refinements.Qubit
import QATAAUM.Refinements.Circuit
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Time in nanoseconds
{-@ type Time = {v:Double | v >= 0.0} @-}
type Time = Double

-- | Duration in nanoseconds
{-@ type Duration = {v:Double | v > 0.0} @-}
type Duration = Double

-- | Time interval [start, end)
data TimeInterval = TimeInterval
    { intervalStart :: Time
    , intervalEnd   :: Time
    }
    deriving (Eq, Show)

-- | Check if interval is valid (start < end)
{-@ validInterval :: ti:TimeInterval -> {v:Bool | v <=> (intervalStart ti < intervalEnd ti)} @-}
validInterval :: TimeInterval -> Bool
validInterval ti = intervalStart ti < intervalEnd ti

-- | Scheduled operation with timing
data ScheduledOp = ScheduledOp
    { schedGate     :: Gate
    , schedStart    :: Time
    , schedDuration :: Duration
    , schedQubits   :: [QubitId]
    }
    deriving (Eq, Show)

-- | Get end time of scheduled operation
{-@ schedEnd :: op:ScheduledOp -> {v:Time | v == schedStart op + schedDuration op} @-}
schedEnd :: ScheduledOp -> Time
schedEnd op = schedStart op + schedDuration op

-- | Complete schedule
data Schedule = Schedule
    { schedOps      :: [ScheduledOp]
    , schedMakespan :: Time  -- ^ Total execution time
    , schedQubits   :: QubitSet
    }
    deriving (Eq, Show)

-- | Check if timing is valid (start >= 0, duration > 0)
{-@ validTiming :: op:ScheduledOp -> Bool @-}
validTiming :: ScheduledOp -> Bool
validTiming op = schedStart op >= 0.0 && schedDuration op > 0.0

-- | Check if two operations overlap in time on shared qubits
{-@ noOverlap :: op1:ScheduledOp -> op2:ScheduledOp -> Bool @-}
noOverlap :: ScheduledOp -> ScheduledOp -> Bool
noOverlap op1 op2 =
    let sharedQubits = not $ null $ filter (`elem` schedQubits op2) (schedQubits op1)
        timeOverlap = not (schedEnd op1 <= schedStart op2 || schedEnd op2 <= schedStart op1)
    in not (sharedQubits && timeOverlap)

-- | Check if operation respects dependencies (starts after predecessors)
{-@ respectsDependencies :: op:ScheduledOp -> predecessors:[ScheduledOp] -> Bool @-}
respectsDependencies :: ScheduledOp -> [ScheduledOp] -> Bool
respectsDependencies op preds = all (\p -> schedEnd p <= schedStart op) preds

-- | Add operation to schedule
{-@ addOperation :: s:Schedule -> op:ScheduledOp 
                 -> {v:Schedule | length (schedOps v) == length (schedOps s) + 1} @-}
addOperation :: Schedule -> ScheduledOp -> Schedule
addOperation s op = s 
    { schedOps = schedOps s ++ [op]
    , schedMakespan = max (schedMakespan s) (schedEnd op)
    , schedQubits = schedQubits s `Set.union` Set.fromList (schedQubits op)
    }

-- | Check if adding operation would create conflict
{-@ checkConflict :: op:ScheduledOp -> s:Schedule -> Bool @-}
checkConflict :: ScheduledOp -> Schedule -> Bool
checkConflict op s = any (not . noOverlap op) (schedOps s)

-- | Compute makespan (total execution time)
{-@ computeMakespan :: s:Schedule -> {v:Time | v >= 0.0} @-}
computeMakespan :: Schedule -> Time
computeMakespan s = 
    if null (schedOps s)
    then 0.0
    else maximum $ map schedEnd (schedOps s)

-- | Witness that a schedule is valid
data ScheduleWitness = ScheduleWitness
    { swSchedule        :: Schedule
    , swNoConflicts     :: Bool  -- ^ No resource conflicts
    , swValidTiming     :: Bool  -- ^ All timings are valid
    , swRespectsDeps    :: Bool  -- ^ Dependencies are respected
    }
    deriving (Eq, Show)

-- | Witness for timing constraints
data TimingWitness = TimingWitness
    { twOperation       :: ScheduledOp
    , twStartValid      :: Bool  -- ^ Start time >= 0
    , twDurationValid   :: Bool  -- ^ Duration > 0
    , twNoConflict      :: Bool  -- ^ No conflicts with other ops
    }
    deriving (Eq, Show)

-- | Create schedule witness
{-@ createScheduleWitness :: s:Schedule -> Bool -> Bool -> Bool -> ScheduleWitness @-}
createScheduleWitness :: Schedule -> Bool -> Bool -> Bool -> ScheduleWitness
createScheduleWitness s noConf validT respDeps = ScheduleWitness
    { swSchedule = s
    , swNoConflicts = noConf
    , swValidTiming = validT
    , swRespectsDeps = respDeps
    }

-- | Validate schedule witness
{-@ validateScheduleWitness :: sw:ScheduleWitness -> Bool @-}
validateScheduleWitness :: ScheduleWitness -> Bool
validateScheduleWitness sw = 
    swNoConflicts sw && swValidTiming sw && swRespectsDeps sw

-- | Create timing witness
{-@ createTimingWitness :: op:ScheduledOp -> Bool -> Bool -> Bool -> TimingWitness @-}
createTimingWitness :: ScheduledOp -> Bool -> Bool -> Bool -> TimingWitness
createTimingWitness op startV durV noConf = TimingWitness
    { twOperation = op
    , twStartValid = startV
    , twDurationValid = durV
    , twNoConflict = noConf
    }

-- | Validate timing witness
{-@ validateTimingWitness :: tw:TimingWitness -> Bool @-}
validateTimingWitness :: TimingWitness -> Bool
validateTimingWitness tw =
    twStartValid tw && twDurationValid tw && twNoConflict tw

-- | Empty schedule
{-@ emptySchedule :: {v:Schedule | length (schedOps v) == 0 && schedMakespan v == 0.0} @-}
emptySchedule :: Schedule
emptySchedule = Schedule
    { schedOps = []
    , schedMakespan = 0.0
    , schedQubits = Set.empty
    }

-- | Check if schedule is empty
{-@ isEmptySchedule :: s:Schedule -> {v:Bool | v <=> (length (schedOps s) == 0)} @-}
isEmptySchedule :: Schedule -> Bool
isEmptySchedule s = null (schedOps s)

-- | Get operations using a specific qubit
{-@ opsUsingQubit :: qid:QubitId -> s:Schedule -> [ScheduledOp] @-}
opsUsingQubit :: QubitId -> Schedule -> [ScheduledOp]
opsUsingQubit qid s = filter (\op -> qid `elem` schedQubits op) (schedOps s)

-- | Check if all operations have valid timing
{-@ allValidTiming :: s:Schedule -> Bool @-}
allValidTiming :: Schedule -> Bool
allValidTiming s = all validTiming (schedOps s)

-- | Check if schedule has no conflicts
{-@ noConflicts :: s:Schedule -> Bool @-}
noConflicts :: Schedule -> Bool
noConflicts s = and [noOverlap op1 op2 | op1 <- schedOps s, op2 <- schedOps s, op1 /= op2]

-- | Compute critical path length
{-@ criticalPathLength :: s:Schedule -> {v:Time | v >= 0.0} @-}
criticalPathLength :: Schedule -> Time
criticalPathLength = computeMakespan

-- | Count operations in time window
{-@ opsInWindow :: start:Time -> end:Time -> s:Schedule -> {v:Int | v >= 0} @-}
opsInWindow :: Time -> Time -> Schedule -> Int
opsInWindow start end s = length $ filter inWindow (schedOps s)
  where
    inWindow op = schedStart op < end && schedEnd op > start

-- Made with Bob
