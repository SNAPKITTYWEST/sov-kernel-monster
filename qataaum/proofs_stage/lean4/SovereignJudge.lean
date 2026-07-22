-- SovereignJudge.lean
-- Canonical verdict algebra — single source of truth
-- Bridges: Lean4PolicyKernel/Policies/Core.lean + holy-agents/TheologyValidator.lean
--          + SnaklTalk Verdict (evidence/silence) + Prolog sovereign_kernel.pl
--
-- Architecture:
--   Verdict          — operational (5-case): approve|reject|defer|escalate|human_required
--   MoralVerdict     — theological (3-case): approve|reject|repent  [TheologyValidator]
--   MoralAction      — boolean action fields shared across layers
--   MoralVerdict.toVerdict — bridge: moral → operational
--   SnaklVerdict     — Smalltalk wire format bridge: evidence|silence
--
-- Cross-language map:
--   Lean4 Verdict.approve    ↔  Prolog approve  ↔  Smalltalk Verdict evidence:
--   Lean4 Verdict.reject     ↔  Prolog reject   ↔  Smalltalk Verdict silence:
--   Lean4 Verdict.escalate   ↔  Prolog escalate ↔  VortexAgent audit escalation
--   Haskell EREPass          ↔  Lean4 .approve  ↔  five-pass pipeline
--   Idris2 (1 qt : QuantumTemp) ↔ Lean4 WormSeal subtype ↔ Haskell %1
--
-- Ahmad Ali Parr · SnapKitty Collective · 2026
-- SEIT NGO — Sovereign Enochian Institute of Technology

namespace Sovereign.Judge

-- ── Type aliases ──────────────────────────────────────────────────────────────
abbrev PolicyId       := String
abbrev DID            := String
abbrev HashURI        := String
abbrev Role           := String
abbrev CorrelationId  := String

-- ── WORM seal: dependent subtype ─────────────────────────────────────────────
-- Mirrors SovereignMorphism.lean WormSeal and SnaklTalk Seal
-- The length constraint lives in the TYPE — no runtime check needed
def WormSeal := { s : String // s.length = 64 }

-- ── Evidence bundle ───────────────────────────────────────────────────────────
structure Evidence where
  refs       : List HashURI
  hashes     : List ByteArray
  signatures : List (DID × ByteArray)
  deriving Repr

-- ── Evaluation context ────────────────────────────────────────────────────────
structure EvalContext where
  correlation_id : CorrelationId
  actor          : DID
  task_type      : String
  evidence       : Evidence
  timestamp      : UInt64
  nonce          : ByteArray
  deriving Repr

-- ── Operational Verdict (5 cases) ────────────────────────────────────────────
-- Canonical verdict algebra for policy enforcement.
-- Matches Prolog sovereign_kernel.pl approve|reject|defer|escalate|human_required.
-- Priority (strict): escalate > human_required > reject > defer > approve.
-- A chain of policies is as strict as its strictest member.

inductive Verdict where
  | approve        (policy_id   : PolicyId)        : Verdict
  | reject         (policy_id   : PolicyId)        : Verdict
  | defer          (reason      : String)          : Verdict
  | escalate       (target      : Role)            : Verdict
  | human_required (policy_ids  : List PolicyId)  : Verdict
  deriving Repr, BEq

def Verdict.priority : Verdict → Nat
  | .escalate _       => 4
  | .human_required _ => 3
  | .reject _         => 2
  | .defer _          => 1
  | .approve _        => 0

def Verdict.combine : List Verdict → Verdict
  | []        => .approve "SOV-DEFAULT-PASS"
  | v :: rest =>
    rest.foldl (fun acc cur =>
      if cur.priority > acc.priority then
        match acc, cur with
        | .human_required ps, .human_required qs => .human_required (ps ++ qs)
        | _, _                                    => cur
      else
        match acc, cur with
        | .human_required ps, .human_required qs => .human_required (ps ++ qs)
        | _, _                                    => acc
    ) v

def Verdict.isFinal : Verdict → Bool
  | .approve _ | .reject _ => true
  | _                      => false

def Verdict.requiresHuman : Verdict → Bool
  | .human_required _ => true
  | _                 => false

def Verdict.toNatsSubject : Verdict → String
  | .approve _        => "sovereign.audit.bifrost.commit.v1"
  | .reject _         => "sovereign.audit.bifrost.commit.v1"
  | .defer _          => "sovereign.governance.decision.pending.v1"
  | .escalate _       => "sovereign.governance.decision.pending.v1"
  | .human_required _ => "sovereign.governance.decision.pending.v1"

-- ── Moral Verdict (3 cases) ───────────────────────────────────────────────────
-- Theological verdict for the holy-agents moral judgement layer.
-- Simpler than the operational Verdict — no policy IDs, no escalation targets.
-- Previously duplicated in TheologyValidator.lean; canonical here.

inductive MoralVerdict where
  | approve : MoralVerdict
  | reject  : MoralVerdict
  | repent  : MoralVerdict   -- unique to the moral layer: calls for correction
  deriving Repr, DecidableEq

-- ── Moral Action ──────────────────────────────────────────────────────────────
-- Shared across moral judgement and theological reasoning.
-- Seven boolean predicates form the lawfulness check.

structure MoralAction where
  truthful        : Bool
  harmful         : Bool
  exploitative    : Bool
  requiresConsent : Bool
  hasConsent      : Bool
  witnessed       : Bool
  cited           : Bool
  deriving Repr

-- ── Lawfulness predicate ──────────────────────────────────────────────────────
def lawful (a : MoralAction) : Bool :=
  a.truthful &&
  !a.harmful &&
  !a.exploitative &&
  (!a.requiresConsent || a.hasConsent) &&
  a.witnessed &&
  a.cited

-- ── Moral judge ───────────────────────────────────────────────────────────────
def judge (a : MoralAction) : MoralVerdict :=
  if lawful a then .approve else .repent

-- ── Bridge: MoralVerdict → Verdict ───────────────────────────────────────────
-- Converts the theological 3-case verdict to the operational 5-case verdict.
-- repent → escalate: the moral arbiter escalates for review, does not silently reject.
def MoralVerdict.toVerdict (policyId : PolicyId) : MoralVerdict → Verdict
  | .approve => .approve policyId
  | .reject  => .reject  policyId
  | .repent  => .escalate "moral_arbiter"

-- ── SnaklVerdict bridge ───────────────────────────────────────────────────────
-- Maps Smalltalk SnaklTalk Verdict (evidence/silence) to operational Verdict.
-- SnaklTalk: Verdict evidence: aSeal  ↔  Lean4: .approve policyId
-- SnaklTalk: Verdict silence: aString ↔  Lean4: .reject  policyId
inductive SnaklVerdict where
  | evidence (seal    : WormSeal) : SnaklVerdict
  | silence  (reason  : String)   : SnaklVerdict
  deriving Repr

def SnaklVerdict.toVerdict (policyId : PolicyId) : SnaklVerdict → Verdict
  | .evidence _ => .approve policyId
  | .silence  _ => .reject  policyId

-- ── Sovereign critical tasks ──────────────────────────────────────────────────
-- Actions that always require human oversight — sovereignty boundary.
-- Any policy evaluating these MUST return human_required.
def sovereignCriticalTasks : List String :=
  [ "deploy_mainnet", "rotate_root_keys", "modify_trust_deed",
    "corpus_training_export", "capability_grant", "treasury_transfer",
    "worm_chain_reset", "agent_revocation", "seal_override" ]

def requiresHumanGate (taskType : String) : Bool :=
  taskType ∈ sovereignCriticalTasks

-- ── Policy typeclass ──────────────────────────────────────────────────────────
class Policy (π : PolicyId) where
  eval : EvalContext → Verdict

-- ── Proofs ────────────────────────────────────────────────────────────────────

theorem approved_is_lawful (a : MoralAction) :
    judge a = .approve → lawful a = true := by
  intro h
  unfold judge at h
  by_cases hl : lawful a = true
  · exact hl
  · simp [hl] at h

theorem repent_implies_not_lawful (a : MoralAction) :
    judge a = .repent → lawful a = false := by
  intro h
  unfold judge at h
  by_cases hl : lawful a = true
  · simp [hl] at h
  · rfl

theorem verdict_exhaustive (a : MoralAction) :
    judge a = .approve ∨ judge a = .repent := by
  unfold judge
  by_cases h : lawful a = true <;> simp [h]

theorem combine_singleton (v : Verdict) :
    Verdict.combine [v] = v := by
  simp [Verdict.combine]

-- Priority ordering is strict
theorem priority_bounded (v : Verdict) : v.priority ≤ 4 := by
  match v with
  | .approve _        => simp [Verdict.priority]
  | .reject _         => simp [Verdict.priority]
  | .defer _          => simp [Verdict.priority]
  | .escalate _       => simp [Verdict.priority]
  | .human_required _ => simp [Verdict.priority]

-- Bridge round-trip: evidence → approve, silence → reject
theorem snakl_evidence_approves (seal : WormSeal) (pid : PolicyId) :
    (SnaklVerdict.evidence seal).toVerdict pid = .approve pid := by
  rfl

theorem snakl_silence_rejects (reason : String) (pid : PolicyId) :
    (SnaklVerdict.silence reason).toVerdict pid = .reject pid := by
  rfl

-- repent always escalates (never silently absorbs)
theorem repent_escalates (a : MoralAction) (pid : PolicyId)
    (h : judge a = .repent) :
    (judge a).toVerdict pid = .escalate "moral_arbiter" := by
  rw [h]; rfl

-- ── Example actions ───────────────────────────────────────────────────────────
-- Kept for smoke-testing the predicate logic.

def lawfulAction : MoralAction :=
  { truthful := true, harmful := false, exploitative := false,
    requiresConsent := false, hasConsent := false,
    witnessed := true, cited := true }

def dishonestAction : MoralAction :=
  { truthful := false, harmful := false, exploitative := false,
    requiresConsent := false, hasConsent := false,
    witnessed := true, cited := true }

def harmfulAction : MoralAction :=
  { truthful := true, harmful := true, exploitative := false,
    requiresConsent := false, hasConsent := false,
    witnessed := true, cited := true }

theorem example_lawful_approves    : judge lawfulAction   = .approve  := by native_decide
theorem example_dishonest_repents  : judge dishonestAction = .repent  := by native_decide
theorem example_harmful_repents    : judge harmfulAction  = .repent   := by native_decide

end Sovereign.Judge
