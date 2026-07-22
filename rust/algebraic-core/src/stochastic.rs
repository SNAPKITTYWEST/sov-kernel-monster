//! # Stochastic Solver Module
//!
//! Implements geometric Euler-Maruyama SDE solver for quantum density matrix diffusion
//! on the Bures manifold.
//! Solves: dρₜ = -∇_Riem S(ρₜ) dt + √D dWₜ
//! - Uses tangent space projection for Wiener process (dWₜ)
//! - Updates state via projection-based retraction to preserve manifold constraints
//! - Batched GPU execution for Monte Carlo trajectory simulation
//!
//! ## Key Design Decisions
//! - **Backend**: `tch-rs` with CUDA (`libtorch` backend) for hardware acceleration
//! - **Precision**: Strict `f64` usage (quantum states require double precision)
//! - **Tangent Projection**: Generates random Hermitian matrices on GPU, projects to trace-zero
//! - **Retraction Map**: Projects ρ + update onto density matrix manifold via eigenvalue
//!   clipping/renormalization
//! - **Batching**: All operations vectorized; batch loop only for eigendecomposition
//! - **Memory Safety**: Explicit tensor drops, no_grad scope, no intermediate leaks
//! - **Validation**: Unit tests verify trace preservation and positive semi-definiteness
//!
//! ## Safety Guarantees
//! - All tensor operations occur within `no_grad` scope to prevent autograd overhead
//! - Random number generation strictly on device (Device::Cuda) to avoid PCIe bottlenecks
//! - Eigenvalue decomposition uses `torch.linalg.eigh()` (CUDA-accelerated via cuSOLVER)
//! - Division by zero avoided via epsilon clamping in renormalization
//! - Error handling propagates errors for clear diagnostics
//! - Unit tests validate manifold constraints under floating-point tolerance
//!
//! ## Integration with sov-kernel-monster
//! - Entropy gradient drives density matrix evolution toward thermal equilibrium
//! - Connects to JST φ-decay: contraction rate φ⁻¹ bounds drift magnitude
//! - WORM-attested trajectory snapshots via sov_bifrost_sign at checkpoints
//! - Batched simulation enables Monte Carlo estimation of quantum observables
//!
//! ## Prior Art
//! - SnapKitty Foundry Intel (April 14, 2026)
//! - Original Research Lab: JAB Capital Trust (2021)

use tch::{Device, Kind, Tensor};
use thiserror::Error;
use crate::geometry::BuresGeometry;

/// Configuration for the geometric Euler-Maruyama solver.
///
/// Controls the discretization and noise parameters of the SDE:
/// dρₜ = -∇_Riem S(ρₜ) dt + √D dWₜ
///
/// # Fields
/// - `dt`: Time step size (Δt). Smaller → more accurate but slower.
/// - `diffusion`: Diffusion coefficient (D). Controls noise magnitude.
/// - `total_steps`: Number of Euler-Maruyama steps to simulate.
///
/// # Stability Condition
/// For the geometric Euler-Maruyama method to remain stable:
/// - `dt` should satisfy `dt < 1 / (2 * max_eigenvalue(∇²S))`
/// - In practice, `dt ≤ 0.01` works for most quantum systems with n ≤ 64
#[derive(Debug, Clone, Copy)]
pub struct SolverConfig {
    pub dt: f64,
    pub diffusion: f64,
    pub total_steps: usize,
}

impl SolverConfig {
    /// Creates a new solver configuration.
    ///
    /// # Arguments
    /// * `dt` - Time step size (must be > 0)
    /// * `diffusion` - Diffusion coefficient D (must be ≥ 0; D=0 gives deterministic flow)
    /// * `total_steps` - Number of simulation steps
    ///
    /// # Panics
    /// - If `dt <= 0`
    /// - If `diffusion < 0`
    pub fn new(dt: f64, diffusion: f64, total_steps: usize) -> Self {
        assert!(dt > 0.0, "dt must be positive, got {dt}");
        assert!(diffusion >= 0.0, "diffusion must be non-negative, got {diffusion}");
        Self { dt, diffusion, total_steps }
    }
}

/// Error type for stochastic solver operations
#[derive(Debug, Error)]
pub enum StochasticError {
    /// Underlying tensor operation failure (CUDA, memory, computation)
    #[error("Tensor operation failed: {0}")]
    TchError(#[from] tch::TchError),

    /// Input tensors have incompatible dimensions
    #[error("Invalid tensor dimensions: expected [batch, n, n] square matrices")]
    DimensionMismatch,

    /// Input tensor uses insufficient precision
    #[error("Tensor must be f64 precision for quantum state stability")]
    PrecisionError,

    /// Geometry module error (from gradient computation)
    #[error("Geometry error: {0}")]
    GeometryError(String),

    /// Manifold constraint violated after retraction (should never happen)
    #[error("Manifold constraint violated: trace={0}, expected 1.0")]
    ManifoldViolation(f64),
}

pub type Result<T> = std::result::Result<T, StochasticError>;

/// Geometric Euler-Maruyama SDE solver for quantum density matrix diffusion.
///
/// Solves: dρₜ = drift(ρₜ) dt + √D · dWₜ
/// where:
/// - drift(ρ) = -∇_Riem S(ρ) (negative Riemannian gradient of von Neumann entropy)
/// - dWₜ is a Wiener process in the tangent space T_ρ M (Hermitian, traceless matrices)
/// - The solution is projected back onto the density matrix manifold at each step
///
/// # Algorithm (per step):
/// 1. Compute drift: μ = -∇_Riem S(ρ) · dt
/// 2. Generate tangent noise: σ = √(D·dt) · project_tangent(randn())
/// 3. Tentative update: ρ̃ = ρ + μ + σ
/// 4. Retraction: ρ_next = project_manifold(ρ̃)
///    - Eigendecompose ρ̃
///    - Clip negative eigenvalues to 0
///    - Renormalize eigenvalues to sum to 1
///    - Reconstruct density matrix
pub struct GeometricEulerMaruyama;

impl GeometricEulerMaruyama {
    /// Performs a single step of the geometric Euler-Maruyama solver.
    ///
    /// # Arguments
    /// * `rho` - Current state tensor ([batch, n, n] or [n, n], Hermitian, trace=1, f64)
    /// * `config` - Solver configuration (dt, diffusion)
    ///
    /// # Returns
    /// * `Ok(Tensor)` - Next state tensor on the density matrix manifold
    /// * `Err(StochasticError)` - On validation failure or backend error
    ///
    /// # Manifold Guarantees
    /// The output tensor satisfies:
    /// - Hermitian (symmetric for real): ρ = ρ†
    /// - Trace one: Tr(ρ) = 1
    /// - Positive semi-definite: all eigenvalues ≥ 0
    pub fn step(rho: &Tensor, config: &SolverConfig) -> Result<Tensor> {
        let result = tch::no_grad(|| {
            // Validate input precision
            if rho.kind() != Kind::Double {
                return Err(StochasticError::PrecisionError);
            }

            let size = rho.size();
            let (is_batched, batch, n) = match size.len() {
                2 => {
                    if size[0] != size[1] {
                        return Err(StochasticError::DimensionMismatch);
                    }
                    (false, 1i64, size[0])
                }
                3 => {
                    if size[1] != size[2] {
                        return Err(StochasticError::DimensionMismatch);
                    }
                    (true, size[0], size[1])
                }
                _ => return Err(StochasticError::DimensionMismatch),
            };

            let device = rho.device();

            // Reshape to [batch, n, n] for uniform processing
            let rho_batch = if is_batched {
                rho.shallow_clone()
            } else {
                rho.unsqueeze(0)
            };

            // ══════════════════════════════════════════════════════════════
            // STEP 1: Compute deterministic drift = -∇_Riem S(ρ) · dt
            // ══════════════════════════════════════════════════════════════
            // Process each batch element through geometry module
            let mut drift_components = Vec::with_capacity(batch as usize);
            for i in 0..batch {
                let rho_i = rho_batch.get(i); // [n, n]
                let grad = BuresGeometry::grad_von_neumann_entropy(&rho_i)
                    .map_err(|e| StochasticError::GeometryError(e.to_string()))?;
                // drift = -grad_S * dt (entropy gradient descent)
                let drift_i = grad * (-config.dt);
                drift_components.push(drift_i.unsqueeze(0));
            }
            let drift = Tensor::cat(&drift_components, 0); // [batch, n, n]
            drop(drift_components);

            // ══════════════════════════════════════════════════════════════
            // STEP 2: Generate Wiener increment in tangent space
            // All noise generated ON DEVICE (no PCIe bottleneck)
            // ══════════════════════════════════════════════════════════════
            let noise = if config.diffusion > 0.0 {
                // a. Sample random matrix on GPU
                let z_raw = Tensor::randn([batch, n, n], (Kind::Double, device));

                // b. Make Hermitian (symmetric): Z = (Z + Z^T) / 2
                let z_herm = (&z_raw + &z_raw.transpose(1, 2)) * 0.5f64;
                drop(z_raw);

                // c. Project to tangent space (trace-zero subspace)
                //    Z_tan = Z - (Tr(Z)/n) · I
                //    Tr(Z) computed per batch element
                let diag_sum = z_herm.diagonal(0, 1, 2).sum_dim_intlist([-1i64].as_slice(), false, Kind::Double);
                // diag_sum: [batch]
                let trace_correction = diag_sum.unsqueeze(-1).unsqueeze(-1) / (n as f64);
                // trace_correction: [batch, 1, 1]
                let eye = Tensor::eye(n, (Kind::Double, device)).unsqueeze(0); // [1, n, n]
                let z_tangent = &z_herm - &(trace_correction * &eye);
                drop(z_herm);

                // d. Scale by √(D · dt)
                let noise_scale = (config.diffusion * config.dt).sqrt();
                z_tangent * noise_scale
            } else {
                // D=0 → deterministic flow (no noise)
                Tensor::zeros([batch, n, n], (Kind::Double, device))
            };

            // ══════════════════════════════════════════════════════════════
            // STEP 3: Tentative state: ρ̃ = ρ + drift + noise
            // (Hermitian, trace≈1, but may have negative eigenvalues)
            // ══════════════════════════════════════════════════════════════
            let rho_tilde = &rho_batch + &drift + &noise;
            drop(drift);
            drop(noise);

            // ══════════════════════════════════════════════════════════════
            // STEP 4: Retraction — project ρ̃ onto density matrix manifold
            // - Eigendecompose: ρ̃ = VΛV^T
            // - Clip negatives: Λ' = max(Λ, 0)
            // - Renormalize: Λ'' = Λ' / Σᵢλ'ᵢ (ensures trace=1)
            // - Reconstruct: ρ_next = VΛ''V^T
            // ══════════════════════════════════════════════════════════════
            let mut projected = Vec::with_capacity(batch as usize);
            for i in 0..batch {
                let rho_i = rho_tilde.get(i); // [n, n]

                // Make exactly symmetric (remove numerical asymmetry)
                let rho_sym = (&rho_i + &rho_i.tr()) * 0.5f64;

                // Eigendecompose
                let (evals, evecs) = rho_sym.linalg_eigh("L")?;

                // Clip negative eigenvalues
                let evals_clipped = evals.clamp_min(0.0);

                // Renormalize to trace=1
                let trace_sum: f64 = evals_clipped.sum(Kind::Double).double_value(&[]);
                let evals_normed = if trace_sum > 1e-12 {
                    &evals_clipped / trace_sum
                } else {
                    // Degenerate case: fallback to maximally mixed state
                    Tensor::ones([n], (Kind::Double, device)) / (n as f64)
                };

                // Reconstruct density matrix: V · diag(λ) · V^T
                let diag_matrix = Tensor::diag_embed(&evals_normed, 0, -2, -1);
                let rho_proj = evecs.matmul(&diag_matrix).matmul(&evecs.tr());

                projected.push(rho_proj.unsqueeze(0)); // [1, n, n]
            }
            drop(rho_tilde);

            let rho_next = Tensor::cat(&projected, 0); // [batch, n, n]
            drop(projected);

            // Return with original shape
            if is_batched {
                Ok(rho_next)
            } else {
                Ok(rho_next.squeeze_dim(0))
            }
        });
        result
    }

    /// Runs the full trajectory: `total_steps` iterations of geometric Euler-Maruyama.
    ///
    /// # Arguments
    /// * `rho_init` - Initial density matrix ([batch, n, n] or [n, n])
    /// * `config` - Solver configuration
    ///
    /// # Returns
    /// * `Ok(Tensor)` - Final state after all steps (same shape as input)
    pub fn solve(rho_init: &Tensor, config: &SolverConfig) -> Result<Tensor> {
        let mut rho = rho_init.shallow_clone();
        for _step in 0..config.total_steps {
            rho = Self::step(&rho, config)?;
        }
        Ok(rho)
    }

    /// Runs the full trajectory and returns ALL intermediate states.
    ///
    /// # Arguments
    /// * `rho_init` - Initial density matrix ([n, n] only, not batched)
    /// * `config` - Solver configuration
    ///
    /// # Returns
    /// * `Ok(Vec<Tensor>)` - Trajectory of states [ρ₀, ρ₁, ..., ρ_T]
    ///
    /// # Notes
    /// - Returns `total_steps + 1` tensors (includes initial state)
    /// - Useful for trajectory analysis and WORM attestation checkpoints
    pub fn solve_trajectory(rho_init: &Tensor, config: &SolverConfig) -> Result<Vec<Tensor>> {
        let mut trajectory = Vec::with_capacity(config.total_steps + 1);
        trajectory.push(rho_init.shallow_clone());

        let mut rho = rho_init.shallow_clone();
        for _step in 0..config.total_steps {
            rho = Self::step(&rho, config)?;
            trajectory.push(rho.shallow_clone());
        }
        Ok(trajectory)
    }

    /// Computes the Monte Carlo estimate of an observable over trajectories.
    ///
    /// # Arguments
    /// * `rho_init` - Initial state ([batch, n, n]) — each batch element is one trajectory
    /// * `config` - Solver configuration
    /// * `observable` - Observable matrix O (n×n, Hermitian)
    ///
    /// # Returns
    /// * `Ok(f64)` - Mean value ⟨O⟩ = (1/B) Σᵢ Tr[O · ρᵢ_final]
    pub fn monte_carlo_expectation(
        rho_init: &Tensor,
        config: &SolverConfig,
        observable: &Tensor,
    ) -> Result<f64> {
        let result = tch::no_grad(|| {
            // Evolve all trajectories
            let rho_final = Self::solve(rho_init, config)?;

            let batch = rho_final.size()[0];
            let n = rho_final.size()[1];

            // Compute Tr[O · ρ_i] for each trajectory
            // O · ρ: [batch, n, n] via broadcasting
            let obs_expanded = observable.unsqueeze(0).expand([batch, n, n], false);
            let product = obs_expanded.matmul(&rho_final); // [batch, n, n]

            // Trace per batch element
            let traces = product.diagonal(0, 1, 2).sum_dim_intlist([-1i64].as_slice(), false, Kind::Double);
            // traces: [batch]

            // Mean over batch
            let mean: f64 = traces.mean(Kind::Double).double_value(&[]);
            Ok(mean)
        });
        result
    }
}

/// Unit tests validating stochastic solver properties
#[cfg(test)]
mod tests {
    use super::*;

    /// Creates a batch of maximally mixed density matrices (I/n, trace=1)
    fn maximally_mixed_batch(batch: i64, n: i64, device: Device) -> Tensor {
        let eye = Tensor::eye(n, (Kind::Double, device)) / (n as f64);
        eye.unsqueeze(0).expand([batch, n, n], false).contiguous()
    }

    /// Creates a single maximally mixed state
    fn maximally_mixed(n: i64, device: Device) -> Tensor {
        Tensor::eye(n, (Kind::Double, device)) / (n as f64)
    }

    /// Creates a pure state |0><0|
    fn pure_state(n: i64, device: Device) -> Tensor {
        let mut rho = Tensor::zeros([n, n], (Kind::Double, device));
        let _ = rho.narrow(0, 0, 1).narrow(1, 0, 1).fill_(1.0);
        rho
    }

    #[test]
    fn test_manifold_preservation_trace() {
        let device = Device::Cpu;
        let config = SolverConfig::new(0.01, 0.1, 10);
        let rho_init = maximally_mixed(3, device);

        let rho_final = GeometricEulerMaruyama::solve(&rho_init, &config)
            .expect("Solver failed");

        let trace: f64 = rho_final.trace().double_value(&[]);
        assert!(
            (trace - 1.0).abs() < 1e-8,
            "Trace not preserved: got {trace}, expected 1.0"
        );
    }

    #[test]
    fn test_manifold_preservation_psd() {
        let device = Device::Cpu;
        let config = SolverConfig::new(0.01, 0.05, 10);
        let rho_init = maximally_mixed(4, device);

        let rho_final = GeometricEulerMaruyama::solve(&rho_init, &config)
            .expect("Solver failed");

        // All eigenvalues must be non-negative
        let (evals, _) = rho_final.linalg_eigh("L").expect("Eigendecomp failed");
        let min_eval: f64 = evals.min().double_value(&[]);
        assert!(
            min_eval >= -1e-10,
            "PSD violated: min eigenvalue = {min_eval}"
        );
    }

    #[test]
    fn test_manifold_preservation_hermitian() {
        let device = Device::Cpu;
        let config = SolverConfig::new(0.01, 0.1, 5);
        let rho_init = maximally_mixed(3, device);

        let rho_final = GeometricEulerMaruyama::solve(&rho_init, &config)
            .expect("Solver failed");

        // Must be symmetric (Hermitian for real matrices)
        assert!(
            BuresGeometry::is_symmetric(&rho_final, 1e-10),
            "Output not Hermitian/symmetric"
        );
    }

    #[test]
    fn test_zero_diffusion_deterministic() {
        let device = Device::Cpu;
        let config = SolverConfig::new(0.01, 0.0, 5); // D=0
        let rho_init = maximally_mixed(3, device);

        let rho_final = GeometricEulerMaruyama::solve(&rho_init, &config)
            .expect("Solver failed");

        let trace: f64 = rho_final.trace().double_value(&[]);
        assert!(
            (trace - 1.0).abs() < 1e-10,
            "Deterministic flow trace violated: {trace}"
        );

        // Maximally mixed is fixed point of entropy gradient → should stay near identity/n
        let expected = maximally_mixed(3, device);
        let diff: f64 = (&rho_final - &expected).abs().max().double_value(&[]);
        // For maximally mixed state, grad S = 0 → no drift → stays put
        assert!(
            diff < 1e-8,
            "Deterministic flow moved maximally mixed state: max diff = {diff}"
        );
    }

    #[test]
    fn test_batched_execution() {
        let device = Device::Cpu;
        let config = SolverConfig::new(0.005, 0.05, 3);
        let batch_size = 16i64;
        let n = 3i64;
        let rho_init = maximally_mixed_batch(batch_size, n, device);

        let rho_final = GeometricEulerMaruyama::solve(&rho_init, &config)
            .expect("Batched solver failed");

        assert_eq!(rho_final.size(), &[batch_size, n, n]);

        // Check trace preservation for all batch elements
        for i in 0..batch_size {
            let trace: f64 = rho_final.get(i).trace().double_value(&[]);
            assert!(
                (trace - 1.0).abs() < 1e-8,
                "Batch element {i}: trace = {trace}"
            );
        }
    }

    #[test]
    fn test_trajectory_length() {
        let device = Device::Cpu;
        let steps = 7;
        let config = SolverConfig::new(0.01, 0.0, steps);
        let rho_init = maximally_mixed(2, device);

        let trajectory = GeometricEulerMaruyama::solve_trajectory(&rho_init, &config)
            .expect("Trajectory failed");

        // Should have steps + 1 entries (includes initial state)
        assert_eq!(trajectory.len(), steps + 1);

        // All states should have trace=1
        for (i, state) in trajectory.iter().enumerate() {
            let trace: f64 = state.trace().double_value(&[]);
            assert!(
                (trace - 1.0).abs() < 1e-8,
                "Trajectory step {i}: trace = {trace}"
            );
        }
    }

    #[test]
    fn test_pure_state_evolution() {
        let device = Device::Cpu;
        let config = SolverConfig::new(0.005, 0.01, 5);
        let rho_init = pure_state(3, device);

        let rho_final = GeometricEulerMaruyama::solve(&rho_init, &config)
            .expect("Pure state evolution failed");

        // Should still be a valid density matrix
        let trace: f64 = rho_final.trace().double_value(&[]);
        assert!((trace - 1.0).abs() < 1e-8, "Trace violated: {trace}");

        let (evals, _) = rho_final.linalg_eigh("L").unwrap();
        let min_eval: f64 = evals.min().double_value(&[]);
        assert!(min_eval >= -1e-10, "PSD violated: min eval = {min_eval}");
    }

    #[test]
    fn test_precision_enforcement() {
        let config = SolverConfig::new(0.01, 0.1, 1);
        let rho_f32 = Tensor::eye(3, (Kind::Float, Device::Cpu)) / 3.0f64;

        assert!(matches!(
            GeometricEulerMaruyama::step(&rho_f32, &config),
            Err(StochasticError::PrecisionError)
        ));
    }

    #[test]
    #[should_panic(expected = "dt must be positive")]
    fn test_config_negative_dt() {
        SolverConfig::new(-0.01, 0.1, 10);
    }

    #[test]
    #[should_panic(expected = "diffusion must be non-negative")]
    fn test_config_negative_diffusion() {
        SolverConfig::new(0.01, -0.1, 10);
    }
}
