/*
 * quantum_api.h — Unified C API for Quantum Entropy Verification Stack
 * Exposes: Fortran (bh_numerics), OCaml (k3_entropy), Runtime (quantum_entropy.mjs)
 * License: FSL-1.1-Apache-2.0
 * Copyright (c) 2026 SnapKitty Collective
 */

#ifndef QUANTUM_API_H
#define QUANTUM_API_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ═══════════════════════════════════════════════════════════════════════
   BLACK HOLE THERMODYNAMICS (Fortran bh_numerics.f90)
   ═══════════════════════════════════════════════════════════════════════ */

/** Schwarzschild surface gravity: κ = 1/(4M) */
double schwarzschild_kappa(double M);

/** Schwarzschild entropy: S = 4πM² */
double schwarzschild_entropy(double M);

/** Schwarzschild first law: dM = (κ/2π) dS */
bool schwarzschild_first_law(double M, double dM);

/** Kerr surface gravity: κ = (r₊ - M) / (2Mr₊) */
double kerr_kappa(double M, double a);

/** Kerr entropy: S = 2π(r₊² + a²) */
double kerr_entropy(double M, double a);

/** Kerr angular velocity: Ω = a / (2Mr₊) */
double kerr_angular_velocity(double M, double a);

/** Wald entropy for general Lagrangian */
void wald_entropy_general(
    double g_tt, double g_rr, double g_thth, double g_phph,
    const double* L_params, int64_t n_params,
    double* S, double* kappa, double* Omega
);

/** LQG entropy correction: S = A/4 + α ln(A) + β */
double lqg_entropy_correction(double A, double alpha, double beta);

/** String theory entropy correction: S = A/4 + γ√A */
double string_entropy_correction(double A, double gamma);

/* ═══════════════════════════════════════════════════════════════════════
   K3 SURFACE ENTROPY (HOL Light k3_entropy.ml → OCaml extraction)
   ═══════════════════════════════════════════════════════════════════════ */

/** K3 entropy violation: always returns true (proven in HOL Light) */
bool k3_entropy_violates_bound(void);

/** K3 Hodge numbers sum: 24 */
int k3_hodge_numbers_sum(void);

/** K3 Shannon entropy value: 0.831... nats */
double k3_entropy_value(void);

/* ═══════════════════════════════════════════════════════════════════════
   ENTROPY VALIDATION (Coq EntropyValidation.v → extraction)
   ═══════════════════════════════════════════════════════════════════════ */

/** Validation result structure */
typedef struct {
    uint64_t total_bits;
    uint64_t ones_count;
    uint64_t zeros_count;
    double ones_ratio;
    bool passed;
} validation_result_t;

/** Validate entropy distribution (±10% NISQ tolerance) */
validation_result_t entropy_validate_distribution(
    const uint8_t* bytes,
    size_t n_bytes,
    double tolerance
);

/** Check if all-zeros pattern fails validation */
bool entropy_all_zeros_fails(size_t n, double tolerance);

/** Check if all-ones pattern fails validation */
bool entropy_all_ones_fails(size_t n, double tolerance);

/* ═══════════════════════════════════════════════════════════════════════
   BORN RULE COLLAPSE (Lean4 BornRuleCollapse.lean → extraction)
   ═══════════════════════════════════════════════════════════════════════ */

/** Thermal window bounds */
typedef struct {
    double min;
    double max;
} thermal_window_t;

/** Collapse result (Vacuum or Collapsed) */
typedef struct {
    bool is_vacuum;
    double collapsed_value;
    uint32_t branch_count;
    uint32_t total_branches;
} collapse_result_t;

/** Born-rule collapse with thermal window filtering */
collapse_result_t born_rule_collapse(
    const uint16_t* samples,
    size_t n_samples,
    thermal_window_t window
);

/** Check if collapsed value is within thermal window (T2) */
bool born_collapse_valid_range(
    collapse_result_t result,
    thermal_window_t window
);

/** Check if weights sum to 1 (T4) */
bool born_weights_sum_to_one(
    const double* weights,
    size_t n_weights
);

/* ═══════════════════════════════════════════════════════════════════════
   INTEGRATION HELPERS
   ═══════════════════════════════════════════════════════════════════════ */

/** Initialize quantum entropy stack (loads all verification artifacts) */
bool quantum_api_init(void);

/** Clean up resources */
void quantum_api_cleanup(void);

/** Get verification status string */
const char* quantum_api_version(void);

/** Run self-tests (cross-checks all systems) */
bool quantum_api_self_test(void);

#ifdef __cplusplus
}
#endif

#endif /* QUANTUM_API_H */
