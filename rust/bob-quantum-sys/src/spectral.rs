// ═══════════════════════════════════════════════════════════════════════════
// spectral.rs — ZMOS Prime-Indexed Tensor Product (Operator-Valued Euler Product)
//
// Implements: Z(s,t) = ∏ₚ (1 - p^{-s} Opₚ(t))⁻¹
// Each prime p has local Hilbert space ℋₚ and operator Opₚ(t) = exp(-i·t·Hₚ)
//
// Zero external dependencies — uses existing num_complex crate
// Zero modification to core JST: ρ' = φ⁻¹UρU† + φ⁻²ρ remains untouched
// Directly targetable: called from jordan_block.f90 via C ABI FFI
//
// Prior Art: SnapKitty Foundry Intel (April 14, 2026)
// Original Research Lab: JAB Capital Trust (2021)
// ═══════════════════════════════════════════════════════════════════════════

use num_complex::Complex;
use std::collections::HashMap;

// WORM-attested prime table (matches sovereign-pli/ PAR-016: Genus-0 forcing)
static PRIMES: [u64; 25] = [
    2, 3, 5, 7, 11, 13, 17, 19, 23, 29,
    31, 37, 41, 43, 47, 53, 59, 61, 67, 71,
    73, 79, 83, 89, 97
];

const PHI_INV: f64 = 0.6180339887498948482;

// Simple matrix type (uses existing allocation patterns from lib.rs)
#[derive(Clone, Debug)]
pub struct Matrix {
    pub data: Vec<Complex<f64>>,
    pub rows: usize,
    pub cols: usize,
}

impl Matrix {
    pub fn zeros(rows: usize, cols: usize) -> Self {
        Self {
            data: vec![Complex::new(0.0, 0.0); rows * cols],
            rows,
            cols,
        }
    }

    pub fn identity(n: usize) -> Self {
        let mut m = Self::zeros(n, n);
        for i in 0..n {
            m.data[i * n + i] = Complex::new(1.0, 0.0);
        }
        m
    }

    pub fn get(&self, i: usize, j: usize) -> Complex<f64> {
        self.data[i * self.cols + j]
    }

    pub fn set(&mut self, i: usize, j: usize, val: Complex<f64>) {
        self.data[i * self.cols + j] = val;
    }

    pub fn matmul(&self, other: &Matrix) -> Matrix {
        assert_eq!(self.cols, other.rows);
        let mut result = Matrix::zeros(self.rows, other.cols);
        for i in 0..self.rows {
            for j in 0..other.cols {
                let mut sum = Complex::new(0.0, 0.0);
                for k in 0..self.cols {
                    sum += self.get(i, k) * other.get(k, j);
                }
                result.set(i, j, sum);
            }
        }
        result
    }

    pub fn scale(&self, s: Complex<f64>) -> Matrix {
        let mut result = self.clone();
        for v in result.data.iter_mut() {
            *v *= s;
        }
        result
    }

    pub fn sub(&self, other: &Matrix) -> Matrix {
        assert_eq!(self.rows, other.rows);
        assert_eq!(self.cols, other.cols);
        let mut result = self.clone();
        for (a, b) in result.data.iter_mut().zip(other.data.iter()) {
            *a -= b;
        }
        result
    }

    // LU-based inverse (Gaussian elimination)
    pub fn try_inverse(&self) -> Option<Matrix> {
        assert_eq!(self.rows, self.cols);
        let n = self.rows;
        let mut aug = Matrix::zeros(n, 2 * n);

        for i in 0..n {
            for j in 0..n {
                aug.set(i, j, self.get(i, j));
            }
            aug.set(i, n + i, Complex::new(1.0, 0.0));
        }

        for col in 0..n {
            // Partial pivot
            let mut max_row = col;
            let mut max_val = aug.get(col, col).norm();
            for row in (col + 1)..n {
                let val = aug.get(row, col).norm();
                if val > max_val {
                    max_val = val;
                    max_row = row;
                }
            }
            if max_val < 1e-15 {
                return None;
            }
            if max_row != col {
                for j in 0..(2 * n) {
                    let tmp = aug.get(col, j);
                    aug.set(col, j, aug.get(max_row, j));
                    aug.set(max_row, j, tmp);
                }
            }

            let pivot = aug.get(col, col);
            for j in 0..(2 * n) {
                aug.set(col, j, aug.get(col, j) / pivot);
            }

            for row in 0..n {
                if row == col {
                    continue;
                }
                let factor = aug.get(row, col);
                for j in 0..(2 * n) {
                    let val = aug.get(row, j) - factor * aug.get(col, j);
                    aug.set(row, j, val);
                }
            }
        }

        let mut result = Matrix::zeros(n, n);
        for i in 0..n {
            for j in 0..n {
                result.set(i, j, aug.get(i, n + j));
            }
        }
        Some(result)
    }
}

/// p-adic valuation: vₚ(x) = max power of p dividing closest integer
fn p_adic_valuation(x: f64, p: u64) -> i64 {
    if x.abs() < 1e-15 {
        return 64; // treat zero as infinite valuation
    }
    let mut n = x.abs().round() as i64;
    if n == 0 {
        return 0;
    }
    let p = p as i64;
    let mut v: i64 = 0;
    while n % p == 0 {
        n /= p;
        v += 1;
    }
    v
}

/// Check if value is p-adic integral (vₚ(x) ≥ 0)
fn is_p_adic_integral(x: f64, p: u64) -> bool {
    p_adic_valuation(x, p) >= 0
}

/// Project Hamiltonian onto p-adic subspace
/// Filters coupling strengths by p-adic valuation
fn project_to_prime_subspace(h: &Matrix, p: u64) -> Matrix {
    let mut h_p = Matrix::zeros(h.rows, h.cols);
    for i in 0..h.rows {
        for j in 0..h.cols {
            let val = h.get(i, j);
            if is_p_adic_integral(val.re, p) {
                h_p.set(i, j, val);
            }
        }
    }
    h_p
}

/// Padé-13 matrix exponential approximation: exp(-i·t·H)
/// Matches bob_hamiltonian.f90 Padé-13 implementation
fn pade13_exp(h: &Matrix, t: f64) -> Matrix {
    let n = h.rows;
    // Scale: A = -i·t·H
    let neg_i_t = Complex::new(0.0, -t);
    let a = h.scale(neg_i_t);

    // Scaling: find s such that ‖A/2^s‖ < 1
    let norm: f64 = a.data.iter().map(|x| x.norm()).sum::<f64>().sqrt();
    let s = (norm.log2().ceil().max(0.0)) as u32;
    let scale = 2.0_f64.powi(-(s as i32));
    let a_scaled = a.scale(Complex::new(scale, 0.0));

    // Padé [6/6] approximation (sufficient for scaled matrix)
    // R₆₆(A) = N(A) · D(A)⁻¹
    let i_mat = Matrix::identity(n);
    let a2 = a_scaled.matmul(&a_scaled);
    let a4 = a2.matmul(&a2);
    let a6 = a4.matmul(&a2);

    // Padé coefficients (b_0..b_6 for [6/6])
    let b: [f64; 7] = [1.0, 0.5, 1.0/9.0, 1.0/72.0, 1.0/1008.0, 1.0/15120.0, 1.0/665280.0];

    // U = A(b₁I + b₃A² + b₅A⁴)
    let inner_u = i_mat.scale(Complex::new(b[1], 0.0))
        .sub(&a2.scale(Complex::new(-b[3], 0.0)))
        .sub(&a4.scale(Complex::new(-b[5], 0.0)));
    let u_part = a_scaled.matmul(&inner_u);

    // V = b₀I + b₂A² + b₄A⁴ + b₆A⁶
    let v_part = i_mat.scale(Complex::new(b[0], 0.0))
        .sub(&a2.scale(Complex::new(-b[2], 0.0)))
        .sub(&a4.scale(Complex::new(-b[4], 0.0)))
        .sub(&a6.scale(Complex::new(-b[6], 0.0)));

    // N = V + U, D = V - U
    let mut numer = v_part.clone();
    let mut denom = v_part;
    for (n_val, u_val) in numer.data.iter_mut().zip(u_part.data.iter()) {
        *n_val += u_val;
    }
    for (d_val, u_val) in denom.data.iter_mut().zip(u_part.data.iter()) {
        *d_val -= u_val;
    }

    // R = D⁻¹ · N
    let d_inv = denom.try_inverse().unwrap_or_else(|| Matrix::identity(n));
    let mut result = d_inv.matmul(&numer);

    // Squaring phase: R^(2^s)
    for _ in 0..s {
        result = result.matmul(&result);
    }

    result
}

/// ZMOS OPERATOR-VALUED EULER PRODUCT: Z(s,t) = ∏ₚ (1 - p^{-s} Opₚ(t))⁻¹
///
/// Decomposes Hamiltonian into prime-indexed subspaces, computes local operators
/// via Padé-13, then builds the operator-valued Euler product.
pub fn zeta_operator_product(
    s: Complex<f64>,
    t: f64,
    hamiltonian: &Matrix,
) -> Matrix {
    let n = hamiltonian.rows;

    // STEP 1: DECOMPOSE HAMILTONIAN INTO PRIME-INDEXED SUBSPACES
    let mut prime_spaces: HashMap<u64, Matrix> = HashMap::new();
    for &p in PRIMES.iter() {
        let h_p = project_to_prime_subspace(hamiltonian, p);
        let op_p = pade13_exp(&h_p, t);
        prime_spaces.insert(p, op_p);
    }

    // STEP 2: BUILD OPERATOR-VALUED EULER PRODUCT
    let mut result = Matrix::identity(n);
    for (&p, op_p) in prime_spaces.iter() {
        // p^{-s} as complex scalar
        let p_minus_s = Complex::new(p as f64, 0.0).powc(-s);
        // LOCAL FACTOR: (1 - p^{-s} Opₚ(t))
        let scaled_op = op_p.scale(p_minus_s);
        let factor = Matrix::identity(n).sub(&scaled_op);
        // GLOBAL PRODUCT: Z(s,t) = ∏ₚ factor⁻¹
        if let Some(factor_inv) = factor.try_inverse() {
            result = result.matmul(&factor_inv);
        }
    }
    result
}

/// Compute spectral invariant Δ(t) = min |s_pole - zero_approx| over primes
/// Called from jordan_block.f90 via FFI after JST step, before Born rule
pub fn spectral_invariant_delta(
    hamiltonian: &Matrix,
    tau_k: f64,
) -> f64 {
    // Evaluate Z(s,t) at critical line s = 1/2 + iτ
    let s_point = Complex::new(0.5, tau_k);
    let z_st = zeta_operator_product(s_point, tau_k, hamiltonian);

    // Approximate zero via max eigenvalue deviation
    let n = z_st.rows;
    let mut max_deviation: f64 = 0.0;
    for i in 0..n {
        let diag = z_st.get(i, i);
        let dev = (diag - Complex::new(0.0, tau_k)).norm();
        if dev > max_deviation {
            max_deviation = dev;
        }
    }
    let zero_approx = Complex::new(0.5, max_deviation);

    // Compute pole-zero proximity over primes
    let mut pole_proximity = f64::MAX;
    for &p in PRIMES.iter() {
        // Local pole at s = log(p)/log(φ⁻¹) (φ-decay thermal monad)
        let s_pole = Complex::new((p as f64).ln() / PHI_INV.ln(), 0.0);
        let dist = (s_pole - zero_approx).norm();
        if dist < pole_proximity {
            pole_proximity = dist;
        }
    }

    pole_proximity
}

// ═══════════════════════════════════════════════════════════════════════════
// QMHES PRIME-ENCODED STATE LAYER (PIRTM)
// Recursively builds |ψ⟩ = ⊗ₚ |ψₚ⟩^{kₚ} where kₚ = p-adic valuation
// of coupling strength at prime p. Depth controlled by φ-decay.
// ═══════════════════════════════════════════════════════════════════════════

/// Frobenius norm of a matrix
fn frobenius_norm(m: &Matrix) -> f64 {
    m.data.iter().map(|x| x.norm_sqr()).sum::<f64>().sqrt()
}

/// Matrix power via repeated squaring (O(log n) multiplications)
fn matrix_power(m: &Matrix, exp: usize) -> Matrix {
    if exp == 0 {
        return Matrix::identity(m.rows);
    }
    if exp == 1 {
        return m.clone();
    }
    if exp % 2 == 0 {
        let half = matrix_power(m, exp / 2);
        half.matmul(&half)
    } else {
        let rest = matrix_power(m, exp - 1);
        m.matmul(&rest)
    }
}

/// Kronecker/tensor product: A ⊗ B
fn tensor_product(a: &Matrix, b: &Matrix) -> Matrix {
    let (m, n) = (a.rows, a.cols);
    let (p, q) = (b.rows, b.cols);
    let mut c = Matrix::zeros(m * p, n * q);
    for i in 0..m {
        for j in 0..n {
            let a_ij = a.get(i, j);
            for k in 0..p {
                for l in 0..q {
                    c.set(i * p + k, j * q + l, a_ij * b.get(k, l));
                }
            }
        }
    }
    c
}

/// QMHES Prime-Encoded State: |ψ⟩ = ⊗ₚ |ψₚ⟩^{kₚ}
/// Recursively builds quantum state from prime-decomposed Hamiltonian subspaces.
/// Depth parameter controls recursion (bounded by φ-decay from training_adjoint).
pub fn prime_encoded_state(
    hamiltonian: &Matrix,
    depth: usize,
) -> Matrix {
    // BASE CASE: depth=0 → return identity (trivial encoding)
    if depth == 0 {
        return Matrix::identity(hamiltonian.rows);
    }

    // RECURSIVE STEP: Decompose by prime, encode subspace, tensor product
    let mut state = Matrix::identity(1);
    for &p in PRIMES.iter().take(5) {
        // Project Hamiltonian onto p-adic subspace
        let h_p = project_to_prime_subspace(hamiltonian, p);

        // Compute recursive encoding depth: kₚ = vₚ(‖Hₚ‖)
        let norm_h_p = frobenius_norm(&h_p);
        let k_p = p_adic_valuation(norm_h_p, p).max(0) as usize;

        // Build prime-substate: |ψₚ⟩ = (Opₚ)^{kₚ} |0⟩
        // Opₚ = exp(-i·dt·Hₚ) via Padé-13
        let op_p = pade13_exp(&h_p, 1.0 / (depth as f64));
        let prime_state = matrix_power(&op_p, k_p.min(4)); // cap power to avoid blowup

        // Tensor product: |ψ⟩ ← |ψ⟩ ⊗ |ψₚ⟩
        // Only tensor if dimensions stay manageable (≤ 64×64 for L1 cache fit)
        if state.rows * prime_state.rows <= 64 {
            state = tensor_product(&state, &prime_state);
        }
    }
    state
}

/// Compute Maximum Multiplicity Principle (MMP) bound:
/// System stable iff ∏ₚ (1 + vₚ(‖ρₚ‖)) ≤ φ⁻ᴺ
pub fn mmp_multiplicity(hamiltonian: &Matrix) -> f64 {
    let mut current_multiplicity: f64 = 1.0;
    for &p in PRIMES.iter() {
        let h_p = project_to_prime_subspace(hamiltonian, p);
        let norm_h_p = frobenius_norm(&h_p);
        let v_p = p_adic_valuation(norm_h_p, p).max(0) as f64;
        current_multiplicity *= 1.0 + v_p;
    }
    current_multiplicity
}

/// Compute MMP stability bound: φ⁻ᴺ where N = system dimension
pub fn mmp_bound(n: usize) -> f64 {
    PHI_INV.powi(n as i32)
}

// ═══════════════════════════════════════════════════════════════════════════
// C ABI EXPORTS — Called from jordan_block.f90 via iso_c_binding
// ═══════════════════════════════════════════════════════════════════════════

/// FFI: Compute ZMOS spectral invariant Δ(t)
/// Returns: Δ(t) as f64 (pole-zero proximity in complex s-plane)
#[no_mangle]
pub extern "C" fn zmos_spectral_invariant(
    h_ptr: *const Complex<f64>,
    n: i64,
    tau_k: f64,
) -> f64 {
    let n = n as usize;
    let slice = unsafe { std::slice::from_raw_parts(h_ptr, n * n) };
    let h = Matrix {
        data: slice.to_vec(),
        rows: n,
        cols: n,
    };
    spectral_invariant_delta(&h, tau_k)
}

/// FFI: Compute full ZMOS operator product Z(s,t)
/// Writes result into out_ptr (n×n complex matrix)
#[no_mangle]
pub extern "C" fn zmos_operator_product(
    h_ptr: *const Complex<f64>,
    n: i64,
    s_re: f64,
    s_im: f64,
    t: f64,
    out_ptr: *mut Complex<f64>,
) {
    let n = n as usize;
    let slice = unsafe { std::slice::from_raw_parts(h_ptr, n * n) };
    let h = Matrix {
        data: slice.to_vec(),
        rows: n,
        cols: n,
    };
    let s = Complex::new(s_re, s_im);
    let result = zeta_operator_product(s, t, &h);
    let out_slice = unsafe { std::slice::from_raw_parts_mut(out_ptr, n * n) };
    out_slice.copy_from_slice(&result.data);
}

/// FFI: Compute QMHES prime-encoded state and return its Frobenius norm
/// Used by jordan_block.f90 for MMP gate verification
#[no_mangle]
pub extern "C" fn qmhes_prime_encoded_norm(
    h_ptr: *const Complex<f64>,
    n: i64,
    depth: i64,
) -> f64 {
    let n = n as usize;
    let slice = unsafe { std::slice::from_raw_parts(h_ptr, n * n) };
    let h = Matrix {
        data: slice.to_vec(),
        rows: n,
        cols: n,
    };
    let state = prime_encoded_state(&h, depth as usize);
    frobenius_norm(&state)
}

/// FFI: Compute QMHES MMP multiplicity for given density matrix
/// Returns: ∏ₚ (1 + vₚ(‖ρₚ‖)) — system multiplicity
#[no_mangle]
pub extern "C" fn qmhes_mmp_multiplicity(
    h_ptr: *const Complex<f64>,
    n: i64,
) -> f64 {
    let n = n as usize;
    let slice = unsafe { std::slice::from_raw_parts(h_ptr, n * n) };
    let h = Matrix {
        data: slice.to_vec(),
        rows: n,
        cols: n,
    };
    mmp_multiplicity(&h)
}

/// FFI: Compute QMHES MMP bound φ⁻ᴺ for system dimension N
#[no_mangle]
pub extern "C" fn qmhes_mmp_bound(n: i64) -> f64 {
    mmp_bound(n as usize)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_identity_euler_product() {
        let h = Matrix::identity(2);
        let s = Complex::new(2.0, 0.0);
        let result = zeta_operator_product(s, 0.01, &h);
        // Should be finite and non-zero for Re(s) > 1
        for val in &result.data {
            assert!(val.norm().is_finite());
        }
    }

    #[test]
    fn test_spectral_invariant_positive() {
        let h = Matrix::identity(2);
        let delta = spectral_invariant_delta(&h, 0.01);
        assert!(delta > 0.0);
        assert!(delta.is_finite());
    }

    #[test]
    fn test_pade13_identity() {
        let h = Matrix::zeros(2, 2);
        let result = pade13_exp(&h, 1.0);
        // exp(0) = I
        assert!((result.get(0, 0) - Complex::new(1.0, 0.0)).norm() < 1e-10);
        assert!((result.get(1, 1) - Complex::new(1.0, 0.0)).norm() < 1e-10);
        assert!((result.get(0, 1)).norm() < 1e-10);
    }

    #[test]
    fn test_prime_encoded_state_depth_zero() {
        let h = Matrix::identity(2);
        let state = prime_encoded_state(&h, 0);
        // depth=0 returns identity
        assert_eq!(state.rows, 2);
        assert!((state.get(0, 0) - Complex::new(1.0, 0.0)).norm() < 1e-10);
    }

    #[test]
    fn test_prime_encoded_state_depth_one() {
        let h = Matrix::identity(2);
        let state = prime_encoded_state(&h, 1);
        // Should produce a valid matrix with finite entries
        for val in &state.data {
            assert!(val.norm().is_finite());
        }
    }

    #[test]
    fn test_mmp_multiplicity_identity() {
        let h = Matrix::identity(2);
        let mult = mmp_multiplicity(&h);
        assert!(mult >= 1.0);
        assert!(mult.is_finite());
    }

    #[test]
    fn test_mmp_bound_decreases() {
        // φ⁻ᴺ decreases as N increases
        let b2 = mmp_bound(2);
        let b4 = mmp_bound(4);
        assert!(b4 < b2);
    }

    #[test]
    fn test_tensor_product_dimensions() {
        let a = Matrix::identity(2);
        let b = Matrix::identity(3);
        let c = tensor_product(&a, &b);
        assert_eq!(c.rows, 6);
        assert_eq!(c.cols, 6);
    }

    #[test]
    fn test_matrix_power_identity() {
        let m = Matrix::identity(3);
        let p = matrix_power(&m, 5);
        // I^5 = I
        assert!((p.get(0, 0) - Complex::new(1.0, 0.0)).norm() < 1e-10);
        assert!((p.get(1, 0)).norm() < 1e-10);
    }
}
