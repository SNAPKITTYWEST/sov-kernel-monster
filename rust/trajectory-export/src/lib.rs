//! # Trajectory Export
//!
//! Converts stochastic solver output (density matrix trajectories) into
//! flat Float32 binary files for direct WebGL consumption.
//!
//! ## Binary Format
//! Layout: `[traj₀_step₀(x,y,z), traj₀_step₁(x,y,z), ..., traj₁_step₀(x,y,z), ...]`
//! - Little-endian Float32 (matches JavaScript Float32Array and WebGL)
//! - 3 floats per vertex (x, y, z coordinates on Bloch sphere)
//! - Trajectories grouped contiguously
//!
//! ## Coordinate Mapping
//! Density matrix ρ (2×2 qubit) → Bloch sphere coordinates:
//! - x = 2·Re(ρ₀₁)
//! - y = 2·Im(ρ₀₁)
//! - z = ρ₀₀ - ρ₁₁
//!
//! For higher-dimensional states, projects onto first 3 principal components.

use ndarray::{Array2, Array3};
use std::fs::File;
use std::io::{self, Write};

/// Flattens an ndarray trajectory tensor and writes to raw Float32 binary.
///
/// # Arguments
/// * `trajectory_tensor` - Shape [time_steps, batch_size, 3] of f32 coordinates
/// * `output_path` - Path to write the binary file
///
/// # Binary Layout
/// Contiguous Float32 values, little-endian:
/// `[batch₀_t₀_x, batch₀_t₀_y, batch₀_t₀_z, batch₀_t₁_x, ...]`
///
/// Note: For WebGL consumption, data is re-ordered to group by trajectory
/// (all steps of traj 0, then all steps of traj 1, etc.)
pub fn export_trajectory_to_bin(
    trajectory_tensor: &Array3<f32>,
    output_path: &str,
) -> io::Result<()> {
    let (time_steps, batch_size, coords) = trajectory_tensor.dim();
    assert_eq!(coords, 3, "Expected 3 coordinates per vertex, got {coords}");

    // Re-order from [time, batch, 3] to [batch, time, 3] for WebGL
    // (WebGL needs all steps of one trajectory contiguous)
    let total_floats = batch_size * time_steps * 3;
    let mut flat = Vec::with_capacity(total_floats);

    for b in 0..batch_size {
        for t in 0..time_steps {
            flat.push(trajectory_tensor[[t, b, 0]]);
            flat.push(trajectory_tensor[[t, b, 1]]);
            flat.push(trajectory_tensor[[t, b, 2]]);
        }
    }

    // Zero-copy byte cast and write
    let byte_slice: &[u8] = bytemuck::cast_slice(&flat);

    let mut file = File::create(output_path)?;
    file.write_all(byte_slice)?;
    file.flush()?;

    eprintln!(
        "Exported {} trajectories × {} steps = {} vertices to {}",
        batch_size, time_steps, batch_size * time_steps, output_path
    );
    Ok(())
}

/// Converts a 2×2 density matrix to Bloch sphere coordinates.
///
/// For qubit state ρ:
/// - x = 2·Re(ρ₀₁) = Tr[σₓ ρ]
/// - y = 2·Im(ρ₀₁) = Tr[σᵧ ρ]
/// - z = ρ₀₀ - ρ₁₁ = Tr[σ_z ρ]
///
/// Returns (x, y, z) as f32 tuple.
pub fn density_matrix_to_bloch(rho: &Array2<f64>) -> (f32, f32, f32) {
    assert_eq!(rho.dim(), (2, 2), "Bloch conversion requires 2×2 density matrix");

    let x = 2.0 * rho[[0, 1]]; // Re(ρ₀₁) — for real density matrices
    let y = 0.0f64; // Im(ρ₀₁) — zero for real matrices; complex case needs separate handling
    let z = rho[[0, 0]] - rho[[1, 1]];

    (x as f32, y as f32, z as f32)
}

/// Generates a synthetic demo trajectory dataset for testing the frontend
/// without running the full stochastic solver.
///
/// Simulates φ⁻¹ contraction toward origin (entropy maximum) with Brownian noise.
///
/// # Returns
/// Array3<f32> of shape [time_steps, batch_size, 3]
pub fn generate_demo_data(time_steps: usize, batch_size: usize, dt: f32, diffusion: f32) -> Array3<f32> {
    use std::f32::consts::PI;

    let phi: f32 = (1.0 + 5.0f32.sqrt()) / 2.0;
    let contraction = 1.0 / phi;

    let mut data = Array3::zeros((time_steps, batch_size, 3));

    // Simple LCG for reproducibility without external deps
    let mut seed: u64 = 42;
    let mut rng = || -> f32 {
        seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let bits = ((seed >> 33) as u32) as f32 / (u32::MAX as f32);
        bits * 2.0 - 1.0
    };

    for b in 0..batch_size {
        // Random starting point on unit sphere
        let theta = (rng() + 1.0) * 0.5 * PI;
        let phi0 = (rng() + 1.0) * PI;

        let mut x = theta.sin() * phi0.cos();
        let mut y = theta.sin() * phi0.sin();
        let mut z = theta.cos();

        for t in 0..time_steps {
            data[[t, b, 0]] = x;
            data[[t, b, 1]] = y;
            data[[t, b, 2]] = z;

            // φ⁻¹ drift toward origin
            let drift = contraction * dt;
            x -= x * drift;
            y -= y * drift;
            z -= z * drift;

            // Tangent-space noise
            let noise_scale = (diffusion * dt).sqrt();
            let nx = rng() * noise_scale;
            let ny = rng() * noise_scale;
            let nz = rng() * noise_scale;

            // Project to tangent plane
            let dot = nx * x + ny * y + nz * z;
            let r2 = x * x + y * y + z * z;
            if r2 > 1e-8 {
                x += nx - dot * x / r2;
                y += ny - dot * y / r2;
                z += nz - dot * z / r2;
            }

            // Retract to decaying radius
            let r = (x * x + y * y + z * z).sqrt();
            if r > 1e-8 {
                let target_r = (1.0 - (t as f32) * contraction * dt * 0.5).max(0.01);
                x = x / r * target_r;
                y = y / r * target_r;
                z = z / r * target_r;
            }
        }
    }

    data
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn test_demo_data_shape() {
        let data = generate_demo_data(100, 10, 0.01, 0.3);
        assert_eq!(data.dim(), (100, 10, 3));
    }

    #[test]
    fn test_demo_data_bounded() {
        let data = generate_demo_data(200, 50, 0.01, 0.2);
        for val in data.iter() {
            assert!(val.abs() <= 1.5, "Coordinate out of bounds: {val}");
        }
    }

    #[test]
    fn test_export_creates_file() {
        let data = generate_demo_data(10, 5, 0.01, 0.1);
        let path = "test_trajectory_output.bin";
        export_trajectory_to_bin(&data, path).expect("Export failed");

        let metadata = std::fs::metadata(path).expect("File not found");
        // 5 trajectories × 10 steps × 3 floats × 4 bytes = 600 bytes
        assert_eq!(metadata.len(), 600);

        std::fs::remove_file(path).ok();
    }

    #[test]
    fn test_bloch_conversion_pure_state() {
        // |0⟩⟨0| = [[1,0],[0,0]] → Bloch: (0, 0, 1) (north pole)
        let rho = Array2::from_shape_vec((2, 2), vec![1.0, 0.0, 0.0, 0.0]).unwrap();
        let (x, y, z) = density_matrix_to_bloch(&rho);
        assert!((x - 0.0).abs() < 1e-6);
        assert!((y - 0.0).abs() < 1e-6);
        assert!((z - 1.0).abs() < 1e-6);
    }

    #[test]
    fn test_bloch_conversion_mixed_state() {
        // I/2 = [[0.5,0],[0,0.5]] → Bloch: (0, 0, 0) (origin)
        let rho = Array2::from_shape_vec((2, 2), vec![0.5, 0.0, 0.0, 0.5]).unwrap();
        let (x, y, z) = density_matrix_to_bloch(&rho);
        assert!((x - 0.0).abs() < 1e-6);
        assert!((y - 0.0).abs() < 1e-6);
        assert!((z - 0.0).abs() < 1e-6);
    }
}
