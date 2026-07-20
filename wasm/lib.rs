// BOB Quantum Civilization Engine — WASM Bridge
// Ports the math from bob_*.f90 to Rust/WASM for browser execution
// Mirrors: bob_kinds, bob_state, bob_lattice, bob_metrics, bob_measurement, bob_hamiltonian, bob_integrator

use wasm_bindgen::prelude::*;
use serde::{Deserialize, Serialize};
use std::f64::consts::PI;

// ── CONSTANTS (mirrors bob_kinds.f90) ──────────────────────────────────────
const HBAR: f64 = 1.054_571_817e-34;
const NORM_TOL: f64 = 1e-10;

// ── COMPLEX ARITHMETIC ─────────────────────────────────────────────────────
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
pub struct C64 {
    pub re: f64,
    pub im: f64,
}

impl C64 {
    pub fn new(re: f64, im: f64) -> Self { Self { re, im } }
    pub fn zero() -> Self { Self { re: 0.0, im: 0.0 } }
    pub fn one()  -> Self { Self { re: 1.0, im: 0.0 } }
    pub fn i()    -> Self { Self { re: 0.0, im: 1.0 } }

    pub fn norm_sq(&self) -> f64 { self.re * self.re + self.im * self.im }
    pub fn norm(&self) -> f64 { self.norm_sq().sqrt() }
    pub fn conj(&self) -> Self { Self { re: self.re, im: -self.im } }
    pub fn phase(&self) -> f64 { self.im.atan2(self.re) }

    pub fn add(&self, o: &Self) -> Self { Self::new(self.re + o.re, self.im + o.im) }
    pub fn sub(&self, o: &Self) -> Self { Self::new(self.re - o.re, self.im - o.im) }
    pub fn mul(&self, o: &Self) -> Self {
        Self::new(self.re * o.re - self.im * o.im, self.re * o.im + self.im * o.re)
    }
    pub fn scale(&self, s: f64) -> Self { Self::new(self.re * s, self.im * s) }
    pub fn exp_i(theta: f64) -> Self { Self::new(theta.cos(), theta.sin()) }
}

// ── QUANTUM STATE (mirrors bob_state.f90) ──────────────────────────────────
// |ψ⟩ ∈ ℂ^n, n = 2^num_qubits
#[wasm_bindgen]
pub struct QuantumState {
    amplitudes: Vec<C64>,
    num_qubits: usize,
}

#[wasm_bindgen]
impl QuantumState {
    #[wasm_bindgen(constructor)]
    pub fn new(num_qubits: usize) -> Self {
        let n = 1usize << num_qubits;
        let mut amplitudes = vec![C64::zero(); n];
        amplitudes[0] = C64::one(); // |0...0⟩
        Self { amplitudes, num_qubits }
    }

    pub fn num_qubits(&self) -> usize { self.num_qubits }
    pub fn dimension(&self) -> usize { self.amplitudes.len() }

    // Norm: ||ψ|| = sqrt(Σ|ψ_i|²)
    pub fn norm(&self) -> f64 {
        self.amplitudes.iter().map(|a| a.norm_sq()).sum::<f64>().sqrt()
    }

    // Normalize in place: |ψ⟩ → |ψ⟩/||ψ||
    pub fn normalize(&mut self) -> bool {
        let n = self.norm();
        if n < NORM_TOL { return false; }
        for a in &mut self.amplitudes { *a = a.scale(1.0 / n); }
        true
    }

    // Probability of measuring basis state i: |ψ_i|²
    pub fn probability(&self, i: usize) -> f64 {
        if i >= self.amplitudes.len() { return 0.0; }
        self.amplitudes[i].norm_sq()
    }

    // Real part of amplitude i
    pub fn amplitude_re(&self, i: usize) -> f64 {
        if i >= self.amplitudes.len() { 0.0 } else { self.amplitudes[i].re }
    }

    // Imaginary part of amplitude i
    pub fn amplitude_im(&self, i: usize) -> f64 {
        if i >= self.amplitudes.len() { 0.0 } else { self.amplitudes[i].im }
    }

    // Set amplitude
    pub fn set_amplitude(&mut self, i: usize, re: f64, im: f64) {
        if i < self.amplitudes.len() {
            self.amplitudes[i] = C64::new(re, im);
        }
    }

    // Clone into new state
    pub fn clone_state(&self) -> QuantumState {
        QuantumState {
            amplitudes: self.amplitudes.clone(),
            num_qubits: self.num_qubits,
        }
    }
}

// ── GATES (mirrors bob_gates.f90) ──────────────────────────────────────────
// Apply single-qubit gate (2x2 unitary) to qubit k of |ψ⟩
fn apply_single_qubit_gate(state: &mut QuantumState, k: usize, u: [[C64; 2]; 2]) {
    let n = state.amplitudes.len();
    let block = 1usize << k;
    let stride = block << 1;
    let mut i = 0;
    while i < n {
        for j in i..i+block {
            let a = state.amplitudes[j];
            let b = state.amplitudes[j + block];
            state.amplitudes[j]       = u[0][0].mul(&a).add(&u[0][1].mul(&b));
            state.amplitudes[j+block] = u[1][0].mul(&a).add(&u[1][1].mul(&b));
        }
        i += stride;
    }
}

#[wasm_bindgen]
pub fn apply_hadamard(state: &mut QuantumState, qubit: usize) {
    let s = 1.0 / 2.0_f64.sqrt();
    let u = [
        [C64::new(s, 0.0), C64::new(s, 0.0)],
        [C64::new(s, 0.0), C64::new(-s, 0.0)],
    ];
    apply_single_qubit_gate(state, qubit, u);
}

#[wasm_bindgen]
pub fn apply_pauli_x(state: &mut QuantumState, qubit: usize) {
    let u = [[C64::zero(), C64::one()], [C64::one(), C64::zero()]];
    apply_single_qubit_gate(state, qubit, u);
}

#[wasm_bindgen]
pub fn apply_pauli_y(state: &mut QuantumState, qubit: usize) {
    let u = [
        [C64::zero(), C64::new(0.0, -1.0)],
        [C64::new(0.0, 1.0), C64::zero()],
    ];
    apply_single_qubit_gate(state, qubit, u);
}

#[wasm_bindgen]
pub fn apply_pauli_z(state: &mut QuantumState, qubit: usize) {
    let u = [[C64::one(), C64::zero()], [C64::zero(), C64::new(-1.0, 0.0)]];
    apply_single_qubit_gate(state, qubit, u);
}

// Phase gate: R(θ) = [[1,0],[0,e^iθ]]
#[wasm_bindgen]
pub fn apply_phase(state: &mut QuantumState, qubit: usize, theta: f64) {
    let u = [[C64::one(), C64::zero()], [C64::zero(), C64::exp_i(theta)]];
    apply_single_qubit_gate(state, qubit, u);
}

// T gate: phase π/4
#[wasm_bindgen]
pub fn apply_t_gate(state: &mut QuantumState, qubit: usize) {
    apply_phase(state, qubit, PI / 4.0);
}

// S gate: phase π/2
#[wasm_bindgen]
pub fn apply_s_gate(state: &mut QuantumState, qubit: usize) {
    apply_phase(state, qubit, PI / 2.0);
}

// CNOT: control qubit c, target qubit t
#[wasm_bindgen]
pub fn apply_cnot(state: &mut QuantumState, control: usize, target: usize) {
    let n = state.amplitudes.len();
    for i in 0..n {
        if (i >> control) & 1 == 1 {
            let j = i ^ (1 << target);
            if j > i {
                let tmp = state.amplitudes[i];
                state.amplitudes[i] = state.amplitudes[j];
                state.amplitudes[j] = tmp;
            }
        }
    }
}

// ── METRICS (mirrors bob_metrics.f90) ─────────────────────────────────────
#[derive(Serialize, Deserialize)]
pub struct QuantumMetrics {
    pub norm: f64,
    pub energy: f64,
    pub purity: f64,
    pub von_neumann_entropy: f64,
    pub linear_entropy: f64,
    pub coherence: f64,
    pub participation_ratio: f64,
}

#[wasm_bindgen]
pub fn compute_metrics(state: &QuantumState) -> JsValue {
    let probs: Vec<f64> = (0..state.dimension()).map(|i| state.probability(i)).collect();
    let norm = probs.iter().sum::<f64>().sqrt();

    // Purity: Tr(ρ²) = Σ p_i² (diagonal ρ)
    let purity: f64 = probs.iter().map(|p| p * p).sum();

    // Von Neumann entropy: -Σ p_i log(p_i)
    let von_neumann_entropy: f64 = probs.iter()
        .filter(|&&p| p > 1e-15)
        .map(|&p| -p * p.ln())
        .sum();

    // Linear entropy: 1 - Tr(ρ²)
    let linear_entropy = 1.0 - purity;

    // L1 coherence: Σ_{i≠j} |ρ_ij| — for pure state ρ = |ψ⟩⟨ψ|
    // coherence = Σ_{i≠j} |ψ_i||ψ_j| = (Σ|ψ_i|)² - Σ|ψ_i|²
    let sum_amps: f64 = state.amplitudes.iter().map(|a| a.norm()).sum();
    let sum_sq: f64 = state.amplitudes.iter().map(|a| a.norm_sq()).sum();
    let coherence = (sum_amps * sum_amps - sum_sq).max(0.0);

    // Participation ratio (inverse): 1 / Σ p_i²
    let participation_ratio = if purity > 1e-15 { 1.0 / purity } else { 0.0 };

    // Energy = Σ i * p_i (eigenvalue ladder, classical sim of diagonal H)
    let energy: f64 = probs.iter().enumerate()
        .map(|(i, p)| i as f64 * p)
        .sum();

    let m = QuantumMetrics { norm, energy, purity, von_neumann_entropy, linear_entropy, coherence, participation_ratio };
    serde_wasm_bindgen::to_value(&m).unwrap_or(JsValue::NULL)
}

// ── VORTEX LATTICE (mirrors bob_lattice.f90) ────────────────────────────────
#[derive(Clone, Serialize, Deserialize)]
pub struct Vortex {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub winding: i32,       // topological charge ∈ {-2,-1,0,1,2}
    pub phase: f64,         // quantum phase θ ∈ [0, 2π)
    pub energy: f64,        // local energy
    pub coherence: f64,     // local coherence with neighbors
}

#[wasm_bindgen]
pub struct VortexLattice {
    vortices: Vec<Vortex>,
    nx: usize,
    ny: usize,
    coupling: f64,
    time: f64,
    dt: f64,
}

#[wasm_bindgen]
impl VortexLattice {
    #[wasm_bindgen(constructor)]
    pub fn new(nx: usize, ny: usize, coupling: f64, dt: f64) -> Self {
        let n = nx * ny;
        let mut vortices = Vec::with_capacity(n);
        for iy in 0..ny {
            for ix in 0..nx {
                // Initialize with random-ish phases using deterministic seed
                let seed = (ix * 7 + iy * 13) as f64;
                let phase = (seed * 1.618033988).fract() * 2.0 * PI;
                let winding = if (ix + iy) % 7 == 0 { 1 } else if (ix * iy) % 11 == 0 { -1 } else { 0 };
                vortices.push(Vortex {
                    x: ix as f64,
                    y: iy as f64,
                    z: ((ix as f64 * 0.3 + iy as f64 * 0.5).sin() * 0.5 + 0.5),
                    winding,
                    phase,
                    energy: winding.abs() as f64 * 0.5 + (phase * 0.3).cos() * 0.2,
                    coherence: 1.0,
                });
            }
        }
        Self { vortices, nx, ny, coupling, time: 0.0, dt }
    }

    pub fn num_vortices(&self) -> usize { self.vortices.len() }
    pub fn time(&self) -> f64 { self.time }

    // Evolve lattice: Josephson coupling between nearest neighbors
    // dθ_i/dt = -coupling * Σ_j sin(θ_i - θ_j) — discrete Gross-Pitaevskii
    pub fn evolve(&mut self, steps: usize) {
        for _ in 0..steps {
            let old = self.vortices.clone();
            for iy in 0..self.ny {
                for ix in 0..self.nx {
                    let idx = iy * self.nx + ix;
                    let mut dphase = 0.0;
                    let mut total_coherence = 0.0;
                    let mut neighbor_count = 0;

                    // Nearest neighbors (periodic boundary)
                    let neighbors = [
                        ((ix + 1) % self.nx, iy),
                        ((ix + self.nx - 1) % self.nx, iy),
                        (ix, (iy + 1) % self.ny),
                        (ix, (iy + self.ny - 1) % self.ny),
                    ];

                    for (nx2, ny2) in neighbors {
                        let nidx = ny2 * self.nx + nx2;
                        let dphi = old[idx].phase - old[nidx].phase;
                        dphase -= self.coupling * dphi.sin();
                        total_coherence += dphi.cos();
                        neighbor_count += 1;
                    }

                    let v = &mut self.vortices[idx];
                    v.phase = (old[idx].phase + self.dt * dphase).rem_euclid(2.0 * PI);
                    v.coherence = if neighbor_count > 0 { (total_coherence / neighbor_count as f64 + 1.0) * 0.5 } else { 1.0 };
                    v.energy = v.winding.abs() as f64 * 0.5
                        + self.coupling * (1.0 - v.coherence)
                        + (self.time * 0.1).sin() * 0.05;
                }
            }
            self.time += self.dt;

            // Phase transition: occasionally flip winding numbers
            if (self.time * 10.0) as usize % 50 == 0 {
                let flip_idx = (self.time * 97.3) as usize % self.vortices.len();
                self.vortices[flip_idx].winding = match self.vortices[flip_idx].winding {
                    0 => 1, 1 => -1, -1 => 0, _ => 0,
                };
            }
        }
    }

    // Return vortex data as flat arrays for JS canvas rendering
    pub fn vortex_x(&self, i: usize) -> f64 { self.vortices[i].x }
    pub fn vortex_y(&self, i: usize) -> f64 { self.vortices[i].y }
    pub fn vortex_phase(&self, i: usize) -> f64 { self.vortices[i].phase }
    pub fn vortex_winding(&self, i: usize) -> i32 { self.vortices[i].winding }
    pub fn vortex_energy(&self, i: usize) -> f64 { self.vortices[i].energy }
    pub fn vortex_coherence(&self, i: usize) -> f64 { self.vortices[i].coherence }

    // Global metrics
    pub fn total_energy(&self) -> f64 {
        self.vortices.iter().map(|v| v.energy).sum()
    }
    pub fn mean_coherence(&self) -> f64 {
        let s: f64 = self.vortices.iter().map(|v| v.coherence).sum();
        s / self.vortices.len() as f64
    }
    pub fn topological_charge(&self) -> i32 {
        self.vortices.iter().map(|v| v.winding).sum()
    }
    pub fn vortex_count(&self) -> i32 {
        self.vortices.iter().filter(|v| v.winding != 0).count() as i32
    }
}

// ── HAMILTONIAN (mirrors bob_hamiltonian.f90) ──────────────────────────────
// Ising Hamiltonian: H = -J Σ σ_i^z σ_j^z - h Σ σ_i^x
// Applied via Trotter decomposition for time evolution
#[wasm_bindgen]
pub struct IsingHamiltonian {
    num_qubits: usize,
    j: f64,   // coupling
    h: f64,   // transverse field
}

#[wasm_bindgen]
impl IsingHamiltonian {
    #[wasm_bindgen(constructor)]
    pub fn new(num_qubits: usize, j: f64, h: f64) -> Self {
        Self { num_qubits, j, h }
    }

    // Trotter step: e^{-iHdt} ≈ e^{-iH_z dt/2} e^{-iH_x dt} e^{-iH_z dt/2}
    // H_z = -J Σ σ_i^z σ_j^z  →  diagonal, applies phase to each pair
    // H_x = -h Σ σ_i^x         →  single-qubit rotations
    pub fn trotter_step(&self, state: &mut QuantumState, dt: f64) {
        let nq = self.num_qubits;

        // ZZ coupling: apply phase e^{iJ dt/2 σ_i^z σ_j^z} to nearest-neighbor pairs
        let n = state.dimension();
        for i in 0..n {
            let mut phase_sum = 0.0;
            for q in 0..nq-1 {
                let si = if (i >> q) & 1 == 1 { 1.0_f64 } else { -1.0_f64 };
                let sj = if (i >> (q+1)) & 1 == 1 { 1.0_f64 } else { -1.0_f64 };
                phase_sum += si * sj;
            }
            let p = C64::exp_i(self.j * dt * 0.5 * phase_sum);
            state.amplitudes[i] = state.amplitudes[i].mul(&p);
        }

        // X rotations: R_x(-2h*dt) on each qubit
        let theta = self.h * dt;
        for q in 0..nq {
            let c = theta.cos();
            let s = theta.sin();
            let u = [
                [C64::new(c, 0.0), C64::new(0.0, -s)],
                [C64::new(0.0, -s), C64::new(c, 0.0)],
            ];
            apply_single_qubit_gate(state, q, u);
        }

        // ZZ coupling second half
        for i in 0..n {
            let mut phase_sum = 0.0;
            for q in 0..nq-1 {
                let si = if (i >> q) & 1 == 1 { 1.0_f64 } else { -1.0_f64 };
                let sj = if (i >> (q+1)) & 1 == 1 { 1.0_f64 } else { -1.0_f64 };
                phase_sum += si * sj;
            }
            let p = C64::exp_i(self.j * dt * 0.5 * phase_sum);
            state.amplitudes[i] = state.amplitudes[i].mul(&p);
        }
    }

    // Energy expectation ⟨ψ|H|ψ⟩
    pub fn energy_expectation(&self, state: &QuantumState) -> f64 {
        let nq = self.num_qubits;
        let n = state.dimension();
        let mut e = 0.0_f64;

        // ZZ terms: -J Σ ⟨σ_i^z σ_j^z⟩ = -J Σ_k p_k * sz_i(k) * sz_j(k)
        for k in 0..n {
            let p = state.probability(k);
            for q in 0..nq-1 {
                let si = if (k >> q) & 1 == 1 { 1.0_f64 } else { -1.0_f64 };
                let sj = if (k >> (q+1)) & 1 == 1 { 1.0_f64 } else { -1.0_f64 };
                e -= self.j * p * si * sj;
            }
        }

        // X terms: -h Σ ⟨σ_i^x⟩ — off-diagonal, requires amplitude sums
        for q in 0..nq {
            for k in 0..n {
                let flip = k ^ (1 << q);
                let re_part = state.amplitudes[k].conj().mul(&state.amplitudes[flip]).re;
                e -= self.h * re_part;
            }
        }

        e
    }
}

// ── MEASUREMENT (mirrors bob_measurement.f90) ──────────────────────────────
// Measure qubit k — collapses state, returns 0 or 1
// Uses a simple LFSR for deterministic pseudorandomness (no external RNG dep)
#[wasm_bindgen]
pub struct Rng { state: u64 }

#[wasm_bindgen]
impl Rng {
    #[wasm_bindgen(constructor)]
    pub fn new(seed: u64) -> Self { Self { state: if seed == 0 { 1 } else { seed } } }

    pub fn next_f64(&mut self) -> f64 {
        // xorshift64
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        (self.state as f64) / (u64::MAX as f64)
    }
}

#[wasm_bindgen]
pub fn measure_qubit(state: &mut QuantumState, qubit: usize, rng: &mut Rng) -> u32 {
    // P(1) = Σ_{i: bit k=1} |ψ_i|²
    let p1: f64 = (0..state.dimension())
        .filter(|&i| (i >> qubit) & 1 == 1)
        .map(|i| state.probability(i))
        .sum();

    let outcome = if rng.next_f64() < p1 { 1u32 } else { 0u32 };

    // Collapse: zero out incompatible amplitudes, renormalize
    for i in 0..state.dimension() {
        if (i >> qubit) & 1 != outcome as usize {
            state.amplitudes[i] = C64::zero();
        }
    }
    state.normalize();
    outcome
}

// ── TIME INTEGRATOR (mirrors bob_integrator.f90) ────────────────────────────
// Runge-Kutta 4 for Schrödinger equation: iℏ d|ψ⟩/dt = H|ψ⟩
// For Trotter we use the Hamiltonian's own step method
#[wasm_bindgen]
pub fn evolve_state(state: &mut QuantumState, ham: &IsingHamiltonian, dt: f64, steps: usize) {
    for _ in 0..steps {
        ham.trotter_step(state, dt);
    }
    state.normalize();
}

// ── SIMULATION (full engine: mirrors bob_abi.f90 aggregate functions) ───────
#[wasm_bindgen]
pub struct Simulation {
    state: QuantumState,
    ham: IsingHamiltonian,
    lattice: VortexLattice,
    rng: Rng,
    pub time: f64,
    pub dt: f64,
    pub step_count: u64,
}

#[wasm_bindgen]
impl Simulation {
    #[wasm_bindgen(constructor)]
    pub fn new(num_qubits: usize, lattice_n: usize, j: f64, h: f64, coupling: f64, dt: f64, seed: u64) -> Self {
        let mut state = QuantumState::new(num_qubits);
        // Superposition init: apply Hadamard to all qubits
        for q in 0..num_qubits {
            apply_hadamard(&mut state, q);
        }
        Self {
            state,
            ham: IsingHamiltonian::new(num_qubits, j, h),
            lattice: VortexLattice::new(lattice_n, lattice_n, coupling, dt),
            rng: Rng::new(seed),
            time: 0.0,
            dt,
            step_count: 0,
        }
    }

    pub fn step(&mut self) {
        // Evolve quantum state
        self.ham.trotter_step(&mut self.state, self.dt);
        self.state.normalize();
        // Evolve vortex lattice
        self.lattice.evolve(1);
        self.time += self.dt;
        self.step_count += 1;
    }

    pub fn step_n(&mut self, n: usize) {
        for _ in 0..n { self.step(); }
    }

    // Metrics
    pub fn state_energy(&self) -> f64 { self.ham.energy_expectation(&self.state) }
    pub fn lattice_energy(&self) -> f64 { self.lattice.total_energy() }
    pub fn mean_coherence(&self) -> f64 { self.lattice.mean_coherence() }
    pub fn topological_charge(&self) -> i32 { self.lattice.topological_charge() }
    pub fn vortex_count(&self) -> i32 { self.lattice.vortex_count() }
    pub fn state_norm(&self) -> f64 { self.state.norm() }

    // Von Neumann entropy of quantum state
    pub fn entropy(&self) -> f64 {
        (0..self.state.dimension())
            .map(|i| self.state.probability(i))
            .filter(|&p| p > 1e-15)
            .map(|p| -p * p.ln())
            .sum()
    }

    // State amplitude accessors for visualization
    pub fn state_dim(&self) -> usize { self.state.dimension() }
    pub fn state_prob(&self, i: usize) -> f64 { self.state.probability(i) }
    pub fn state_phase(&self, i: usize) -> f64 {
        self.state.amplitudes[i].phase()
    }

    // Lattice accessors
    pub fn num_vortices(&self) -> usize { self.lattice.num_vortices() }
    pub fn vortex_x(&self, i: usize) -> f64 { self.lattice.vortex_x(i) }
    pub fn vortex_y(&self, i: usize) -> f64 { self.lattice.vortex_y(i) }
    pub fn vortex_phase(&self, i: usize) -> f64 { self.lattice.vortex_phase(i) }
    pub fn vortex_winding(&self, i: usize) -> i32 { self.lattice.vortex_winding(i) }
    pub fn vortex_energy(&self, i: usize) -> f64 { self.lattice.vortex_energy(i) }
    pub fn vortex_coherence(&self, i: usize) -> f64 { self.lattice.vortex_coherence(i) }

    // Measure qubit k, collapse state
    pub fn measure(&mut self, qubit: usize) -> u32 {
        measure_qubit(&mut self.state, qubit, &mut self.rng)
    }

    // Lattice dimensions
    pub fn lattice_nx(&self) -> usize { self.lattice.nx }
    pub fn lattice_ny(&self) -> usize { self.lattice.ny }
}

// ── ENGINE INFO ────────────────────────────────────────────────────────────
#[wasm_bindgen]
pub fn engine_version() -> String {
    "BOB Quantum Civilization Engine v1.0.0 — Rust/WASM port of bob_*.f90".to_string()
}

#[wasm_bindgen]
pub fn engine_modules() -> String {
    "bob_kinds | bob_errors | bob_rng | bob_state | bob_gates | bob_lattice | bob_measurement | bob_hamiltonian | bob_integrator | bob_metrics | bob_abi".to_string()
}
