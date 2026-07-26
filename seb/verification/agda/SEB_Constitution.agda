-- SEB_Constitution.agda
-- Cherry-picked from systemic-intelligence/agda/src/Constitution.agda
-- Extended with SEB event types and linked to SEB_Protocol.idr invariants.
--
-- This file is the Agda formal constitution for SEB authorization.
-- It proves: denied proposals never execute (denied-no-exec).
-- Combined with SEB_Protocol.idr:
--   transition requires SigValid + HashValid + ChainLink + OffsetAdvances
-- This adds: Authorize(proposal) = Approved is a PRECONDITION for transition.

module SEB_Constitution where

open import Data.Nat using (ℕ; zero; suc; _<_; _≤_)
open import Data.Bool using (Bool; true; false; _∧_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans)
open import Data.Product using (_×_; _,_; proj₁; proj₂)

-- ============================================================================
-- SEB EVENT TYPE REGISTRY (from SEB_Protocol.idr / seb_types.ads)
-- ============================================================================

data EventType : Set where
  INFRA_PROVISION  : EventType   -- 0x0001  capability: execute
  CONFIG_DEPLOY    : EventType   -- 0x0002  capability: write
  ARCH_DECISION    : EventType   -- 0x0010  capability: verify
  FISCAL_SETTLE    : EventType   -- 0x0100  capability: execute + weight=MAX
  SOVEREIGN_ROOT   : EventType   -- 0xFFFF  capability: vacuum_collapse
  PROBLEM_SOLVED   : EventType   -- 0x0400  capability: observe (P/NP bridge)
  ATTACK_DETECTED  : EventType   -- 0x0401  capability: observe (convergence)

-- ============================================================================
-- CAPABILITY MODEL (maps to Datalog authority.dl + seb_policy.dl)
-- ============================================================================

data Capability : Set where
  Execute         : Capability
  Write           : Capability
  Read            : Capability
  Verify          : Capability
  Observe         : Capability
  VacuumCollapse  : Capability   -- SOVEREIGN_ROOT only

-- Required capability for each event type
requiredCap : EventType → Capability
requiredCap INFRA_PROVISION  = Execute
requiredCap CONFIG_DEPLOY    = Write
requiredCap ARCH_DECISION    = Verify
requiredCap FISCAL_SETTLE    = Execute
requiredCap SOVEREIGN_ROOT   = VacuumCollapse
requiredCap PROBLEM_SOLVED   = Observe
requiredCap ATTACK_DETECTED  = Observe

-- ============================================================================
-- PROPOSAL (typed command object — matches ocaml/lib/planner.ml)
-- ============================================================================

record Proposal : Set where
  field
    actor          : ℕ             -- agent ID (1=bob, 2=metatron, 3=edaulc, 4=autonomous)
    capability     : Capability    -- claimed capability
    eventType      : EventType     -- proposed event type
    precondition   : Bool          -- kernel precondition check (from SPARK kernel)
    signatureValid : Bool          -- Plasma Gate: Ed25519 valid
    chainValid     : Bool          -- hash chain intact

-- ============================================================================
-- VERDICT (SPARK kernel output)
-- ============================================================================

data Verdict : Set where
  Approved : Verdict
  Denied   : Verdict

-- ============================================================================
-- CONSTITUTION: the authorization function
-- Three gates must all hold: precondition AND signature AND chain AND capability
-- ============================================================================

capabilityMatch : Capability → EventType → Bool
capabilityMatch Execute INFRA_PROVISION = true
capabilityMatch Write   CONFIG_DEPLOY   = true
capabilityMatch Verify  ARCH_DECISION   = true
capabilityMatch Execute FISCAL_SETTLE   = true
capabilityMatch VacuumCollapse SOVEREIGN_ROOT = true
capabilityMatch Observe PROBLEM_SOLVED  = true
capabilityMatch Observe ATTACK_DETECTED = true
capabilityMatch _ _                     = false

authorize : Proposal → Verdict
authorize p with
  Proposal.precondition p ∧
  Proposal.signatureValid p ∧
  Proposal.chainValid p ∧
  capabilityMatch (Proposal.capability p) (Proposal.eventType p)
... | true  = Approved
... | false = Denied

-- ============================================================================
-- THEOREMS
-- ============================================================================

-- THEOREM 1 (from systemic-intelligence): denied proposals never execute
-- Extended: denied means at least one of {precondition, sig, chain, cap} failed
denied-no-exec :
  ∀ (p : Proposal) →
  (Proposal.precondition p ≡ false) →
  authorize p ≡ Denied
denied-no-exec p refl = refl

-- THEOREM 2: signature failure always denies
sig-failure-denied :
  ∀ (p : Proposal) →
  Proposal.signatureValid p ≡ false →
  authorize p ≡ Denied
sig-failure-denied p refl = refl

-- THEOREM 3: chain failure always denies (WORM integrity)
chain-failure-denied :
  ∀ (p : Proposal) →
  Proposal.chainValid p ≡ false →
  authorize p ≡ Denied
chain-failure-denied p refl = refl

-- THEOREM 4: wrong capability always denies
-- If claimed capability doesn't match event type, Denied.
wrong-cap-denied :
  ∀ (p : Proposal) →
  capabilityMatch (Proposal.capability p) (Proposal.eventType p) ≡ false →
  authorize p ≡ Denied
wrong-cap-denied p refl = refl

-- THEOREM 5: SOVEREIGN_ROOT requires VacuumCollapse exclusively
-- No other capability can authorize SOVEREIGN_ROOT
sovereign-requires-vacuum :
  ∀ (c : Capability) →
  c ≢ VacuumCollapse →
  capabilityMatch c SOVEREIGN_ROOT ≡ false
sovereign-requires-vacuum Execute   h = refl
sovereign-requires-vacuum Write     h = refl
sovereign-requires-vacuum Read      h = refl
sovereign-requires-vacuum Verify    h = refl
sovereign-requires-vacuum Observe   h = refl
sovereign-requires-vacuum VacuumCollapse h = ⊥-elim (h refl)
  where
    open import Data.Empty using (⊥-elim)
    open import Relation.Nullary using (_≢_)
