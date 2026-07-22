//! QATAAUM Routing Engine
//!
//! Implements SABRE-inspired routing algorithm for mapping logical qubits
//! to physical qubits on constrained topologies.
//!
//! Based on public research:
//! - "SABRE: Practical Quantum Circuit Routing" (Li et al., 2019)
//! - https://arxiv.org/abs/1809.02573

use std::collections::{HashMap, HashSet, VecDeque};

/// Physical qubit identifier
pub type PhysicalQubit = usize;

/// Logical qubit identifier
pub type LogicalQubit = usize;

/// Connectivity graph representing processor topology
#[derive(Debug, Clone)]
pub struct TopologyGraph {
    /// Number of physical qubits
    pub num_qubits: usize,
    
    /// Adjacency list: physical qubit -> connected physical qubits
    pub edges: HashMap<PhysicalQubit, Vec<PhysicalQubit>>,
    
    /// Distance matrix (precomputed shortest paths)
    pub distances: Vec<Vec<usize>>,
}

impl TopologyGraph {
    /// Create a new topology graph
    pub fn new(num_qubits: usize) -> Self {
        let mut edges = HashMap::new();
        for i in 0..num_qubits {
            edges.insert(i, Vec::new());
        }
        
        let distances = vec![vec![usize::MAX; num_qubits]; num_qubits];
        
        Self {
            num_qubits,
            edges,
            distances,
        }
    }
    
    /// Add an undirected edge between two physical qubits
    pub fn add_edge(&mut self, q1: PhysicalQubit, q2: PhysicalQubit) {
        self.edges.entry(q1).or_insert_with(Vec::new).push(q2);
        self.edges.entry(q2).or_insert_with(Vec::new).push(q1);
    }
    
    /// Compute all-pairs shortest paths (Floyd-Warshall)
    pub fn compute_distances(&mut self) {
        // Initialize distances
        for i in 0..self.num_qubits {
            for j in 0..self.num_qubits {
                if i == j {
                    self.distances[i][j] = 0;
                } else {
                    self.distances[i][j] = usize::MAX / 2; // Avoid overflow
                }
            }
        }
        
        // Set edge distances
        for (q1, neighbors) in &self.edges {
            for q2 in neighbors {
                self.distances[*q1][*q2] = 1;
            }
        }
        
        // Floyd-Warshall algorithm
        for k in 0..self.num_qubits {
            for i in 0..self.num_qubits {
                for j in 0..self.num_qubits {
                    if self.distances[i][k] + self.distances[k][j] < self.distances[i][j] {
                        self.distances[i][j] = self.distances[i][k] + self.distances[k][j];
                    }
                }
            }
        }
    }
    
    /// Get distance between two physical qubits
    pub fn distance(&self, q1: PhysicalQubit, q2: PhysicalQubit) -> usize {
        self.distances[q1][q2]
    }
    
    /// Check if two physical qubits are adjacent
    pub fn are_adjacent(&self, q1: PhysicalQubit, q2: PhysicalQubit) -> bool {
        self.edges.get(&q1).map_or(false, |neighbors| neighbors.contains(&q2))
    }
    
    /// Get neighbors of a physical qubit
    pub fn neighbors(&self, q: PhysicalQubit) -> &[PhysicalQubit] {
        self.edges.get(&q).map_or(&[], |v| v.as_slice())
    }
}

/// Two-qubit gate in the circuit
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TwoQubitGate {
    pub control: LogicalQubit,
    pub target: LogicalQubit,
    pub gate_index: usize,
}

/// SWAP gate insertion
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SwapGate {
    pub q1: PhysicalQubit,
    pub q2: PhysicalQubit,
    pub insert_before: usize, // Gate index to insert before
}

/// Qubit mapping: logical -> physical
pub type QubitMapping = HashMap<LogicalQubit, PhysicalQubit>;

/// Routing result
#[derive(Debug, Clone)]
pub struct RoutingResult {
    /// Initial qubit mapping
    pub initial_mapping: QubitMapping,
    
    /// SWAP gates to insert
    pub swaps: Vec<SwapGate>,
    
    /// Final qubit mapping
    pub final_mapping: QubitMapping,
    
    /// Total number of SWAPs inserted
    pub swap_count: usize,
}

/// SABRE routing algorithm
pub struct SabreRouter {
    /// Topology graph
    topology: TopologyGraph,
    
    /// Lookahead window size
    lookahead: usize,
    
    /// Decay parameter for extended set
    decay_delta: f64,
    
    /// Weight for distance heuristic
    weight_distance: f64,
    
    /// Weight for parallelism heuristic
    weight_parallelism: f64,
}

impl SabreRouter {
    /// Create a new SABRE router
    pub fn new(topology: TopologyGraph) -> Self {
        Self {
            topology,
            lookahead: 20,
            decay_delta: 0.001,
            weight_distance: 0.5,
            weight_parallelism: 0.5,
        }
    }
    
    /// Set lookahead window size
    pub fn with_lookahead(mut self, lookahead: usize) -> Self {
        self.lookahead = lookahead;
        self
    }
    
    /// Set heuristic weights
    pub fn with_weights(mut self, distance: f64, parallelism: f64) -> Self {
        self.weight_distance = distance;
        self.weight_parallelism = parallelism;
        self
    }
    
    /// Route a circuit
    pub fn route(&self, gates: &[TwoQubitGate], num_logical_qubits: usize) -> RoutingResult {
        // Initial mapping (trivial: logical i -> physical i)
        let mut mapping: QubitMapping = (0..num_logical_qubits)
            .map(|i| (i, i))
            .collect();
        
        let initial_mapping = mapping.clone();
        let mut swaps = Vec::new();
        let mut gate_index = 0;
        
        while gate_index < gates.len() {
            let gate = gates[gate_index];
            let phys_control = mapping[&gate.control];
            let phys_target = mapping[&gate.target];
            
            // Check if gate is executable
            if self.topology.are_adjacent(phys_control, phys_target) {
                // Gate is executable, move to next gate
                gate_index += 1;
            } else {
                // Need to insert SWAP
                let swap = self.find_best_swap(&mapping, gates, gate_index);
                
                // Apply SWAP to mapping
                let q1_logical = self.find_logical_qubit(&mapping, swap.q1);
                let q2_logical = self.find_logical_qubit(&mapping, swap.q2);
                
                if let (Some(l1), Some(l2)) = (q1_logical, q2_logical) {
                    mapping.insert(l1, swap.q2);
                    mapping.insert(l2, swap.q1);
                }
                
                swaps.push(swap);
            }
        }
        
        RoutingResult {
            initial_mapping,
            swaps: swaps.clone(),
            final_mapping: mapping,
            swap_count: swaps.len(),
        }
    }
    
    /// Find the best SWAP to insert
    fn find_best_swap(
        &self,
        mapping: &QubitMapping,
        gates: &[TwoQubitGate],
        current_index: usize,
    ) -> SwapGate {
        let mut best_swap = None;
        let mut best_score = f64::MAX;
        
        // Get front layer (executable gates)
        let front_layer = self.get_front_layer(mapping, gates, current_index);
        
        // Get extended set (lookahead)
        let extended_set = self.get_extended_set(mapping, gates, current_index);
        
        // Try all possible SWAPs
        for &q1 in mapping.values() {
            for &q2 in self.topology.neighbors(q1) {
                // Compute heuristic score
                let score = self.compute_swap_score(
                    mapping,
                    q1,
                    q2,
                    &front_layer,
                    &extended_set,
                );
                
                if score < best_score {
                    best_score = score;
                    best_swap = Some(SwapGate {
                        q1,
                        q2,
                        insert_before: current_index,
                    });
                }
            }
        }
        
        best_swap.expect("No valid SWAP found")
    }
    
    /// Get front layer of gates (immediately executable after SWAPs)
    fn get_front_layer(
        &self,
        mapping: &QubitMapping,
        gates: &[TwoQubitGate],
        start_index: usize,
    ) -> Vec<TwoQubitGate> {
        let mut front = Vec::new();
        let mut executed = HashSet::new();
        
        for i in start_index..gates.len() {
            let gate = gates[i];
            
            // Check if gate's qubits are not blocked
            if !executed.contains(&gate.control) && !executed.contains(&gate.target) {
                front.push(gate);
                executed.insert(gate.control);
                executed.insert(gate.target);
            }
            
            if front.len() >= self.lookahead {
                break;
            }
        }
        
        front
    }
    
    /// Get extended set (lookahead with decay)
    fn get_extended_set(
        &self,
        mapping: &QubitMapping,
        gates: &[TwoQubitGate],
        start_index: usize,
    ) -> Vec<TwoQubitGate> {
        let mut extended = Vec::new();
        
        for i in start_index..gates.len().min(start_index + self.lookahead) {
            extended.push(gates[i]);
        }
        
        extended
    }
    
    /// Compute heuristic score for a SWAP
    fn compute_swap_score(
        &self,
        mapping: &QubitMapping,
        q1: PhysicalQubit,
        q2: PhysicalQubit,
        front_layer: &[TwoQubitGate],
        extended_set: &[TwoQubitGate],
    ) -> f64 {
        // Apply hypothetical SWAP
        let mut temp_mapping = mapping.clone();
        let l1 = self.find_logical_qubit(mapping, q1);
        let l2 = self.find_logical_qubit(mapping, q2);
        
        if let (Some(logical1), Some(logical2)) = (l1, l2) {
            temp_mapping.insert(logical1, q2);
            temp_mapping.insert(logical2, q1);
        }
        
        // Distance heuristic: sum of distances for front layer
        let mut distance_score = 0.0;
        for gate in front_layer {
            let phys_control = temp_mapping[&gate.control];
            let phys_target = temp_mapping[&gate.target];
            distance_score += self.topology.distance(phys_control, phys_target) as f64;
        }
        
        // Parallelism heuristic: number of gates that become executable
        let mut parallelism_score = 0.0;
        for gate in extended_set {
            let phys_control = temp_mapping[&gate.control];
            let phys_target = temp_mapping[&gate.target];
            if self.topology.are_adjacent(phys_control, phys_target) {
                parallelism_score -= 1.0; // Negative because we want to maximize
            }
        }
        
        // Combined score
        self.weight_distance * distance_score + self.weight_parallelism * parallelism_score
    }
    
    /// Find logical qubit mapped to a physical qubit
    fn find_logical_qubit(&self, mapping: &QubitMapping, physical: PhysicalQubit) -> Option<LogicalQubit> {
        mapping.iter()
            .find(|(_, &p)| p == physical)
            .map(|(&l, _)| l)
    }
}

/// Create a linear topology (chain)
pub fn linear_topology(num_qubits: usize) -> TopologyGraph {
    let mut topology = TopologyGraph::new(num_qubits);
    
    for i in 0..num_qubits - 1 {
        topology.add_edge(i, i + 1);
    }
    
    topology.compute_distances();
    topology
}

/// Create a heavy-hex topology (IBM Quantum)
pub fn heavy_hex_topology(rows: usize, cols: usize) -> TopologyGraph {
    let num_qubits = rows * cols;
    let mut topology = TopologyGraph::new(num_qubits);
    
    // Heavy-hex pattern: degree-3 connectivity
    for row in 0..rows {
        for col in 0..cols {
            let q = row * cols + col;
            
            // Horizontal connections
            if col + 1 < cols {
                topology.add_edge(q, q + 1);
            }
            
            // Vertical connections (alternating pattern)
            if row + 1 < rows {
                if col % 2 == 0 {
                    topology.add_edge(q, q + cols);
                } else if col > 0 {
                    topology.add_edge(q, q + cols - 1);
                }
            }
        }
    }
    
    topology.compute_distances();
    topology
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_linear_topology() {
        let topology = linear_topology(5);
        
        assert_eq!(topology.num_qubits, 5);
        assert!(topology.are_adjacent(0, 1));
        assert!(topology.are_adjacent(1, 2));
        assert!(!topology.are_adjacent(0, 2));
        
        assert_eq!(topology.distance(0, 4), 4);
        assert_eq!(topology.distance(1, 3), 2);
    }
    
    #[test]
    fn test_routing_simple() {
        let topology = linear_topology(3);
        let router = SabreRouter::new(topology);
        
        // Circuit: CNOT(0, 2) - requires SWAP
        let gates = vec![
            TwoQubitGate {
                control: 0,
                target: 2,
                gate_index: 0,
            },
        ];
        
        let result = router.route(&gates, 3);
        
        // Should insert at least one SWAP
        assert!(result.swap_count > 0);
    }
    
    #[test]
    fn test_routing_adjacent() {
        let topology = linear_topology(3);
        let router = SabreRouter::new(topology);
        
        // Circuit: CNOT(0, 1) - no SWAP needed
        let gates = vec![
            TwoQubitGate {
                control: 0,
                target: 1,
                gate_index: 0,
            },
        ];
        
        let result = router.route(&gates, 3);
        
        // Should not insert any SWAPs
        assert_eq!(result.swap_count, 0);
    }
    
    #[test]
    fn test_heavy_hex_topology() {
        let topology = heavy_hex_topology(2, 3);
        
        assert_eq!(topology.num_qubits, 6);
        
        // Check some connections
        assert!(topology.are_adjacent(0, 1));
        assert!(topology.are_adjacent(0, 3));
    }
}

// Made with Bob
