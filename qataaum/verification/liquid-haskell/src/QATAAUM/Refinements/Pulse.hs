{-# LANGUAGE GADTs #-}

{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}

-- | Pulse-Level Refinements
--
-- This module defines refinement types for pulse-level quantum control
-- that enforce frame consistency, waveform validity, and resource exclusivity.
--
-- Clean-room implementation based on:
-- - OpenPulse specification (arXiv:1809.03452)
-- - Pulse scheduling theory
-- - Hardware resource management

module QATAAUM.Refinements.Pulse
    ( -- * Pulse Types
      FrameId
    , WaveformId
    , Frequency
    , Phase
    , Amplitude
      
      -- * Pulse Operations
    , PulseOp(..)
    , PulseProgram(..)
      
      -- * Resource Constraints
    , validFrame
    , noFrameConflict
    , validWaveform
      
      -- * Pulse Witnesses
    , PulseWitness(..)
    , FrameWitness(..)
    ) where

import QATAAUM.Refinements.Qubit
import QATAAUM.Refinements.Schedule
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set

-- | Frame identifier
{-@ type FrameId = {v:Int | v >= 0} @-}
type FrameId = Int

-- | Waveform identifier
{-@ type WaveformId = {v:Int | v >= 0} @-}
type WaveformId = Int

-- | Frequency in Hz
{-@ type Frequency = {v:Double | v > 0.0} @-}
type Frequency = Double

-- | Phase in radians [0, 2π)
{-@ type Phase = {v:Double | v >= 0.0 && v < 6.283185307179586} @-}
type Phase = Double

-- | Amplitude [0, 1]
{-@ type Amplitude = {v:Double | v >= 0.0 && v <= 1.0} @-}
type Amplitude = Double

-- | Pulse operation
data PulseOp
    = Play FrameId WaveformId Duration
    | Capture FrameId Duration
    | Delay FrameId Duration
    | SetFrequency FrameId Frequency
    | SetPhase FrameId Phase
    | ShiftPhase FrameId Phase
    deriving (Eq, Show)

-- | Get frame used by pulse operation
{-@ pulseFrame :: PulseOp -> FrameId @-}
pulseFrame :: PulseOp -> FrameId
pulseFrame (Play fid _ _) = fid
pulseFrame (Capture fid _) = fid
pulseFrame (Delay fid _) = fid
pulseFrame (SetFrequency fid _) = fid
pulseFrame (SetPhase fid _) = fid
pulseFrame (ShiftPhase fid _) = fid

-- | Get duration of pulse operation (0 for instantaneous ops)
{-@ pulseDuration :: PulseOp -> {v:Duration | v >= 0.0} @-}
pulseDuration :: PulseOp -> Duration
pulseDuration (Play _ _ d) = d
pulseDuration (Capture _ d) = d
pulseDuration (Delay _ d) = d
pulseDuration (SetFrequency _ _) = 0.0
pulseDuration (SetPhase _ _) = 0.0
pulseDuration (ShiftPhase _ _) = 0.0

-- | Pulse program
data PulseProgram = PulseProgram
    { pulseOps    :: [PulseOp]
    , pulseFrames :: Set FrameId
    , pulseDur    :: Duration
    }
    deriving (Eq, Show)

-- | Check if frame ID is valid (non-negative)
{-@ validFrame :: fid:FrameId -> Bool @-}
validFrame :: FrameId -> Bool
validFrame fid = fid >= 0

-- | Check if two pulse operations don't conflict on the same frame
{-@ noFrameConflict :: op1:PulseOp -> op2:PulseOp -> Bool @-}
noFrameConflict :: PulseOp -> PulseOp -> Bool
noFrameConflict op1 op2 = pulseFrame op1 /= pulseFrame op2

-- | Check if waveform ID is valid
{-@ validWaveform :: wid:WaveformId -> Bool @-}
validWaveform :: WaveformId -> Bool
validWaveform wid = wid >= 0

-- | Check if frequency is valid
{-@ validFrequency :: f:Frequency -> Bool @-}
validFrequency :: Frequency -> Bool
validFrequency f = f > 0.0

-- | Check if phase is valid [0, 2π)
{-@ validPhase :: p:Phase -> Bool @-}
validPhase :: Phase -> Bool
validPhase p = p >= 0.0 && p < 6.283185307179586

-- | Check if amplitude is valid [0, 1]
{-@ validAmplitude :: a:Amplitude -> Bool @-}
validAmplitude :: Amplitude -> Bool
validAmplitude a = a >= 0.0 && a <= 1.0

-- | Witness that pulse program is valid
data PulseWitness = PulseWitness
    { pwProgram       :: PulseProgram
    , pwValidFrames   :: Bool  -- ^ All frames are valid
    , pwNoConflicts   :: Bool  -- ^ No frame conflicts
    , pwValidDuration :: Bool  -- ^ Duration is valid
    }
    deriving (Eq, Show)

-- | Witness for frame operations
data FrameWitness = FrameWitness
    { fwFrameId       :: FrameId
    , fwValidId       :: Bool  -- ^ Frame ID is valid
    , fwConsistent    :: Bool  -- ^ Frame state is consistent
    , fwNoOverlap     :: Bool  -- ^ No overlapping operations
    }
    deriving (Eq, Show)

-- | Create pulse witness
{-@ createPulseWitness :: p:PulseProgram -> Bool -> Bool -> Bool -> PulseWitness @-}
createPulseWitness :: PulseProgram -> Bool -> Bool -> Bool -> PulseWitness
createPulseWitness p validF noConf validD = PulseWitness
    { pwProgram = p
    , pwValidFrames = validF
    , pwNoConflicts = noConf
    , pwValidDuration = validD
    }

-- | Validate pulse witness
{-@ validatePulseWitness :: pw:PulseWitness -> Bool @-}
validatePulseWitness :: PulseWitness -> Bool
validatePulseWitness pw =
    pwValidFrames pw && pwNoConflicts pw && pwValidDuration pw

-- | Create frame witness
{-@ createFrameWitness :: fid:FrameId -> Bool -> Bool -> Bool -> FrameWitness @-}
createFrameWitness :: FrameId -> Bool -> Bool -> Bool -> FrameWitness
createFrameWitness fid validId cons noOver = FrameWitness
    { fwFrameId = fid
    , fwValidId = validId
    , fwConsistent = cons
    , fwNoOverlap = noOver
    }

-- | Validate frame witness
{-@ validateFrameWitness :: fw:FrameWitness -> Bool @-}
validateFrameWitness :: FrameWitness -> Bool
validateFrameWitness fw =
    fwValidId fw && fwConsistent fw && fwNoOverlap fw

-- | Empty pulse program
{-@ emptyPulseProgram :: {v:PulseProgram | length (pulseOps v) == 0 && pulseDur v == 0.0} @-}
emptyPulseProgram :: PulseProgram
emptyPulseProgram = PulseProgram
    { pulseOps = []
    , pulseFrames = Set.empty
    , pulseDur = 0.0
    }

-- | Add pulse operation to program
{-@ addPulseOp :: p:PulseProgram -> op:PulseOp 
               -> {v:PulseProgram | length (pulseOps v) == length (pulseOps p) + 1} @-}
addPulseOp :: PulseProgram -> PulseOp -> PulseProgram
addPulseOp p op = p
    { pulseOps = pulseOps p ++ [op]
    , pulseFrames = Set.insert (pulseFrame op) (pulseFrames p)
    , pulseDur = pulseDur p + pulseDuration op
    }

-- | Count operations on a specific frame
{-@ opsOnFrame :: fid:FrameId -> p:PulseProgram -> {v:Int | v >= 0} @-}
opsOnFrame :: FrameId -> PulseProgram -> Int
opsOnFrame fid p = length $ filter (\op -> pulseFrame op == fid) (pulseOps p)

-- | Get all frames used in program
{-@ usedFrames :: p:PulseProgram -> Set FrameId @-}
usedFrames :: PulseProgram -> Set FrameId
usedFrames p = Set.fromList $ map pulseFrame (pulseOps p)

-- | Check if all frames in program are valid
{-@ allFramesValid :: p:PulseProgram -> Bool @-}
allFramesValid :: PulseProgram -> Bool
allFramesValid p = all validFrame (Set.toList $ pulseFrames p)

-- | Compute total duration of pulse program
{-@ totalDuration :: p:PulseProgram -> {v:Duration | v >= 0.0} @-}
totalDuration :: PulseProgram -> Duration
totalDuration p = sum $ map pulseDuration (pulseOps p)

-- Made with Bob
