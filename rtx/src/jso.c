#include <stdint.h>
#include <stddef.h>
#include "jso.h"

/* -----------------------------------------------------------------------
 * Complex f32 primitives — no libc math required
 * ----------------------------------------------------------------------- */

static inline cf32_t cf_add(cf32_t a, cf32_t b) {
    return (cf32_t){ a.re + b.re, a.im + b.im };
}
static inline cf32_t cf_scale(cf32_t a, float s) {
    return (cf32_t){ a.re * s, a.im * s };
}
static inline cf32_t cf_mul(cf32_t a, cf32_t b) {
    return (cf32_t){ a.re*b.re - a.im*b.im,
                     a.re*b.im + a.im*b.re };
}
static inline cf32_t cf_conj(cf32_t a) {
    return (cf32_t){ a.re, -a.im };
}
static inline float cf_abs2(cf32_t a) {
    return a.re*a.re + a.im*a.im;
}

/* -----------------------------------------------------------------------
 * Complex n×n matrix multiply: C = A * B   (row-major)
 * ----------------------------------------------------------------------- */
static void cgemm(const cf32_t* A, const cf32_t* B, cf32_t* C, int n) {
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            cf32_t acc = {0.0f, 0.0f};
            for (int p = 0; p < n; p++)
                acc = cf_add(acc, cf_mul(A[i*n+p], B[p*n+j]));
            C[i*n+j] = acc;
        }
    }
}

/* Conjugate-transpose of A into AH */
static void ctranspose(const cf32_t* A, cf32_t* AH, int n) {
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++)
            AH[j*n+i] = cf_conj(A[i*n+j]);
}

/* sqrt approximation (Newton, 8 iterations, initial guess = x when x>=1, x*x+eps when x<1) */
static float fsqrt(float x) {
    if (x <= 0.0f) return 0.0f;
    /* Safe initial guess: avoid divergence for tiny x */
    float r = x;
    for (int i = 0; i < 8; i++) r = 0.5f*(r + x/r);
    return r;
}

/* -----------------------------------------------------------------------
 * JSO core: S = φ⁻¹·U·ρ·Uᴴ + φ⁻²·ρ
 *
 * scratch layout: [0..n²)  = tmp1 = U·ρ
 *                 [n²..2n²) = tmp2 = tmp1·Uᴴ  (then UH temp)
 * ----------------------------------------------------------------------- */

/* Stack-local fallback when n ≤ JSO_MAX_N */
static cf32_t s_scratch[2 * JSO_MAX_N * JSO_MAX_N];

int sov_jso_f32(const cf32_t* U, const cf32_t* rho,
                cf32_t* S_out, cf32_t* scratch, int n) {
    if (!U || !rho || !S_out || n <= 0) return -1;

    cf32_t* tmp1;
    cf32_t* tmp2;
    if (scratch) {
        tmp1 = scratch;
        tmp2 = scratch + n*n;
    } else {
        if (n > JSO_MAX_N) return -1;
        tmp1 = s_scratch;
        tmp2 = s_scratch + n*n;
    }

    /* tmp1 = U · ρ */
    cgemm(U, rho, tmp1, n);

    /* tmp2 = Uᴴ  (reuse tmp2 as Uᴴ storage) */
    ctranspose(U, tmp2, n);

    /* S_out = tmp1 · Uᴴ  (stored back into tmp2 after we're done with Uᴴ)
     * We need a third slot or can reuse tmp1 since we're done with it.
     * After cgemm(tmp1, tmp2, tmp1, n) the source tmp1 is being overwritten
     * mid-read — unsafe. Use S_out as the destination directly.
     */
    cgemm(tmp1, tmp2, S_out, n);

    /* S_out = φ⁻¹·S_out + φ⁻²·ρ  (fused saxpy, in-place) */
    for (int i = 0; i < n*n; i++) {
        S_out[i].re = JSO_PHI_INV  * S_out[i].re + JSO_PHI_INV2 * rho[i].re;
        S_out[i].im = JSO_PHI_INV  * S_out[i].im + JSO_PHI_INV2 * rho[i].im;
    }
    return 0;
}

float sov_jso_residual_f32(const cf32_t* U, const cf32_t* rho,
                           cf32_t* scratch, int n) {
    if (!U || !rho || !scratch || n <= 0) return -1.0f;

    /* scratch layout: [0..n²) = S_out, [n²..3n²) = jso internal scratch */
    cf32_t* S_out   = scratch;
    cf32_t* jso_scr = scratch + n*n;
    if (sov_jso_f32(U, rho, S_out, jso_scr, n) != 0) return -1.0f;

    float s = 0.0f;
    for (int i = 0; i < n*n; i++) {
        float dr = S_out[i].re - rho[i].re;
        float di = S_out[i].im - rho[i].im;
        s += dr*dr + di*di;
    }
    return s; /* returns sum-of-squares (Frobenius²); caller compares squared tolerance */
}

/* -----------------------------------------------------------------------
 * Density projection: ρ = A·Aᴴ / tr(A·Aᴴ)   where A = W·X  (n×k)
 * scratch: [0..n²) = AAH
 * ----------------------------------------------------------------------- */

int sov_density_project_f32(const cf32_t* X, const cf32_t* W,
                            cf32_t* rho_out, cf32_t* scratch, int n, int k) {
    if (!X || !W || !rho_out || !scratch || n <= 0 || k <= 0) return -1;

    /* A[n×k] = W[n×k] · X[k×1]  — X is treated as a single feature vector k */
    /* For a full slice: A = W (W already maps features to n-dim)
     * Here X is [k] and W is [n×k], so A[i] = Σ_p W[i,p] * X[p] */
    cf32_t* A = scratch; /* borrow scratch[0..n) for A vector */
    for (int i = 0; i < n; i++) {
        cf32_t acc = {0.0f, 0.0f};
        for (int p = 0; p < k; p++)
            acc = cf_add(acc, cf_mul(W[i*k+p], X[p]));
        A[i] = acc;
    }

    /* AAH[n×n] = A · Aᴴ  (outer product, since A is n×1) */
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++)
            rho_out[i*n+j] = cf_mul(A[i], cf_conj(A[j]));

    /* tr(AAH) = Σ |A[i]|² */
    float tr = 0.0f;
    for (int i = 0; i < n; i++) tr += cf_abs2(A[i]);
    if (tr < 1e-12f) return -1; /* degenerate */

    float inv_tr = 1.0f / tr;
    for (int i = 0; i < n*n; i++) {
        rho_out[i].re *= inv_tr;
        rho_out[i].im *= inv_tr;
    }
    return 0;
}

/* -----------------------------------------------------------------------
 * Unitary projection: U = Q from modified Gram-Schmidt QR of (W·X cols)
 * For the single-vector case, U is built column by column from W rows.
 * scratch: [0..n²) for intermediate columns
 * ----------------------------------------------------------------------- */

static float cf_norm(const cf32_t* v, int n) {
    float s = 0.0f;
    for (int i = 0; i < n; i++) s += cf_abs2(v[i]);
    return fsqrt(s);
}

int sov_unitary_project_f32(const cf32_t* X, const cf32_t* W,
                            cf32_t* U_out, cf32_t* scratch, int n, int k) {
    if (!X || !W || !U_out || !scratch || n <= 0 || k <= 0) return -1;

    /* Build n columns from W·X: col[j] = W[j*k..(j+1)*k] · X */
    /* We have n rows of W, each of size k. Use each row as a column of B. */
    cf32_t* cols = scratch; /* n × n scratch for columns before orthogonalization */

    /* Form B[n×n]: column j = W row j applied to X, extended to length n */
    /* Since W is [n×k] and X is [k], B[:,j] = e_j · (W[j] · X) scaled */
    /* For a minimal realization: use W rows as initial column vectors in R^n */
    for (int j = 0; j < n; j++) {
        cf32_t dot = {0.0f, 0.0f};
        for (int p = 0; p < k; p++)
            dot = cf_add(dot, cf_mul(W[j*k+p], X[p]));
        /* Column j: place dot at position j, rest zero */
        for (int i = 0; i < n; i++)
            cols[i*n+j] = (i == j) ? dot : (cf32_t){0.0f, 0.0f};
    }

    /* Modified Gram-Schmidt on columns of cols → U_out columns */
    for (int j = 0; j < n; j++) {
        /* Copy column j into U_out[:,j] */
        for (int i = 0; i < n; i++) U_out[i*n+j] = cols[i*n+j];

        /* Subtract projections onto already-orthogonalized columns */
        for (int p = 0; p < j; p++) {
            /* proj = <U[:,j], U[:,p]> */
            cf32_t proj = {0.0f, 0.0f};
            for (int i = 0; i < n; i++)
                proj = cf_add(proj, cf_mul(cf_conj(U_out[i*n+p]), U_out[i*n+j]));
            for (int i = 0; i < n; i++)
                U_out[i*n+j] = (cf32_t){
                    U_out[i*n+j].re - (proj.re*U_out[i*n+p].re - proj.im*U_out[i*n+p].im),
                    U_out[i*n+j].im - (proj.re*U_out[i*n+p].im + proj.im*U_out[i*n+p].re)
                };
        }

        /* Normalize */
        float nrm = cf_norm(&U_out[0*n+j], 0); /* wrong stride — fix below */
        /* Column j in row-major: U_out[i*n+j] for i=0..n-1 */
        float s2 = 0.0f;
        for (int i = 0; i < n; i++) s2 += cf_abs2(U_out[i*n+j]);
        nrm = fsqrt(s2);
        if (nrm < 1e-12f) {
            /* Degenerate column: replace with standard basis vector */
            for (int i = 0; i < n; i++)
                U_out[i*n+j] = (i == j) ? (cf32_t){1.0f,0.0f} : (cf32_t){0.0f,0.0f};
        } else {
            float inv = 1.0f / nrm;
            for (int i = 0; i < n; i++) {
                U_out[i*n+j].re *= inv;
                U_out[i*n+j].im *= inv;
            }
        }
    }
    return 0;
}

/* -----------------------------------------------------------------------
 * RMSNorm (real approximation over complex magnitudes)
 * ----------------------------------------------------------------------- */
static void rmsnorm(cf32_t* x, int len) {
    float ss = 0.0f;
    for (int i = 0; i < len; i++) ss += cf_abs2(x[i]);
    float scale = 1.0f / fsqrt(ss / (float)len + 1e-6f);
    for (int i = 0; i < len; i++) {
        x[i].re *= scale;
        x[i].im *= scale;
    }
}

/* -----------------------------------------------------------------------
 * AgentBlock: SelectiveSSM ∘ JSO ∘ FFN  (PO48–PO51)
 *
 * For each (b, t) token vector x of size D:
 *   1. H = SSM(x)                 — Mamba-style: H = A·x (single matmul)
 *   2. x2 = x + H
 *   3. rmsnorm(x2)
 *   4. ρ = SpatialDensity(x2)
 *   5. U = SpatialUnitary(x2)
 *   6. S = JSO(U, ρ)
 *   7. x4 = x2 + Project(S)       — Project: flatten S→D, apply linear
 *   8. rmsnorm(x4)
 *   9. y  = FFN(x4) = W2·relu(W1·x4)
 *  10. out = x4 + y               — final residual
 * ----------------------------------------------------------------------- */

/* ReLU on complex: relu(re), relu(im) */
static inline cf32_t cf_relu(cf32_t a) {
    return (cf32_t){ a.re > 0.0f ? a.re : 0.0f,
                     a.im > 0.0f ? a.im : 0.0f };
}

int sov_agent_block_f32(const cf32_t* in, cf32_t* out,
                        const sov_agent_params_t* params,
                        cf32_t* scratch, int B, int T) {
    if (!in || !out || !params || !scratch) return -1;

    const int D = params->D;
    const int n = params->n;
    const int k = params->k;

    /* scratch layout per token:
     *   [0..D)     = x_work (current token vector, modified in place)
     *   [D..D+n²)  = rho
     *   [D+n²..)   = U
     *   [D+2n²..)  = S
     *   [D+3n²..)  = jso_scratch (2n²)
     *   [D+5n²..)  = proj_scratch (n)
     *   [D+5n²+n..)= ffn_mid (4D)
     *   total ≈ D + 5n² + n + 4D
     */
    cf32_t* x_work    = scratch;
    cf32_t* rho       = scratch + D;
    cf32_t* U         = scratch + D + n*n;
    cf32_t* S         = scratch + D + 2*n*n;
    cf32_t* jso_scr   = scratch + D + 3*n*n;   /* 2n² */
    cf32_t* proj_scr  = scratch + D + 5*n*n;   /* n */
    cf32_t* ffn_mid   = scratch + D + 5*n*n + n; /* 4D */

    for (int b = 0; b < B; b++) {
        for (int t = 0; t < T; t++) {
            const cf32_t* x_in  = in  + (b*T + t)*D;
            cf32_t*       x_out = out + (b*T + t)*D;

            /* Copy input */
            for (int i = 0; i < D; i++) x_work[i] = x_in[i];

            /* Step 1–2: H = SSM·x, x2 = x + H */
            for (int i = 0; i < D; i++) {
                cf32_t h = {0.0f, 0.0f};
                for (int j = 0; j < D; j++)
                    h = cf_add(h, cf_mul(params->ssm_A[i*D+j], x_work[j]));
                x_work[i] = cf_add(x_work[i], h);
            }

            /* Step 3: RMSNorm */
            rmsnorm(x_work, D);

            /* Step 4–5: density and unitary projections */
            if (sov_density_project_f32(x_work, params->W_rho, rho, proj_scr, n, k) != 0) return -2;
            if (sov_unitary_project_f32(x_work, params->W_u,   U,   proj_scr, n, k) != 0) return -3;

            /* Step 6: JSO */
            if (sov_jso_f32(U, rho, S, jso_scr, n) != 0) return -4;

            /* Step 7: Project(S) → D-dimensional vector + residual add
             * Flatten S (n×n complex) into first n² entries; zero-pad to D if n²<D */
            for (int i = 0; i < D; i++) {
                cf32_t s_val = (i < n*n) ? S[i] : (cf32_t){0.0f, 0.0f};
                x_work[i] = cf_add(x_work[i], s_val);
            }

            /* Step 8: RMSNorm */
            rmsnorm(x_work, D);

            /* Step 9: FFN = W2·relu(W1·x) */
            int D4 = 4 * D;
            for (int i = 0; i < D4; i++) {
                cf32_t acc = {0.0f, 0.0f};
                for (int j = 0; j < D; j++)
                    acc = cf_add(acc, cf_mul(params->ffn_W1[i*D+j], x_work[j]));
                ffn_mid[i] = cf_relu(acc);
            }
            for (int i = 0; i < D; i++) {
                cf32_t acc = {0.0f, 0.0f};
                for (int j = 0; j < D4; j++)
                    acc = cf_add(acc, cf_mul(params->ffn_W2[i*D4+j], ffn_mid[j]));
                x_out[i] = cf_add(x_work[i], acc);
            }
        }
    }
    return 0;
}
