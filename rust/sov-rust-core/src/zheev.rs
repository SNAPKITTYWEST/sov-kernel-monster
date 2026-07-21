// Complex Hermitian eigensolver via nalgebra real-block reduction.
// Fixes spe_encoder.f90 sov_zheev stub.
//
// Method: for H Hermitian, decompose as H = A + iB where A = Re(H) symmetric,
// B = Im(H) antisymmetric. Build real block matrix M = [[A, -B],[B, A]] (2n×2n).
// M is real symmetric. Its eigenvalues are the doubled eigenvalues of H.
// Recover eigenvectors by decoding the real pairs back to complex.

use nalgebra::{DMatrix, DVector};
use num_complex::Complex64;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ZheevError {
    #[error("Matrix is not square: {rows}x{cols}")]
    NotSquare { rows: usize, cols: usize },
    #[error("Matrix is not Hermitian (max off-symmetry: {max_err})")]
    NotHermitian { max_err: f64 },
}

pub struct ZheevResult {
    pub eigenvalues: DVector<f64>,
    pub eigenvectors: DMatrix<Complex64>,
}

pub fn zheev(h: &DMatrix<Complex64>) -> Result<ZheevResult, ZheevError> {
    let (rows, cols) = h.shape();
    if rows != cols {
        return Err(ZheevError::NotSquare { rows, cols });
    }
    let n = rows;

    let max_err = hermitian_error(h);
    if max_err > 1e-10 {
        return Err(ZheevError::NotHermitian { max_err });
    }

    // Build real block matrix [[Re(H), -Im(H)], [Im(H), Re(H)]]
    let mut m = DMatrix::<f64>::zeros(2 * n, 2 * n);
    for i in 0..n {
        for j in 0..n {
            let h_ij = h[(i, j)];
            m[(i, j)] = h_ij.re;
            m[(i, n + j)] = -h_ij.im;
            m[(n + i, j)] = h_ij.im;
            m[(n + i, n + j)] = h_ij.re;
        }
    }

    let eig = m.symmetric_eigen();
    // eigenvalues come in pairs; take every other one (first n)
    let mut pairs: Vec<(f64, usize)> = (0..2 * n)
        .map(|i| (eig.eigenvalues[i], i))
        .collect();
    pairs.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());

    let mut eigenvalues = DVector::<f64>::zeros(n);
    let mut eigenvectors = DMatrix::<Complex64>::zeros(n, n);

    // eigenvalues are doubled (each appears twice); take one from each pair: indices 0,2,4,...
    for (k, &(eval, col)) in pairs.iter().step_by(2).take(n).enumerate() {
        eigenvalues[k] = eval;
        for i in 0..n {
            let re = eig.eigenvectors[(i, col)];
            let im = eig.eigenvectors[(n + i, col)];
            eigenvectors[(i, k)] = Complex64::new(re, im);
        }
        // normalize
        let norm: f64 = (0..n).map(|i| eigenvectors[(i, k)].norm_sqr()).sum::<f64>().sqrt();
        if norm > 1e-14 {
            for i in 0..n {
                eigenvectors[(i, k)] /= norm;
            }
        }
    }

    Ok(ZheevResult { eigenvalues, eigenvectors })
}

/// exp(-i * dt * H) for Hermitian H via eigendecomposition.
/// This is the unitary evolution operator U = exp(-i H dt).
pub fn exp_hermitian(h: &DMatrix<Complex64>, dt: f64) -> DMatrix<Complex64> {
    let res = zheev(h).expect("exp_hermitian requires Hermitian input");
    let n = res.eigenvalues.len();
    let mut diag = DMatrix::<Complex64>::zeros(n, n);
    for i in 0..n {
        let phase = Complex64::new(0.0, -dt * res.eigenvalues[i]);
        diag[(i, i)] = phase.exp();
    }
    &res.eigenvectors * &diag * res.eigenvectors.adjoint()
}

fn hermitian_error(h: &DMatrix<Complex64>) -> f64 {
    let n = h.nrows();
    let mut max = 0.0_f64;
    for i in 0..n {
        for j in 0..n {
            let err = (h[(i, j)] - h[(j, i)].conj()).norm();
            if err > max {
                max = err;
            }
        }
    }
    max
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_real_diagonal() {
        // H = diag(1, 2, 3) — trivially Hermitian
        let mut h = DMatrix::<Complex64>::zeros(3, 3);
        h[(0, 0)] = Complex64::new(1.0, 0.0);
        h[(1, 1)] = Complex64::new(2.0, 0.0);
        h[(2, 2)] = Complex64::new(3.0, 0.0);
        let res = zheev(&h).unwrap();
        let mut evals: Vec<f64> = res.eigenvalues.iter().copied().collect();
        evals.sort_by(|a, b| a.partial_cmp(b).unwrap());
        assert!((evals[0] - 1.0).abs() < 1e-10);
        assert!((evals[1] - 2.0).abs() < 1e-10);
        assert!((evals[2] - 3.0).abs() < 1e-10);
    }

    #[test]
    fn test_exp_unitary() {
        // H = [[1, 0],[0, -1]], dt = pi/2 → U = diag(e^{-i pi/2}, e^{i pi/2})
        let mut h = DMatrix::<Complex64>::zeros(2, 2);
        h[(0, 0)] = Complex64::new(1.0, 0.0);
        h[(1, 1)] = Complex64::new(-1.0, 0.0);
        let u = exp_hermitian(&h, std::f64::consts::PI / 2.0);
        // U†U should be identity
        let prod = u.adjoint() * &u;
        let eye = DMatrix::<Complex64>::identity(2, 2);
        let residual = (&prod - &eye).norm();
        assert!(residual < 1e-12, "residual={}", residual);
    }
}
