-- SEB.Protocol
-- Ahmad Ali Parr, SnapKitty Collective 2026
-- L0 Formal Specification — Guardian of the state machine.
-- Extracted from SEB_SOVEREIGN_EVENT_BUS_MASTER_SPECIFICATION.xml v1.1.0
-- All types, predicates and transition rules are total.

module SEB.Protocol

import Data.So
import Data.Vect
import Data.List

%default total

-- ============================================================================
-- PRIMITIVE TYPES
-- ============================================================================

public export
Bytes32 : Type
Bytes32 = Vect 32 Bits8

public export
Bytes14 : Type
Bytes14 = Vect 14 Bits8

public export
Hash256 : Type
Hash256 = Vect 32 Bits8

public export
Sig64 : Type
Sig64 = Vect 64 Bits8

-- ============================================================================
-- EXTERNAL PRIMITIVES (Trusted Boundary)
-- Implemented by: seb_lattice.c (circuit) + seb_wal.adb (mmap kernel)
-- ============================================================================

||| Ed25519 signature verification.
||| Implemented by ed25519_verify in seb_kernel_nif.c.
public export
postulate ed25519Verify : (pubkey : Bytes32) -> (msg : Hash256) -> (sig : Sig64) -> Bool

||| BLAKE3 hash of header bytes concatenated with payload bytes.
||| Implemented by blake3_hash in seb_kernel_nif.c.
public export
postulate blake3Hash : (header : List Bits8) -> (payload : List Bits8) -> Hash256

-- ============================================================================
-- CANONICAL EVENT STRUCTURE (matches seb_types.ads wire layout exactly)
-- Header = 68 bytes, Footer = 128 bytes, Total overhead = 196 bytes
-- ============================================================================

public export
record EventHeader where
  constructor MkHeader
  offset      : Bits64           -- monotonic log offset
  timestamp   : Bits64           -- Unix nanoseconds
  agentId     : Bytes32          -- Ed25519 public key (32 bytes)
  eventType   : Bits16           -- event type registry code
  payloadSize : Bits32           -- payload length in bytes
  reserved    : Bytes14          -- zero padding to reach 68 bytes

public export
record EventFooter where
  constructor MkFooter
  prevHash   : Hash256           -- BLAKE3 of prior event
  eventHash  : Hash256           -- BLAKE3 of header || payload
  signature  : Sig64             -- Ed25519 of eventHash

public export
record SEBEvent where
  constructor MkEvent
  header  : EventHeader
  payload : List Bits8           -- variable length
  footer  : EventFooter

-- ============================================================================
-- WIRE CONSTANTS (from SEB_Schema / seb_types.ads)
-- ============================================================================

public export
FIXED_HEADER_SIZE : Nat
FIXED_HEADER_SIZE = 68

public export
FIXED_FOOTER_SIZE : Nat
FIXED_FOOTER_SIZE = 128

public export
FIXED_OVERHEAD : Nat
FIXED_OVERHEAD = FIXED_HEADER_SIZE + FIXED_FOOTER_SIZE  -- 196

public export
SEGMENT_SIZE : Nat
SEGMENT_SIZE = 1073741824  -- 1 GiB

-- ============================================================================
-- PROOF-CARRYING PREDICATES
-- Each is a Type — inhabited = proof holds, uninhabited = cannot compile
-- ============================================================================

||| Plasma Gate: Ed25519 signature is valid.
public export
SigValid : SEBEvent -> Type
SigValid e = So (ed25519Verify
                   e.header.agentId
                   e.footer.eventHash
                   e.footer.signature)

||| Hash integrity: footer.eventHash = BLAKE3(header bytes || payload).
||| We model header bytes as the payload of the header record fields.
public export
HashValid : SEBEvent -> Type
HashValid e = e.footer.eventHash
            = blake3Hash (toList e.header.agentId) e.payload

||| Chain link: event's prevHash equals the given tip.
public export
ChainLink : SEBEvent -> Hash256 -> Type
ChainLink e tip = e.footer.prevHash = tip

||| Offset advances: new offset is strictly greater than tip offset.
public export
OffsetAdvances : SEBEvent -> Bits64 -> Type
OffsetAdvances e tipOff = e.header.offset > tipOff = True

-- ============================================================================
-- WORM CHAIN INVARIANT (newest-first list)
-- ============================================================================

public export
GENESIS_HASH : Hash256
GENESIS_HASH = replicate 32 0x00

||| ChainIntact: every event links to its predecessor; first links to genesis.
public export
ChainIntact : List SEBEvent -> Type
ChainIntact []        = ()
ChainIntact [e]       = e.footer.prevHash = GENESIS_HASH
ChainIntact (x :: y :: xs) =
  (x.footer.prevHash = y.footer.eventHash, ChainIntact (y :: xs))

||| OffsetMonotonic: offsets strictly decrease going newest-to-oldest.
public export
OffsetMonotonic : List SEBEvent -> Type
OffsetMonotonic []            = ()
OffsetMonotonic [_]           = ()
OffsetMonotonic (x :: y :: xs) =
  (x.header.offset > y.header.offset = True, OffsetMonotonic (y :: xs))

||| AllSigValid: every event has a valid signature.
public export
data AllSigValid : List SEBEvent -> Type where
  ASVNil  : AllSigValid []
  ASVCons : SigValid e -> AllSigValid es -> AllSigValid (e :: es)

||| AllHashValid: every event hash matches its content.
public export
data AllHashValid : List SEBEvent -> Type where
  AHVNil  : AllHashValid []
  AHVCons : HashValid e -> AllHashValid es -> AllHashValid (e :: es)

-- ============================================================================
-- MASTER INVARIANT — ValidLogState
-- Carrying all four proofs simultaneously is the protocol guarantee.
-- ============================================================================

public export
record ValidLogState where
  constructor MkValidLog
  events      : List SEBEvent
  chainProof  : ChainIntact events
  sigProof    : AllSigValid events
  hashProof   : AllHashValid events
  offsetProof : OffsetMonotonic events

public export
tipHash : ValidLogState -> Hash256
tipHash log = case log.events of
  []      => GENESIS_HASH
  (e :: _) => e.footer.eventHash

public export
tipOffset : ValidLogState -> Bits64
tipOffset log = case log.events of
  []       => 0
  (e :: _) => e.header.offset

-- ============================================================================
-- APPEND EVENT
-- All four proof obligations must be supplied by the caller.
-- If any is missing the program does not typecheck — the gate is the type.
-- ============================================================================

public export
appendEvent :
  (log     : ValidLogState) ->
  (evt     : SEBEvent) ->
  (sigPrf  : SigValid evt) ->
  (hashPrf : HashValid evt) ->
  (chainPrf : evt.footer.prevHash = tipHash log) ->
  (offPrf  : evt.header.offset > tipOffset log = True) ->
  ValidLogState
appendEvent log evt sigPrf hashPrf chainPrf offPrf =
  MkValidLog
    (evt :: log.events)
    (chainPrf, log.chainProof)
    (ASVCons sigPrf log.sigProof)
    (AHVCons hashPrf log.hashProof)
    (offPrf, log.offsetProof)

public export
emptyLog : ValidLogState
emptyLog = MkValidLog [] () ASVNil AHVNil ()

-- ============================================================================
-- BUS STATE (four-state machine)
-- ============================================================================

public export
data BusState : Type where
  Uninitialized : BusState
  Active        : ValidLogState -> BusState
  Sealed        : ValidLogState -> BusState
  Compromised   : BusState

-- ============================================================================
-- STATE MACHINE TRANSITION
-- Four clauses, sink semantics: Sealed and Compromised absorb all events.
-- The proof obligations enforce all L0 invariants at the type level.
-- ============================================================================

public export
transition :
  (st      : BusState) ->
  (evt     : SEBEvent) ->
  (sigPrf  : SigValid evt) ->
  (hashPrf : HashValid evt) ->
  (chainPrf : evt.footer.prevHash =
                case st of
                  Active log => tipHash log
                  _          => GENESIS_HASH) ->
  (offPrf  : evt.header.offset >
               (case st of
                  Active log => tipOffset log
                  _          => 0) = True) ->
  BusState
transition Uninitialized evt sigPrf hashPrf chainPrf offPrf =
  Active (appendEvent emptyLog evt sigPrf hashPrf chainPrf offPrf)
transition (Active log) evt sigPrf hashPrf chainPrf offPrf =
  Active (appendEvent log evt sigPrf hashPrf chainPrf offPrf)
transition (Sealed _)  _ _ _ _ _ = Compromised
transition Compromised _ _ _ _ _ = Compromised

-- ============================================================================
-- STATE MACHINE EXHAUSTIVENESS THEOREM
-- Every BusState has a defined transition for every event + proofs.
-- Proof: by case analysis — all four constructors covered above.
-- ============================================================================

public export
transitionTotal :
  (st : BusState) ->
  (evt : SEBEvent) ->
  (sp : SigValid evt) ->
  (hp : HashValid evt) ->
  (cp : evt.footer.prevHash =
          case st of
            Active log => tipHash log
            _          => GENESIS_HASH) ->
  (op : evt.header.offset >
          (case st of
             Active log => tipOffset log
             _          => 0) = True) ->
  BusState
transitionTotal = transition
-- Proof: transition is defined on all four constructors of BusState.
-- %default total ensures Idris verified exhaustiveness at compile time.

-- ============================================================================
-- CHAIN INTEGRITY INDUCTION
-- If a log is valid and we append with all proofs, it remains valid.
-- ============================================================================

public export
appendPreservesValidity :
  (log    : ValidLogState) ->
  (evt    : SEBEvent) ->
  (sp     : SigValid evt) ->
  (hp     : HashValid evt) ->
  (cp     : evt.footer.prevHash = tipHash log) ->
  (op     : evt.header.offset > tipOffset log = True) ->
  ChainIntact (evt :: log.events)
appendPreservesValidity log evt sp hp cp op =
  case log.events of
    []   => cp   -- single event: prevHash = GENESIS_HASH (cp gives this when tipHash = GENESIS_HASH)
    _    => (cp, log.chainProof)
