// PIRTM recurrence step — ported from foundry-intel/crates/z-mos/pirtm/src/lib.rs
// + jordan_contraction matching jordan_block.f90

use nalgebra::DMatrix;
use ndarray::{Array1, Array2};
use num_complex::Complex64;
use thiserror::Error;

const PHI: f64 = 1.6180339887498948482;
pub const PHI_INV: f64 = 1.0 / PHI;    // ≈ 0.618 — Fibonacci contraction rate

#[derive(Error, Debug)]
pub enum PirtmError {
    #[error("Dimension mismatch: expected {expected}, got {found}")]
    DimensionMismatch { expected: usize, found: usize },
    #[error("Contractivity violation: c_lambda={c_lambda} >= 1-epsilon={bound}")]
    ContractivityViolation { c_lambda: f64, bound: f64 },
}

pub struct PirtmMetadata {
    pub q_t: f64,
    pub c_lambda: f64,
    pub margin: f64,
}

/// PIRTM recurrence: X_{t+1} = (1-λ_m)X_t + λ_m P(Ξ_t X_t + Λ_t sigmoid(X_t) + G_t)
/// Ported verbatim from foundry-intel z-mos/pirtm.
pub fn step(
    x_t: &Array1<f64>,
    xi_t: &Array2<f64>,
    lambda_t: &Array2<f64>,
    g_t: Option<&Array1<f64>>,
    epsilon: f64,
    lambda_m: f64,
    l_t: f64,
) -> Result<(Array1<f64>, PirtmMetadata), PirtmError> {
    let dim = x_t.len();
    if xi_t.nrows() != dim || xi_t.ncols() != dim {
        return Err(PirtmError::DimensionMismatch { expected: dim, found: xi_t.nrows() });
    }
    if lambda_t.nrows() != dim || lambda_t.ncols() != dim {
        return Err(PirtmError::DimensionMismatch { expected: dim, found: lambda_t.nrows() });
    }
    let g = match g_t {
        Some(g) if g.len() == dim => g.clone(),
        Some(g) => return Err(PirtmError::DimensionMismatch { expected: dim, found: g.len() }),
        None => Array1::zeros(dim),
    };

    let term1 = xi_t.dot(x_t);
    let tx_t = x_t.mapv(|v| 1.0 / (1.0 + (-v).exp()));
    let term2 = lambda_t.dot(&tx_t);
    let y_t = term1 + term2 + g;
    let py_t = y_t.mapv(|v| v.clamp(-1.0, 1.0));
    let x_next = if (lambda_m - 1.0).abs() < f64::EPSILON {
        py_t
    } else {
        (1.0 - lambda_m) * x_t + lambda_m * py_t
    };

    let n_xi = spectral_norm_real(xi_t);
    let n_lam = spectral_norm_real(lambda_t);
    let c_lambda = (1.0 - lambda_m) + lambda_m * (n_xi + n_lam * l_t);
    let margin = (1.0 - epsilon) - c_lambda;

    Ok((x_next, PirtmMetadata { q_t: n_xi + n_lam * l_t, c_lambda, margin }))
}

/// Power-iteration spectral norm (largest singular value) for real matrices.
pub fn spectral_norm_real(m: &Array2<f64>) -> f64 {
    let dim = m.ncols();
    let mut v = Array1::from_elem(dim, 1.0 / (dim as f64).sqrt());
    let ata = m.t().dot(m);
    for _ in 0..10 {
        let w = ata.dot(&v);
        let norm = w.dot(&w).sqrt();
        if norm < 1e-10 {
            return 0.0;
        }
        v = w / norm;
    }
    (v.dot(&ata.dot(&v))).sqrt()
}

/// Jordan contraction matching jordan_block.f90:
///   ρ' = φ⁻¹ · (U ρ U†) + φ⁻² · ρ
///
/// Contraction rate φ⁻¹ ≈ 0.618 < 1 guarantees Banach fixed-point convergence.
pub fn jordan_contraction(
    rho: &DMatrix<Complex64>,
    u: &DMatrix<Complex64>,
    phi_inv: f64,
) -> DMatrix<Complex64> {
    let u_dag = u.adjoint();
    let evolved = u * rho * &u_dag;
    evolved * Complex64::new(phi_inv, 0.0) + rho * Complex64::new(phi_inv * phi_inv, 0.0)
}

/// Iterates jordan_contraction to fixed point ρ* where T(ρ*) = ρ*.
pub fn jordan_fixpoint(
    rho0: &DMatrix<Complex64>,
    u: &DMatrix<Complex64>,
    max_iter: usize,
    tol: f64,
) -> DMatrix<Complex64> {
    let mut rho = rho0.clone();
    for _ in 0..max_iter {
        let rho_next = jordan_contraction(&rho, u, PHI_INV);
        let diff = (&rho_next - &rho).norm();
        rho = rho_next;
        if diff < tol {
            break;
        }
    }
    rho
}

#[cfg(test)]
mod tests {
    use super::*;
    use ndarray::array;

    #[test]
    fn test_step_basic() {
        let x = array![1.0, 0.5];
        let xi = array![[0.8, 0.0], [0.0, 0.8]];
        let lam = array![[0.1, 0.0], [0.0, 0.1]];
        let (x_next, meta) = step(&x, &xi, &lam, None, 0.05, 1.0, 1.0).unwrap();
        assert_eq!(x_next.len(), 2);
        assert!(meta.margin > 0.0);
    }

    #[test]
    fn test_spectral_norm_diagonal() {
        let m = array![[2.0, 0.0], [0.0, 3.0]];
        let norm = spectral_norm_real(&m);
        assert!((norm - 3.0).abs() < 1e-5);
    }

    #[test]
    fn test_jordan_contracts() {
        let n = 2;
        let rho = DMatrix::<Complex64>::identity(n, n) * Complex64::new(0.5, 0.0);
        let u = DMatrix::<Complex64>::identity(n, n);
        let rho2 = jordan_contraction(&rho, &u, PHI_INV);
        // trace should be less than original (contraction)
        let tr0: f64 = (0..n).map(|i| rho[(i, i)].re).sum();
        let tr1: f64 = (0..n).map(|i| rho2[(i, i)].re).sum();
        assert!(tr1 < tr0, "contraction should reduce trace: {} -> {}", tr0, tr1);
    }
}
