#ifndef BH_BRIDGE_H
#define BH_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <float.h>
#ifdef __cplusplus
extern "C" {
#endif

double schwarzschild_kappa(double M);
double schwarzschild_entropy(double M);
bool   schwarzschild_first_law(double M, double dM);
double kerr_kappa(double M, double a);
double kerr_entropy(double M, double a);
double kerr_angular_velocity(double M, double a);
double lqg_entropy_correction(double A, double alpha, double beta);
double string_entropy_correction(double A, double gamma);

static inline double machine_eps(double x) {
    double e = DBL_EPSILON * fabs(x);
    return e > DBL_MIN ? e : DBL_MIN;
}

static inline bool bh_verify_schwarzschild(double M, double dM,
                   double *kappa_out, double *entropy_out, bool *fl_out) {
    if (M <= 0.0) return false;
    double k = schwarzschild_kappa(M);
    double s = schwarzschild_entropy(M);
    bool   f = schwarzschild_first_law(M, dM);
    if (fabs(k - 1.0/(4.0*M))          > machine_eps(1.0/(4.0*M)))          return false;
    if (fabs(s - 4.0*M_PI*M*M)         > machine_eps(4.0*M_PI*M*M))         return false;
    if (kappa_out)   *kappa_out   = k;
    if (entropy_out) *entropy_out = s;
    if (fl_out)      *fl_out      = f;
    return true;
}

static inline bool bh_verify_kerr(double M, double a,
                   double *kappa_out, double *entropy_out, double *omega_out) {
    if (M <= 0.0 || M*M < a*a) return false;
    double r = M + sqrt(M*M - a*a);
    double k = kerr_kappa(M, a);
    double s = kerr_entropy(M, a);
    double o = kerr_angular_velocity(M, a);
    double ke = (r - M)/(2.0*M*r);
    double se = 2.0*M_PI*(r*r + a*a);
    double oe = a/(2.0*M*r);
    if (fabs(k - ke) > machine_eps(ke)) return false;
    if (fabs(s - se) > machine_eps(se)) return false;
    if (fabs(o - oe) > machine_eps(oe)) return false;
    if (kappa_out)   *kappa_out   = k;
    if (entropy_out) *entropy_out = s;
    if (omega_out)   *omega_out   = o;
    return true;
}

static inline bool bh_verify_lqg(double A, double alpha, double beta, double *S) {
    if (A <= 0.0) return false;
    double s = lqg_entropy_correction(A, alpha, beta);
    double e = A/4.0 + alpha*log(A) + beta;
    if (fabs(s - e) > machine_eps(e)) return false;
    if (S) *S = s;
    return true;
}

static inline bool bh_verify_string(double A, double gamma, double *S) {
    if (A <= 0.0) return false;
    double s = string_entropy_correction(A, gamma);
    double e = A/4.0 + gamma*sqrt(A);
    if (fabs(s - e) > machine_eps(e)) return false;
    if (S) *S = s;
    return true;
}

#ifdef __cplusplus
}
#endif
#endif
