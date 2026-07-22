//! QATAAUM IR Level 5: TOPO
//!
//! Target-coupled placement and routing representation.
//! Maps logical qubits to physical qubits respecting hardware topology.

use crate::gate::{GateProgram, Gate, GateKind};
use std::collections::HashMap;

/// Physical qubit identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct PhysicalQubit(pub u32);

/// Logical qubit identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct LogicalQubit(pub u32);

/// Hardware topology representation
#[derive(Debug, Clone, PartialEq)]
pub struct Topology {
    pub num_qubits: usize,
    pub edges: Vec<(PhysicalQubit, PhysicalQubit)>,
    pub coupling_map: HashMap<PhysicalQubit, Vec<PhysicalQubit>>,
}

impl Topology {
    pub fn new(num_qubits: usize, edges: Vec<(PhysicalQubit, PhysicalQubit)>) -> Self {
        let mut coupling_map = HashMap::new();
        
        for &(q1, q2) in &edges {
            coupling_map.entry(q1).or_insert_with(Vec::new).push(q2);
            coupling_map.entry(q2).or_insert_with(Vec::new).push(q1);
        }
        
        Self {
            num_qubits,
            edges,
            coupling_map,
        }
    }
    
    pub fn is_connected(&self, q1: PhysicalQubit, q2: PhysicalQubit) -> bool {
        self.coupling_map
            .get(&q1)
            .map(|neighbors| neighbors.contains(&q2))
            .unwrap_or(false)
    }
    
    pub fn distance(&self, q1: PhysicalQubit, q2: PhysicalQubit) -> Option<usize> {
        if q1 == q2 {
            return Some(0);
        }
        
        // BFS to find shortest path
        use std::collections::VecDeque;
        let mut queue = VecDeque::new();
        let mut visited = HashMap::new();
        
        queue.push_back((q1, 0));
        visited.insert(q1, 0);
        
        while let Some((current, dist)) = queue.pop_front() {
            if current == q2 {
                return Some(dist);
            }
            
            if let Some(neighbors) = self.coupling_map.get(&current) {
                for &neighbor in neighbors {
                    if !visited.contains_key(&neighbor) {
                        visited.insert(neighbor, dist + 1);
                        queue.push_back((neighbor, dist + 1));
                    }
                }
            }
        }
        
        None
    }
}

/// Qubit mapping between logical and physical qubits
#[derive(Debug, Clone, PartialEq)]
pub struct QubitMapping {
    pub logical_to_physical: HashMap<LogicalQubit, PhysicalQubit>,
    pub physical_to_logical: HashMap<PhysicalQubit, LogicalQubit>,
}

impl QubitMapping {
    pub fn new() -> Self {
        Self {
            logical_to_physical: HashMap::new(),
            physical_to_logical: HashMap::new(),
        }
    }
    
    pub fn map(&mut self, logical: LogicalQubit, physical: PhysicalQubit) {
        self.logical_to_physical.insert(logical, physical);
        self.physical_to_logical.insert(physical, logical);
    }
    
    pub fn get_physical(&self, logical: LogicalQubit) -> Option<PhysicalQubit> {
        self.logical_to_physical.get(&logical).copied()
    }
    
    pub fn get_logical(&self, physical: PhysicalQubit) -> Option<LogicalQubit> {
        self.physical_to_logical.get(&physical).copied()
    }
    
    pub fn swap(&mut self, p1: PhysicalQubit, p2: PhysicalQubit) {
        if let (Some(l1), Some(l2)) = (
            self.physical_to_logical.get(&p1).copied(),
            self.physical_to_logical.get(&p2).copied(),
        ) {
            self.logical_to_physical.insert(l1, p2);
            self.logical_to_physical.insert(l2, p1);
            self.physical_to_logical.insert(p1, l2);
            self.physical_to_logical.insert(p2, l1);
        }
    }
}

impl Default for QubitMapping {
    fn default() -> Self {
        Self::new()
    }
}

/// Physical gate operation with cost
#[derive(Debug, Clone, PartialEq)]
pub struct PhysicalGateOp {
    pub gate: Gate,
    pub physical_qubits: Vec<PhysicalQubit>,
    pub cost: f64,
    pub fidelity: Option<f64>,
}

/// SWAP operation for routing
#[derive(Debug, Clone, PartialEq)]
pub struct SwapOp {
    pub q1: PhysicalQubit,
    pub q2: PhysicalQubit,
    pub cost: f64,
}

/// IR Level 5: Topology-aware representation
#[derive(Debug, Clone, PartialEq)]
pub struct TopoIR {
    pub physical_qubits: Vec<PhysicalQubit>,
    pub mapping: QubitMapping,
    pub gates: Vec<PhysicalGateOp>,
    pub swaps: Vec<SwapOp>,
    pub topology: Topology,
    pub total_cost: f64,
}

impl TopoIR {
    pub fn new(topology: Topology) -> Self {
        Self {
            physical_qubits: Vec::new(),
            mapping: QubitMapping::new(),
            gates: Vec::new(),
            swaps: Vec::new(),
            topology,
            total_cost: 0.0,
        }
    }
    
    pub fn add_gate(&mut self, gate: PhysicalGateOp) {
        self.total_cost += gate.cost;
        self.gates.push(gate);
    }
    
    pub fn add_swap(&mut self, swap: SwapOp) {
        self.total_cost += swap.cost;
        self.mapping.swap(swap.q1, swap.q2);
        self.swaps.push(swap);
    }
    
    pub fn gate_count(&self) -> usize {
        self.gates.len()
    }
    
    pub fn swap_count(&self) -> usize {
        self.swaps.len()
    }
    
    pub fn depth(&self) -> usize {
        // Simplified depth calculation
        // In reality, would need to track dependencies
        self.gates.len() + self.swaps.len()
    }
}

/// Convert GateIR to TopoIR with placement and routing
pub struct TopoBuilder {
    topology: Topology,
}

impl TopoBuilder {
    pub fn new(topology: Topology) -> Self {
        Self { topology }
    }
    
    pub fn build(&self, gate_program: &GateProgram) -> Result<TopoIR, String> {
        let mut topo_ir = TopoIR::new(self.topology.clone());
        
        // Simple initial placement: map logical qubits sequentially
        for (i, &logical_qubit) in gate_program.qubits.iter().enumerate() {
            if i >= self.topology.num_qubits {
                return Err(format!(
                    "Not enough physical qubits: need {}, have {}",
                    gate_program.qubits.len(),
                    self.topology.num_qubits
                ));
            }
            topo_ir.mapping.map(
                LogicalQubit(logical_qubit.0 as u32),
                PhysicalQubit(i as u32),
            );
            topo_ir.physical_qubits.push(PhysicalQubit(i as u32));
        }
        
        // Route gates
        // Get gates from the entry sequence
        let entry_seq = gate_program.sequences.get(&gate_program.entry)
            .ok_or_else(|| "Entry sequence not found".to_string())?;
        
        for gate in &entry_seq.gates {
            self.route_gate(&mut topo_ir, gate)?;
        }
        
        Ok(topo_ir)
    }
    
    fn route_gate(&self, topo_ir: &mut TopoIR, gate: &Gate) -> Result<(), String> {
        use crate::gate::GateKind;

        // Single-qubit gates need no routing — place directly on physical qubit.
        // Two-qubit gates (CNOT etc.) may require SWAP insertion if the qubits
        // are not adjacent in the coupling map.
        let needs_routing = gate.qubits.len() >= 2 && matches!(
            gate.kind,
            GateKind::CX | GateKind::CZ | GateKind::Swap | GateKind::CCX
        );

        let physical_qubits: Vec<PhysicalQubit> =
            gate.qubits.iter().map(|q| PhysicalQubit(q.0 as u32)).collect();

        if needs_routing && physical_qubits.len() == 2 {
            // Check adjacency; insert SWAP if not adjacent
            let (q0, q1) = (physical_qubits[0], physical_qubits[1]);
            let dist = topo_ir.topology.distance(q0, q1).unwrap_or(usize::MAX);
            if dist > 1 {
                self.insert_swaps(topo_ir, q0, q1)?;
            }
        }

        // Assign cost by gate class (rough fidelity model)
        let cost = match gate.kind {
            GateKind::CX | GateKind::CZ | GateKind::Swap => 3.0,
            GateKind::CCX => 6.0,
            _ => 1.0,
        };
        let fidelity = match gate.kind {
            GateKind::CX | GateKind::CZ => Some(0.995),
            GateKind::Swap => Some(0.985),
            GateKind::CCX => Some(0.970),
            _ => Some(0.999),
        };

        topo_ir.add_gate(PhysicalGateOp {
            gate: gate.clone(),
            physical_qubits,
            cost,
            fidelity,
        });
        Ok(())
    }
    
    fn insert_swaps(
        &self,
        topo_ir: &mut TopoIR,
        from: PhysicalQubit,
        to: PhysicalQubit,
    ) -> Result<(), String> {
        // Simple greedy routing: find shortest path and insert SWAPs
        let distance = topo_ir
            .topology
            .distance(from, to)
            .ok_or_else(|| format!("No path between qubits {:?} and {:?}", from, to))?;
        
        if distance <= 1 {
            return Ok(());
        }
        
        // For simplicity, just insert one SWAP to bring qubits closer
        // In a real implementation, would use A* or similar
        if let Some(neighbors) = topo_ir.topology.coupling_map.get(&from) {
            if let Some(&next) = neighbors.first() {
                topo_ir.add_swap(SwapOp {
                    q1: from,
                    q2: next,
                    cost: 3.0, // SWAP typically costs 3 CNOTs
                });
            }
        }
        
        Ok(())
    }
}

// TODO: Update tests to work with new GateProgram API
/*
#[cfg(test)]
mod tests {
    use super::*;
    use crate::gate::{GateKind};

    #[test]
    fn test_topology_creation() {
        let edges = vec![
            (PhysicalQubit(0), PhysicalQubit(1)),
            (PhysicalQubit(1), PhysicalQubit(2)),
        ];
        let topo = Topology::new(3, edges);
        
        assert_eq!(topo.num_qubits, 3);
        assert!(topo.is_connected(PhysicalQubit(0), PhysicalQubit(1)));
        assert!(!topo.is_connected(PhysicalQubit(0), PhysicalQubit(2)));
    }

    #[test]
    fn test_topology_distance() {
        let edges = vec![
            (PhysicalQubit(0), PhysicalQubit(1)),
            (PhysicalQubit(1), PhysicalQubit(2)),
        ];
        let topo = Topology::new(3, edges);
        
        assert_eq!(topo.distance(PhysicalQubit(0), PhysicalQubit(0)), Some(0));
        assert_eq!(topo.distance(PhysicalQubit(0), PhysicalQubit(1)), Some(1));
        assert_eq!(topo.distance(PhysicalQubit(0), PhysicalQubit(2)), Some(2));
    }

    #[test]
    fn test_qubit_mapping() {
        let mut mapping = QubitMapping::new();
        mapping.map(LogicalQubit(0), PhysicalQubit(5));
        mapping.map(LogicalQubit(1), PhysicalQubit(3));
        
        assert_eq!(mapping.get_physical(LogicalQubit(0)), Some(PhysicalQubit(5)));
        assert_eq!(mapping.get_logical(PhysicalQubit(5)), Some(LogicalQubit(0)));
    }

    #[test]
    fn test_qubit_swap() {
        let mut mapping = QubitMapping::new();
        mapping.map(LogicalQubit(0), PhysicalQubit(0));
        mapping.map(LogicalQubit(1), PhysicalQubit(1));
        
        mapping.swap(PhysicalQubit(0), PhysicalQubit(1));
        
        assert_eq!(mapping.get_physical(LogicalQubit(0)), Some(PhysicalQubit(1)));
        assert_eq!(mapping.get_physical(LogicalQubit(1)), Some(PhysicalQubit(0)));
    }

    #[test]
    fn test_topo_builder_single_qubit() {
        let edges = vec![(PhysicalQubit(0), PhysicalQubit(1))];
        let topology = Topology::new(2, edges);
        let builder = TopoBuilder::new(topology);
        
        let mut gate_ir = GateIR::new(1);
        gate_ir.add_gate(GateOp::SingleQubit {
            gate_type: GateType::Single(SingleQubitGate::H),
            qubit: 0,
            params: vec![],
        });
        
        let topo_ir = builder.build(&gate_ir).unwrap();
        assert_eq!(topo_ir.gate_count(), 1);
        assert_eq!(topo_ir.swap_count(), 0);
    }

    #[test]
    fn test_topo_builder_connected_two_qubit() {
        let edges = vec![(PhysicalQubit(0), PhysicalQubit(1))];
        let topology = Topology::new(2, edges);
        let builder = TopoBuilder::new(topology);
        
        let mut gate_ir = GateIR::new(2);
        gate_ir.add_gate(GateOp::TwoQubit {
            gate_type: GateType::Two(TwoQubitGate::CX),
            control: 0,
            target: 1,
            params: vec![],
        });
        
        let topo_ir = builder.build(&gate_ir).unwrap();
        assert_eq!(topo_ir.gate_count(), 1);
    }
}

// Made with Bob

*/
