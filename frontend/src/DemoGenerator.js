/**
 * Generates synthetic trajectory data for demo/testing without a Rust backend.
 * Simulates geometric Euler-Maruyama diffusion on a Bloch sphere.
 *
 * Produces the same binary layout as the Rust trajectory-export crate:
 * Float32Array of [x,y,z] coordinates, trajectories grouped contiguously.
 */

/**
 * Generate synthetic Bloch sphere trajectory data.
 * Simulates dρₜ = -∇S dt + √D dWₜ projected onto the sphere surface.
 *
 * @param {number} numTrajectories - Number of parallel paths (e.g., 1000)
 * @param {number} numSteps - Time steps per trajectory (e.g., 500)
 * @param {number} dt - Time step size
 * @param {number} diffusion - Noise coefficient D
 * @returns {ArrayBuffer} Raw binary data matching Rust export format
 */
export function generateDemoTrajectories(numTrajectories = 1000, numSteps = 500, dt = 0.01, diffusion = 0.3) {
    const totalFloats = numTrajectories * numSteps * 3;
    const data = new Float32Array(totalFloats);

    const phi = (1 + Math.sqrt(5)) / 2; // Golden ratio φ
    const contraction = 1 / phi; // φ⁻¹ ≈ 0.618

    for (let b = 0; b < numTrajectories; b++) {
        // Random starting point on sphere surface
        const theta0 = Math.random() * Math.PI;
        const phi0 = Math.random() * 2 * Math.PI;

        let x = Math.sin(theta0) * Math.cos(phi0);
        let y = Math.sin(theta0) * Math.sin(phi0);
        let z = Math.cos(theta0);

        const baseIdx = b * numSteps * 3;

        for (let t = 0; t < numSteps; t++) {
            const idx = baseIdx + t * 3;

            // Store current position
            data[idx] = x;
            data[idx + 1] = y;
            data[idx + 2] = z;

            // Drift: contract toward maximally mixed state (origin) with φ⁻¹ rate
            // This models -∇S driving toward entropy maximum
            const driftScale = contraction * dt;
            const dx_drift = -x * driftScale;
            const dy_drift = -y * driftScale;
            const dz_drift = -z * driftScale;

            // Wiener noise in tangent space (project random vector onto tangent plane)
            const noiseScale = Math.sqrt(diffusion * dt);
            let nx = gaussianRandom() * noiseScale;
            let ny = gaussianRandom() * noiseScale;
            let nz = gaussianRandom() * noiseScale;

            // Project noise onto tangent plane at (x,y,z):
            // n_tangent = n - (n·r)r where r = (x,y,z) is the radial unit vector
            const dot = nx * x + ny * y + nz * z;
            nx -= dot * x;
            ny -= dot * y;
            nz -= dot * z;

            // Update position
            x += dx_drift + nx;
            y += dy_drift + ny;
            z += dz_drift + nz;

            // Retract to sphere surface (normalize)
            const r = Math.sqrt(x * x + y * y + z * z);
            if (r > 1e-8) {
                // Bloch sphere radius decays with entropy growth
                // Pure states live on surface (r=1), maximally mixed at origin (r=0)
                const targetRadius = Math.max(0.01, 1.0 - t * contraction * dt * 0.5);
                x = (x / r) * targetRadius;
                y = (y / r) * targetRadius;
                z = (z / r) * targetRadius;
            }
        }
    }

    return data.buffer;
}

/**
 * Box-Muller transform for Gaussian random numbers.
 */
function gaussianRandom() {
    let u = 0, v = 0;
    while (u === 0) u = Math.random();
    while (v === 0) v = Math.random();
    return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
}
