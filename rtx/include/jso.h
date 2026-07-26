#pragma once
/*
 * JSO — Jordan Spectral Operator
 * T(ρ) = φ⁻¹ · U·ρ·Uᴴ + φ⁻² · ρ
 *
 * Authority: JordanMatrixProof.lean (PAR-011, PAR-013)
 *   Fixed-point:     T(ρ*) = ρ*  ⟹  [U, ρ*] = 0
 *   Trace-preserve:  tr(ρ) = 1   ⟹  tr(T(ρ)) = 1
 *   Contraction:     φ⁻¹ < 1     ⟹  Banach rate
 *
 * Hardware lowering (Layer-22 path):
 *   tmp1 = GEMM(U, ρ)            complex n×n
 *   tmp2 = GEMM(tmp1, Uᴴ)       complex n×n
 *   S    = φ⁻¹·tmp2 + φ⁻²·ρ    fused saxpy
 *
 * Compiler contract (PO45–PO47):
 *   Input  U : Unitary(n)   — UᴴU = I
 *   Input  ρ : Density(n)   — ρᴴ = ρ, tr(ρ) = 1
 *   Output S : Density(n)   — Sᴴ = S, tr(S) = 1
 *   Compiler does NOT verify unitarity at runtime.
 *   Runtime only checks the fixed-point residual ‖S − ρ‖ when asked.
 */

#include <stdint.h>
#include <stddef.h>

/* φ⁻¹ = (√5 − 1)/2 ≈ 0.6180339887  (compile-time constant) */
#define JSO_PHI_INV  0.6180339887498949f
/* φ⁻² = 1 − φ⁻¹  ≈ 0.3819660113    (trace-preservation identity) */
#define JSO_PHI_INV2 0.3819660112501051f

/* Maximum static matrix dimension for stack-local scratch.
 * Larger matrices must supply external scratch. */
#define JSO_MAX_N 64

typedef struct {
    float re;
    float im;
} cf32_t;

/*
 * sov_jso_f32 — Jordan Spectral Operator over complex f32 matrices.
 *
 * U     : [n×n] unitary input   (row-major, complex interleaved)
 * rho   : [n×n] density input   (row-major, complex interleaved)
 * S_out : [n×n] density output  (row-major, complex interleaved)
 * scratch: caller-supplied [2×n×n] cf32 workspace (or NULL if n ≤ JSO_MAX_N)
 *
 * Returns 0 on success, -1 on bad arguments.
 */
int sov_jso_f32(const cf32_t* U, const cf32_t* rho,
                cf32_t* S_out, cf32_t* scratch, int n);

/*
 * sov_jso_residual_f32 — compute ‖JSO(U,ρ) − ρ‖₂ (Frobenius).
 * Used by the runtime fixed-point check (theorem vs runtime boundary).
 * Returns residual, or -1.0f on error.
 */
float sov_jso_residual_f32(const cf32_t* U, const cf32_t* rho,
                           cf32_t* scratch, int n);

/*
 * sov_density_project_f32 — X → ρ  (A·Aᴴ / tr(A·Aᴴ))
 * X  : [n×k] real or complex feature slice
 * W  : [n×k] learned weight matrix
 * rho_out : [n×n] output density
 */
int sov_density_project_f32(const cf32_t* X, const cf32_t* W,
                            cf32_t* rho_out, cf32_t* scratch, int n, int k);

/*
 * sov_unitary_project_f32 — X → U  (thin QR of W·X, U = Q)
 * Deterministic: modified Gram-Schmidt, fixed column order.
 */
int sov_unitary_project_f32(const cf32_t* X, const cf32_t* W,
                            cf32_t* U_out, cf32_t* scratch, int n, int k);

/*
 * sov_agent_block_f32 — full SelectiveSSM ∘ JSO ∘ FFN block (PO48–PO51)
 *
 * in     : [B×T×D] input tensor  (B=batch, T=seq, D=model_dim)
 * out    : [B×T×D] output tensor (same shape — PO48)
 * params : opaque parameter block (W_ρ, W_U, SSM state, FFN weights)
 * scratch: caller-supplied workspace
 *
 * Shape invariant: output shape == input shape  (PO48)
 * Memory:          no aliasing in/out; static scratch bounds (PO49)
 * Determinism:     same in+params → same out  (PO50)
 * Invariant:       SSM state never violates JSO preconditions (PO51)
 */
typedef struct {
    cf32_t* W_rho;   /* [n×k] density projection weights  */
    cf32_t* W_u;     /* [n×k] unitary projection weights  */
    cf32_t* ssm_A;   /* [D×D] SSM transition matrix       */
    cf32_t* ffn_W1;  /* [D×4D] FFN first layer            */
    cf32_t* ffn_W2;  /* [4D×D] FFN second layer           */
    int n;           /* JSO matrix dimension               */
    int k;           /* feature slice width                */
    int D;           /* model dimension                    */
} sov_agent_params_t;

int sov_agent_block_f32(const cf32_t* in, cf32_t* out,
                        const sov_agent_params_t* params,
                        cf32_t* scratch, int B, int T);
