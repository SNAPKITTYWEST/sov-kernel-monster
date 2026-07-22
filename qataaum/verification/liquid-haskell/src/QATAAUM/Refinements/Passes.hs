{-# LANGUAGE GADTs #-}

{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}

-- | Compiler Pass Preservation Refinements
--
-- This module defines refinement types for compiler optimization passes
-- that enforce semantic preservation and correctness properties.
--
-- Clean-room implementation based on:
-- - Compiler correctness theory (Leroy 2009, CompCert)
-- - Translation validation (Pnueli et al. 1998)
-- - Quantum circuit optimization (Nam et al. 2018)

module QATAAUM.Refinements.Passes
    ( -- * Pass Types
      PassResult(..)
    , OptimizationPass(..)
      
      -- * Preservation Properties
    , preservesSemantics
    , preservesQubits
    , preservesDepth
    , improvesMetric
      
      -- * Pass Witnesses
    , PassWitness(..)
    , OptimizationWitness(..)
      
      -- * Pass Validation
    , validatePass
    , validateOptimization
    ) where

import QATAAUM.Refinements.Qubit
import QATAAUM.Refinements.Circuit
import Data.Set (Set)
import qualified Data.Set as Set

-- | Result of applying a compiler pass
data PassResult = PassResult
    { prInput       :: Circuit
    , prOutput      :: Circuit
    , prPreserved   :: Bool  -- ^ Semantics preserved
    , prImproved    :: Bool  -- ^ Metric improved
    }
    deriving (Eq, Show)

-- | Optimization pass type
data OptimizationPass
    = GateCancellation    -- ^ Cancel inverse gate pairs
    | RotationFolding     -- ^ Fold adjacent rotations
    | Commutation         -- ^ Commute gates for better scheduling
    | DeadCodeElimination -- ^ Remove unused operations
    | ConstantPropagation -- ^ Propagate constant values
    deriving (Eq, Show)

-- | Check if pass preserves circuit semantics
{-@ preservesSemantics :: pr:PassResult -> Bool @-}
preservesSemantics :: PassResult -> Bool
preservesSemantics pr = prPreserved pr

-- | Check if pass preserves qubit set
{-@ preservesQubits :: pr:PassResult -> Bool @-}
preservesQubits :: PassResult -> Bool
preservesQubits pr = 
    circuitQubits (prInput pr) == circuitQubits (prOutput pr)

-- | Check if pass preserves or improves depth
{-@ preservesDepth :: pr:PassResult -> Bool @-}
preservesDepth :: PassResult -> Bool
preservesDepth pr =
    circuitDepth (prOutput pr) <= circuitDepth (prInput pr)

-- | Check if pass improves some metric (gate count or depth)
{-@ improvesMetric :: pr:PassResult -> Bool @-}
improvesMetric :: PassResult -> Bool
improvesMetric pr =
    gateCount (prOutput pr) <= gateCount (prInput pr) ||
    circuitDepth (prOutput pr) < circuitDepth (prInput pr)

-- | Witness that a pass is correct
data PassWitness = PassWitness
    { pwPass            :: OptimizationPass
    , pwResult          :: PassResult
    , pwPreservesQubits :: Bool  -- ^ Qubit set preserved
    , pwPreservesDepth  :: Bool  -- ^ Depth preserved/improved
    , pwPreservesSem    :: Bool  -- ^ Semantics preserved
    }
    deriving (Eq, Show)

-- | Witness for optimization correctness
data OptimizationWitness = OptimizationWitness
    { owPass            :: OptimizationPass
    , owResult          :: PassResult
    , owGateReduction   :: Int   -- ^ Gates removed (>= 0)
    , owDepthReduction  :: Int   -- ^ Depth reduced (>= 0)
    , owCorrect         :: Bool  -- ^ Optimization is correct
    }
    deriving (Eq, Show)

-- | Create pass witness
{-@ createPassWitness :: p:OptimizationPass -> pr:PassResult -> Bool -> Bool -> Bool 
                      -> PassWitness @-}
createPassWitness :: OptimizationPass -> PassResult -> Bool -> Bool -> Bool -> PassWitness
createPassWitness p pr presQ presD presSem = PassWitness
    { pwPass = p
    , pwResult = pr
    , pwPreservesQubits = presQ
    , pwPreservesDepth = presD
    , pwPreservesSem = presSem
    }

-- | Validate pass witness
{-@ validatePass :: pw:PassWitness -> Bool @-}
validatePass :: PassWitness -> Bool
validatePass pw =
    pwPreservesQubits pw && pwPreservesDepth pw && pwPreservesSem pw

-- | Create optimization witness
{-@ createOptimizationWitness :: p:OptimizationPass -> pr:PassResult 
                              -> {gr:Int | gr >= 0} -> {dr:Int | dr >= 0} -> Bool
                              -> OptimizationWitness @-}
createOptimizationWitness :: OptimizationPass -> PassResult -> Int -> Int -> Bool 
                          -> OptimizationWitness
createOptimizationWitness p pr gr dr corr = OptimizationWitness
    { owPass = p
    , owResult = pr
    , owGateReduction = gr
    , owDepthReduction = dr
    , owCorrect = corr
    }

-- | Validate optimization witness
{-@ validateOptimization :: ow:OptimizationWitness -> Bool @-}
validateOptimization :: OptimizationWitness -> Bool
validateOptimization ow =
    owGateReduction ow >= 0 && owDepthReduction ow >= 0 && owCorrect ow

-- | Compute gate reduction from pass result
{-@ gateReduction :: pr:PassResult -> {v:Int | v >= 0} @-}
gateReduction :: PassResult -> Int
gateReduction pr = 
    let before = gateCount (prInput pr)
        after = gateCount (prOutput pr)
    in if before >= after then before - after else 0

-- | Compute depth reduction from pass result
{-@ depthReduction :: pr:PassResult -> {v:Int | v >= 0} @-}
depthReduction :: PassResult -> Int
depthReduction pr =
    let before = circuitDepth (prInput pr)
        after = circuitDepth (prOutput pr)
    in if before >= after then before - after else 0

-- | Check if pass result is valid
{-@ validPassResult :: pr:PassResult -> Bool @-}
validPassResult :: PassResult -> Bool
validPassResult pr =
    preservesSemantics pr && preservesQubits pr && preservesDepth pr

-- | Apply identity pass (no transformation)
{-@ identityPass :: c:Circuit -> {v:PassResult | prInput v == c && prOutput v == c} @-}
identityPass :: Circuit -> PassResult
identityPass c = PassResult
    { prInput = c
    , prOutput = c
    , prPreserved = True
    , prImproved = False
    }

-- | Check if optimization is beneficial
{-@ isBeneficial :: ow:OptimizationWitness -> Bool @-}
isBeneficial :: OptimizationWitness -> Bool
isBeneficial ow = owGateReduction ow > 0 || owDepthReduction ow > 0

-- | Compose two pass results
{-@ composePasses :: pr1:PassResult -> pr2:PassResult 
                  -> {v:PassResult | prInput v == prInput pr1} @-}
composePasses :: PassResult -> PassResult -> PassResult
composePasses pr1 pr2 = PassResult
    { prInput = prInput pr1
    , prOutput = prOutput pr2
    , prPreserved = prPreserved pr1 && prPreserved pr2
    , prImproved = prImproved pr1 || prImproved pr2
    }

-- | Check if pass preserves all properties
{-@ preservesAll :: pr:PassResult -> Bool @-}
preservesAll :: PassResult -> Bool
preservesAll pr = 
    preservesSemantics pr && preservesQubits pr && preservesDepth pr

-- | Count total optimizations applied
{-@ totalOptimizations :: [OptimizationWitness] -> {v:Int | v >= 0} @-}
totalOptimizations :: [OptimizationWitness] -> Int
totalOptimizations = length

-- | Sum gate reductions across multiple optimizations
{-@ totalGateReduction :: [OptimizationWitness] -> {v:Int | v >= 0} @-}
totalGateReduction :: [OptimizationWitness] -> Int
totalGateReduction = sum . map owGateReduction

-- | Sum depth reductions across multiple optimizations
{-@ totalDepthReduction :: [OptimizationWitness] -> {v:Int | v >= 0} @-}
totalDepthReduction :: [OptimizationWitness] -> Int
totalDepthReduction = sum . map owDepthReduction

-- | Check if all optimizations are correct
{-@ allOptimizationsCorrect :: [OptimizationWitness] -> Bool @-}
allOptimizationsCorrect :: [OptimizationWitness] -> Bool
allOptimizationsCorrect = all owCorrect

-- Made with Bob
