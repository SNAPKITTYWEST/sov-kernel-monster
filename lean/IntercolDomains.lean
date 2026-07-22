/-
  INTERCOL DOMAINS — Formal Definition & Orthogonality Proofs

  4 orthogonal domains from Sovereign Calculus:
  - D₁ = Treasury (financial reasoning, account movement)
  - D₂ = Clinical (verification, proof, measurement)
  - D₃ = Legal (policy, authorization, capability)
  - D₄ = Operations (execution, state change)

  Theorem: intercol_transition_impossible — Transitions between orthogonal
  domains return ⊥ (null state).
-/

import Lean
import Mathlib.Data.List.Perm
import Mathlib.Logic.Equiv.Set

namespace IntercolDomains

-- ══════════════════════════════════════════════════════════════════════════════
-- 1. DOMAIN DEFINITION
-- ══════════════════════════════════════════════════════════════════════════════

inductive Domain : Type where
  | treasury : Domain      -- D₁: Financial reasoning
  | clinical : Domain      -- D₂: Verification & proof
  | legal : Domain         -- D₃: Policy & authorization
  | operations : Domain    -- D₄: Execution & state change

deriving DecidableEq, Repr

/-- String representation for debugging -/
def Domain.toString : Domain → String
  | Domain.treasury => "Treasury (D₁)"
  | Domain.clinical => "Clinical (D₂)"
  | Domain.legal => "Legal (D₃)"
  | Domain.operations => "Operations (D₄)"

-- ══════════════════════════════════════════════════════════════════════════════
-- 2. ORTHOGONALITY RELATION
-- ══════════════════════════════════════════════════════════════════════════════

/-- Two domains are orthogonal if they are distinct -/
def orthogonal (d1 d2 : Domain) : Prop :=
  d1 ≠ d2

/-- Orthogonality is symmetric -/
theorem orthogonal_symm (d1 d2 : Domain) :
    orthogonal d1 d2 ↔ orthogonal d2 d1 := by
  constructor <;> (intro h; exact fun h' => h (h'.symm))

/-- Orthogonality is irreflexive -/
theorem orthogonal_irrefl (d : Domain) :
    ¬(orthogonal d d) := by
  intro h
  exact h rfl

-- ══════════════════════════════════════════════════════════════════════════════
-- 3. TRANSITION RULE
-- ══════════════════════════════════════════════════════════════════════════════

inductive TransitionResult : Type where
  | success (d : Domain) : TransitionResult
  | nullState : TransitionResult
  | error : String → TransitionResult

/-- Transition between same domain succeeds; between orthogonal domains returns null -/
def transition (d_from d_to : Domain) : TransitionResult :=
  if d_from = d_to then
    TransitionResult.success d_to
  else
    TransitionResult.nullState

-- ══════════════════════════════════════════════════════════════════════════════
-- 4. THEOREM: TRANSITION IMPOSSIBILITY
-- ══════════════════════════════════════════════════════════════════════════════

/-- Orthogonal transition returns null state -/
theorem intercol_transition_impossible (d1 d2 : Domain) :
    orthogonal d1 d2 →
    transition d1 d2 = TransitionResult.nullState := by
  intro h_orth
  unfold transition orthogonal at *
  by_cases h : d1 = d2
  · contradiction
  · simp [h]

/-- Converse: same-domain transition succeeds -/
theorem intercol_same_domain_allowed (d : Domain) :
    transition d d = TransitionResult.success d := by
  unfold transition
  simp

-- ══════════════════════════════════════════════════════════════════════════════
-- 5. DOMAIN ISOLATION INVARIANT
-- ══════════════════════════════════════════════════════════════════════════════

structure IsolatedState where
  domain : Domain
  authority : String      -- e.g., "agent-xyz"
  payload : ByteArray

/-- Transition preserves domain invariant -/
def preservesDomainInvariant (s : IsolatedState) (d_new : Domain) : Prop :=
  s.domain = d_new

/-- Isolated state cannot escape its domain -/
theorem domain_isolation_invariant (s : IsolatedState) (d_target : Domain) :
    orthogonal s.domain d_target →
    ¬(preservesDomainInvariant s d_target) := by
  intro h_orth h_preserve
  unfold preservesDomainInvariant orthogonal at *
  exact h_orth h_preserve.symm

-- ══════════════════════════════════════════════════════════════════════════════
-- 6. ENUMERATION & COMPLETENESS
-- ══════════════════════════════════════════════════════════════════════════════

/-- All 4 domains are distinct -/
theorem domains_distinct :
    let d1 := Domain.treasury
    let d2 := Domain.clinical
    let d3 := Domain.legal
    let d4 := Domain.operations
    d1 ≠ d2 ∧ d1 ≠ d3 ∧ d1 ≠ d4 ∧
    d2 ≠ d3 ∧ d2 ≠ d4 ∧
    d3 ≠ d4 := by
  decide

/-- Pairwise orthogonality (6 pairs) -/
theorem pairwise_orthogonal :
    let domains := [Domain.treasury, Domain.clinical, Domain.legal, Domain.operations]
    ∀ d1 d2 : Domain, d1 ∈ domains → d2 ∈ domains → d1 ≠ d2 →
    orthogonal d1 d2 := by
  intro domains d1 d2 _ _ h_ne
  exact h_ne

-- ══════════════════════════════════════════════════════════════════════════════
-- 7. APPLICAT ION: BIFROST PERSONA CONSTRAINT
-- ══════════════════════════════════════════════════════════════════════════════

/-- Persona has an allowed domain; cannot jump to orthogonal domain -/
structure PersonaConstraint where
  persona_id : Nat
  allowed_domain : Domain

/-- Constraint violation check -/
def violatesConstraint (c : PersonaConstraint) (d : Domain) : Bool :=
  c.allowed_domain ≠ d

/-- If constraint violated, transition fails -/
theorem constraint_enforces_isolation (c : PersonaConstraint) (d : Domain) :
    violatesConstraint c d = true →
    transition c.allowed_domain d = TransitionResult.nullState := by
  intro h_violate
  unfold transition violatesConstraint at *
  by_cases h_eq : c.allowed_domain = d
  · simp [h_eq] at h_violate
  · simp [h_eq]

end IntercolDomains
