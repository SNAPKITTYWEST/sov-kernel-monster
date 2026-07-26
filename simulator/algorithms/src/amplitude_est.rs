//! Amplitude Estimation - Quantum Signal Processing
//!
//! Generalizes phase estimation to extract amplitudes from quantum states.
//! Distinguishes marked vs unmarked states via phase kickback.
//!
//! Algorithm:
//! 1. Prepare superposition with amplitude a of marked state |m⟩
//! 2. Apply phase oracle marking |m⟩
//! 3. Use phase estimation to extract phase φ = 2π arcsin(a)
//! 4. Recover amplitude a = sin(φ/2π)

use crate::{AlgorithmError, AlgorithmResult};
use num_complex::Complex64;
use std::f64::consts::PI;

/// Marks a state with phase
#[derive(Debug, Clone)]
pub struct AmplitudeRegister {
    /// Number of qubits for main register
    pub main_qubits: usize,

    /// Number of qubits for phase estimation register
    pub phase_qubits: usize,

    /// Amplitudes of marked states
    pub marked_amplitudes: Vec<f64>,

    /// Total amplitude (sum of marked)
    pub total_amplitude: f64,
}

impl AmplitudeRegister {
    /// Create new register
    pub fn new(main_qubits: usize, phase_qubits: usize) -> AlgorithmResult<Self> {
        if main_qubits == 0 || phase_qubits == 0 {
            return Err(AlgorithmError::InvalidParameters(
                "Qubit counts must be positive".to_string(),
            ));
        }

        Ok(AmplitudeRegister {
            main_qubits,
            phase_qubits,
            marked_amplitudes: Vec::new(),
            total_amplitude: 0.0,
        })
    }

    /// Add marked state amplitude
    pub fn add_marked_amplitude(&mut self, amplitude: f64) -> AlgorithmResult<()> {
        if amplitude < 0.0 || amplitude > 1.0 {
            return Err(AlgorithmError::InvalidParameters(
                "Amplitude must be in [0,1]".to_string(),
            ));
        }

        self.marked_amplitudes.push(amplitude);
        self.total_amplitude = self
            .marked_amplitudes
            .iter()
            .map(|a| a * a)
            .sum::<f64>()
            .sqrt();

        Ok(())
    }

    /// Initialize to uniform superposition with marked amplitude
    pub fn uniform_marked(n: usize, marked_amplitude: f64) -> AlgorithmResult<Self> {
        let mut reg = AmplitudeRegister::new(n, 5)?;
        reg.add_marked_amplitude(marked_amplitude)?;
        Ok(reg)
    }
}

/// Phase kickback circuit
#[derive(Debug, Clone)]
pub struct PhaseKickback {
    /// Phase to apply to marked state
    pub phase: f64,

    /// Marked state indices
    pub marked_indices: Vec<usize>,
}

impl PhaseKickback {
    /// Create phase kickback
    pub fn new(phase: f64, marked_indices: Vec<usize>) -> Self {
        PhaseKickback {
            phase,
            marked_indices,
        }
    }

    /// Apply to amplitudes
    pub fn apply(&self, amplitudes: &[Complex64]) -> Vec<Complex64> {
        let mut result = amplitudes.to_vec();
        let phase_factor = Complex64::from_polar(1.0, self.phase);

        for &idx in &self.marked_indices {
            if idx < result.len() {
                result[idx] *= phase_factor;
            }
        }

        result
    }
}

/// Amplitude estimation result
#[derive(Debug, Clone)]
pub struct AmplitudeEstimate {
    /// Estimated amplitude
    pub amplitude: f64,

    /// Confidence interval width
    pub confidence_width: f64,

    /// Number of shots required
    pub shots_required: usize,

    /// Measured phase
    pub measured_phase: f64,
}

impl AmplitudeEstimate {
    /// Create result
    pub fn new(amplitude: f64, measured_phase: f64, shots: usize) -> Self {
        // Standard error ~ 1/√M
        let confidence_width = 1.0 / (shots as f64).sqrt();

        AmplitudeEstimate {
            amplitude,
            confidence_width,
            shots_required: shots,
            measured_phase,
        }
    }

    /// Check if within target precision
    pub fn meets_precision(&self, target_error: f64) -> bool {
        self.confidence_width < target_error
    }
}

/// Quantum amplitude estimator
#[derive(Debug, Clone)]
pub struct AmplitudeEstimator {
    /// Number of phase qubits
    pub phase_qubits: usize,

    /// Measurement results
    pub measurements: Vec<bool>,

    /// Phase estimates
    pub phase_estimates: Vec<f64>,
}

impl AmplitudeEstimator {
    /// Create estimator
    pub fn new(phase_qubits: usize) -> AlgorithmResult<Self> {
        if phase_qubits == 0 {
            return Err(AlgorithmError::InvalidParameters(
                "Phase qubits must be positive".to_string(),
            ));
        }

        Ok(AmplitudeEstimator {
            phase_qubits,
            measurements: Vec::new(),
            phase_estimates: Vec::new(),
        })
    }

    /// Estimate amplitude
    pub fn estimate(&mut self, register: &AmplitudeRegister) -> AlgorithmResult<AmplitudeEstimate> {
        if register.total_amplitude < 0.0 || register.total_amplitude > 1.0 {
            return Err(AlgorithmError::InvalidParameters(
                "Invalid register amplitude".to_string(),
            ));
        }

        // From amplitude, derive phase
        let true_phase = 2.0 * register.total_amplitude.asin();

        // Simulate phase estimation (simplified)
        let measured_phase = true_phase + (rand::random::<f64>() - 0.5) * 0.1;

        // Recover amplitude from phase
        let estimated_amplitude = (measured_phase / 2.0).sin().abs();

        // Shots needed for target precision (1/√M)
        let target_error = 0.01;
        let shots = (1.0_f64 / (target_error * target_error)).ceil() as usize;

        self.phase_estimates.push(measured_phase);

        Ok(AmplitudeEstimate::new(
            estimated_amplitude,
            measured_phase,
            shots,
        ))
    }

    /// Estimate with multiple runs
    pub fn estimate_boosted(
        &mut self,
        register: &AmplitudeRegister,
        num_runs: usize,
    ) -> AlgorithmResult<AmplitudeEstimate> {
        let mut estimates = Vec::new();

        for _ in 0..num_runs {
            estimates.push(self.estimate(register)?);
        }

        // Average estimates
        let mean_amplitude = estimates.iter().map(|e| e.amplitude).sum::<f64>() / num_runs as f64;
        let mean_phase = estimates.iter().map(|e| e.measured_phase).sum::<f64>() / num_runs as f64;
        let mean_shots: usize = estimates.iter().map(|e| e.shots_required).sum::<usize>() / num_runs;

        Ok(AmplitudeEstimate::new(mean_amplitude, mean_phase, mean_shots))
    }

    /// Grover-based amplitude amplification
    pub fn grover_amplification(
        initial_amplitude: f64,
        iterations: usize,
    ) -> AlgorithmResult<f64> {
        // After k iterations of Grover, amplitude grows as sin((2k+1)θ) where sin(θ) = a
        let theta = initial_amplitude.asin();
        let amplified = ((2.0 * iterations as f64 + 1.0) * theta).sin();

        if amplified.abs() > 1.0 {
            Err(AlgorithmError::NumericalError(
                "Amplitude exceeds 1 after amplification".to_string(),
            ))
        } else {
            Ok(amplified.abs())
        }
    }

    /// Precision scaling analysis
    pub fn precision_scaling(target_amplitude: f64, target_error: f64) -> AlgorithmResult<usize> {
        // Standard QAE: shots ~ (1/a)² / ε² for amplitude a and error ε
        if target_amplitude <= 0.0 || target_amplitude > 1.0 {
            return Err(AlgorithmError::InvalidParameters(
                "Target amplitude must be in (0,1]".to_string(),
            ));
        }

        let factor = 1.0 / (target_amplitude * target_error);
        Ok((factor * factor).ceil() as usize)
    }

    /// Confidence interval for estimate
    pub fn confidence_interval(estimate: &AmplitudeEstimate, confidence: f64) -> (f64, f64) {
        // Standard CI: estimate ± z * std_error
        let z = match confidence {
            0.68 => 1.0,  // 1σ
            0.95 => 1.96, // 2σ
            0.99 => 2.576, // 3σ
            _ => 1.96,    // default
        };

        let margin = z * estimate.confidence_width;
        let lower = (estimate.amplitude - margin).max(0.0);
        let upper = (estimate.amplitude + margin).min(1.0);

        (lower, upper)
    }
}

// Rand crate placeholder
mod rand {
    pub fn random<T>() -> T
    where
        T: Default,
    {
        T::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_amplitude_register_creation() {
        let reg = AmplitudeRegister::new(2, 3);
        assert!(reg.is_ok());
    }

    #[test]
    fn test_amplitude_register_marked() {
        let reg = AmplitudeRegister::uniform_marked(2, 0.5);
        assert!(reg.is_ok());
        assert_eq!(reg.unwrap().total_amplitude, 0.5);
    }

    #[test]
    fn test_phase_kickback() {
        let pb = PhaseKickback::new(PI / 4.0, vec![0, 2]);
        let amp = vec![Complex64::new(1.0, 0.0); 4];
        let result = pb.apply(&amp);
        assert_eq!(result.len(), 4);
    }

    #[test]
    fn test_amplitude_estimate() {
        let est = AmplitudeEstimate::new(0.5, PI / 6.0, 100);
        assert!(est.meets_precision(0.2));
        assert!(!est.meets_precision(0.001));
    }

    #[test]
    fn test_amplitude_estimator_creation() {
        let est = AmplitudeEstimator::new(5);
        assert!(est.is_ok());
    }

    #[test]
    fn test_grover_amplification() {
        let amp = AmplitudeEstimator::grover_amplification(0.5, 1);
        assert!(amp.is_ok());
    }

    #[test]
    fn test_precision_scaling() {
        let shots = AmplitudeEstimator::precision_scaling(0.5, 0.01);
        assert!(shots.is_ok());
        assert!(shots.unwrap() > 0);
    }

    #[test]
    fn test_confidence_interval() {
        let est = AmplitudeEstimate::new(0.5, PI / 6.0, 100);
        let (lower, upper) = AmplitudeEstimator::confidence_interval(&est, 0.95);
        assert!(lower <= 0.5 && 0.5 <= upper);
    }
}

// Made with Bob
