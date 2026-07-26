//! # Quantum Noise Channels (Kraus Formalism)
//!
//! Implements noise channels as Kraus operator sums:
//! E(ρ) = Σ_k E_k ρ E_k†
//!
//! Key invariants:
//! - **Trace preservation**: Σ_k E_k† E_k = I (ensures Tr(E(ρ)) = Tr(ρ))
//! - **Positivity**: E(ρ) ⪰ 0 for all ρ ⪰ 0
//! - **Composability**: Channels compose via tensor product (preserving CP)
//!
//! ## Supported Channels
//! - Depolarizing: (1-p)ρ + (p/3)(XρX + YρY + ZρZ)
//! - Amplitude damping: decay to ground state with rate γ
//! - Phase damping: pure dephasing with rate γ
//! - Readout error: bit-flip with asymmetric probabilities
//! - Pauli channel: probabilistic Pauli application

use tch::{Device, Kind, Tensor};
use thiserror::Error;
use std::f64;

/// Error type for noise channel operations
#[derive(Debug, Error)]
pub enum NoiseError {
    #[error("Tensor operation failed: {0}")]
    TchError(#[from] tch::TchError),

    #[error("Invalid tensor dimensions: expected [n, n] density matrix")]
    InvalidDimensions,

    #[error("Invalid probability: {0}, expected 0 ≤ p ≤ 1")]
    InvalidProbability(f64),

    #[error("Invalid rate parameter: {0}, expected γ ≥ 0")]
    InvalidRate(f64),

    #[error("Kraus operators did not preserve trace (Σ E_k† E_k ≠ I, error={error})")]
    TraceNotPreserved { error: f64 },

    #[error("Output not positive semi-definite: min eigenvalue = {eig}")]
    NotPositiveSemiDefinite { eig: f64 },

    #[error("Precision error: density matrix must be f64")]
    PrecisionError,
}

pub type Result<T> = std::result::Result<T, NoiseError>;

/// Trait for quantum noise channels
pub trait NoiseChannel {
    /// Apply channel to density matrix: E(ρ)
    fn apply(&self, rho: &Tensor) -> Result<Tensor>;

    /// Get Kraus operators [E_0, E_1, ...]
    fn kraus_operators(&self) -> Result<Vec<Tensor>>;

    /// Verify trace preservation: Σ_k E_k† E_k = I
    fn verify_trace_preservation(&self) -> Result<()>;
}

/// Depolarizing channel: E(ρ) = (1-p)ρ + (p/3)(XρX + YρY + ZρZ)
///
/// # Parameters
/// - `p`: depolarizing rate (0 ≤ p ≤ 1)
///
/// # Invariants
/// - p=0: identity (no noise)
/// - p=1: maximally mixed (I/2 for 1-qubit)
/// - Trace-preserving by construction
#[derive(Debug, Clone)]
pub struct DepolarizingChannel {
    p: f64,
    dim: usize, // Hilbert space dimension (2 for qubits)
}

impl DepolarizingChannel {
    /// Create a new depolarizing channel
    pub fn new(p: f64) -> Result<Self> {
        if p < 0.0 || p > 1.0 {
            return Err(NoiseError::InvalidProbability(p));
        }
        Ok(DepolarizingChannel { p, dim: 2 })
    }

    /// Pauli X matrix
    fn pauli_x() -> Tensor {
        Tensor::of_slice(&[0.0, 1.0, 1.0, 0.0])
            .reshape(&[2, 2])
            .to(Kind::Double)
    }

    /// Pauli Y matrix
    fn pauli_y() -> Tensor {
        Tensor::of_slice(&[0.0, -1.0, 1.0, 0.0])
            .reshape(&[2, 2])
            .to(Kind::Double)
    }

    /// Pauli Z matrix
    fn pauli_z() -> Tensor {
        Tensor::of_slice(&[1.0, 0.0, 0.0, -1.0])
            .reshape(&[2, 2])
            .to(Kind::Double)
    }
}

impl NoiseChannel for DepolarizingChannel {
    fn kraus_operators(&self) -> Result<Vec<Tensor>> {
        let device = Device::Cpu;
        let sqrt_1_minus_p = (1.0 - self.p).sqrt();
        let sqrt_p_third = (self.p / 3.0).sqrt();

        let eye = Tensor::eye(2, (Kind::Double, device));
        let x = Self::pauli_x().to(device);
        let y = Self::pauli_y().to(device);
        let z = Self::pauli_z().to(device);

        Ok(vec![
            &eye * sqrt_1_minus_p,
            &x * sqrt_p_third,
            &y * sqrt_p_third,
            &z * sqrt_p_third,
        ])
    }

    fn apply(&self, rho: &Tensor) -> Result<Tensor> {
        if rho.kind() != Kind::Double {
            return Err(NoiseError::PrecisionError);
        }

        let size = rho.size();
        if size.len() != 2 || size[0] != size[1] {
            return Err(NoiseError::InvalidDimensions);
        }

        let n = size[0];
        let device = rho.device();

        tch::no_grad(|| {
            // E(ρ) = Σ_k E_k ρ E_k†
            let mut result = Tensor::zeros(size, (Kind::Double, device));

            let kraus = self.kraus_operators()?;
            for e_k in kraus {
                let e_k = e_k.to(device);
                let e_k_dag = e_k.transpose(0, 1); // E_k†
                let term = e_k.matmul(rho).matmul(&e_k_dag);
                result = result + term;
            }

            // Verify constraints
            verify_density_matrix(&result)?;

            Ok(result)
        })
    }

    fn verify_trace_preservation(&self) -> Result<()> {
        // Σ_k E_k† E_k = I
        let eye = Tensor::eye(2, (Kind::Double, Device::Cpu));
        let mut sum = Tensor::zeros([2, 2], (Kind::Double, Device::Cpu));

        for e_k in self.kraus_operators()? {
            let e_k_dag = e_k.transpose(0, 1);
            sum = sum + e_k_dag.matmul(&e_k);
        }

        let diff: f64 = (&sum - &eye).abs().max().double_value(&[]);
        if diff > 1e-10 {
            return Err(NoiseError::TraceNotPreserved { error: diff });
        }
        Ok(())
    }
}

/// Amplitude damping channel: decay to ground state
///
/// # Parameters
/// - `gamma`: decay rate (0 ≤ γ ≤ 1)
///
/// # Kraus operators
/// E_0 = |0><0| + √(1-γ)|1><1|
/// E_1 = √γ|0><1|
///
/// # Physical meaning
/// Represents energy loss (T1 decay) at rate γ per operation
#[derive(Debug, Clone)]
pub struct AmplitudeDampingChannel {
    gamma: f64,
}

impl AmplitudeDampingChannel {
    /// Create a new amplitude damping channel
    pub fn new(gamma: f64) -> Result<Self> {
        if gamma < 0.0 || gamma > 1.0 {
            return Err(NoiseError::InvalidRate(gamma));
        }
        Ok(AmplitudeDampingChannel { gamma })
    }
}

impl NoiseChannel for AmplitudeDampingChannel {
    fn kraus_operators(&self) -> Result<Vec<Tensor>> {
        let device = Device::Cpu;
        let sqrt_1_minus_gamma = (1.0 - self.gamma).sqrt();
        let sqrt_gamma = self.gamma.sqrt();

        // E_0 = [[1, 0], [0, √(1-γ)]]
        let e0_data = vec![1.0, 0.0, 0.0, sqrt_1_minus_gamma];
        let e0 = Tensor::of_slice(&e0_data)
            .reshape(&[2, 2])
            .to(Kind::Double)
            .to(device);

        // E_1 = [[0, √γ], [0, 0]]
        let e1_data = vec![0.0, sqrt_gamma, 0.0, 0.0];
        let e1 = Tensor::of_slice(&e1_data)
            .reshape(&[2, 2])
            .to(Kind::Double)
            .to(device);

        Ok(vec![e0, e1])
    }

    fn apply(&self, rho: &Tensor) -> Result<Tensor> {
        if rho.kind() != Kind::Double {
            return Err(NoiseError::PrecisionError);
        }

        let size = rho.size();
        if size.len() != 2 || size[0] != size[1] {
            return Err(NoiseError::InvalidDimensions);
        }

        let device = rho.device();

        tch::no_grad(|| {
            let kraus = self.kraus_operators()?;
            let mut result = Tensor::zeros(size, (Kind::Double, device));

            for e_k in kraus {
                let e_k = e_k.to(device);
                let e_k_dag = e_k.transpose(0, 1);
                let term = e_k.matmul(rho).matmul(&e_k_dag);
                result = result + term;
            }

            verify_density_matrix(&result)?;
            Ok(result)
        })
    }

    fn verify_trace_preservation(&self) -> Result<()> {
        let mut sum = Tensor::zeros([2, 2], (Kind::Double, Device::Cpu));
        for e_k in self.kraus_operators()? {
            let e_k_dag = e_k.transpose(0, 1);
            sum = sum + e_k_dag.matmul(&e_k);
        }

        let eye = Tensor::eye(2, (Kind::Double, Device::Cpu));
        let diff: f64 = (&sum - &eye).abs().max().double_value(&[]);
        if diff > 1e-10 {
            return Err(NoiseError::TraceNotPreserved { error: diff });
        }
        Ok(())
    }
}

/// Phase damping channel: pure dephasing (T2 decay)
///
/// # Parameters
/// - `gamma`: dephasing rate (0 ≤ γ ≤ 1)
///
/// # Kraus operators
/// E_0 = [[1, 0], [0, √(1-γ)]]
/// E_1 = [[0, 0], [0, √γ]]
///
/// # Physical meaning
/// Represents loss of coherence without energy loss (T2 decay)
#[derive(Debug, Clone)]
pub struct PhaseDampingChannel {
    gamma: f64,
}

impl PhaseDampingChannel {
    /// Create a new phase damping channel
    pub fn new(gamma: f64) -> Result<Self> {
        if gamma < 0.0 || gamma > 1.0 {
            return Err(NoiseError::InvalidRate(gamma));
        }
        Ok(PhaseDampingChannel { gamma })
    }
}

impl NoiseChannel for PhaseDampingChannel {
    fn kraus_operators(&self) -> Result<Vec<Tensor>> {
        let device = Device::Cpu;
        let sqrt_1_minus_gamma = (1.0 - self.gamma).sqrt();
        let sqrt_gamma = self.gamma.sqrt();

        // E_0 = [[1, 0], [0, √(1-γ)]]
        let e0_data = vec![1.0, 0.0, 0.0, sqrt_1_minus_gamma];
        let e0 = Tensor::of_slice(&e0_data)
            .reshape(&[2, 2])
            .to(Kind::Double)
            .to(device);

        // E_1 = [[0, 0], [0, √γ]]
        let e1_data = vec![0.0, 0.0, 0.0, sqrt_gamma];
        let e1 = Tensor::of_slice(&e1_data)
            .reshape(&[2, 2])
            .to(Kind::Double)
            .to(device);

        Ok(vec![e0, e1])
    }

    fn apply(&self, rho: &Tensor) -> Result<Tensor> {
        if rho.kind() != Kind::Double {
            return Err(NoiseError::PrecisionError);
        }

        let size = rho.size();
        if size.len() != 2 || size[0] != size[1] {
            return Err(NoiseError::InvalidDimensions);
        }

        let device = rho.device();

        tch::no_grad(|| {
            let kraus = self.kraus_operators()?;
            let mut result = Tensor::zeros(size, (Kind::Double, device));

            for e_k in kraus {
                let e_k = e_k.to(device);
                let e_k_dag = e_k.transpose(0, 1);
                let term = e_k.matmul(rho).matmul(&e_k_dag);
                result = result + term;
            }

            verify_density_matrix(&result)?;
            Ok(result)
        })
    }

    fn verify_trace_preservation(&self) -> Result<()> {
        let mut sum = Tensor::zeros([2, 2], (Kind::Double, Device::Cpu));
        for e_k in self.kraus_operators()? {
            let e_k_dag = e_k.transpose(0, 1);
            sum = sum + e_k_dag.matmul(&e_k);
        }

        let eye = Tensor::eye(2, (Kind::Double, Device::Cpu));
        let diff: f64 = (&sum - &eye).abs().max().double_value(&[]);
        if diff > 1e-10 {
            return Err(NoiseError::TraceNotPreserved { error: diff });
        }
        Ok(())
    }
}

/// Readout error channel: asymmetric bit-flip
///
/// # Parameters
/// - `p_0_to_1`: P(measure 1 | actual state 0)
/// - `p_1_to_0`: P(measure 0 | actual state 1)
///
/// # Kraus operators
/// E_0 = [[√(1-p_0_to_1), 0], [0, √(1-p_1_to_0)]]
/// E_1 = [[√p_0_to_1, 0], [0, √p_1_to_0]]
/// (with appropriate action on computational basis)
#[derive(Debug, Clone)]
pub struct ReadoutErrorChannel {
    p_0_to_1: f64,
    p_1_to_0: f64,
}

impl ReadoutErrorChannel {
    /// Create a new readout error channel
    pub fn new(p_0_to_1: f64, p_1_to_0: f64) -> Result<Self> {
        if p_0_to_1 < 0.0 || p_0_to_1 > 1.0 {
            return Err(NoiseError::InvalidProbability(p_0_to_1));
        }
        if p_1_to_0 < 0.0 || p_1_to_0 > 1.0 {
            return Err(NoiseError::InvalidProbability(p_1_to_0));
        }
        Ok(ReadoutErrorChannel { p_0_to_1, p_1_to_0 })
    }
}

impl NoiseChannel for ReadoutErrorChannel {
    fn kraus_operators(&self) -> Result<Vec<Tensor>> {
        let device = Device::Cpu;

        // Dirac deltas for measurement outcomes
        // M_0 = |0><0| with weight √(1-p_0_to_1)
        // M_1 = |1><1| with weight √(1-p_1_to_0)
        // M_2 = |1><0| with weight √(p_0_to_1)
        // M_3 = |0><1| with weight √(p_1_to_0)

        let m0_data = vec![(1.0 - self.p_0_to_1).sqrt(), 0.0, 0.0, 0.0];
        let m0 = Tensor::of_slice(&m0_data)
            .reshape(&[2, 2])
            .to(Kind::Double)
            .to(device);

        let m1_data = vec![0.0, 0.0, 0.0, (1.0 - self.p_1_to_0).sqrt()];
        let m1 = Tensor::of_slice(&m1_data)
            .reshape(&[2, 2])
            .to(Kind::Double)
            .to(device);

        let m2_data = vec![0.0, 0.0, self.p_0_to_1.sqrt(), 0.0];
        let m2 = Tensor::of_slice(&m2_data)
            .reshape(&[2, 2])
            .to(Kind::Double)
            .to(device);

        let m3_data = vec![0.0, self.p_1_to_0.sqrt(), 0.0, 0.0];
        let m3 = Tensor::of_slice(&m3_data)
            .reshape(&[2, 2])
            .to(Kind::Double)
            .to(device);

        Ok(vec![m0, m1, m2, m3])
    }

    fn apply(&self, rho: &Tensor) -> Result<Tensor> {
        if rho.kind() != Kind::Double {
            return Err(NoiseError::PrecisionError);
        }

        let size = rho.size();
        if size.len() != 2 || size[0] != size[1] {
            return Err(NoiseError::InvalidDimensions);
        }

        let device = rho.device();

        tch::no_grad(|| {
            let kraus = self.kraus_operators()?;
            let mut result = Tensor::zeros(size, (Kind::Double, device));

            for m in kraus {
                let m = m.to(device);
                let m_dag = m.transpose(0, 1);
                let term = m.matmul(rho).matmul(&m_dag);
                result = result + term;
            }

            verify_density_matrix(&result)?;
            Ok(result)
        })
    }

    fn verify_trace_preservation(&self) -> Result<()> {
        let mut sum = Tensor::zeros([2, 2], (Kind::Double, Device::Cpu));
        for e_k in self.kraus_operators()? {
            let e_k_dag = e_k.transpose(0, 1);
            sum = sum + e_k_dag.matmul(&e_k);
        }

        let eye = Tensor::eye(2, (Kind::Double, Device::Cpu));
        let diff: f64 = (&sum - &eye).abs().max().double_value(&[]);
        if diff > 1e-10 {
            return Err(NoiseError::TraceNotPreserved { error: diff });
        }
        Ok(())
    }
}

/// Pauli channel: probabilistic application of Pauli gates
///
/// # Parameters
/// - `px`: probability of X error
/// - `py`: probability of Y error
/// - `pz`: probability of Z error
///
/// # Kraus operators
/// E_0 = √(1 - px - py - pz) I
/// E_1 = √px X
/// E_2 = √py Y
/// E_3 = √pz Z
#[derive(Debug, Clone)]
pub struct PauliChannel {
    px: f64,
    py: f64,
    pz: f64,
}

impl PauliChannel {
    /// Create a new Pauli channel
    pub fn new(px: f64, py: f64, pz: f64) -> Result<Self> {
        if px < 0.0 || py < 0.0 || pz < 0.0 {
            return Err(NoiseError::InvalidProbability(px.min(py).min(pz)));
        }
        if (px + py + pz).abs() > 1.0 {
            return Err(NoiseError::InvalidProbability(px + py + pz));
        }
        Ok(PauliChannel { px, py, pz })
    }

    fn pauli_x() -> Tensor {
        Tensor::of_slice(&[0.0, 1.0, 1.0, 0.0])
            .reshape(&[2, 2])
            .to(Kind::Double)
    }

    fn pauli_y() -> Tensor {
        Tensor::of_slice(&[0.0, -1.0, 1.0, 0.0])
            .reshape(&[2, 2])
            .to(Kind::Double)
    }

    fn pauli_z() -> Tensor {
        Tensor::of_slice(&[1.0, 0.0, 0.0, -1.0])
            .reshape(&[2, 2])
            .to(Kind::Double)
    }
}

impl NoiseChannel for PauliChannel {
    fn kraus_operators(&self) -> Result<Vec<Tensor>> {
        let device = Device::Cpu;
        let p_identity = 1.0 - self.px - self.py - self.pz;

        let eye = Tensor::eye(2, (Kind::Double, device));
        let x = Self::pauli_x().to(device);
        let y = Self::pauli_y().to(device);
        let z = Self::pauli_z().to(device);

        Ok(vec![
            &eye * p_identity.sqrt(),
            &x * self.px.sqrt(),
            &y * self.py.sqrt(),
            &z * self.pz.sqrt(),
        ])
    }

    fn apply(&self, rho: &Tensor) -> Result<Tensor> {
        if rho.kind() != Kind::Double {
            return Err(NoiseError::PrecisionError);
        }

        let size = rho.size();
        if size.len() != 2 || size[0] != size[1] {
            return Err(NoiseError::InvalidDimensions);
        }

        let device = rho.device();

        tch::no_grad(|| {
            let kraus = self.kraus_operators()?;
            let mut result = Tensor::zeros(size, (Kind::Double, device));

            for e_k in kraus {
                let e_k = e_k.to(device);
                let e_k_dag = e_k.transpose(0, 1);
                let term = e_k.matmul(rho).matmul(&e_k_dag);
                result = result + term;
            }

            verify_density_matrix(&result)?;
            Ok(result)
        })
    }

    fn verify_trace_preservation(&self) -> Result<()> {
        let mut sum = Tensor::zeros([2, 2], (Kind::Double, Device::Cpu));
        for e_k in self.kraus_operators()? {
            let e_k_dag = e_k.transpose(0, 1);
            sum = sum + e_k_dag.matmul(&e_k);
        }

        let eye = Tensor::eye(2, (Kind::Double, Device::Cpu));
        let diff: f64 = (&sum - &eye).abs().max().double_value(&[]);
        if diff > 1e-10 {
            return Err(NoiseError::TraceNotPreserved { error: diff });
        }
        Ok(())
    }
}

/// Verify density matrix constraints
fn verify_density_matrix(rho: &Tensor) -> Result<()> {
    // Check trace = 1
    let trace: f64 = rho.trace().double_value(&[]);
    if (trace - 1.0).abs() > 1e-8 {
        return Err(NoiseError::InvalidDimensions);
    }

    // Check positive semi-definite
    let (evals, _) = rho.linalg_eigh("L")?;
    let min_eval: f64 = evals.min().double_value(&[]);
    if min_eval < -1e-10 {
        return Err(NoiseError::NotPositiveSemiDefinite { eig: min_eval });
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn maximally_mixed() -> Tensor {
        Tensor::eye(2, (Kind::Double, Device::Cpu)) * 0.5
    }

    #[test]
    fn test_depolarizing_channel_trace() {
        let channel = DepolarizingChannel::new(0.1).unwrap();
        let rho_init = maximally_mixed();
        let rho_final = channel.apply(&rho_init).unwrap();

        let trace: f64 = rho_final.trace().double_value(&[]);
        assert!((trace - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_depolarizing_channel_psd() {
        let channel = DepolarizingChannel::new(0.5).unwrap();
        let rho_init = maximally_mixed();
        let rho_final = channel.apply(&rho_init).unwrap();

        let (evals, _) = rho_final.linalg_eigh("L").unwrap();
        let min_eval: f64 = evals.min().double_value(&[]);
        assert!(min_eval >= -1e-10);
    }

    #[test]
    fn test_amplitude_damping_trace() {
        let channel = AmplitudeDampingChannel::new(0.2).unwrap();
        let rho_init = maximally_mixed();
        let rho_final = channel.apply(&rho_init).unwrap();

        let trace: f64 = rho_final.trace().double_value(&[]);
        assert!((trace - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_phase_damping_trace() {
        let channel = PhaseDampingChannel::new(0.15).unwrap();
        let rho_init = maximally_mixed();
        let rho_final = channel.apply(&rho_init).unwrap();

        let trace: f64 = rho_final.trace().double_value(&[]);
        assert!((trace - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_readout_error_trace() {
        let channel = ReadoutErrorChannel::new(0.05, 0.03).unwrap();
        let rho_init = maximally_mixed();
        let rho_final = channel.apply(&rho_init).unwrap();

        let trace: f64 = rho_final.trace().double_value(&[]);
        assert!((trace - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_pauli_channel_trace() {
        let channel = PauliChannel::new(0.01, 0.01, 0.02).unwrap();
        let rho_init = maximally_mixed();
        let rho_final = channel.apply(&rho_init).unwrap();

        let trace: f64 = rho_final.trace().double_value(&[]);
        assert!((trace - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_kraus_trace_preservation_depolarizing() {
        let channel = DepolarizingChannel::new(0.1).unwrap();
        assert!(channel.verify_trace_preservation().is_ok());
    }

    #[test]
    fn test_kraus_trace_preservation_amplitude_damping() {
        let channel = AmplitudeDampingChannel::new(0.1).unwrap();
        assert!(channel.verify_trace_preservation().is_ok());
    }

    #[test]
    fn test_invalid_probability() {
        assert!(DepolarizingChannel::new(-0.1).is_err());
        assert!(DepolarizingChannel::new(1.5).is_err());
    }

    #[test]
    fn test_readout_error_invalid_probability() {
        assert!(ReadoutErrorChannel::new(-0.1, 0.1).is_err());
        assert!(ReadoutErrorChannel::new(0.1, -0.1).is_err());
    }

    #[test]
    fn test_pauli_channel_invalid_probability_sum() {
        assert!(PauliChannel::new(0.5, 0.5, 0.5).is_err());
    }
}
