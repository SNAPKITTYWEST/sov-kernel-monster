{-# LANGUAGE GADTs #-}

module SnapKitty.Liquid.ERE5 where

import SnapKitty.Liquid.Core

data ERE5 = ERE5
  { p1NoSecrets   :: Pass
  , p2NoEval      :: Pass
  , p3Budget      :: Pass
  , p4NoTelemetry :: Pass
  , p5AuditHash   :: Pass
  }

{-@ reflect ereAccept @-}
ereAccept :: ERE5 -> Bool
ereAccept e =
     isPass (p1NoSecrets e)
  && isPass (p2NoEval e)
  && isPass (p3Budget e)
  && isPass (p4NoTelemetry e)
  && isPass (p5AuditHash e)

{-@ theorem_ere_accept_implies_hash :: e:{ERE5 | ereAccept e} -> { isPass (p5AuditHash e) } @-}
theorem_ere_accept_implies_hash :: ERE5 -> Proof
theorem_ere_accept_implies_hash _ = ()

{-@ theorem_ere_accept_implies_no_eval :: e:{ERE5 | ereAccept e} -> { isPass (p2NoEval e) } @-}
theorem_ere_accept_implies_no_eval :: ERE5 -> Proof
theorem_ere_accept_implies_no_eval _ = ()

{-@ theorem_ere_accept_implies_no_secrets :: e:{ERE5 | ereAccept e} -> { isPass (p1NoSecrets e) } @-}
theorem_ere_accept_implies_no_secrets :: ERE5 -> Proof
theorem_ere_accept_implies_no_secrets _ = ()

{-@ theorem_ere_accept_implies_no_telemetry :: e:{ERE5 | ereAccept e} -> { isPass (p4NoTelemetry e) } @-}
theorem_ere_accept_implies_no_telemetry :: ERE5 -> Proof
theorem_ere_accept_implies_no_telemetry _ = ()

ereAllPass :: ERE5
ereAllPass = ERE5 Pass Pass Pass Pass Pass

ereFivePass :: ERE5 -> ERE5 -> ERE5 -> ERE5 -> ERE5 -> ERE5
ereFivePass e1 e2 e3 e4 e5 = ERE5
  (if p1NoSecrets e1 == Pass && p1NoSecrets e2 == Pass && p1NoSecrets e3 == Pass && p1NoSecrets e4 == Pass && p1NoSecrets e5 == Pass then Pass else Fail)
  (if p2NoEval e1 == Pass && p2NoEval e2 == Pass && p2NoEval e3 == Pass && p2NoEval e4 == Pass && p2NoEval e5 == Pass then Pass else Fail)
  (if p3Budget e1 == Pass && p3Budget e2 == Pass && p3Budget e3 == Pass && p3Budget e4 == Pass && p3Budget e5 == Pass then Pass else Fail)
  (if p4NoTelemetry e1 == Pass && p4NoTelemetry e2 == Pass && p4NoTelemetry e3 == Pass && p4NoTelemetry e4 == Pass && p4NoTelemetry e5 == Pass then Pass else Fail)
  (if p5AuditHash e1 == Pass && p5AuditHash e2 == Pass && p5AuditHash e3 == Pass && p5AuditHash e4 == Pass && p5AuditHash e5 == Pass then Pass else Fail)
