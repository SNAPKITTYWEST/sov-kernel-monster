// GHZ State (Greenberger-Horne-Zeilinger)
// Creates a three-qubit entangled state
// |GHZ⟩ = (|000⟩ + |111⟩) / √2

OPENQASM 2.0;
include "qelib1.inc";

qreg q[3];
creg c[3];

// Create GHZ state
h q[0];
cx q[0], q[1];
cx q[1], q[2];

// Measure all qubits
measure q -> c;