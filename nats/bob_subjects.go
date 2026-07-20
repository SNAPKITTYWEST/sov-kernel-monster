package bob

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
)

// Subject constants for BOB Quantum Civilization Engine
const (
	// Lattice operations
	SubjectLatticeCreate      = "bob.lattice.create"
	SubjectLatticeEvolve      = "bob.lattice.evolve"
	SubjectLatticeEnergy      = "bob.lattice.energy"
	SubjectLatticeEntropy     = "bob.lattice.entropy"
	SubjectLatticeCorrelate   = "bob.lattice.correlate"
	SubjectLatticeMeasure     = "bob.lattice.measure"
	SubjectLatticeSnapshot    = "bob.lattice.snapshot"
	SubjectLatticeRestore     = "bob.lattice.restore"

	// State vector operations
	SubjectStateCreate        = "bob.state.create"
	SubjectStateMeasure       = "bob.state.measure"
	SubjectStateMeasureShots  = "bob.state.measure_shots"
	SubjectStateInnerProduct  = "bob.state.inner_product"
	SubjectStateNormalize     = "bob.state.normalize"
	SubjectStateTensor        = "bob.state.tensor"
	SubjectStatePartialTrace  = "bob.state.partial_trace"
	SubjectStateFidelity      = "bob.state.fidelity"
	SubjectStateEntropy       = "bob.state.entropy"
	SubjectStateBloch         = "bob.state.bloch"

	// Hamiltonian operations
	SubjectHamiltonianCreate      = "bob.hamiltonian.create"
	SubjectHamiltonianAddTerm     = "bob.hamiltonian.add_term"
	SubjectHamiltonianExpectation = "bob.hamiltonian.expectation"
	SubjectHamiltonianEigenvalues = "bob.hamiltonian.eigenvalues"
	SubjectHamiltonianTimeEvolve  = "bob.hamiltonian.time_evolve"
	SubjectHamiltonianCommutator  = "bob.hamiltonian.commutator"
	SubjectHamiltonianTrotterize  = "bob.hamiltonian.trotterize"
	SubjectHamiltonianIsing       = "bob.hamiltonian.ising"
	SubjectHamiltonianHeisenberg  = "bob.hamiltonian.heisenberg"
	SubjectHamiltonianHubbard     = "bob.hamiltonian.hubbard"

	// Evolution algorithms
	SubjectEvolveExact    = "bob.evolve.exact"
	SubjectEvolveTrotter  = "bob.evolve.trotter"
	SubjectEvolveKrylov   = "bob.evolve.krylov"
	SubjectEvolveTEBD     = "bob.evolve.tebd"
	SubjectEvolveTDVP     = "bob.evolve.tdvp"
	SubjectEvolveChebyshev = "bob.evolve.chebyshev"
	SubjectEvolveMagnus   = "bob.evolve.magnus"

	// Random number generation
	SubjectRNGCreate   = "bob.rng.create"
	SubjectRNGUniform  = "bob.rng.uniform"
	SubjectRNGNormal   = "bob.rng.normal"
	SubjectRNGComplex  = "bob.rng.complex"
	SubjectRNGHaar     = "bob.rng.haar"
	SubjectRNGClifford = "bob.rng.clifford"
	SubjectRNGSeed     = "bob.rng.seed"

	// Quantum circuits
	SubjectCircuitQFT      = "bob.circuit.qft"
	SubjectCircuitGrover   = "bob.circuit.grover"
	SubjectCircuitQPE      = "bob.circuit.qpe"
	SubjectCircuitVQE      = "bob.circuit.vqe"
	SubjectCircuitQAOA     = "bob.circuit.qaoa"
	SubjectCircuitTeleport = "bob.circuit.teleport"
	SubjectCircuitSuperdense = "bob.circuit.superdense"
	SubjectCircuitErrorCorr = "bob.circuit.error_corr"
	SubjectCircuitCompile  = "bob.circuit.compile"
	SubjectCircuitOptimize = "bob.circuit.optimize"

	// Proof system
	SubjectProofCheck    = "bob.proof.check"
	SubjectProofCompile  = "bob.proof.compile"
	SubjectProofVerify   = "bob.proof.verify"
	SubjectProofGenerate = "bob.proof.generate"
	SubjectProofExport   = "bob.proof.export"

	// Plasma consensus
	SubjectPlasmaEnforce = "bob.plasma.enforce"
	SubjectPlasmaVerify  = "bob.plasma.verify"
	SubjectPlasmaPropose = "bob.plasma.propose"
	SubjectPlasmaCommit  = "bob.plasma.commit"
	SubjectPlasmaView    = "bob.plasma.view"
	SubjectPlasmaSlash   = "bob.plasma.slash"

	// Swarm coordination
	SubjectSwarmTaskClaim   = "bob.swarm.task.claim"
	SubjectSwarmTaskComplete = "bob.swarm.task.complete"
	SubjectSwarmTaskAssign  = "bob.swarm.task.assign"
	SubjectSwarmTaskCancel  = "bob.swarm.task.cancel"
	SubjectSwarmNodeRegister = "bob.swarm.node.register"
	SubjectSwarmNodeHeartbeat = "bob.swarm.node.heartbeat"
	SubjectSwarmNodeStatus  = "bob.swarm.node.status"
	SubjectSwarmPartition   = "bob.swarm.partition"
	SubjectSwarmMerge       = "bob.swarm.merge"

	// Bifrost bridge
	SubjectBifrostLog     = "bob.bifrost.log"
	SubjectBifrostVerify  = "bob.bifrost.verify"
	SubjectBifrostAttest  = "bob.bifrost.attest"
	SubjectBifrostAnchor  = "bob.bifrost.anchor"
	SubjectBifrostQuery   = "bob.bifrost.query"
	SubjectBifrostProof   = "bob.bifrost.proof"

	// System/control
	SubjectSystemHealth   = "bob.system.health"
	SubjectSystemMetrics  = "bob.system.metrics"
	SubjectSystemConfig   = "bob.system.config"
	SubjectSystemShutdown = "bob.system.shutdown"
)

// Error codes
const (
	ErrCodeInvalidRequest   = "INVALID_REQUEST"
	ErrCodeNotFound         = "NOT_FOUND"
	ErrCodeInternalError    = "INTERNAL_ERROR"
	ErrCodeTimeout          = "TIMEOUT"
	ErrCodeUnauthorized     = "UNAUTHORIZED"
	ErrCodeResourceExhausted = "RESOURCE_EXHAUSTED"
	ErrCodeInvalidState     = "INVALID_STATE"
	ErrCodeConsensusFailed  = "CONSENSUS_FAILED"
	ErrCodeProofFailed      = "PROOF_FAILED"
)

// Base response structure
type BaseResponse struct {
	Success   bool   `json:"success"`
	ErrorCode string `json:"error_code,omitempty"`
	ErrorMsg  string `json:"error_msg,omitempty"`
	RequestID string `json:"request_id,omitempty"`
	Timestamp int64  `json:"timestamp"`
}

// ============================================================================
// LATTICE OPERATIONS
// ============================================================================

type LatticeCreateRequest struct {
	RequestID   string                 `json:"request_id"`
	Dimensions  []int                  `json:"dimensions"`
	Boundary    string                 `json:"boundary"` // periodic, open, twisted
	Precision   string                 `json:"precision"` // complex64, complex128
	InitialState string                `json:"initial_state,omitempty"` // zero, random, thermal, custom
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

type LatticeCreateResponse struct {
	BaseResponse
	LatticeID string `json:"lattice_id"`
	Size      int    `json:"size"`
	Rank      int    `json:"rank"`
}

type LatticeEvolveRequest struct {
	RequestID    string                 `json:"request_id"`
	LatticeID    string                 `json:"lattice_id"`
	HamiltonianID string                `json:"hamiltonian_id"`
	TimeStep     float64                `json:"time_step"`
	Steps        int                    `json:"steps"`
	Method       string                 `json:"method"` // exact, trotter, krylov, tebd
	Options      map[string]interface{} `json:"options,omitempty"`
}

type LatticeEvolveResponse struct {
	BaseResponse
	LatticeID      string  `json:"lattice_id"`
	FinalTime      float64 `json:"final_time"`
	EnergyDrift    float64 `json:"energy_drift"`
	EntropyChange  float64 `json:"entropy_change"`
	Fidelity       float64 `json:"fidelity"`
}

type LatticeEnergyRequest struct {
	RequestID     string `json:"request_id"`
	LatticeID     string `json:"lattice_id"`
	HamiltonianID string `json:"hamiltonian_id"`
}

type LatticeEnergyResponse struct {
	BaseResponse
	Energy       float64 `json:"energy"`
	Variance     float64 `json:"variance"`
	GroundState  bool    `json:"ground_state"`
}

type LatticeEntropyRequest struct {
	RequestID  string   `json:"request_id"`
	LatticeID  string   `json:"lattice_id"`
	Subsystem  []int    `json:"subsystem,omitempty"`
	RenyiIndex float64  `json:"renyi_index,omitempty"` // 1 for von Neumann
}

type LatticeEntropyResponse struct {
	BaseResponse
	Entropy       float64 `json:"entropy"`
	RenyiEntropy  float64 `json:"renyi_entropy,omitempty"`
	MutualInfo    float64 `json:"mutual_info,omitempty"`
}

type LatticeCorrelateRequest struct {
	RequestID  string  `json:"request_id"`
	LatticeID  string  `json:"lattice_id"`
	OperatorA  string  `json:"operator_a"`
	OperatorB  string  `json:"operator_b"`
	Distance   int     `json:"distance"`
	TimeSep    float64 `json:"time_separation,omitempty"`
}

type LatticeCorrelateResponse struct {
	BaseResponse
	Correlation complex128 `json:"correlation"`
	Connected   complex128 `json:"connected"`
}

type LatticeMeasureRequest struct {
	RequestID  string   `json:"request_id"`
	LatticeID  string   `json:"lattice_id"`
	Observables []string `json:"observables"`
	Shots      int      `json:"shots,omitempty"`
}

type LatticeMeasureResponse struct {
	BaseResponse
	Results map[string]MeasurementResult `json:"results"`
}

type MeasurementResult struct {
	Expectation complex128 `json:"expectation"`
	Variance    float64    `json:"variance"`
	Histogram   []int      `json:"histogram,omitempty"`
	Outcomes    []complex128 `json:"outcomes,omitempty"`
}

type LatticeSnapshotRequest struct {
	RequestID  string `json:"request_id"`
	LatticeID  string `json:"lattice_id"`
	Compress   bool   `json:"compress"`
}

type LatticeSnapshotResponse struct {
	BaseResponse
	SnapshotID string `json:"snapshot_id"`
	SizeBytes  int64  `json:"size_bytes"`
	Checksum   string `json:"checksum"`
}

type LatticeRestoreRequest struct {
	RequestID   string `json:"request_id"`
	SnapshotID  string `json:"snapshot_id"`
	NewLatticeID string `json:"new_lattice_id,omitempty"`
}

type LatticeRestoreResponse struct {
	BaseResponse
	LatticeID string `json:"lattice_id"`
}

// ============================================================================
// STATE VECTOR OPERATIONS
// ============================================================================

type StateCreateRequest struct {
	RequestID   string                 `json:"request_id"`
	NumQubits   int                    `json:"num_qubits"`
	InitialState string                `json:"initial_state"` // zero, plus, random, basis, custom
	BasisIndex  int                    `json:"basis_index,omitempty"`
	Amplitudes  []complex128           `json:"amplitudes,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

type StateCreateResponse struct {
	BaseResponse
	StateID string `json:"state_id"`
	Norm    float64 `json:"norm"`
}

type StateMeasureRequest struct {
	RequestID  string   `json:"request_id"`
	StateID    string   `json:"state_id"`
	Qubits     []int    `json:"qubits"`
	Basis      string   `json:"basis"` // computational, x, y, bell
	Collapse   bool     `json:"collapse"`
}

type StateMeasureResponse struct {
	BaseResponse
	Outcome    int         `json:"outcome"`
	Probability float64    `json:"probability"`
	PostStateID string     `json:"post_state_id,omitempty"`
}

type StateMeasureShotsRequest struct {
	RequestID string `json:"request_id"`
	StateID   string `json:"state_id"`
	Qubits    []int  `json:"qubits"`
	Shots     int    `json:"shots"`
	Basis     string `json:"basis"`
}

type StateMeasureShotsResponse struct {
	BaseResponse
	Counts map[int]int `json:"counts"`
	Probs  map[int]float64 `json:"probs"`
}

type StateInnerProductRequest struct {
	RequestID string `json:"request_id"`
	StateID1  string `json:"state_id_1"`
	StateID2  string `json:"state_id_2"`
}

type StateInnerProductResponse struct {
	BaseResponse
	InnerProduct complex128 `json:"inner_product"`
	Fidelity     float64    `json:"fidelity"`
}

type StateNormalizeRequest struct {
	RequestID string `json:"request_id"`
	StateID   string `json:"state_id"`
}

type StateNormalizeResponse struct {
	BaseResponse
	StateID string  `json:"state_id"`
	Norm    float64 `json:"norm"`
}

type StateTensorRequest struct {
	RequestID string   `json:"request_id"`
	StateIDs  []string `json:"state_ids"`
}

type StateTensorResponse struct {
	BaseResponse
	StateID string `json:"state_id"`
	NumQubits int   `json:"num_qubits"`
}

type StatePartialTraceRequest struct {
	RequestID  string `json:"request_id"`
	StateID    string `json:"state_id"`
	KeepQubits []int  `json:"keep_qubits"`
}

type StatePartialTraceResponse struct {
	BaseResponse
	StateID string `json:"state_id"`
	Purity  float64 `json:"purity"`
}

type StateFidelityRequest struct {
	RequestID string `json:"request_id"`
	StateID1  string `json:"state_id_1"`
	StateID2  string `json:"state_id_2"`
}

type StateFidelityResponse struct {
	BaseResponse
	Fidelity float64 `json:"fidelity"`
}

type StateEntropyRequest struct {
	RequestID  string  `json:"request_id"`
	StateID    string  `json:"state_id"`
	Subsystem  []int   `json:"subsystem,omitempty"`
	RenyiIndex float64 `json:"renyi_index,omitempty"`
}

type StateEntropyResponse struct {
	BaseResponse
	Entropy float64 `json:"entropy"`
}

type StateBlochRequest struct {
	RequestID string `json:"request_id"`
	StateID   string `json:"state_id"`
	Qubit     int    `json:"qubit"`
}

type StateBlochResponse struct {
	BaseResponse
	Vector [3]float64 `json:"vector"`
	Purity float64    `json:"purity"`
}

// ============================================================================
// HAMILTONIAN OPERATIONS
// ============================================================================

type HamiltonianCreateRequest struct {
	RequestID   string                 `json:"request_id"`
	NumQubits   int                    `json:"num_qubits"`
	Type        string                 `json:"type"` // sparse, dense, mpo, pauli_sum
	Terms       []PauliTerm            `json:"terms,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

type PauliTerm struct {
	Coefficient complex128 `json:"coefficient"`
	Paulis      []PauliOp  `json:"paulis"`
}

type PauliOp struct {
	Qubit int    `json:"qubit"`
	Op    string `json:"op"` // I, X, Y, Z
}

type HamiltonianCreateResponse struct {
	BaseResponse
	HamiltonianID string `json:"hamiltonian_id"`
	NumTerms      int    `json:"num_terms"`
	Norm          float64 `json:"norm"`
}

type HamiltonianAddTermRequest struct {
	RequestID     string    `json:"request_id"`
	HamiltonianID string    `json:"hamiltonian_id"`
	Term          PauliTerm `json:"term"`
}

type HamiltonianAddTermResponse struct {
	BaseResponse
	HamiltonianID string `json:"hamiltonian_id"`
	NumTerms      int    `json:"num_terms"`
}

type HamiltonianExpectationRequest struct {
	RequestID     string `json:"request_id"`
	HamiltonianID string `json:"hamiltonian_id"`
	StateID       string `json:"state_id"`
}

type HamiltonianExpectationResponse struct {
	BaseResponse
	Expectation complex128 `json:"expectation"`
	Variance    float64    `json:"variance"`
}

type HamiltonianEigenvaluesRequest struct {
	RequestID     string `json:"request_id"`
	HamiltonianID string `json:"hamiltonian_id"`
	NumEigenvals  int    `json:"num_eigenvals"`
	Which         string `json:"which"` // smallest, largest, both
}

type HamiltonianEigenvaluesResponse struct {
	BaseResponse
	Eigenvalues []float64 `json:"eigenvalues"`
	Eigenstates []string  `json:"eigenstates,omitempty"` // state IDs
}

type HamiltonianTimeEvolveRequest struct {
	RequestID     string                 `json:"request_id"`
	HamiltonianID string                 `json:"hamiltonian_id"`
	StateID       string                 `json:"state_id"`
	Time          float64                `json:"time"`
	Method        string                 `json:"method"`
	Options       map[string]interface{} `json:"options,omitempty"`
}

type HamiltonianTimeEvolveResponse struct {
	BaseResponse
	StateID     string  `json:"state_id"`
	Fidelity    float64 `json:"fidelity"`
	ErrorBound  float64 `json:"error_bound"`
}

type HamiltonianCommutatorRequest struct {
	RequestID      string `json:"request_id"`
	HamiltonianID1 string `json:"hamiltonian_id_1"`
	HamiltonianID2 string `json:"hamiltonian_id_2"`
}

type HamiltonianCommutatorResponse struct {
	BaseResponse
	CommutatorID string `json:"commutator_id"`
	Norm         float64 `json:"norm"`
}

type HamiltonianTrotterizeRequest struct {
	RequestID     string  `json:"request_id"`
	HamiltonianID string  `json:"hamiltonian_id"`
	TimeStep      float64 `json:"time_step"`
	Order         int     `json:"order"` // 1, 2, 4
}

type HamiltonianTrotterizeResponse struct {
	BaseResponse
	CircuitID string `json:"circuit_id"`
	Depth     int    `json:"depth"`
	NumGates  int    `json:"num_gates"`
}

type HamiltonianIsingRequest struct {
	RequestID  string    `json:"request_id"`
	NumQubits  int       `json:"num_qubits"`
	Couplings  []float64 `json:"couplings"`  // J_ij
	Fields     []float64 `json:"fields"`     // h_i
	Topology   string    `json:"topology"`   // chain, square, triangular, all-to-all
}

type HamiltonianIsingResponse struct {
	BaseResponse
	HamiltonianID string `json:"hamiltonian_id"`
}

type HamiltonianHeisenbergRequest struct {
	RequestID  string    `json:"request_id"`
	NumQubits  int       `json:"num_qubits"`
	Jx, Jy, Jz []float64 `json:"jx,omitempty" json:"jy,omitempty" json:"jz,omitempty"`
	Fields     []float64 `json:"fields,omitempty"`
	Topology   string    `json:"topology"`
}

type HamiltonianHeisenbergResponse struct {
	BaseResponse
	HamiltonianID string `json:"hamiltonian_id"`
}

type HamiltonianHubbardRequest struct {
	RequestID  string  `json:"request_id"`
	Lx, Ly     int     `json:"lx" json:"ly"`
	T          float64 `json:"t"`
	U          float64 `json:"u"`
	Mu         float64 `json:"mu"`
	Periodic   bool    `json:"periodic"`
}

type HamiltonianHubbardResponse struct {
	BaseResponse
	HamiltonianID string `json:"hamiltonian_id"`
}

// ============================================================================
// EVOLUTION ALGORITHMS
// ============================================================================

type EvolveExactRequest struct {
	RequestID     string `json:"request_id"`
	HamiltonianID string `json:"hamiltonian_id"`
	StateID       string `json:"state_id"`
	Time          float64 `json:"time"`
}

type EvolveExactResponse struct {
	BaseResponse
	StateID string `json:"state_id"`
}

type EvolveTrotterRequest struct {
	RequestID     string                 `json:"request_id"`
	HamiltonianID string                 `json:"hamiltonian_id"`
	StateID       string                 `json:"state_id"`
	Time          float64                `json:"time"`
	TimeStep      float64                `json:"time_step"`
	Order         int                    `json:"order"`
	Options       map[string]interface{} `json:"options,omitempty"`
}

type EvolveTrotterResponse struct {
	BaseResponse
	StateID      string  `json:"state_id"`
	NumSteps     int     `json:"num_steps"`
	ErrorBound   float64 `json:"error_bound"`
	TrotterError float64 `json:"trotter_error"`
}

type EvolveKrylovRequest struct {
	RequestID     string  `json:"request_id"`
	HamiltonianID string  `json:"hamiltonian_id"`
	StateID       string  `json:"state_id"`
	Time          float64 `json:"time"`
	KrylovDim     int     `json:"krylov_dim"`
	Tolerance     float64 `json:"tolerance"`
}

type EvolveKrylovResponse struct {
	BaseResponse
	StateID       string  `json:"state_id"`
	KrylovDimUsed int     `json:"krylov_dim_used"`
	ErrorEstimate float64 `json:"error_estimate"`
}

type EvolveTEBDRequest struct {
	RequestID     string                 `json:"request_id"`
	HamiltonianID string                 `json:"hamiltonian_id"`
	StateID       string                 `json:"state_id"` // MPS state
	Time          float64                `json:"time"`
	TimeStep      float64                `json:"time_step"`
	ChiMax        int                    `json:"chi_max"`
	TruncTol      float64                `json:"trunc_tol"`
	Options       map[string]interface{} `json:"options,omitempty"`
}

type EvolveTEBDResponse struct {
	BaseResponse
	StateID       string  `json:"state_id"`
	TruncationErr float64 `json:"truncation_error"`
	BondDims      []int   `json:"bond_dims"`
}

type EvolveTDVPRequest struct {
	RequestID     string                 `json:"request_id"`
	HamiltonianID string                 `json:"hamiltonian_id"`
	StateID       string                 `json:"state_id"`
	Time          float64                `json:"time"`
	TimeStep      float64                `json:"time_step"`
	Options       map[string]interface{} `json:"options,omitempty"`
}

type EvolveTDVPResponse struct {
	BaseResponse
	StateID string `json:"state_id"`
	Energy  float64 `json:"energy"`
}

type EvolveChebyshevRequest struct {
	RequestID     string  `json:"request_id"`
	HamiltonianID string  `json:"hamiltonian_id"`
	StateID       string  `json:"state_id"`
	Time          float64 `json:"time"`
	Order         int     `json:"order"`
}

type EvolveChebyshevResponse struct {
	BaseResponse
	StateID string `json:"state_id"`
	Order   int    `json:"order_used"`
}

type EvolveMagnusRequest struct {
	RequestID     string  `json:"request_id"`
	HamiltonianID string  `json:"hamiltonian_id"`
	StateID       string  `json:"state_id"`
	Time          float64 `json:"time"`
	Order         int     `json:"order"`
	TimeSteps     int     `json:"time_steps"`
}

type EvolveMagnusResponse struct {
	BaseResponse
	StateID string `json:"state_id"`
	Order   int    `json:"order_used"`
}

// ============================================================================
// RANDOM NUMBER GENERATION
// ============================================================================

type RNGCreateRequest struct {
	RequestID string `json:"request_id"`
	Seed      uint64 `json:"seed,omitempty"`
	Algorithm string `json:"algorithm,omitempty"` // pcg64, chacha20, aes
}

type RNGCreateResponse struct {
	BaseResponse
	RNGID string `json:"rng_id"`
}

type RNGUniformRequest struct {
	RequestID string `json:"request_id"`
	RNGID     string `json:"rng_id"`
	Count     int    `json:"count"`
	Min       float64 `json:"min,omitempty"`
	Max       float64 `json:"max,omitempty"`
}

type RNGUniformResponse struct {
	BaseResponse
	Values []float64 `json:"values"`
}

type RNGNormalRequest struct {
	RequestID string  `json:"request_id"`
	RNGID     string  `json:"rng_id"`
	Count     int     `json:"count"`
	Mean      float64 `json:"mean,omitempty"`
	StdDev    float64 `json:"std_dev,omitempty"`
}

type RNGNormalResponse struct {
	BaseResponse
	Values []float64 `json:"values"`
}

type RNGComplexRequest struct {
	RequestID string `json:"request_id"`
	RNGID     string `json:"rng_id"`
	Count     int    `json:"count"`
	Dist      string `json:"dist"` // uniform_disk, normal_circular
}

type RNGComplexResponse struct {
	BaseResponse
	Values []complex128 `json:"values"`
}

type RNGHaarRequest struct {
	RequestID string `json:"request_id"`
	RNGID     string `json:"rng_id"`
	Dimension int    `json:"dimension"`
}

type RNGHaarResponse struct {
	BaseResponse
	Unitary [][]complex128 `json:"unitary"`
}

type RNGCliffordRequest struct {
	RequestID string `json:"request_id"`
	RNGID     string `json:"rng_id"`
	NumQubits int    `json:"num_qubits"`
}

type RNGCliffordResponse struct {
	BaseResponse
	Tableau [][]int `json:"tableau"` // symplectic representation
}

type RNGSeedRequest struct {
	RequestID string `json:"request_id"`
	RNGID     string `json:"rng_id"`
	Seed      uint64 `json:"seed"`
}

type RNGSeedResponse struct {
	BaseResponse
}

// ============================================================================
// QUANTUM CIRCUITS
// ============================================================================

type CircuitQFTRequest struct {
	RequestID   string `json:"request_id"`
	NumQubits   int    `json:"num_qubits"`
	Inverse     bool   `json:"inverse,omitempty"`
	Approximate bool   `json:"approximate,omitempty"`
	Precision   int    `json:"precision,omitempty"`
}

type CircuitQFTResponse struct {
	BaseResponse
	CircuitID string `json:"circuit_id"`
	Depth     int    `json:"depth"`
	NumGates  int    `json:"num_gates"`
}

type CircuitGroverRequest struct {
	RequestID   string          `json:"request_id"`
	NumQubits   int             `json:"num_qubits"`
	Oracle      json.RawMessage `json:"oracle"` // circuit or function
	Iterations  int             `json:"iterations,omitempty"`
}

type CircuitGroverResponse struct {
	BaseResponse
	CircuitID string `json:"circuit_id"`
	Depth     int    `json:"depth"`
	SuccessProb float64 `json:"success_prob"`
}

type CircuitQPERequest struct {
	RequestID     string `json:"request_id"`
	HamiltonianID string `json:"hamiltonian_id"`
	Precision     int    `json:"precision"` // number of ancilla qubits
	Time          float64 `json:"time"`
}

type CircuitQPEResponse struct {
	BaseResponse
	CircuitID string `json:"circuit_id"`
	Depth     int    `json:"depth"`
}

type CircuitVQERequest struct {
	RequestID     string                 `json:"request_id"`
	HamiltonianID string                 `json:"hamiltonian_id"`
	Ansatz        string                 `json:"ansatz"` // hardware_efficient, uccsd, custom
	Parameters    []float64              `json:"parameters,omitempty"`
	Options       map[string]interface{} `json:"options,omitempty"`
}

type CircuitVQEResponse struct {
	BaseResponse
	CircuitID   string   `json:"circuit_id"`
	Energy      float64  `json:"energy"`
	Parameters  []float64 `json:"parameters"`
	Gradient    []float64 `json:"gradient,omitempty"`
}

type CircuitQAOARequest struct {
	RequestID     string   `json:"request_id"`
	HamiltonianID string   `json:"hamiltonian_id"`
	MixerID       string   `json:"mixer_id,omitempty"`
	P             int      `json:"p"` // layers
	Betas         []float64 `json:"betas,omitempty"`
	Gammas        []float64 `json:"gammas,omitempty"`
}

type CircuitQAOAResponse struct {
	BaseResponse
	CircuitID string   `json:"circuit_id"`
	Energy    float64  `json:"energy"`
	Betas     []float64 `json:"betas"`
	Gammas    []float64 `json:"gammas"`
}

type CircuitTeleportRequest struct {
	RequestID string `json:"request_id"`
	StateID   string `json:"state_id"`
}

type CircuitTeleportResponse struct {
	BaseResponse
	CircuitID string `json:"circuit_id"`
}

type CircuitSuperdenseRequest struct {
	RequestID string `json:"request_id"`
	Message   int    `json:"message"` // 0-3
}

type CircuitSuperdenseResponse struct {
	BaseResponse
	CircuitID string `json:"circuit_id"`
}

type CircuitErrorCorrRequest struct {
	RequestID string   `json:"request_id"`
	Code      string   `json:"code"` // surface, color, steane, shor
	Distance  int      `json:"distance"`
	LogicalQubits int  `json:"logical_qubits"`
}

type CircuitErrorCorrResponse struct {
	BaseResponse
	CircuitID     string `json:"circuit_id"`
	PhysicalQubits int   `json:"physical_qubits"`
	Stabilizers   []string `json:"stabilizers"`
}

type CircuitCompileRequest struct {
	RequestID   string   `json:"request_id"`
	CircuitID   string   `json:"circuit_id"`
	TargetGates []string `json:"target_gates"`
	Topology    string   `json:"topology,omitempty"` // coupling map
	Optimize    bool     `json:"optimize"`
}

type CircuitCompileResponse struct {
	BaseResponse
	CircuitID    string `json:"circuit_id"`
	Depth        int    `json:"depth"`
	GateCounts   map[string]int `json:"gate_counts"`
	SwapCount    int    `json:"swap_count"`
}

type CircuitOptimizeRequest struct {
	RequestID string   `json:"request_id"`
	CircuitID string   `json:"circuit_id"`
	Passes    []string `json:"passes"` // commutation, cancellation, rotation_merging, etc.
}

type CircuitOptimizeResponse struct {
	BaseResponse
	CircuitID  string `json:"circuit_id"`
	Depth      int    `json:"depth"`
	Reduction  float64 `json:"reduction"`
}

// ============================================================================
// PROOF SYSTEM
// ============================================================================

type ProofCheckRequest struct {
	RequestID  string          `json:"request_id"`
	Proof      json.RawMessage `json:"proof"`
	Statement  json.RawMessage `json:"statement"`
	Language   string          `json:"language"` // lean, coq, isabelle, custom
}

type ProofCheckResponse struct {
	BaseResponse
	Valid      bool     `json:"valid"`
	Errors     []string `json:"errors,omitempty"`
	Warnings   []string `json:"warnings,omitempty"`
	ProofHash  string   `json:"proof_hash"`
}

type ProofCompileRequest struct {
	RequestID  string          `json:"request_id"`
	Source     string          `json:"source"`
	Language   string          `json:"language"`
	Target     string          `json:"target"` // wasm, native, bytecode
	Optimize   bool            `json:"optimize"`
}

type ProofCompileResponse struct {
	BaseResponse
	ArtifactID string   `json:"artifact_id"`
	Size       int64    `json:"size"`
	Exports    []string `json:"exports"`
}

type ProofVerifyRequest struct {
	RequestID  string `json:"request_id"`
	ArtifactID string `json:"artifact_id"`
	Inputs     json.RawMessage `json:"inputs"`
}

type ProofVerifyResponse struct {
	BaseResponse
	Valid   bool   `json:"valid"`
	Output  json.RawMessage `json:"output,omitempty"`
	GasUsed int64  `json:"gas_used"`
}

type ProofGenerateRequest struct {
	RequestID  string          `json:"request_id"`
	Statement  json.RawMessage `json:"statement"`
	Tactics    []string        `json:"tactics,omitempty"`
	Timeout    int             `json:"timeout,omitempty"`
}

type ProofGenerateResponse struct {
	BaseResponse
	Proof      json.RawMessage `json:"proof,omitempty"`
	ProofHash  string          `json:"proof_hash,omitempty"`
	Complete   bool            `json:"complete"`
}

type ProofExportRequest struct {
	RequestID  string `json:"request_id"`
	ArtifactID string `json:"artifact_id"`
	Format     string `json:"format"` // json, binary, latex, coq
}

type ProofExportResponse struct {
	BaseResponse
	Data string `json:"data"`
}

// ============================================================================
// PLASMA CONSENSUS
// ============================================================================

type PlasmaEnforceRequest struct {
	RequestID  string                 `json:"request_id"`
	PolicyID   string                 `json:"policy_id"`
	Action     string                 `json:"action"`
	Context    map[string]interface{} `json:"context"`
	Proof      json.RawMessage        `json:"proof,omitempty"`
}

type PlasmaEnforceResponse struct {
	BaseResponse
	Allowed    bool   `json:"allowed"`
	DecisionID string `json:"decision_id"`
	Reason     string `json:"reason,omitempty"`
}

type PlasmaVerifyRequest struct {
	RequestID  string `json:"request_id"`
	DecisionID string `json:"decision_id"`
	Proof      json.RawMessage `json:"proof"`
}

type PlasmaVerifyResponse struct {
	BaseResponse
	Valid bool `json:"valid"`
}

type PlasmaProposeRequest struct {
	RequestID  string                 `json:"request_id"`
	Pro