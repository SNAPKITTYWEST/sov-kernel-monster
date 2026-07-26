-- Bifrost.Policy — formal policy as Lean 4 propositions + Boolean decision procedure.
--
-- Structure:
--   1. `valid*`  defs  — declarative Props (what the policy *means*)
--   2. `decide`  def   — computable Bool (what the runtime *checks*)
--   3. `decide_sound` theorem — `decide e s = true → valid_event e s`
--      Currently has a `sorry` placeholder; the proof obligation is tracked
--      as a P0 item for the Policy Engineer.

import Bifrost.State

namespace Bifrost

-- ── Validity propositions ────────────────────────────────────────────────────

/-- A `JitCompile` event is valid when:
    1. The SoulIR source (`souliirCid`) is immutably sealed in WORM_FS.
    2. The WASM output (`wasmCid`) is a fresh artifact (not yet in WORM). -/
def validJitCompile (e : Event) (s : State) : Prop :=
  match e with
  | Event.jitCompile souliir wasm _ _ =>
      s.wormSealed souliir = true ∧ s.wormSealed wasm = false
  | _ => False

/-- A `CapTransfer` event is valid when:
    1. The policy CID is sealed in WORM_FS (or is the zero genesis sentinel).
    2. The capability exists in the cap map (runtime-originated mints with zero
       cap_hash bypass this — they are rights-gated at the silverback level). -/
def validCapTransfer (e : Event) (s : State) : Prop :=
  match e with
  | Event.capTransfer _ _ capHash policyCid =>
      (Cid.isZero policyCid ∨ s.wormSealed policyCid = true) ∧
      (Cid.isZero capHash   ∨ s.capExists capHash = true)
  | _ => False

/-- An `attestation` event is valid when:
    1. The epoch root matches the state's recorded epoch root.
    2. The signature is over the genesis key (checked externally via `bifrost-attest`). -/
def validAttestation (e : Event) (s : State) : Prop :=
  match e with
  | Event.attestation epoch rootCid _ =>
      s.epochRoot epoch = some rootCid
  | _ => False

/-- An event is valid if it satisfies at least one of the valid-event rules. -/
def validEvent (e : Event) (s : State) : Prop :=
  validJitCompile e s ∨ validCapTransfer e s ∨ validAttestation e s

-- ── Decidable decision procedure ──────────────────────────────────────────────

/-- Boolean decision procedure — directly executable in Rust after extraction.
    This is the *single source of truth* for the runtime policy enforcer in
    `bifrost-policy/src/lib.rs::policy_decide`. -/
def decide (e : Event) (s : State) : Bool :=
  match e with
  | Event.jitCompile souliir wasm _ _ =>
      s.wormSealed souliir && !s.wormSealed wasm
  | Event.capTransfer _ _ capHash policyCid =>
      (Cid.isZero policyCid || s.wormSealed policyCid) &&
      (Cid.isZero capHash   || s.capExists capHash)
  | Event.attestation epoch rootCid _ =>
      (s.epochRoot epoch) == some rootCid

-- ── Soundness theorem ────────────────────────────────────────────────────────

/-- **Soundness**: if `decide` returns `true`, then `validEvent` holds.

    Proof: case analysis on `e`. For each constructor, unfold `decide` and
    the matching `valid*` predicate; the other two predicates reduce to `False`
    via their `| _ => False` arms, leaving a single conjunction to close
    with `Bool.and_eq_true`, `Bool.or_eq_true`, and `Bool.not_eq_true`. -/
theorem decide_sound (e : Event) (s : State)
    (h : decide e s = true) : validEvent e s := by
  match e with
  | Event.jitCompile souliir wasm _ _ =>
    simp only [validEvent, validJitCompile, validCapTransfer, validAttestation, decide,
               Bool.and_eq_true, Bool.not_eq_true, or_false, false_or] at *
    exact h
  | Event.capTransfer _ _ capHash policyCid =>
    simp only [validEvent, validJitCompile, validCapTransfer, validAttestation, decide,
               Bool.and_eq_true, Bool.or_eq_true, or_false, false_or] at *
    exact h
  | Event.attestation epoch rootCid _ =>
    simp only [validEvent, validJitCompile, validCapTransfer, validAttestation, decide,
               or_false, false_or] at *
    exact eq_of_beq h

/-- **Completeness**: if `validEvent` holds, then `decide` returns `true`.

    The converse of `decide_sound` — together they establish that `decide`
    is a correct decision procedure: it accepts exactly the valid events. -/
theorem decide_complete (e : Event) (s : State)
    (h : validEvent e s) : decide e s = true := by
  match e with
  | Event.jitCompile souliir wasm _ _ =>
    simp only [validEvent, validJitCompile, validCapTransfer, validAttestation,
               or_false, false_or] at h
    simp only [decide, Bool.and_eq_true, Bool.not_eq_true]
    exact h
  | Event.capTransfer _ _ capHash policyCid =>
    simp only [validEvent, validJitCompile, validCapTransfer, validAttestation,
               or_false, false_or] at h
    simp only [decide, Bool.and_eq_true, Bool.or_eq_true]
    exact h
  | Event.attestation epoch rootCid _ =>
    simp only [validEvent, validJitCompile, validCapTransfer, validAttestation,
               or_false, false_or] at h
    simp only [decide]
    exact beq_iff_eq.mpr h

end Bifrost
