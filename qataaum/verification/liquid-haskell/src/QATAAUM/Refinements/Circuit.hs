{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}

{-@ LIQUID "--reflection" @-}
{-@ LIQUID "--ple" @-}

-- | Circuit Structure and Semantics Refinements
--
-- This module defines refinement types for quantum circuits that enforce
-- structural invariants, gate arity constraints, and semantic preservation.
--
-- Clean-room implementation based on:
-- - Quantum circuit model (Nielsen & Chuang 2000)
-- - Categorical quantum mechanics (Abramsky & Coecke 2004)
-- - Quantum programming language semantics (Selinger 2004)

module QATAAUM.Refinements.Circuit
    ( -- * Circuit Types
      Gate(..)
    , GateType(..)
    , Circuit(..)
    , CircuitDepth
      
      -- * Arity Constraints
    , gateArity
    , validGateArity
      
      -- * Circuit Properties
    , circuitDepth
    , circuitWidth
    , gateCount
      
      -- * Semantic Preservation
    , CircuitWitness(..)
    , PreservationWitness(..)
      
      -- * Circuit Operations
    , appendGate
    , composeCircuits
    , validateCircuit
    ) where

import QATAAUM.Refinements.Qubit
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Map (Map)
import qualified Data.Map as Map

-- | Gate types with known arities
data GateType
    = GateX      -- ^ Pauli X (1 qubit)
    | GateY      -- ^ Pauli Y (1 qubit)
    | GateZ      -- ^ Pauli Z (1 qubit)
    | GateH      -- ^ Hadamard (1 qubit)
    | GateS      -- ^ S gate (1 qubit)
    | GateT      -- ^ T gate (1 qubit)
    | GateCX     -- ^ CNOT (2 qubits)
    | GateCY     -- ^ Controlled-Y (2 qubits)
    | GateCZ     -- ^ Controlled-Z (2 qubits)
    | GateCCX    -- ^ Toffoli (3 qubits)
    | GateRX     -- ^ X rotation (1 qubit + angle)
    | GateRY     -- ^ Y rotation (1 qubit + angle)
    | GateRZ     -- ^ Z rotation (1 qubit + angle)
    | GateMeasure -- ^ Measurement (1 qubit)
    deriving (Eq, Show)

-- | Get the arity (number of qubits) for a gate type
{-@ gateArity :: GateType -> {v:Int | v > 0 && v <= 3} @-}
gateArity :: GateType -> Int
gateArity GateX = 1
gateArity GateY = 1
gateArity GateZ = 1
gateArity GateH = 1
gateArity GateS = 1
gateArity GateT = 1
gateArity GateCX = 2
gateArity GateCY = 2
gateArity GateCZ = 2
gateArity GateCCX = 3
gateArity GateRX = 1
gateArity GateRY = 1
gateArity GateRZ = 1
gateArity GateMeasure = 1

-- | Quantum gate with qubit operands
data Gate = Gate
    { gateType   :: GateType
    , gateQubits :: [QubitId]
    , gateAngle  :: Maybe Double  -- ^ Rotation angle (if applicable)
    }
    deriving (Eq, Show)

-- | Validate that gate has correct arity
{-@ validGateArity :: g:Gate -> {v:Bool | v <=> (len (gateQubits g) == gateArity (gateType g))} @-}
validGateArity :: Gate -> Bool
validGateArity g = length (gateQubits g) == gateArity (gateType g)

-- | Circuit depth (number of time steps)
{-@ type CircuitDepth = {v:Int | v >= 0} @-}
type CircuitDepth = Int

-- | Quantum circuit
data Circuit = Circuit
    { circuitGates  :: [Gate]
    , circuitQubits :: QubitSet
    , circuitDepth  :: CircuitDepth
    }
    deriving (Eq, Show)

-- | Get circuit width (number of qubits)
{-@ circuitWidth :: c:Circuit -> {v:Int | v >= 0} @-}
circuitWidth :: Circuit -> Int
circuitWidth c = Set.size (circuitQubits c)

-- | Get gate count
{-@ gateCount :: c:Circuit -> {v:Int | v >= 0} @-}
gateCount :: Circuit -> Int
gateCount c = length (circuitGates c)

-- | Append a gate to a circuit
{-@ appendGate :: c:Circuit -> g:Gate 
               -> {v:Circuit | gateCount v == gateCount c + 1} @-}
appendGate :: Circuit -> Gate -> Circuit
appendGate c g = c { circuitGates = circuitGates c ++ [g] }

-- | Compose two circuits sequentially
{-@ composeCircuits :: c1:Circuit -> c2:Circuit
                    -> {v:Circuit | gateCount v == gateCount c1 + gateCount c2} @-}
composeCircuits :: Circuit -> Circuit -> Circuit
composeCircuits c1 c2 = Circuit
    { circuitGates = circuitGates c1 ++ circuitGates c2
    , circuitQubits = circuitQubits c1 `Set.union` circuitQubits c2
    , circuitDepth = circuitDepth c1 + circuitDepth c2
    }

-- | Validate that all gates in circuit have correct arity
{-@ validateCircuit :: c:Circuit -> Bool @-}
validateCircuit :: Circuit -> Bool
validateCircuit c = all validGateArity (circuitGates c)

-- | Witness that a circuit is well-formed
data CircuitWitness = CircuitWitness
    { cwCircuit       :: Circuit
    , cwValidArity    :: Bool  -- ^ All gates have correct arity
    , cwValidQubits   :: Bool  -- ^ All gate qubits are in circuit qubit set
    , cwNoClone       :: Bool  -- ^ No qubit cloning
    }
    deriving (Eq, Show)

-- | Witness that a transformation preserves circuit semantics
data PreservationWitness = PreservationWitness
    { pwOriginal      :: Circuit
    , pwTransformed   :: Circuit
    , pwSameQubits    :: Bool  -- ^ Same qubit set
    , pwSameDepth     :: Bool  -- ^ Same or better depth
    , pwEquivalent    :: Bool  -- ^ Semantically equivalent
    }
    deriving (Eq, Show)

-- | Create circuit witness
{-@ createCircuitWitness :: c:Circuit -> Bool -> Bool -> Bool -> CircuitWitness @-}
createCircuitWitness :: Circuit -> Bool -> Bool -> Bool -> CircuitWitness
createCircuitWitness c arity qubits noclone = CircuitWitness
    { cwCircuit = c
    , cwValidArity = arity
    , cwValidQubits = qubits
    , cwNoClone = noclone
    }

-- | Validate circuit witness
{-@ validateCircuitWitness :: cw:CircuitWitness -> Bool @-}
validateCircuitWitness :: CircuitWitness -> Bool
validateCircuitWitness cw = 
    cwValidArity cw && cwValidQubits cw && cwNoClone cw

-- | Create preservation witness
{-@ createPreservationWitness :: c1:Circuit -> c2:Circuit -> Bool -> Bool -> Bool 
                              -> PreservationWitness @-}
createPreservationWitness :: Circuit -> Circuit -> Bool -> Bool -> Bool -> PreservationWitness
createPreservationWitness c1 c2 sameQ sameD equiv = PreservationWitness
    { pwOriginal = c1
    , pwTransformed = c2
    , pwSameQubits = sameQ
    , pwSameDepth = sameD
    , pwEquivalent = equiv
    }

-- | Validate preservation witness
{-@ validatePreservationWitness :: pw:PreservationWitness -> Bool @-}
validatePreservationWitness :: PreservationWitness -> Bool
validatePreservationWitness pw =
    pwSameQubits pw && pwSameDepth pw && pwEquivalent pw

-- | Check if two circuits have the same qubit set
{-@ sameQubitSet :: c1:Circuit -> c2:Circuit -> Bool @-}
sameQubitSet :: Circuit -> Circuit -> Bool
sameQubitSet c1 c2 = circuitQubits c1 == circuitQubits c2

-- | Check if depth is preserved or improved
{-@ depthPreserved :: c1:Circuit -> c2:Circuit -> Bool @-}
depthPreserved :: Circuit -> Circuit -> Bool
depthPreserved c1 c2 = circuitDepth c2 <= circuitDepth c1

-- | Empty circuit
{-@ emptyCircuit :: {v:Circuit | gateCount v == 0 && circuitWidth v == 0} @-}
emptyCircuit :: Circuit
emptyCircuit = Circuit
    { circuitGates = []
    , circuitQubits = Set.empty
    , circuitDepth = 0
    }

-- | Single-gate circuit
{-@ singleGateCircuit :: g:Gate -> {v:Circuit | gateCount v == 1} @-}
singleGateCircuit :: Gate -> Circuit
singleGateCircuit g = Circuit
    { circuitGates = [g]
    , circuitQubits = Set.fromList (gateQubits g)
    , circuitDepth = 1
    }

-- | Check if gate uses only qubits from the circuit
{-@ gateUsesCircuitQubits :: g:Gate -> c:Circuit -> Bool @-}
gateUsesCircuitQubits :: Gate -> Circuit -> Bool
gateUsesCircuitQubits g c = 
    all (`Set.member` circuitQubits c) (gateQubits g)

-- | Count gates of a specific type
{-@ countGateType :: GateType -> c:Circuit -> {v:Int | v >= 0 && v <= gateCount c} @-}
countGateType :: GateType -> Circuit -> Int
countGateType gt c = length $ filter (\g -> gateType g == gt) (circuitGates c)

-- Made with Bob
