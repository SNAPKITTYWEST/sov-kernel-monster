;; SEB Agent Sandbox — isolated WASM execution container
;; Cherry-picked from systemic-intelligence/wasm/agents/sandbox.wat
;; Extended: adds SEB receipt emission after approved SUBLEQ execution.
;;
;; Execution model:
;;   1. SPARK kernel approves Proposal → Verdict = Approved
;;   2. Agent executes inside this sandbox (isolated memory)
;;   3. SUBLEQ instruction is the only control flow primitive
;;   4. On halt: emit_receipt seals execution result to SEB chain
;;
;; SUBLEQ: M[B] = M[B] - M[A]; if M[B] <= 0 goto C else PC += 3
;;
;; Memory layout (64KB = 1 WASM page):
;;   [0x0000..0x03FF]  agent stack (1KB)
;;   [0x0400..0x7FFF]  agent heap  (31KB)
;;   [0x8000..0x8FFF]  SEB receipt region (4KB)
;;   [0x9000..0xFFFF]  reserved

(module
  (memory (export "mem") 1)

  ;; ── Stack ─────────────────────────────────────────────────────────────────

  (global $sp (mut i32) (i32.const 0x0400))   ;; stack grows up from 0x0400

  (func $push (param $val i32)
    (i32.store (global.get $sp) (local.get $val))
    (global.set $sp (i32.add (global.get $sp) (i32.const 4)))
  )

  (func $pop (result i32)
    (global.set $sp (i32.sub (global.get $sp) (i32.const 4)))
    (i32.load (global.get $sp))
  )

  ;; ── SUBLEQ (from systemic-intelligence) ──────────────────────────────────
  ;; M[B] = M[B] - M[A]
  ;; Returns: C if M[B] <= 0, else -1 (continue: PC += 3)
  (func (export "subleq")
        (param $a i32) (param $b i32) (param $c i32) (result i32)
    (local $va i32)
    (local $vb i32)
    (local $result i32)
    (local.set $va     (i32.load (local.get $a)))
    (local.set $vb     (i32.load (local.get $b)))
    (local.set $result (i32.sub  (local.get $vb) (local.get $va)))
    (i32.store (local.get $b) (local.get $result))
    (if (result i32) (i32.le_s (local.get $result) (i32.const 0))
      (then (local.get $c))
      (else (i32.const -1))
    )
  )

  ;; ── SUBLEQ runner — executes program from PC until halt ──────────────────
  ;; Halt condition: PC = -1 (branch past end) or max_steps exceeded
  ;; Returns final PC value
  (func (export "run_subleq")
        (param $pc i32) (param $max_steps i32) (result i32)
    (local $steps i32)
    (local $a i32) (local $b i32) (local $c i32)
    (local $branch i32)
    (local.set $steps (i32.const 0))
    (block $done
      (loop $loop
        ;; Check step limit
        (br_if $done (i32.ge_u (local.get $steps) (local.get $max_steps)))
        ;; Check halt
        (br_if $done (i32.lt_s (local.get $pc) (i32.const 0)))
        ;; Load A, B, C from memory at PC
        (local.set $a (i32.load (local.get $pc)))
        (local.set $b (i32.load (i32.add (local.get $pc) (i32.const 4))))
        (local.set $c (i32.load (i32.add (local.get $pc) (i32.const 8))))
        ;; Execute SUBLEQ
        (local.set $branch
          (call $subleq_internal (local.get $a) (local.get $b) (local.get $c)))
        ;; Advance PC: branch if result <= 0 else PC += 12 (3 × 4-byte ints)
        (if (i32.ge_s (local.get $branch) (i32.const 0))
          (then (local.set $pc (local.get $branch)))
          (else (local.set $pc (i32.add (local.get $pc) (i32.const 12))))
        )
        (local.set $steps (i32.add (local.get $steps) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $pc)
  )

  ;; Internal SUBLEQ (operates on 4-byte aligned addresses)
  (func $subleq_internal
        (param $a i32) (param $b i32) (param $c i32) (result i32)
    (local $va i32) (local $vb i32) (local $result i32)
    (local.set $va     (i32.load (local.get $a)))
    (local.set $vb     (i32.load (local.get $b)))
    (local.set $result (i32.sub  (local.get $vb) (local.get $va)))
    (i32.store (local.get $b) (local.get $result))
    (if (result i32) (i32.le_s (local.get $result) (i32.const 0))
      (then (local.get $c))
      (else (i32.const -1))
    )
  )

  ;; ── SEB Receipt Region ────────────────────────────────────────────────────
  ;; After execution completes, emit_receipt writes a 64-byte record
  ;; to the receipt region [0x8000..0x8040].
  ;; The host (Erlang NIF) reads this region and appends it to the WORM chain.
  ;;
  ;; Receipt layout (64 bytes = SEB payload size):
  ;;   [0:8]   event_type  (i64 LE): 0x0500 = SANDBOX_EXECUTION
  ;;   [8:16]  final_pc    (i64 LE): last program counter value
  ;;   [16:24] step_count  (i64 LE): number of SUBLEQ steps executed
  ;;   [24:32] verdict     (i64 LE): 1=approved, 0=denied
  ;;   [32:64] reserved    (zeros)

  (global $receipt_base (i32) (i32.const 0x8000))

  (func (export "emit_receipt")
        (param $final_pc i32) (param $steps i32) (param $verdict i32)
    (local $base i32)
    (local.set $base (global.get $receipt_base))
    ;; event_type = 0x0500
    (i64.store (local.get $base)
               (i64.const 0x0500))
    ;; final_pc
    (i64.store (i32.add (local.get $base) (i32.const 8))
               (i64.extend_i32_u (local.get $final_pc)))
    ;; step_count
    (i64.store (i32.add (local.get $base) (i32.const 16))
               (i64.extend_i32_u (local.get $steps)))
    ;; verdict
    (i64.store (i32.add (local.get $base) (i32.const 24))
               (i64.extend_i32_u (local.get $verdict)))
    ;; reserved zeros [32:64]
    (i64.store (i32.add (local.get $base) (i32.const 32)) (i64.const 0))
    (i64.store (i32.add (local.get $base) (i32.const 40)) (i64.const 0))
    (i64.store (i32.add (local.get $base) (i32.const 48)) (i64.const 0))
    (i64.store (i32.add (local.get $base) (i32.const 56)) (i64.const 0))
  )

  ;; ── get_receipt_ptr — returns pointer to receipt region ──────────────────
  ;; Host calls this to read the 64-byte SEB payload after execution
  (func (export "get_receipt_ptr") (result i32)
    (global.get $receipt_base)
  )
)
