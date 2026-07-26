//! # Quantum Topology Module
//!
//! Coupling graph representation and native gate support queries.
//! Re-exports from backend_contract but provides specialized operations
//! for topology analysis.

use crate::backend_contract::{CouplingGraph, NativeGate, BackendError, Result};
use std::collections::BTreeSet;

/// Extended topology analysis
pub struct TopologyAnalyzer;

impl TopologyAnalyzer {
    /// Check if graph is connected
    pub fn is_connected(graph: &CouplingGraph) -> Result<bool> {
        let n = graph.num_qubits();
        if n == 0 {
            return Err(BackendError::EmptyBackend);
        }

        let mut visited = vec![false; n];
        let mut queue = std::collections::VecDeque::new();
        queue.push_back(0);
        visited[0] = true;

        while let Some(node) = queue.pop_front() {
            for neighbor in graph.neighbors(node)? {
                if !visited[neighbor] {
                    visited[neighbor] = true;
                    queue.push_back(neighbor);
                }
            }
        }

        Ok(visited.iter().all(|&v| v))
    }

    /// Find connected components
    pub fn connected_components(graph: &CouplingGraph) -> Result<Vec<Vec<usize>>> {
        let n = graph.num_qubits();
        let mut visited = vec![false; n];
        let mut components = Vec::new();

        for start in 0..n {
            if !visited[start] {
                let mut component = Vec::new();
                let mut queue = std::collections::VecDeque::new();
                queue.push_back(start);
                visited[start] = true;

                while let Some(node) = queue.pop_front() {
                    component.push(node);
                    for neighbor in graph.neighbors(node)? {
                        if !visited[neighbor] {
                            visited[neighbor] = true;
                            queue.push_back(neighbor);
                        }
                    }
                }

                components.push(component);
            }
        }

        Ok(components)
    }

    /// Compute diameter (max distance between any two qubits)
    pub fn diameter(graph: &CouplingGraph) -> Result<usize> {
        let n = graph.num_qubits();
        if n == 0 {
            return Err(BackendError::EmptyBackend);
        }

        let mut max_dist = 0;
        for i in 0..n {
            for j in i + 1..n {
                let dist = graph.distance(i, j)?;
                if dist == usize::MAX {
                    return Ok(usize::MAX); // Not connected
                }
                max_dist = max_dist.max(dist);
            }
        }

        Ok(max_dist)
    }

    /// Compute average degree
    pub fn average_degree(graph: &CouplingGraph) -> Result<f64> {
        let n = graph.num_qubits();
        if n == 0 {
            return Err(BackendError::EmptyBackend);
        }

        let mut total_degree = 0usize;
        for i in 0..n {
            let neighbors = graph.neighbors(i)?;
            total_degree += neighbors.len();
        }

        Ok(total_degree as f64 / n as f64)
    }

    /// Check if topology is a line (path graph)
    pub fn is_linear(graph: &CouplingGraph) -> Result<bool> {
        let n = graph.num_qubits();
        for i in 0..n {
            let degree = graph.neighbors(i)?.len();
            match i {
                0 | _ if i == n - 1 => {
                    if degree != 2 {
                        return Ok(false);
                    }
                }
                _ => {
                    if degree != 3 {
                        // 3 = 2 neighbors + self-loop (if present)
                        return Ok(false);
                    }
                }
            }
        }
        Ok(true)
    }

    /// Check if topology is fully connected
    pub fn is_fully_connected(graph: &CouplingGraph) -> Result<bool> {
        let n = graph.num_qubits();
        for i in 0..n {
            for j in 0..n {
                if !graph.are_connected(i, j)? {
                    return Ok(false);
                }
            }
        }
        Ok(true)
    }

    /// Get all two-qubit connections that support a gate
    pub fn get_two_qubit_gate_support(
        graph: &CouplingGraph,
        gate: &NativeGate,
    ) -> Result<Vec<(usize, usize)>> {
        if !matches!(gate, NativeGate::CX | NativeGate::CZ | NativeGate::SWAP) {
            return Err(BackendError::UnsupportedGate(gate.to_string()));
        }

        let n = graph.num_qubits();
        let mut connections = Vec::new();

        for i in 0..n {
            for j in i + 1..n {
                if graph.are_connected(i, j)? {
                    connections.push((i, j));
                }
            }
        }

        Ok(connections)
    }

    /// Find shortest path between two qubits
    pub fn shortest_path(graph: &CouplingGraph, start: usize, end: usize) -> Result<Vec<usize>> {
        let n = graph.num_qubits();
        if start >= n || end >= n {
            return Err(BackendError::InvalidQubit(if start >= n { start } else { end }));
        }

        if start == end {
            return Ok(vec![start]);
        }

        let mut visited = vec![false; n];
        let mut parent = vec![None; n];
        let mut queue = std::collections::VecDeque::new();
        queue.push_back(start);
        visited[start] = true;

        while let Some(node) = queue.pop_front() {
            if node == end {
                // Reconstruct path
                let mut path = vec![end];
                let mut current = end;
                while let Some(Some(p)) = parent.get(current) {
                    path.push(*p);
                    current = *p;
                }
                path.reverse();
                return Ok(path);
            }

            for neighbor in graph.neighbors(node)? {
                if !visited[neighbor] {
                    visited[neighbor] = true;
                    parent[neighbor] = Some(node);
                    queue.push_back(neighbor);
                }
            }
        }

        Ok(Vec::new()) // Not connected
    }

    /// Identify bottleneck qubits (critical for connectivity)
    pub fn articulation_points(graph: &CouplingGraph) -> Result<Vec<usize>> {
        let n = graph.num_qubits();
        let mut articulation = Vec::new();

        for v in 0..n {
            // Try removing vertex v
            let mut visited = vec![false; n];
            let components = Self::count_connected_components_excluding(graph, v, &mut visited)?;

            // If removing v increases component count, v is articulation point
            if components > 1 {
                articulation.push(v);
            }
        }

        Ok(articulation)
    }

    fn count_connected_components_excluding(
        graph: &CouplingGraph,
        excluded: usize,
        visited: &mut Vec<bool>,
    ) -> Result<usize> {
        let n = graph.num_qubits();
        let mut components = 0;

        for start in 0..n {
            if start != excluded && !visited[start] {
                components += 1;
                let mut queue = std::collections::VecDeque::new();
                queue.push_back(start);
                visited[start] = true;

                while let Some(node) = queue.pop_front() {
                    for neighbor in graph.neighbors(node)? {
                        if neighbor != excluded && !visited[neighbor] {
                            visited[neighbor] = true;
                            queue.push_back(neighbor);
                        }
                    }
                }
            }
        }

        Ok(components)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn linear_graph(n: usize) -> CouplingGraph {
        let mut connectivity = vec![vec![false; n]; n];
        for i in 0..n {
            connectivity[i][i] = true; // self-loop
            if i + 1 < n {
                connectivity[i][i + 1] = true;
                connectivity[i + 1][i] = true;
            }
        }
        CouplingGraph::new(connectivity).unwrap()
    }

    fn fully_connected(n: usize) -> CouplingGraph {
        let connectivity = vec![vec![true; n]; n];
        CouplingGraph::new(connectivity).unwrap()
    }

    #[test]
    fn test_is_connected() {
        let graph = linear_graph(5);
        assert!(TopologyAnalyzer::is_connected(&graph).unwrap());
    }

    #[test]
    fn test_is_linear() {
        let graph = linear_graph(5);
        assert!(TopologyAnalyzer::is_linear(&graph).unwrap());
    }

    #[test]
    fn test_is_fully_connected() {
        let graph = fully_connected(4);
        assert!(TopologyAnalyzer::is_fully_connected(&graph).unwrap());
    }

    #[test]
    fn test_diameter() {
        let graph = linear_graph(5);
        assert_eq!(TopologyAnalyzer::diameter(&graph).unwrap(), 4);
    }

    #[test]
    fn test_shortest_path() {
        let graph = linear_graph(5);
        let path = TopologyAnalyzer::shortest_path(&graph, 0, 4).unwrap();
        assert_eq!(path, vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn test_average_degree() {
        let graph = linear_graph(5);
        let avg = TopologyAnalyzer::average_degree(&graph).unwrap();
        // Edges: 0-1, 1-2, 2-3, 3-4 + 5 self-loops = 9 edges / 5 = 1.8
        assert!(avg > 1.0 && avg < 3.0);
    }

    #[test]
    fn test_two_qubit_gate_support() {
        let graph = linear_graph(3);
        let connections = TopologyAnalyzer::get_two_qubit_gate_support(&graph, &NativeGate::CX)
            .unwrap();
        assert_eq!(connections.len(), 2); // (0,1) and (1,2)
    }
}
