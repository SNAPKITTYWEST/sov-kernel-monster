// Bell Pair (EPR Pair) Circuit
// Creates a maximally entangled two-qubit state
// |Φ+⟩ = (|00⟩ + |11⟩) / √2

OPENQASM 2.0;
include "qelib1.inc";

// Declare quantum and classical registers
qreg q[2];
creg c[2];

// Create Bell pair
h q[0];           // Hadamard on first qubit
cx q[0], q[1];    // CNOT with first qubit as control

// Measure both qubits
measure q[0] -> c[0];
measure q[1] -> c[1];