// Spectral + entropy primitives matching resonance-math/lib/entropy.mjs in Rust.

use nalgebra::DMatrix;
use num_complex::Complex64;

const EPSILON: f64 = 1e-14;

/// Shannon entropy H = -Σ p·log₂(p). Matches entropy.mjs:shannonEntropy.
pub fn shannon_entropy(probs: &[f64]) -> f64 {
    probs.iter()
        .filter(|&&p| p > EPSILON)
        .map(|&p| -p * p.log2())
        .sum::<f64>()
}

/// Von Neumann entropy S(ρ) = -tr(ρ log₂ ρ) = -Σ λᵢ log₂ λᵢ.
/// Matches entropy.mjs:vonNeumannEntropy but takes density matrix, not pre-computed eigenvalues.
pub fn von_neumann_entropy(rho: &DMatrix<Complex64>) -> f64 {
    let res = crate::zheev::zheev(rho).expect("von_neumann_entropy requires Hermitian input");
    shannon_entropy(res.eigenvalues.as_slice())
}

/// KL divergence D(p||q) = Σ pᵢ log₂(pᵢ/qᵢ). Matches entropy.mjs:klDivergence.
pub fn kl_divergence(p: &[f64], q: &[f64]) -> f64 {
    assert_eq!(p.len(), q.len(), "kl_divergence: length mismatch");
    p.iter().zip(q.iter())
        .filter(|(&pi, _)| pi > EPSILON)
        .map(|(&pi, &qi)| pi * (pi / qi.max(EPSILON)).log2())
        .sum()
}

/// Cross-entropy H(p,q) = -Σ pᵢ log₂(qᵢ). Matches entropy.mjs:crossEntropy.
pub fn cross_entropy(p: &[f64], q: &[f64]) -> f64 {
    assert_eq!(p.len(), q.len(), "cross_entropy: length mismatch");
    -p.iter().zip(q.iter())
        .filter(|(&pi, _)| pi > EPSILON)
        .map(|(&pi, &qi)| pi * qi.max(EPSILON).log2())
        .sum::<f64>()
}

/// Normalize weights to sum to 1. Matches entropy.mjs:normalize.
pub fn normalize(weights: &[f64]) -> Vec<f64> {
    let total: f64 = weights.iter().sum();
    if total <= EPSILON {
        let n = weights.len() as f64;
        return vec![1.0 / n; weights.len()];
    }
    weights.iter().map(|&w| w / total).collect()
}

/// Born rule probabilities: pⱼ = tr(Eⱼ · ρ) for POVM elements {Eⱼ}.
/// Matches measurement_head.f90:measurement_execute.
pub fn born_probabilities(rho: &DMatrix<Complex64>, povms: &[DMatrix<Complex64>]) -> Vec<f64> {
    let probs: Vec<f64> = povms.iter()
        .map(|e| {
            let prod = e * rho;
            let tr: f64 = (0..prod.nrows()).map(|i| prod[(i, i)].re).sum();
            tr.max(0.0)
        })
        .collect();
    normalize(&probs)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shannon_uniform() {
        let probs = vec![0.5, 0.5];
        let h = shannon_entropy(&probs);
        assert!((h - 1.0).abs() < 1e-12, "H = {}", h);
    }

    #[test]
    fn test_kl_self_zero() {
        let p = vec![0.3, 0.4, 0.3];
        let kl = kl_divergence(&p, &p);
        assert!(kl.abs() < 1e-12);
    }

    #[test]
    fn test_normalize_sum() {
        let w = vec![1.0, 2.0, 3.0];
        let n = normalize(&w);
        let s: f64 = n.iter().sum();
        assert!((s - 1.0).abs() < 1e-12);
    }

    #[test]
    fn test_born_sums_to_one() {
        let n = 2;
        let rho = DMatrix::<Complex64>::identity(n, n) * Complex64::new(0.5, 0.0);
        let e0 = DMatrix::<Complex64>::identity(n, n) * Complex64::new(0.5, 0.0);
        let e1 = DMatrix::<Complex64>::identity(n, n) * Complex64::new(0.5, 0.0);
        let probs = born_probabilities(&rho, &[e0, e1]);
        let s: f64 = probs.iter().sum();
        assert!((s - 1.0).abs() < 1e-10, "sum={}", s);
    }
}
