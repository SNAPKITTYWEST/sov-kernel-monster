//! QATAAUM IR Level 6: SCHEDULE
//!
//! Time-aware operations, resource reservations, barriers, and dependencies.
//! Schedules operations to minimize circuit execution time while respecting dependencies.

use crate::topo::{PhysicalGateOp, PhysicalQubit, TopoIR};
use std::collections::HashMap;

/// Time in nanoseconds
#[derive(Debug, Clone, Copy, PartialEq, PartialOrd)]
pub struct Time(pub f64);

/// Duration in nanoseconds
#[derive(Debug, Clone, Copy, PartialEq, PartialOrd)]
pub struct Duration(pub f64);

impl std::ops::Add for Time {
    type Output = Time;
    fn add(self, other: Time) -> Time {
        Time(self.0 + other.0)
    }
}

impl std::ops::Add<Duration> for Time {
    type Output = Time;
    fn add(self, duration: Duration) -> Time {
        Time(self.0 + duration.0)
    }
}

/// Operation identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct OpId(pub usize);

/// Resource (qubit, classical register, etc.)
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Resource {
    Qubit(PhysicalQubit),
    ClassicalBit(usize),
    MeasurementUnit,
    ControlUnit,
}

/// Scheduled operation with timing information
#[derive(Debug, Clone, PartialEq)]
pub struct ScheduledOp {
    pub id: OpId,
    pub op: PhysicalGateOp,
    pub start_time: Time,
    pub duration: Duration,
    pub resources: Vec<Resource>,
    pub dependencies: Vec<OpId>,
}

impl ScheduledOp {
    pub fn end_time(&self) -> Time {
        self.start_time + self.duration
    }
}

/// Timeline analysis
#[derive(Debug, Clone, PartialEq)]
pub struct Timeline {
    pub total_duration: Duration,
    pub critical_path: Vec<OpId>,
    pub parallelism: f64,
}

/// Dependency graph
#[derive(Debug, Clone, PartialEq)]
pub struct DependencyGraph {
    pub edges: HashMap<OpId, Vec<OpId>>,
}

impl DependencyGraph {
    pub fn new() -> Self {
        Self {
            edges: HashMap::new(),
        }
    }
    
    pub fn add_dependency(&mut self, from: OpId, to: OpId) {
        self.edges.entry(from).or_insert_with(Vec::new).push(to);
    }
    
    pub fn get_dependencies(&self, op: OpId) -> Vec<OpId> {
        self.edges.get(&op).cloned().unwrap_or_default()
    }
}

impl Default for DependencyGraph {
    fn default() -> Self {
        Self::new()
    }
}

/// Resource availability tracker
#[derive(Debug, Clone)]
#[derive(PartialEq)]
pub struct ResourceMap {
    pub availability: HashMap<Resource, Time>,
}

impl ResourceMap {
    pub fn new() -> Self {
        Self {
            availability: HashMap::new(),
        }
    }
    
    pub fn reserve(&mut self, resource: Resource, until: Time) {
        self.availability.insert(resource, until);
    }
    
    pub fn available_at(&self, resource: &Resource) -> Time {
        self.availability.get(resource).copied().unwrap_or(Time(0.0))
    }
    
    pub fn earliest_available(&self, resources: &[Resource]) -> Time {
        resources
            .iter()
            .map(|r| self.available_at(r))
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(Time(0.0))
    }
}

impl Default for ResourceMap {
    fn default() -> Self {
        Self::new()
    }
}

/// IR Level 6: Scheduled representation
#[derive(Debug, Clone, PartialEq)]
pub struct ScheduleIR {
    pub timeline: Timeline,
    pub operations: Vec<ScheduledOp>,
    pub resources: ResourceMap,
    pub dependencies: DependencyGraph,
}

impl ScheduleIR {
    pub fn new() -> Self {
        Self {
            timeline: Timeline {
                total_duration: Duration(0.0),
                critical_path: Vec::new(),
                parallelism: 0.0,
            },
            operations: Vec::new(),
            resources: ResourceMap::new(),
            dependencies: DependencyGraph::new(),
        }
    }
    
    pub fn add_operation(&mut self, op: ScheduledOp) {
        self.operations.push(op);
    }
    
    pub fn compute_timeline(&mut self) {
        if self.operations.is_empty() {
            return;
        }
        
        // Find total duration
        let max_end_time = self
            .operations
            .iter()
            .map(|op| op.end_time())
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(Time(0.0));
        
        self.timeline.total_duration = Duration(max_end_time.0);
        
        // Compute parallelism (average number of concurrent operations)
        let total_op_time: f64 = self
            .operations
            .iter()
            .map(|op| op.duration.0)
            .sum();
        
        self.timeline.parallelism = if max_end_time.0 > 0.0 {
            total_op_time / max_end_time.0
        } else {
            0.0
        };
        
        // Find critical path (simplified - just longest chain)
        self.timeline.critical_path = self.find_critical_path();
    }
    
    fn find_critical_path(&self) -> Vec<OpId> {
        // Simplified: return operations in order
        self.operations.iter().map(|op| op.id).collect()
    }
}

impl Default for ScheduleIR {
    fn default() -> Self {
        Self::new()
    }
}

/// Scheduler that converts TopoIR to ScheduleIR
pub struct Scheduler {
    gate_durations: HashMap<String, Duration>,
}

impl Scheduler {
    pub fn new() -> Self {
        let mut gate_durations = HashMap::new();
        
        // Default gate durations (in nanoseconds)
        gate_durations.insert("H".to_string(), Duration(40.0));
        gate_durations.insert("X".to_string(), Duration(40.0));
        gate_durations.insert("Y".to_string(), Duration(40.0));
        gate_durations.insert("Z".to_string(), Duration(0.0)); // Virtual
        gate_durations.insert("S".to_string(), Duration(0.0)); // Virtual
        gate_durations.insert("T".to_string(), Duration(0.0)); // Virtual
        gate_durations.insert("RX".to_string(), Duration(40.0));
        gate_durations.insert("RY".to_string(), Duration(40.0));
        gate_durations.insert("RZ".to_string(), Duration(0.0)); // Virtual
        gate_durations.insert("CX".to_string(), Duration(400.0));
        gate_durations.insert("CZ".to_string(), Duration(400.0));
        gate_durations.insert("SWAP".to_string(), Duration(1200.0)); // 3x CX
        gate_durations.insert("MEASURE".to_string(), Duration(1000.0));
        gate_durations.insert("RESET".to_string(), Duration(1000.0));
        
        Self { gate_durations }
    }
    
    pub fn schedule(&self, topo_ir: &TopoIR) -> Result<ScheduleIR, String> {
        let mut schedule_ir = ScheduleIR::new();
        let mut resource_map = ResourceMap::new();
        let mut dependencies = DependencyGraph::new();
        
        // Schedule each gate
        for (i, gate) in topo_ir.gates.iter().enumerate() {
            let op_id = OpId(i);
            
            // Determine resources needed
            let resources: Vec<Resource> = gate
                .physical_qubits
                .iter()
                .map(|&q| Resource::Qubit(q))
                .collect();
            
            // Find earliest time when all resources are available
            let earliest_start = resource_map.earliest_available(&resources);
            
            // Get gate duration
            let duration = self.get_gate_duration(gate);
            
            // Create scheduled operation
            let scheduled_op = ScheduledOp {
                id: op_id,
                op: gate.clone(),
                start_time: earliest_start,
                duration,
                resources: resources.clone(),
                dependencies: Vec::new(), // Simplified
            };
            
            // Reserve resources
            let end_time = scheduled_op.end_time();
            for resource in resources {
                resource_map.reserve(resource, end_time);
            }
            
            schedule_ir.add_operation(scheduled_op);
        }
        
        schedule_ir.resources = resource_map;
        schedule_ir.dependencies = dependencies;
        schedule_ir.compute_timeline();
        
        Ok(schedule_ir)
    }
    
    fn get_gate_duration(&self, gate: &PhysicalGateOp) -> Duration {
        let gate_name = format!("{:?}", gate.gate);
        self.gate_durations
            .get(&gate_name)
            .copied()
            .unwrap_or(Duration(100.0))
    }
}

impl Default for Scheduler {
    fn default() -> Self {
        Self::new()
    }
}

// TODO: Update tests to work with new GateProgram API
/*
#[cfg(test)]
mod tests {
    use super::*;
    use crate::gate::{Gate, GateKind};
    use crate::topo::{PhysicalQubit, Topology, TopoBuilder};

    #[test]
    fn test_time_arithmetic() {
        let t1 = Time(100.0);
        let t2 = Time(50.0);
        let d = Duration(25.0);
        
        assert_eq!(t1 + t2, Time(150.0));
        assert_eq!(t1 + d, Time(125.0));
    }

    #[test]
    fn test_resource_map() {
        let mut resources = ResourceMap::new();
        let q0 = Resource::Qubit(PhysicalQubit(0));
        let q1 = Resource::Qubit(PhysicalQubit(1));
        
        resources.reserve(q0.clone(), Time(100.0));
        resources.reserve(q1.clone(), Time(50.0));
        
        assert_eq!(resources.available_at(&q0), Time(100.0));
        assert_eq!(resources.available_at(&q1), Time(50.0));
        assert_eq!(resources.earliest_available(&[q0, q1]), Time(100.0));
    }

    #[test]
    fn test_dependency_graph() {
        let mut deps = DependencyGraph::new();
        deps.add_dependency(OpId(0), OpId(1));
        deps.add_dependency(OpId(0), OpId(2));
        
        let dependents = deps.get_dependencies(OpId(0));
        assert_eq!(dependents.len(), 2);
        assert!(dependents.contains(&OpId(1)));
        assert!(dependents.contains(&OpId(2)));
    }

    #[test]
    fn test_scheduler_single_qubit() {
        let edges = vec![(PhysicalQubit(0), PhysicalQubit(1))];
        let topology = Topology::new(2, edges);
        let topo_builder = TopoBuilder::new(topology);
        
        let mut gate_ir = crate::gate::GateIR::new(1);
        gate_ir.add_gate(GateOp::SingleQubit {
            gate_type: GateType::Single(SingleQubitGate::H),
            qubit: 0,
            params: vec![],
        });
        
        let topo_ir = topo_builder.build(&gate_ir).unwrap();
        let scheduler = Scheduler::new();
        let schedule_ir = scheduler.schedule(&topo_ir).unwrap();
        
        assert_eq!(schedule_ir.operations.len(), 1);
        assert_eq!(schedule_ir.operations[0].start_time, Time(0.0));
    }

    #[test]
    fn test_scheduler_sequential_gates() {
        let edges = vec![(PhysicalQubit(0), PhysicalQubit(1))];
        let topology = Topology::new(2, edges);
        let topo_builder = TopoBuilder::new(topology);
        
        let mut gate_ir = crate::gate::GateIR::new(1);
        gate_ir.add_gate(GateOp::SingleQubit {
            gate_type: GateType::Single(SingleQubitGate::H),
            qubit: 0,
            params: vec![],
        });
        gate_ir.add_gate(GateOp::SingleQubit {
            gate_type: GateType::Single(SingleQubitGate::X),
            qubit: 0,
            params: vec![],
        });
        
        let topo_ir = topo_builder.build(&gate_ir).unwrap();
        let scheduler = Scheduler::new();
        let schedule_ir = scheduler.schedule(&topo_ir).unwrap();
        
        assert_eq!(schedule_ir.operations.len(), 2);
        // Second gate should start after first finishes
        assert!(schedule_ir.operations[1].start_time.0 >= schedule_ir.operations[0].end_time().0);
    }

    #[test]
    fn test_timeline_computation() {
        let mut schedule_ir = ScheduleIR::new();
        
        schedule_ir.add_operation(ScheduledOp {
            id: OpId(0),
            op: PhysicalGateOp {
                gate: GateOp::SingleQubit {
                    gate_type: GateType::Single(SingleQubitGate::H),
                    qubit: 0,
                    params: vec![],
                },
                physical_qubits: vec![PhysicalQubit(0)],
                cost: 1.0,
                fidelity: Some(0.999),
            },
            start_time: Time(0.0),
            duration: Duration(40.0),
            resources: vec![Resource::Qubit(PhysicalQubit(0))],
            dependencies: vec![],
        });
        
        schedule_ir.compute_timeline();
        
        assert_eq!(schedule_ir.timeline.total_duration, Duration(40.0));
        assert_eq!(schedule_ir.timeline.parallelism, 1.0);
    }
}

// Made with Bob

*/
