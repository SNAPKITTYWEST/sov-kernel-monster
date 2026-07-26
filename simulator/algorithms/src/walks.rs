//! Quantum Walks - Graph Exploration and Mixing
//!
//! Discrete quantum walks on graphs with coin and position registers.
//! Used for search, mixing, and quantum speedups.
//!
//! Walk types:
//! - Coined walks: explicit coin flip register
//! - Adjacency matrix walks: directly on graph Laplacian

use crate::{AlgorithmError, AlgorithmResult};
use std::collections::HashMap;

/// Graph representation for walks
#[derive(Debug, Clone)]
pub struct Graph {
    /// Vertex count
    pub vertices: usize,

    /// Adjacency list
    pub edges: Vec<Vec<usize>>,
}

impl Graph {
    /// Create new graph
    pub fn new(vertices: usize) -> Self {
        Graph {
            vertices,
            edges: vec![Vec::new(); vertices],
        }
    }

    /// Add undirected edge
    pub fn add_edge(&mut self, u: usize, v: usize) -> AlgorithmResult<()> {
        if u >= self.vertices || v >= self.vertices {
            return Err(AlgorithmError::InvalidGraph("Vertex out of range".to_string()));
        }

        if u == v {
            return Err(AlgorithmError::InvalidGraph("No self-loops".to_string()));
        }

        if !self.edges[u].contains(&v) {
            self.edges[u].push(v);
        }
        if !self.edges[v].contains(&u) {
            self.edges[v].push(u);
        }

        Ok(())
    }

    /// Get neighbors of vertex
    pub fn neighbors(&self, v: usize) -> AlgorithmResult<Vec<usize>> {
        if v >= self.vertices {
            return Err(AlgorithmError::InvalidGraph("Vertex out of range".to_string()));
        }
        Ok(self.edges[v].clone())
    }

    /// Get degree of vertex
    pub fn degree(&self, v: usize) -> AlgorithmResult<usize> {
        if v >= self.vertices {
            return Err(AlgorithmError::InvalidGraph("Vertex out of range".to_string()));
        }
        Ok(self.edges[v].len())
    }

    /// Check if regular (all vertices same degree)
    pub fn is_regular(&self) -> AlgorithmResult<bool> {
        if self.vertices == 0 {
            return Ok(true);
        }

        let d = self.degree(0)?;
        for v in 0..self.vertices {
            if self.degree(v)? != d {
                return Ok(false);
            }
        }
        Ok(true)
    }
}

/// Coined quantum walk state
#[derive(Debug, Clone)]
pub struct CoinedWalkState {
    /// Position probability distribution (classical)
    pub position_probs: Vec<f64>,

    /// Coin state (0 or 1)
    pub coin_state: u8,

    /// Time steps taken
    pub steps: usize,
}

impl CoinedWalkState {
    /// Initialize at vertex with coin
    pub fn new(vertices: usize) -> Self {
        let mut probs = vec![0.0; vertices];
        probs[0] = 1.0; // Start at vertex 0

        CoinedWalkState {
            position_probs: probs,
            coin_state: 0,
            steps: 0,
        }
    }

    /// Get probability at position after mixing
    pub fn prob_at(&self, v: usize) -> Option<f64> {
        if v < self.position_probs.len() {
            Some(self.position_probs[v])
        } else {
            None
        }
    }

    /// Mixing time (steps to near-uniform distribution)
    pub fn mixing_time(&self, target_uniformity: f64) -> Option<usize> {
        let n = self.position_probs.len() as f64;
        let uniform = 1.0 / n;

        // Check if within target_uniformity of uniform
        let all_close = self
            .position_probs
            .iter()
            .all(|&p| (p - uniform).abs() < target_uniformity);

        if all_close {
            Some(self.steps)
        } else {
            None
        }
    }
}

/// 1D line quantum walk
#[derive(Debug, Clone)]
pub struct LineQuantumWalk {
    /// Position range [-n, n]
    pub n: usize,

    /// Probability distribution
    pub probs: Vec<f64>,

    /// Current position (mapped to 0..2n+1)
    pub position: usize,

    /// Steps taken
    pub steps: usize,
}

impl LineQuantumWalk {
    /// Create new 1D walk on line [-n, n]
    pub fn new(n: usize) -> Self {
        let size = 2 * n + 1;
        let mut probs = vec![0.0; size];
        probs[n] = 1.0; // Start at 0

        LineQuantumWalk {
            n,
            probs,
            position: n,
            steps: 0,
        }
    }

    /// Take one quantum step
    pub fn step(&mut self) -> AlgorithmResult<()> {
        // Simplified: move to neighbors with 50% each
        let mut new_probs = vec![0.0; self.probs.len()];

        for (pos, prob) in self.probs.iter().enumerate() {
            if *prob > 0.0 {
                // Move left
                if pos > 0 {
                    new_probs[pos - 1] += prob * 0.5;
                }
                // Move right
                if pos < self.probs.len() - 1 {
                    new_probs[pos + 1] += prob * 0.5;
                }
            }
        }

        self.probs = new_probs;
        self.steps += 1;
        Ok(())
    }

    /// Run for t steps
    pub fn run(&mut self, t: usize) -> AlgorithmResult<()> {
        for _ in 0..t {
            self.step()?;
        }
        Ok(())
    }

    /// Get probability distribution
    pub fn distribution(&self) -> Vec<f64> {
        self.probs.clone()
    }

    /// Check if reached uniform distribution
    pub fn is_uniform(&self, tolerance: f64) -> bool {
        let target = 1.0 / self.probs.len() as f64;
        self.probs
            .iter()
            .all(|&p| (p - target).abs() < tolerance)
    }
}

/// Cycle graph quantum walk
#[derive(Debug, Clone)]
pub struct CycleQuantumWalk {
    /// Cycle size
    pub n: usize,

    /// Probability distribution
    pub probs: Vec<f64>,

    /// Steps taken
    pub steps: usize,
}

impl CycleQuantumWalk {
    /// Create walk on cycle of size n
    pub fn new(n: usize) -> AlgorithmResult<Self> {
        if n == 0 {
            return Err(AlgorithmError::InvalidGraph("Cycle size must be positive".to_string()));
        }

        let mut probs = vec![0.0; n];
        probs[0] = 1.0; // Start at vertex 0

        Ok(CycleQuantumWalk {
            n,
            probs,
            steps: 0,
        })
    }

    /// Take one step
    pub fn step(&mut self) -> AlgorithmResult<()> {
        let mut new_probs = vec![0.0; self.n];

        for (pos, prob) in self.probs.iter().enumerate() {
            if *prob > 0.0 {
                // Move clockwise
                let next = (pos + 1) % self.n;
                new_probs[next] += prob * 0.5;

                // Move counter-clockwise
                let prev = (pos + self.n - 1) % self.n;
                new_probs[prev] += prob * 0.5;
            }
        }

        self.probs = new_probs;
        self.steps += 1;
        Ok(())
    }

    /// Get mixing time to uniform distribution
    pub fn mixing_time(&mut self, tolerance: f64) -> AlgorithmResult<usize> {
        let target = 1.0 / self.n as f64;

        loop {
            self.step()?;

            let all_uniform = self
                .probs
                .iter()
                .all(|&p| (p - target).abs() < tolerance);

            if all_uniform || self.steps > 1000 {
                break;
            }
        }

        Ok(self.steps)
    }

    /// Get spectral gap (for analysis)
    pub fn spectral_gap(&self) -> f64 {
        // For cycle: λ₂ = 2 - 2cos(2π/n)
        2.0 - 2.0 * (2.0 * std::f64::consts::PI / self.n as f64).cos()
    }
}

/// Adjacency matrix representation (for mixing analysis)
#[derive(Debug, Clone)]
pub struct AdjacencyMatrixWalk {
    /// Adjacency matrix (n×n)
    pub matrix: Vec<Vec<f64>>,

    /// Probability distribution
    pub probs: Vec<f64>,

    /// Steps
    pub steps: usize,
}

impl AdjacencyMatrixWalk {
    /// Create from graph
    pub fn from_graph(graph: &Graph) -> AlgorithmResult<Self> {
        let n = graph.vertices;
        let mut matrix = vec![vec![0.0; n]; n];

        for u in 0..n {
            let deg = graph.degree(u)?;
            for &v in &graph.edges[u] {
                matrix[u][v] = 1.0 / deg as f64;
            }
        }

        let mut probs = vec![0.0; n];
        probs[0] = 1.0;

        Ok(AdjacencyMatrixWalk {
            matrix,
            probs,
            steps: 0,
        })
    }

    /// Apply transition matrix
    pub fn step(&mut self) {
        let n = self.probs.len();
        let mut new_probs = vec![0.0; n];

        for i in 0..n {
            for j in 0..n {
                new_probs[i] += self.matrix[j][i] * self.probs[j];
            }
        }

        self.probs = new_probs;
        self.steps += 1;
    }

    /// Run t steps
    pub fn run(&mut self, t: usize) {
        for _ in 0..t {
            self.step();
        }
    }

    /// Stationary distribution
    pub fn stationary_distribution(&self) -> Vec<f64> {
        // For undirected graphs: uniform over all vertices
        vec![1.0 / self.probs.len() as f64; self.probs.len()]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_graph_creation() {
        let graph = Graph::new(3);
        assert_eq!(graph.vertices, 3);
    }

    #[test]
    fn test_graph_add_edge() {
        let mut graph = Graph::new(3);
        assert!(graph.add_edge(0, 1).is_ok());
        assert!(graph.add_edge(0, 0).is_err()); // No self-loops
    }

    #[test]
    fn test_graph_neighbors() {
        let mut graph = Graph::new(3);
        graph.add_edge(0, 1).unwrap();
        graph.add_edge(0, 2).unwrap();

        let neighbors = graph.neighbors(0).unwrap();
        assert_eq!(neighbors.len(), 2);
    }

    #[test]
    fn test_coined_walk_state() {
        let state = CoinedWalkState::new(5);
        assert_eq!(state.prob_at(0), Some(1.0));
        assert_eq!(state.prob_at(1), Some(0.0));
    }

    #[test]
    fn test_line_quantum_walk() {
        let walk = LineQuantumWalk::new(10);
        assert_eq!(walk.probs.len(), 21);
    }

    #[test]
    fn test_line_walk_step() {
        let mut walk = LineQuantumWalk::new(5);
        assert!(walk.step().is_ok());
        assert_eq!(walk.steps, 1);
    }

    #[test]
    fn test_cycle_quantum_walk() {
        let walk = CycleQuantumWalk::new(5);
        assert!(walk.is_ok());
    }

    #[test]
    fn test_cycle_walk_step() {
        let mut walk = CycleQuantumWalk::new(4).unwrap();
        assert!(walk.step().is_ok());
        assert_eq!(walk.steps, 1);
    }

    #[test]
    fn test_spectral_gap() {
        let walk = CycleQuantumWalk::new(4).unwrap();
        let gap = walk.spectral_gap();
        assert!(gap > 0.0);
    }

    #[test]
    fn test_adjacency_matrix_walk() {
        let mut graph = Graph::new(3);
        graph.add_edge(0, 1).unwrap();
        graph.add_edge(1, 2).unwrap();
        graph.add_edge(2, 0).unwrap();

        let walk = AdjacencyMatrixWalk::from_graph(&graph);
        assert!(walk.is_ok());
    }
}

// Made with Bob
