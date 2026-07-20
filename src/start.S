/* ════════════════════════════════════════════════════════════════
 * start.S — SOVEREIGN ENTRY POINT
 * Zero runtime. No libc. No crt0. Pure metal.
 * Targets: ARM64 (primary) | x86_64 (secondary)
 * ════════════════════════════════════════════════════════════════ */

/* ── ARM64 ────────────────────────────────────────────────────── */
#if defined(__aarch64__)

.section .text
.global _start
.type   _start, %function

_start:
    /* Stack alignment: AArch64 ABI requires 16-byte alignment */
    mov     x29, sp
    bic     sp,  x29, #0xF

    /* Call Fortran entry: sov_apl_evolve_sequence
     * Caller sets up X0..X7 with H, rho, n, steps, dt, sk, pk, receipts
     * before jumping here (Lean FFI trampoline handles this) */
    bl      sov_apl_evolve_sequence

    /* Sovereign halt — we own the metal, no exit syscall */
    hlt     #0

.L_fault:
    /* Write fault code to known address, halt */
    ldr     x1, =0x0000DEAD0000
    str     x0, [x1]
    hlt     #1

.size _start, . - _start


/* ── x86_64 ───────────────────────────────────────────────────── */
#elif defined(__x86_64__)

.section .text
.global _start
.type   _start, @function

_start:
    /* Stack alignment: System V AMD64 ABI requires 16-byte at call */
    andq    $-16, %rsp

    /* Call Fortran entry */
    call    sov_apl_evolve_sequence

    /* Sovereign halt */
    hlt

.L_fault:
    movq    $0x0000DEAD0000, %rsi
    movq    %rax, (%rsi)
    hlt

.size _start, . - _start


/* ── NVIDIA PTX (stub — real entry via nvcc driver) ───────────── */
#elif defined(__nvptx__)
/* PTX does not use _start; kernel launched via cuLaunchKernel.
 * Entry point is sov_fused_uru declared in sov_pipeline.mlir.
 * This file intentionally empty for PTX target. */
#endif


/* ── .note.sov section: Blake3 hash + Ed25519 sig baked at build ─
 * Populated by build_monster.sh after linking.
 * Format: [magic:8]["BIFROST\0"] [hash:32] [sig:64]
 * ─────────────────────────────────────────────────────────────── */
.section .note.sov, "a", %note
.align 4
.long   8                    /* namesz */
.long   96                   /* descsz: 32 + 64 */
.long   1                    /* type: NT_SOV_BIFROST */
.ascii  "BIFROST\0"          /* name */
.fill   96, 1, 0             /* desc: filled by build_monster.sh */
