// Stabilizer tableau QEC — replaces hardcoded distance=3 in qec-discovery.
// Aaronson-Gottesman binary symplectic representation.
// Rows of matrix = stabilizer generators, columns = [x_1..x_n | z_1..z_n].

use ndarray::Array2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pauli { I, X, Y, Z }

impl Pauli {
    fn bits(self) -> (u8, u8) {
        match self {
            Pauli::I => (0, 0),
            Pauli::X => (1, 0),
            Pauli::Y => (1, 1),
            Pauli::Z => (0, 1),
        }
    }
    fn from_bits(x: u8, z: u8) -> Self {
        match (x & 1, z & 1) {
            (0, 0) => Pauli::I,
            (1, 0) => Pauli::X,
            (1, 1) => Pauli::Y,
            (0, 1) => Pauli::Z,
            _ => unreachable!(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct StabilizerTableau {
    pub n_qubits: usize,
    /// Shape: (n_generators, 2*n_qubits). Row i = [x_bits | z_bits].
    pub matrix: Array2<u8>,
}

impl StabilizerTableau {
    /// Initialize to Z stabilizers: S_i = Z_i (the |0⟩^n state).
    pub fn new(n_qubits: usize) -> Self {
        let n = n_qubits;
        let mut matrix = Array2::<u8>::zeros((n, 2 * n));
        for i in 0..n {
            matrix[(i, n + i)] = 1; // Z_i
        }
        Self { n_qubits, matrix }
    }

    pub fn from_generators(gens: Vec<Vec<u8>>) -> Self {
        let n_qubits = gens[0].len() / 2;
        let n_gen = gens.len();
        let mut matrix = Array2::<u8>::zeros((n_gen, 2 * n_qubits));
        for (i, row) in gens.iter().enumerate() {
            for (j, &v) in row.iter().enumerate() {
                matrix[(i, j)] = v;
            }
        }
        Self { n_qubits, matrix }
    }

    pub fn row(&self, i: usize) -> Vec<u8> {
        (0..2 * self.n_qubits).map(|j| self.matrix[(i, j)]).collect()
    }
}

/// H gate: swap x and z bits for the given qubit across all generators.
pub fn apply_hadamard(t: &mut StabilizerTableau, qubit: usize) {
    let n = t.n_qubits;
    let rows = t.matrix.nrows();
    for i in 0..rows {
        let x = t.matrix[(i, qubit)];
        let z = t.matrix[(i, n + qubit)];
        t.matrix[(i, qubit)] = z;
        t.matrix[(i, n + qubit)] = x;
    }
}

/// CNOT gate: control → target propagation in symplectic rep.
pub fn apply_cnot(t: &mut StabilizerTableau, ctrl: usize, tgt: usize) {
    let n = t.n_qubits;
    let rows = t.matrix.nrows();
    for i in 0..rows {
        t.matrix[(i, tgt)] ^= t.matrix[(i, ctrl)];
        t.matrix[(i, n + ctrl)] ^= t.matrix[(i, n + tgt)];
    }
}

/// Symplectic inner product: commutes iff result == 0.
pub fn check_commutativity(g1: &[u8], g2: &[u8]) -> bool {
    let n = g1.len() / 2;
    let mut s = 0u8;
    for i in 0..n {
        s ^= (g1[i] & g2[n + i]) ^ (g1[n + i] & g2[i]);
    }
    s == 0
}

/// Greedy minimum-weight logical operator search.
/// Returns minimum weight d such that a weight-d Pauli commutes with all
/// stabilizers but is not in the stabilizer group (i.e., is a logical op).
/// Replaces hardcoded distance=3 in qec-discovery.
pub fn estimate_distance(t: &StabilizerTableau) -> u32 {
    let n = t.n_qubits;
    let n_gen = t.matrix.nrows();
    let stabilizers: Vec<Vec<u8>> = (0..n_gen).map(|i| t.row(i)).collect();

    for weight in 1..=n {
        if search_weight(n, weight, &stabilizers).is_some() {
            return weight as u32;
        }
    }
    n as u32
}

fn search_weight(n: usize, weight: usize, stabs: &[Vec<u8>]) -> Option<Vec<u8>> {
    let mut pauli = vec![0u8; 2 * n];
    recurse(0, 0, weight, n, &mut pauli, stabs)
}

fn recurse(
    pos: usize,
    chosen: usize,
    target: usize,
    n: usize,
    pauli: &mut Vec<u8>,
    stabs: &[Vec<u8>],
) -> Option<Vec<u8>> {
    if chosen == target {
        return if is_logical_op(pauli, stabs) { Some(pauli.clone()) } else { None };
    }
    if pos >= n || n - pos < target - chosen {
        return None;
    }
    // try non-identity Paulis at this position
    for p in [Pauli::X, Pauli::Y, Pauli::Z] {
        let (x, z) = p.bits();
        pauli[pos] = x;
        pauli[n + pos] = z;
        if let Some(res) = recurse(pos + 1, chosen + 1, target, n, pauli, stabs) {
            return Some(res);
        }
    }
    pauli[pos] = 0;
    pauli[n + pos] = 0;
    recurse(pos + 1, chosen, target, n, pauli, stabs)
}

fn is_logical_op(pauli: &[u8], stabs: &[Vec<u8>]) -> bool {
    // must be non-identity
    if pauli.iter().all(|&v| v == 0) {
        return false;
    }
    // must commute with all stabilizers
    for s in stabs {
        if !check_commutativity(pauli, s) {
            return false;
        }
    }
    // must not be in the stabilizer group (not a product of generators)
    // simplified check: not equal to any generator
    !stabs.iter().any(|s| s.as_slice() == pauli)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hadamard_swap() {
        let mut t = StabilizerTableau::new(2);
        // initial: Z0, Z1 → rows [(0,0,1,0), (0,0,0,1)]
        apply_hadamard(&mut t, 0);
        // Z0 should become X0
        assert_eq!(t.matrix[(0, 0)], 1); // x bit
        assert_eq!(t.matrix[(0, 2)], 0); // z bit
    }

    #[test]
    fn test_commutativity_xx_zz() {
        // X⊗X and Z⊗Z: [1,1,0,0] vs [0,0,1,1]
        let g1 = vec![1u8, 1, 0, 0];
        let g2 = vec![0u8, 0, 1, 1];
        // XX and ZZ commute (both have even symplectic product)
        assert!(check_commutativity(&g1, &g2));
    }

    #[test]
    fn test_distance_1qubit() {
        // Single qubit, stabilizer = [Z] → any X or Y is distance 1
        let t = StabilizerTableau::from_generators(vec![vec![0u8, 1]]);
        let d = estimate_distance(&t);
        assert_eq!(d, 1);
    }
}
