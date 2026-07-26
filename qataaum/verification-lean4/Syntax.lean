/-
  QATAAUM Quantum Compiler - Syntax Formalization
  
  This module defines the formal syntax of quantum circuits, gates, and
  intermediate representations used in the QATAAUM compiler.
  
  Clean-room implementation based on:
  - Quantum circuit model (Nielsen & Chuang 2000)
  - Formal semantics of quantum programming (Selinger 2004)
  - Type theory for quantum computing (Altenkirch & Grattage 2005)
-/

import Mathlib.Data.Finset.Basic
import Mathlib.Data.List.Basic
import Mathlib.Data.Nat.Basic

namespace QATAAUMVerification

/-- Qubit identifier (natural number) -/
def QubitId := Nat
deriving DecidableEq, Repr

/-- Classical bit identifier -/
def ClassicalId := Nat
deriving DecidableEq, Repr

/-- Angle parameter (real number in radians) -/
def Angle := Float
deriving Repr

/-- Gate types in quantum circuits -/
inductive GateType where
  | X       : GateType  -- Pauli X (NOT)
  | Y       : GateType  -- Pauli Y
  | Z       : GateType  -- Pauli Z
  | H       : GateType  -- Hadamard
  | S       : GateType  -- S gate (phase)
  | T       : GateType  -- T gate (π/8)
  | CX      : GateType  -- CNOT
  | CY      : GateType  -- Controlled-Y
  | CZ      : GateType  -- Controlled-Z
  | CCX     : GateType  -- Toffoli (CCNOT)
  | RX      : GateType  -- X rotation
  | RY      : GateType  -- Y rotation
  | RZ      : GateType  -- Z rotation
  | Measure : GateType  -- Measurement
deriving DecidableEq, Repr

/-- Get the arity (number of qubits) for a gate type -/
def GateType.arity : GateType → Nat
  | GateType.X => 1
  | GateType.Y => 1
  | GateType.Z => 1
  | GateType.H => 1
  | GateType.S => 1
  | GateType.T => 1
  | GateType.CX => 2
  | GateType.CY => 2
  | GateType.CZ => 2
  | GateType.CCX => 3
  | GateType.RX => 1
  | GateType.RY => 1
  | GateType.RZ => 1
  | GateType.Measure => 1

/-- Quantum gate with operands -/
structure Gate where
  gateType : GateType
  qubits   : List QubitId
  angle    : Option Angle
  deriving Repr

/-- Well-formed gate: arity matches qubit count -/
def Gate.wellFormed (g : Gate) : Prop :=
  g.qubits.length = g.gateType.arity

/-- Quantum circuit as a sequence of gates -/
structure Circuit where
  gates      : List Gate
  qubitCount : Nat
  deriving Repr

/-- All gates in circuit are well-formed -/
def Circuit.wellFormed (c : Circuit) : Prop :=
  ∀ g ∈ c.gates, Gate.wellFormed g

/-- All qubits used in circuit are within bounds -/
def Circuit.qubitsBounded (c : Circuit) : Prop :=
  ∀ g ∈ c.gates, ∀ q ∈ g.qubits, q < c.qubitCount

/-- Circuit is valid if well-formed and qubits bounded -/
def Circuit.valid (c : Circuit) : Prop :=
  c.wellFormed ∧ c.qubitsBounded

/-- Empty circuit with n qubits -/
def Circuit.empty (n : Nat) : Circuit :=
  { gates := [], qubitCount := n }

/-- Append a gate to a circuit -/
def Circuit.append (c : Circuit) (g : Gate) : Circuit :=
  { gates := c.gates ++ [g], qubitCount := c.qubitCount }

/-- Compose two circuits sequentially -/
def Circuit.compose (c1 c2 : Circuit) : Circuit :=
  { gates := c1.gates ++ c2.gates
  , qubitCount := max c1.qubitCount c2.qubitCount }

/-- Circuit depth (number of time steps) -/
def Circuit.depth (c : Circuit) : Nat :=
  c.gates.length  -- Simplified: assumes no parallelism

/-- Gate count -/
def Circuit.gateCount (c : Circuit) : Nat :=
  c.gates.length

/-- Qubit state: Owned, Released, or Measured -/
inductive QubitState where
  | Owned    : QubitState
  | Released : QubitState
  | Measured : QubitState
deriving DecidableEq, Repr

/-- Qubit with state tracking -/
structure Qubit where
  id    : QubitId
  state : QubitState
deriving Repr

/-- Qubit is owned (can be used) -/
def Qubit.isOwned (q : Qubit) : Prop :=
  q.state = QubitState.Owned

/-- Qubit is released (cannot be reused) -/
def Qubit.isReleased (q : Qubit) : Prop :=
  q.state = QubitState.Released

/-- Qubit is measured -/
def Qubit.isMeasured (q : Qubit) : Prop :=
  q.state = QubitState.Measured

/-- Valid state transition -/
def QubitState.validTransition : QubitState → QubitState → Prop
  | Owned, Owned => True
  | Owned, Released => True
  | Owned, Measured => True
  | Released, Released => True
  | Measured, Measured => True
  | _, _ => False

/-- Scheduled operation with timing -/
structure ScheduledOp where
  gate      : Gate
  startTime : Float
  duration  : Float
  deriving Repr

/-- Scheduled operation has valid timing -/
def ScheduledOp.validTiming (op : ScheduledOp) : Prop :=
  op.startTime ≥ 0 ∧ op.duration > 0

/-- End time of scheduled operation -/
def ScheduledOp.endTime (op : ScheduledOp) : Float :=
  op.startTime + op.duration

/-- Two operations overlap in time -/
def ScheduledOp.timeOverlap (op1 op2 : ScheduledOp) : Prop :=
  ¬(op1.endTime ≤ op2.startTime ∨ op2.endTime ≤ op1.startTime)

/-- Two operations share qubits -/
def ScheduledOp.shareQubits (op1 op2 : ScheduledOp) : Prop :=
  ∃ q, q ∈ op1.gate.qubits ∧ q ∈ op2.gate.qubits

/-- Two operations conflict (overlap in time on shared qubits) -/
def ScheduledOp.conflict (op1 op2 : ScheduledOp) : Prop :=
  op1.shareQubits op2 ∧ op1.timeOverlap op2

/-- Schedule of operations -/
structure Schedule where
  ops      : List ScheduledOp
  makespan : Float
  deriving Repr

/-- Schedule has no conflicts -/
def Schedule.noConflicts (s : Schedule) : Prop :=
  ∀ op1 ∈ s.ops, ∀ op2 ∈ s.ops, op1 ≠ op2 → ¬op1.conflict op2

/-- All operations have valid timing -/
def Schedule.validTiming (s : Schedule) : Prop :=
  ∀ op ∈ s.ops, op.validTiming

/-- Schedule is valid -/
def Schedule.valid (s : Schedule) : Prop :=
  s.noConflicts ∧ s.validTiming

/-- Compiler pass result -/
structure PassResult where
  input  : Circuit
  output : Circuit
deriving Repr

/-- Pass preserves qubit count -/
def PassResult.preservesQubits (pr : PassResult) : Prop :=
  pr.input.qubitCount = pr.output.qubitCount

/-- Pass preserves or improves depth -/
def PassResult.preservesDepth (pr : PassResult) : Prop :=
  pr.output.depth ≤ pr.input.depth

/-- Pass reduces gate count -/
def PassResult.reducesGates (pr : PassResult) : Prop :=
  pr.output.gateCount ≤ pr.input.gateCount

end QATAAUMVerification