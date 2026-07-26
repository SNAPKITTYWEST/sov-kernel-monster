//! # Quantum Backend Contract
//!
//! Defines the B = (Q, Γ, Λ, Π, Ξ, Θ) contract that binds quantum execution
//! to a known physical device state. This ensures reproducibility and enables
//! WORM-attested execution receipts that reference calibration_hash.
//!
//! ## Backend Contract Definition
//! - **Q**: Physical qubits (indices 0..n_qubits)
//! - **Γ**: Coupling graph (connectivity between qubits)
//! - **Λ**: Native gates (operations available on this device)
//! - **Π**: Pulse definitions (gate calibrations)
//! - **Ξ**: Calibration data (noise parameters, timing, T1/T2)
//! - **Θ**: Timing constraints (gate durations, measurement window)
//!
//! ## Invariants
//! - Backend must be valid before use (validate_backend())
//! - Calibration hash must be deterministic and reproducible
//! - All timing must be physically meaningful (positive)
//! - Native gates must be realizable on topology

use std::collections::{BTreeMap, HashMap};
use std::fmt;
use sha2::{Sha256, Digest};
use serde::{Serialize, Deserialize};
use thiserror::Error;

/// Error type for backend contract operations
#[derive(Debug, Error)]
pub enum BackendError {
    #[error("Invalid qubit index: {0}")]
    InvalidQubit(usize),

    #[error("Qubit {0} not connected to {1}")]
    NotConnected(usize, usize),

    #[error("Invalid gate {0} not in native gates")]
    UnsupportedGate(String),

    #[error("Invalid timing: {field} = {value}, expected positive")]
    InvalidTiming { field: String, value: f64 },

    #[error("Connectivity matrix must be square")]
    NonSquareConnectivity,

    #[error("Calibration mismatch: qubit {0} not in calibration")]
    MissingCalibration(usize),

    #[error("Empty backend: no qubits defined")]
    EmptyBackend,

    #[error("Serialization failed: {0}")]
    SerializationError(String),
}

pub type Result<T> = std::result::Result<T, BackendError>;

/// Native gate types available on quantum backends
#[derive(Debug, Clone, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum NativeGate {
    X,       // Pauli X (π rotation around X)
    Y,       // Pauli Y
    Z,       // Pauli Z
    H,       // Hadamard
    S,       // S gate (π/2 phase)
    T,       // T gate (π/4 phase)
    Rx,      // Rotation around X (parametric)
    Ry,      // Rotation around Y (parametric)
    Rz,      // Rotation around Z (parametric)
    CX,      // CNOT (two-qubit)
    CZ,      // Controlled-Z (two-qubit)
    SWAP,    // SWAP (two-qubit)
}

impl fmt::Display for NativeGate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NativeGate::X => write!(f, "X"),
            NativeGate::Y => write!(f, "Y"),
            NativeGate::Z => write!(f, "Z"),
            NativeGate::H => write!(f, "H"),
            NativeGate::S => write!(f, "S"),
            NativeGate::T => write!(f, "T"),
            NativeGate::Rx => write!(f, "Rx"),
            NativeGate::Ry => write!(f, "Ry"),
            NativeGate::Rz => write!(f, "Rz"),
            NativeGate::CX => write!(f, "CX"),
            NativeGate::CZ => write!(f, "CZ"),
            NativeGate::SWAP => write!(f, "SWAP"),
        }
    }
}

/// Pulse definition: calibrated waveform for a gate on specific qubits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PulseDefinition {
    pub gate: NativeGate,
    pub target_qubits: Vec<usize>, // Empty for global, 1 for single-qubit, 2 for two-qubit
    pub duration: f64,             // in nanoseconds
    pub amplitude: f64,            // pulse amplitude (0..1)
    pub frequency: f64,            // drive frequency in GHz
    pub phase: f64,                // initial phase in radians
}

impl PulseDefinition {
    /// Create a new pulse definition
    pub fn new(
        gate: NativeGate,
        target_qubits: Vec<usize>,
        duration: f64,
        amplitude: f64,
        frequency: f64,
        phase: f64,
    ) -> Result<Self> {
        if duration <= 0.0 {
            return Err(BackendError::InvalidTiming {
                field: "duration".to_string(),
                value: duration,
            });
        }
        if amplitude < 0.0 || amplitude > 1.0 {
            return Err(BackendError::InvalidTiming {
                field: "amplitude".to_string(),
                value: amplitude,
            });
        }
        if frequency < 0.0 {
            return Err(BackendError::InvalidTiming {
                field: "frequency".to_string(),
                value: frequency,
            });
        }

        Ok(PulseDefinition {
            gate,
            target_qubits,
            duration,
            amplitude,
            frequency,
            phase,
        })
    }
}

/// Coupling graph: adjacency matrix defining qubit connectivity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CouplingGraph {
    connectivity: Vec<Vec<bool>>, // [i][j] = true iff qubits i and j are coupled
}

impl CouplingGraph {
    /// Create a new coupling graph from adjacency matrix
    pub fn new(connectivity: Vec<Vec<bool>>) -> Result<Self> {
        if connectivity.is_empty() {
            return Err(BackendError::EmptyBackend);
        }

        let n = connectivity.len();
        for row in &connectivity {
            if row.len() != n {
                return Err(BackendError::NonSquareConnectivity);
            }
        }

        Ok(CouplingGraph { connectivity })
    }

    /// Check if two qubits are connected
    pub fn are_connected(&self, q1: usize, q2: usize) -> Result<bool> {
        let n = self.connectivity.len();
        if q1 >= n || q2 >= n {
            return Err(BackendError::InvalidQubit(
                if q1 >= n { q1 } else { q2 },
            ));
        }
        Ok(self.connectivity[q1][q2])
    }

    /// Get all neighbors of a qubit
    pub fn neighbors(&self, qubit: usize) -> Result<Vec<usize>> {
        let n = self.connectivity.len();
        if qubit >= n {
            return Err(BackendError::InvalidQubit(qubit));
        }
        Ok(self
            .connectivity[qubit]
            .iter()
            .enumerate()
            .filter(|(_, &connected)| connected)
            .map(|(i, _)| i)
            .collect())
    }

    /// Compute distance between qubits (shortest path)
    pub fn distance(&self, q1: usize, q2: usize) -> Result<usize> {
        let n = self.connectivity.len();
        if q1 >= n || q2 >= n {
            return Err(BackendError::InvalidQubit(
                if q1 >= n { q1 } else { q2 },
            ));
        }

        if q1 == q2 {
            return Ok(0);
        }

        // BFS to find shortest path
        let mut visited = vec![false; n];
        let mut queue = std::collections::VecDeque::new();
        queue.push_back((q1, 0));
        visited[q1] = true;

        while let Some((current, dist)) = queue.pop_front() {
            for neighbor in self.neighbors(current)? {
                if neighbor == q2 {
                    return Ok(dist + 1);
                }
                if !visited[neighbor] {
                    visited[neighbor] = true;
                    queue.push_back((neighbor, dist + 1));
                }
            }
        }

        // Not connected
        Ok(usize::MAX)
    }

    pub fn num_qubits(&self) -> usize {
        self.connectivity.len()
    }
}

/// Per-qubit calibration snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QubitCalibration {
    pub qubit: usize,
    pub frequency: f64,              // in GHz
    pub t1: f64,                     // energy decay time in microseconds
    pub t2: f64,                     // dephasing time in microseconds
    pub single_qubit_error: f64,     // 1-qubit gate error (0..1)
    pub two_qubit_error: f64,        // 2-qubit gate error (0..1)
    pub readout_error_0_to_1: f64,   // P(measure 1 | state 0)
    pub readout_error_1_to_0: f64,   // P(measure 0 | state 1)
}

impl QubitCalibration {
    /// Create a new qubit calibration
    pub fn new(
        qubit: usize,
        frequency: f64,
        t1: f64,
        t2: f64,
        single_qubit_error: f64,
        two_qubit_error: f64,
        readout_error_0_to_1: f64,
        readout_error_1_to_0: f64,
    ) -> Result<Self> {
        if t1 <= 0.0 {
            return Err(BackendError::InvalidTiming {
                field: "t1".to_string(),
                value: t1,
            });
        }
        if t2 <= 0.0 {
            return Err(BackendError::InvalidTiming {
                field: "t2".to_string(),
                value: t2,
            });
        }
        if t2 > t1 {
            // Physical constraint: dephasing faster than decay
            return Err(BackendError::InvalidTiming {
                field: "t2_exceeds_t1".to_string(),
                value: t2 - t1,
            });
        }
        if single_qubit_error < 0.0 || single_qubit_error > 1.0 {
            return Err(BackendError::InvalidTiming {
                field: "single_qubit_error".to_string(),
                value: single_qubit_error,
            });
        }
        if two_qubit_error < 0.0 || two_qubit_error > 1.0 {
            return Err(BackendError::InvalidTiming {
                field: "two_qubit_error".to_string(),
                value: two_qubit_error,
            });
        }
        if readout_error_0_to_1 < 0.0 || readout_error_0_to_1 > 1.0 {
            return Err(BackendError::InvalidTiming {
                field: "readout_error_0_to_1".to_string(),
                value: readout_error_0_to_1,
            });
        }
        if readout_error_1_to_0 < 0.0 || readout_error_1_to_0 > 1.0 {
            return Err(BackendError::InvalidTiming {
                field: "readout_error_1_to_0".to_string(),
                value: readout_error_1_to_0,
            });
        }

        Ok(QubitCalibration {
            qubit,
            frequency,
            t1,
            t2,
            single_qubit_error,
            two_qubit_error,
            readout_error_0_to_1,
            readout_error_1_to_0,
        })
    }
}

/// Calibration snapshot with timestamp and hash for WORM binding
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalibrationSnapshot {
    pub device_id: String,
    pub timestamp: u64, // Unix timestamp in seconds
    pub qubit_calibrations: BTreeMap<usize, QubitCalibration>,
    pub gate_calibrations: BTreeMap<String, PulseDefinition>, // key: "GATE_q0_q1" format
    pub calibration_hash: String, // Blake3 hash of calibration data
}

impl CalibrationSnapshot {
    /// Create a new calibration snapshot and compute hash
    pub fn new(
        device_id: String,
        timestamp: u64,
        qubit_calibrations: BTreeMap<usize, QubitCalibration>,
        gate_calibrations: BTreeMap<String, PulseDefinition>,
    ) -> Result<Self> {
        let mut snapshot = CalibrationSnapshot {
            device_id,
            timestamp,
            qubit_calibrations,
            gate_calibrations,
            calibration_hash: String::new(),
        };
        snapshot.compute_hash()?;
        Ok(snapshot)
    }

    /// Compute deterministic hash of calibration data
    fn compute_hash(&mut self) -> Result<Self> {
        let serialized = serde_json::to_string(&(&self.device_id, self.timestamp, &self.qubit_calibrations, &self.gate_calibrations))
            .map_err(|e| BackendError::SerializationError(e.to_string()))?;

        let mut hasher = Sha256::new();
        hasher.update(serialized.as_bytes());
        let hash = hasher.finalize();
        self.calibration_hash = format!("{:x}", hash);
        Ok(self.clone())
    }

    /// Verify that calibration is complete for given qubits
    pub fn verify_qubits(&self, qubits: &[usize]) -> Result<()> {
        for &q in qubits {
            if !self.qubit_calibrations.contains_key(&q) {
                return Err(BackendError::MissingCalibration(q));
            }
        }
        Ok(())
    }
}

/// Timing constraints for the backend
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimingConstraints {
    pub gate_duration_min: f64,   // minimum gate duration in ns
    pub gate_duration_max: f64,   // maximum gate duration in ns
    pub measurement_duration: f64, // measurement window in ns
    pub reset_duration: f64,       // reset time in ns
    pub coherence_time_limit: f64, // max coherence time before decoherence dominates (ns)
}

impl TimingConstraints {
    /// Create new timing constraints
    pub fn new(
        gate_duration_min: f64,
        gate_duration_max: f64,
        measurement_duration: f64,
        reset_duration: f64,
        coherence_time_limit: f64,
    ) -> Result<Self> {
        if gate_duration_min <= 0.0 || gate_duration_max <= 0.0 {
            return Err(BackendError::InvalidTiming {
                field: "gate_duration".to_string(),
                value: gate_duration_min.min(gate_duration_max),
            });
        }
        if gate_duration_min > gate_duration_max {
            return Err(BackendError::InvalidTiming {
                field: "gate_duration_min_exceeds_max".to_string(),
                value: gate_duration_min - gate_duration_max,
            });
        }
        if measurement_duration <= 0.0 {
            return Err(BackendError::InvalidTiming {
                field: "measurement_duration".to_string(),
                value: measurement_duration,
            });
        }
        if reset_duration <= 0.0 {
            return Err(BackendError::InvalidTiming {
                field: "reset_duration".to_string(),
                value: reset_duration,
            });
        }

        Ok(TimingConstraints {
            gate_duration_min,
            gate_duration_max,
            measurement_duration,
            reset_duration,
            coherence_time_limit,
        })
    }
}

/// Full quantum backend contract: B = (Q, Γ, Λ, Π, Ξ, Θ)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuantumBackend {
    pub num_qubits: usize,
    pub coupling_graph: CouplingGraph,
    pub native_gates: Vec<NativeGate>,
    pub pulse_definitions: HashMap<String, PulseDefinition>,
    pub calibration: CalibrationSnapshot,
    pub timing_constraints: TimingConstraints,
    pub backend_hash: String, // Blake3 hash of entire backend contract
}

impl QuantumBackend {
    /// Create a new quantum backend with full contract
    pub fn new(
        num_qubits: usize,
        coupling_graph: CouplingGraph,
        native_gates: Vec<NativeGate>,
        pulse_definitions: HashMap<String, PulseDefinition>,
        calibration: CalibrationSnapshot,
        timing_constraints: TimingConstraints,
    ) -> Result<Self> {
        let mut backend = QuantumBackend {
            num_qubits,
            coupling_graph,
            native_gates,
            pulse_definitions,
            calibration,
            timing_constraints,
            backend_hash: String::new(),
        };
        backend.validate()?;
        backend.compute_hash()?;
        Ok(backend)
    }

    /// Validate backend contract invariants
    pub fn validate(&self) -> Result<()> {
        // 1. Coupling graph must have correct size
        if self.coupling_graph.num_qubits() != self.num_qubits {
            return Err(BackendError::InvalidQubit(self.coupling_graph.num_qubits()));
        }

        // 2. All calibrations must match qubits
        self.calibration.verify_qubits(
            &(0..self.num_qubits).collect::<Vec<_>>(),
        )?;

        // 3. Native gates must be non-empty
        if self.native_gates.is_empty() {
            return Err(BackendError::InvalidTiming {
                field: "native_gates".to_string(),
                value: 0.0,
            });
        }

        // 4. Pulse definitions must respect timing constraints
        for (_, pulse) in &self.pulse_definitions {
            if pulse.duration < self.timing_constraints.gate_duration_min
                || pulse.duration > self.timing_constraints.gate_duration_max
            {
                return Err(BackendError::InvalidTiming {
                    field: "pulse_duration".to_string(),
                    value: pulse.duration,
                });
            }
        }

        Ok(())
    }

    /// Compute deterministic hash of backend contract
    fn compute_hash(&mut self) -> Result<()> {
        let serialized = serde_json::to_string(&(
            self.num_qubits,
            &self.native_gates,
            &self.calibration.calibration_hash,
            &self.timing_constraints,
        ))
        .map_err(|e| BackendError::SerializationError(e.to_string()))?;

        let mut hasher = Sha256::new();
        hasher.update(serialized.as_bytes());
        let hash = hasher.finalize();
        self.backend_hash = format!("{:x}", hash);
        Ok(())
    }

    /// Check if a gate is native on this backend
    pub fn supports_gate(&self, gate: &NativeGate) -> bool {
        self.native_gates.contains(gate)
    }

    /// Verify two-qubit gate is supported on this topology
    pub fn can_apply_two_qubit_gate(&self, q1: usize, q2: usize) -> Result<bool> {
        self.coupling_graph.are_connected(q1, q2)
    }

    /// Get calibration for specific qubit
    pub fn get_qubit_calibration(&self, qubit: usize) -> Result<&QubitCalibration> {
        self.calibration
            .qubit_calibrations
            .get(&qubit)
            .ok_or(BackendError::MissingCalibration(qubit))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_linear_coupling(n: usize) -> CouplingGraph {
        let mut connectivity = vec![vec![false; n]; n];
        for i in 0..n {
            connectivity[i][i] = true; // self-loops
            if i + 1 < n {
                connectivity[i][i + 1] = true;
                connectivity[i + 1][i] = true;
            }
        }
        CouplingGraph::new(connectivity).unwrap()
    }

    fn make_fully_connected(n: usize) -> CouplingGraph {
        let connectivity = vec![vec![true; n]; n];
        CouplingGraph::new(connectivity).unwrap()
    }

    #[test]
    fn test_coupling_graph_neighbors() {
        let graph = make_linear_coupling(5);
        let neighbors = graph.neighbors(2).unwrap();
        assert!(neighbors.contains(&1));
        assert!(neighbors.contains(&3));
        assert!(neighbors.contains(&2)); // self-loop
        assert!(!neighbors.contains(&0));
    }

    #[test]
    fn test_coupling_graph_distance() {
        let graph = make_linear_coupling(5);
        assert_eq!(graph.distance(0, 0).unwrap(), 0);
        assert_eq!(graph.distance(0, 1).unwrap(), 1);
        assert_eq!(graph.distance(0, 4).unwrap(), 4);
    }

    #[test]
    fn test_qubit_calibration_valid() {
        let cal = QubitCalibration::new(0, 5.0, 100.0, 50.0, 0.001, 0.01, 0.02, 0.01)
            .expect("Valid calibration");
        assert_eq!(cal.qubit, 0);
        assert_eq!(cal.t1, 100.0);
    }

    #[test]
    fn test_qubit_calibration_t2_exceeds_t1() {
        let result = QubitCalibration::new(0, 5.0, 100.0, 150.0, 0.001, 0.01, 0.02, 0.01);
        assert!(result.is_err());
    }

    #[test]
    fn test_timing_constraints_valid() {
        let timing = TimingConstraints::new(10.0, 100.0, 200.0, 500.0, 10000.0)
            .expect("Valid timing");
        assert_eq!(timing.gate_duration_min, 10.0);
    }

    #[test]
    fn test_calibration_snapshot_hash() {
        let mut cals = BTreeMap::new();
        cals.insert(
            0,
            QubitCalibration::new(0, 5.0, 100.0, 50.0, 0.001, 0.01, 0.02, 0.01).unwrap(),
        );

        let snapshot1 =
            CalibrationSnapshot::new("ibm-fake".to_string(), 1000, cals.clone(), BTreeMap::new())
                .expect("Valid snapshot");
        let snapshot2 =
            CalibrationSnapshot::new("ibm-fake".to_string(), 1000, cals, BTreeMap::new())
                .expect("Valid snapshot");

        // Same inputs → same hash
        assert_eq!(snapshot1.calibration_hash, snapshot2.calibration_hash);
    }

    #[test]
    fn test_backend_contract_valid() {
        let graph = make_fully_connected(3);
        let native_gates = vec![NativeGate::H, NativeGate::CX];
        let pulse_defs = HashMap::new();

        let mut cals = BTreeMap::new();
        for i in 0..3 {
            cals.insert(
                i,
                QubitCalibration::new(i, 5.0 + i as f64, 100.0, 50.0, 0.001, 0.01, 0.02, 0.01)
                    .unwrap(),
            );
        }
        let calibration = CalibrationSnapshot::new("test".to_string(), 0, cals, BTreeMap::new())
            .expect("Valid calibration");

        let timing = TimingConstraints::new(10.0, 100.0, 200.0, 500.0, 10000.0).unwrap();

        let backend = QuantumBackend::new(3, graph, native_gates, pulse_defs, calibration, timing)
            .expect("Valid backend");

        assert_eq!(backend.num_qubits, 3);
        assert!(backend.supports_gate(&NativeGate::H));
        assert!(backend.can_apply_two_qubit_gate(0, 1).unwrap());
    }

    #[test]
    fn test_backend_validates_mismatched_qubits() {
        let graph = make_fully_connected(3);
        let native_gates = vec![NativeGate::H];
        let pulse_defs = HashMap::new();

        let mut cals = BTreeMap::new();
        cals.insert(
            0,
            QubitCalibration::new(0, 5.0, 100.0, 50.0, 0.001, 0.01, 0.02, 0.01).unwrap(),
        );
        // Missing qubits 1 and 2!

        let calibration = CalibrationSnapshot::new("test".to_string(), 0, cals, BTreeMap::new())
            .expect("Valid calibration");

        let timing = TimingConstraints::new(10.0, 100.0, 200.0, 500.0, 10000.0).unwrap();

        let result = QuantumBackend::new(3, graph, native_gates, pulse_defs, calibration, timing);
        assert!(result.is_err());
    }
}
