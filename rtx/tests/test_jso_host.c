#include <stdio.h>
#include <string.h>
#include "jso.h"
#include "sov_test_stubs.h"

/* -----------------------------------------------------------------------
 * Helpers
 * ----------------------------------------------------------------------- */

static float fabsf_local(float x) { return x < 0.0f ? -x : x; }

/* Trace of an n×n complex matrix (sum of diagonal real parts) */
static float trace_re(const cf32_t* M, int n) {
    float t = 0.0f;
    for (int i = 0; i < n; i++) t += M[i*n+i].re;
    return t;
}

/* Frobenius distance */
static float frob_dist(const cf32_t* A, const cf32_t* B, int n) {
    float s = 0.0f;
    for (int i = 0; i < n*n; i++) {
        float dr = A[i].re - B[i].re;
        float di = A[i].im - B[i].im;
        s += dr*dr + di*di;
    }
    return s; /* return sum-of-squares; tests compare against squared tolerance */
}

/* Build 2×2 identity unitary */
static void make_identity_U(cf32_t* U, int n) {
    for (int i = 0; i < n*n; i++) U[i] = (cf32_t){0.0f, 0.0f};
    for (int i = 0; i < n; i++) U[i*n+i] = (cf32_t){1.0f, 0.0f};
}

/* Build 2×2 diagonal density: rho = diag(0.6, 0.4) */
static void make_diag_density(cf32_t* rho, int n) {
    for (int i = 0; i < n*n; i++) rho[i] = (cf32_t){0.0f, 0.0f};
    if (n >= 2) {
        rho[0*n+0] = (cf32_t){0.6f, 0.0f};
        rho[1*n+1] = (cf32_t){0.4f, 0.0f};
    } else {
        rho[0] = (cf32_t){1.0f, 0.0f};
    }
}

/* -----------------------------------------------------------------------
 * PO46: Trace preservation — tr(JSO(U,ρ)) = tr(ρ) when tr(ρ)=1
 * For U=I: JSO(I,ρ) = φ⁻¹·ρ + φ⁻²·ρ = (φ⁻¹+φ⁻²)·ρ = 1·ρ = ρ
 * So tr(S) = tr(ρ) = 1.
 * ----------------------------------------------------------------------- */
static int test_trace_preservation(void) {
    const int n = 2;
    cf32_t U[4], rho[4], S[4], scr[8];
    make_identity_U(U, n);
    make_diag_density(rho, n);

    SOV_ASSERT(sov_jso_f32(U, rho, S, scr, n) == 0);
    float tr_rho = trace_re(rho, n);
    float tr_S   = trace_re(S, n);
    SOV_ASSERT(fabsf_local(tr_S - tr_rho) < 1e-5f);
    SOV_PASS("trace_preservation");
    return 0;
}

/* -----------------------------------------------------------------------
 * PO45: Fixed-point commutativity — U=I means everything commutes;
 * verify residual ‖JSO(I,ρ)−ρ‖ = 0 (I is the fixed point of T with U=I)
 * ----------------------------------------------------------------------- */
static int test_identity_is_fixed_point(void) {
    const int n = 2;
    cf32_t U[4], rho[4], S[4], scr[8];
    make_identity_U(U, n);
    make_diag_density(rho, n);

    SOV_ASSERT(sov_jso_f32(U, rho, S, scr, n) == 0);
    /* JSO(I,ρ) = (φ⁻¹+φ⁻²)·ρ = ρ exactly */
    float dist = frob_dist(S, rho, n);
    SOV_ASSERT(dist < 1e-8f); /* sum-of-squares; float rounding only */
    SOV_PASS("identity_is_fixed_point");
    return 0;
}

/* -----------------------------------------------------------------------
 * PO47: Contraction — |φ⁻¹| < 1, verify constants sum to 1
 * ----------------------------------------------------------------------- */
static int test_phi_constants(void) {
    SOV_ASSERT(JSO_PHI_INV  > 0.0f);
    SOV_ASSERT(JSO_PHI_INV  < 1.0f);
    SOV_ASSERT(JSO_PHI_INV2 > 0.0f);
    SOV_ASSERT(JSO_PHI_INV2 < 1.0f);
    float sum = JSO_PHI_INV + JSO_PHI_INV2;
    SOV_ASSERT(fabsf_local(sum - 1.0f) < 1e-6f);
    SOV_PASS("phi_constants");
    return 0;
}

/* -----------------------------------------------------------------------
 * PO50: Determinism — same (U, ρ) → same S, twice
 * ----------------------------------------------------------------------- */
static int test_determinism(void) {
    const int n = 2;
    cf32_t U[4], rho[4], S1[4], S2[4], scr1[8], scr2[8];
    make_identity_U(U, n);
    make_diag_density(rho, n);

    SOV_ASSERT(sov_jso_f32(U, rho, S1, scr1, n) == 0);
    SOV_ASSERT(sov_jso_f32(U, rho, S2, scr2, n) == 0);
    SOV_ASSERT(frob_dist(S1, S2, n) < 1e-7f);
    SOV_PASS("determinism");
    return 0;
}

/* -----------------------------------------------------------------------
 * Residual API: sov_jso_residual_f32 returns 0 for fixed-point case
 * ----------------------------------------------------------------------- */
static int test_residual_api(void) {
    const int n = 2;
    cf32_t U[4], rho[4];
    cf32_t scr[3*4]; /* n² (S_out) + 2n² (jso internal) = 3n² */
    make_identity_U(U, n);
    make_diag_density(rho, n);
    float r = sov_jso_residual_f32(U, rho, scr, n);
    SOV_ASSERT(r >= 0.0f);
    SOV_ASSERT(r < 1e-12f); /* returns Frobenius²; float rounding only */
    SOV_PASS("residual_api");
    return 0;
}

/* -----------------------------------------------------------------------
 * Bad-args guards
 * ----------------------------------------------------------------------- */
static int test_null_args_rejected(void) {
    cf32_t U[4], rho[4], S[4], scr[8];
    make_identity_U(U, 2);
    make_diag_density(rho, 2);
    SOV_ASSERT(sov_jso_f32(NULL, rho, S, scr, 2) == -1);
    SOV_ASSERT(sov_jso_f32(U, NULL, S, scr, 2) == -1);
    SOV_ASSERT(sov_jso_f32(U, rho, NULL, scr, 2) == -1);
    SOV_ASSERT(sov_jso_f32(U, rho, S, scr, 0) == -1);
    SOV_PASS("null_args_rejected");
    return 0;
}

/* -----------------------------------------------------------------------
 * Density project: trace should be 1 after projection
 * ----------------------------------------------------------------------- */
static int test_density_project_trace(void) {
    const int n = 2, k = 2;
    cf32_t X[2] = {{1.0f,0.0f},{1.0f,0.0f}};
    cf32_t W[4] = {{1.0f,0.0f},{0.0f,0.0f},{0.0f,0.0f},{1.0f,0.0f}};
    cf32_t rho[4], scr[4];
    SOV_ASSERT(sov_density_project_f32(X, W, rho, scr, n, k) == 0);
    float tr = trace_re(rho, n);
    SOV_ASSERT(fabsf_local(tr - 1.0f) < 1e-5f);
    SOV_PASS("density_project_trace");
    return 0;
}

/* -----------------------------------------------------------------------
 * Unitary project: columns should be orthonormal (UᴴU ≈ I)
 * ----------------------------------------------------------------------- */
static int test_unitary_project_orthonormal(void) {
    const int n = 2, k = 2;
    cf32_t X[2] = {{1.5f,0.0f},{0.5f,0.0f}};
    cf32_t W[4] = {{1.0f,0.0f},{0.0f,0.0f},{0.0f,0.0f},{1.0f,0.0f}};
    cf32_t U[4], scr[4 + 16]; /* n + n² scratch (n=2: 4+4=8 entries) */
    SOV_ASSERT(sov_unitary_project_f32(X, W, U, scr, n, k) == 0);
    /* Check UᴴU = I: (UᴴU)[i,j] = Σ_k conj(U[k,i]) * U[k,j] */
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < n; j++) {
            cf32_t acc = {0.0f, 0.0f};
            for (int p = 0; p < n; p++) {
                cf32_t uh = (cf32_t){ U[p*n+i].re, -U[p*n+i].im };
                acc.re += uh.re*U[p*n+j].re - uh.im*U[p*n+j].im;
                acc.im += uh.re*U[p*n+j].im + uh.im*U[p*n+j].re;
            }
            float expected_re = (i == j) ? 1.0f : 0.0f;
            SOV_ASSERT(fabsf_local(acc.re - expected_re) < 1e-3f);
            SOV_ASSERT(fabsf_local(acc.im) < 1e-3f);
        }
    }
    SOV_PASS("unitary_project_orthonormal");
    return 0;
}

int main(void) {
    int fail = 0;
    fail |= test_phi_constants();
    fail |= test_trace_preservation();
    fail |= test_identity_is_fixed_point();
    fail |= test_determinism();
    fail |= test_residual_api();
    fail |= test_null_args_rejected();
    fail |= test_density_project_trace();
    fail |= test_unitary_project_orthonormal();
    if (!fail) printf("ALL PASS\n");
    return fail;
}
