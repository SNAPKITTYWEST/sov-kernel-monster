# Sovereign PL/I — Non-Recursive Polyglot Compute Layer

**PAR-020** · Ahmad Ali Parr · SnapKitty Collective · 2026

PL/I upgraded into a high-performance sovereign compute layer,
interlocked with COBOL (record gate) and INTERCAL (control inversion).
Non-recursive throughout. All stack-growth eliminated.

---

## Five Upgrades Implemented

### 1. Zero-Cost Abstractions (`sov_kernel.pli`)
PL/I `%REPLACE` and `%INCLUDE` directives act as compile-time macros —
no runtime type coercion, no dynamic dispatch. All type bindings resolved
at expansion time. The resulting binary carries zero runtime overhead from
type checking. φ⁻¹ encoded as an exact fixed-point integer (`6180339887`).

### 2. S-Expression Metacoding (`sov_kernel.pli` + `intercal_invert.i`)
PL/I `BASED` structures form homoiconic tree nodes (TAG, ATOM_VAL, CAR_PTR,
CDR_PTR). INTERCAL arrays mirror these nodes as demand-driven ASTs — the
result *pulls* the computation via `COME FROM` instead of the computation
*pushing* to the result. Non-recursive: all tree walks are iterative `DO` loops.

### 3. Cryptographic State at Variable Assignment (`sov_record_gate.cbl`)
Every COBOL field assignment triggers a Blake3 partial hash accumulation.
The density matrix record carries its own `REC-BLAKE3-HASH` and `REC-ED25519-SIG`
fields inline. No external middleware — the record IS the proof.
φ-decay applied directly: `MULTIPLY WS-PHI-INV BY REC-PHI-ENERGY`.

### 4. Non-Blocking Actor Queue (`sov_kernel.pli` + `sov_record_gate.cbl`)
Ring buffer of capacity 256, no locks, power-of-2 wrapping via `MOD`.
PL/I enqueue/dequeue are O(1) with no mutex. COBOL's `500-ENQUEUE-STATE`
uses the same ring buffer pattern. INTERCAL's `COME FROM` models actor
*receive*: the actor does not call — it becomes available and the sender's
label fires it.

### 5. Bare-Metal Tensor Interop (`sov_kernel.pli`)
PL/I `EXTERNAL ENTRY` declarations wire directly into the Fortran ABI:
- `sov_jordan_step` → `jordan_block.f90` (φ⁻¹ Jordan step)
- `sov_bifrost_sign` → `sov_monster_kernel.f90` (Blake3 + Ed25519)

PL/I provides the record shell. Fortran does the ZGEMM. One ABI, no layers.

---

## The Interlock

```
PL/I kernel (sov_kernel.pli)
   │
   ├─ CALL COBOL_RECORD_GATE()  ──►  sov_record_gate.cbl
   │     Fixed-format density record validation
   │     φ-decay applied to PHI-ENERGY field
   │     Blake3 hash accumulated per field assignment
   │     Actor queue enqueue (non-blocking ring buffer)
   │
   ├─ CALL INTERCAL_INVERT()    ──►  intercal_invert.i
   │     COME FROM = demand-driven pull
   │     S-expression nodes built as INTERCAL arrays
   │     Born collapse gate (ABSTAIN/REINSTATE on eigenvalue threshold)
   │     NEXT depth capped at 1 — non-recursive
   │
   └─ EXTERNAL sov_jordan_step  ──►  ../src/jordan_block.f90
         φ⁻¹·UρU† + φ⁻²·ρ (the Jordan step)
         Blake3 + Ed25519 WORM seal
```

---

## Non-Recursive Guarantee

Every control flow path in this stack is non-recursive:
- PL/I: all procedures use `RETURN` not `CALL self`
- COBOL: all `PERFORM`s are `THRU EXIT` terminated, no nested `PERFORM UNTIL`
- INTERCAL: `NEXT` depth capped at 1, `RESUME (1)` fires immediately

The maximum call stack depth across the entire three-language layer is **3**
(PL/I → COBOL → Fortran ABI). No unbounded recursion. No stack overflow.

---

## Build

```bash
cd sovereign-pli && make all
# Requires: GNU PL/I or OpenPL/I, GnuCOBOL (cobc), C-INTERCAL (ick)
# Fortran objects built separately: cd .. && make all
```

---

## Language Stack

| Language | Role | Upgrade |
|---|---|---|
| PL/I | Kernel shell, actor queue, Fortran ABI | 1, 4, 5 |
| COBOL | Fixed-format record gate, φ-decay, crypto state | 3, 4 |
| INTERCAL | Control inversion, S-expr metacoding, Born gate | 2, 4 |
| Fortran 2018 | Matrix math, Jordan step, WORM seal | 5 |
