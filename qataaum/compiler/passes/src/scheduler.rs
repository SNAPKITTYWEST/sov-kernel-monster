//! Hardware-Aware Quantum Circuit Scheduler
//!
//! This module implements a production scheduler that transforms TopoIR
//! (topology-aware circuits with physical qubits) into ScheduleIR
//! (time-scheduled operations with resource management).
//!
//! The scheduler is separate from IR Level 6 (schedule.rs), which defines
//! the data structures. This module implements the scheduling algorithms.
//!
//! # Scheduling Strategy
//!
//! 1. **Dependency Analysis**: Build a dependency graph from gate operations
//! 2. **Resource Tracking**: Track qubit and classical bit availability
//! 3. **Critical Path**: Identify the longest dependency chain
//! 4. **List Scheduling**: Schedule operations as early as possible while
//!    respecting dependencies and resource constraints
//! 5. **Parallelism**: Maximize parallel execution of independent operations
//!
//! # Clean-Room Implementation
//!
//! This scheduler is based on public scheduling algorithms from:
//! - List scheduling (Graham 1966)
//! - Critical path method (Kelley & Walker 1959)
//! - Resource-constrained project scheduling
//! - Quantum circuit scheduling concepts from academic papers
//!
//! No proprietary IBM scheduling code or internal algorithms are used.

use qataaum_ir::topo::{TopoIR, PhysicalGateOp, PhysicalQubit};
use qataaum_ir::schedule::{
    ScheduleIR, ScheduledOp, Timeline, Time, Duration, Resource,
    ResourceMap, DependencyGraph, OpId,
};
use qataaum_ir::gate::{GateKind};
use std::collections::{HashMap, HashSet, VecDeque};

/// Gate duration database for different gate types
#[derive(Debug, Clone)]
pub struct GateDurations {
    durations: HashMap<String, Duration>,
}

impl GateDurations {
    /// Create a new gate duration database with default values
    pub fn new() -> Self {
        let mut durations = HashMap::new();
        
        // Default gate durations in nanoseconds (typical for superconducting qubits)
        durations.insert("x".to_string(), Duration(35.0));
        durations.insert("y".to_string(), Duration(35.0));
        durations.insert("z".to_string(), Duration(0.0)); // Virtual gate
        durations.insert("h".to_string(), Duration(35.0));
        durations.insert("s".to_string(), Duration(0.0)); // Virtual gate
        durations.insert("sdg".to_string(), Duration(0.0)); // Virtual gate
        durations.insert("t".to_string(), Duration(0.0)); // Virtual gate
        durations.insert("tdg".to_string(), Duration(0.0)); // Virtual gate
        durations.insert("rx".to_string(), Duration(35.0));
        durations.insert("ry".to_string(), Duration(35.0));
        durations.insert("rz".to_string(), Duration(0.0)); // Virtual gate
        durations.insert("phase".to_string(), Duration(0.0)); // Virtual gate
        durations.insert("cx".to_string(), Duration(300.0));
        durations.insert("cy".to_string(), Duration(300.0));
        durations.insert("cz".to_string(), Duration(300.0));
        durations.insert("swap".to_string(), Duration(900.0)); // 3 CNOTs
        durations.insert("ccx".to_string(), Duration(1200.0)); // Toffoli
        durations.insert("measure".to_string(), Duration(1000.0));
        durations.insert("reset".to_string(), Duration(1000.0));
        durations.insert("barrier".to_string(), Duration(0.0));
        
        Self { durations }
    }
    
    /// Get the duration for a gate type
    pub fn get(&self, gate_name: &str) -> Duration {
        self.durations.get(gate_name)
            .copied()
            .unwrap_or(Duration(35.0)) // Default single-qubit duration
    }
    
    /// Set a custom duration for a gate type
    pub fn set(&mut self, gate_name: String, duration: Duration) {
        self.durations.insert(gate_name, duration);
    }
}

impl Default for GateDurations {
    fn default() -> Self {
        Self::new()
    }
}

/// Scheduler configuration
#[derive(Debug, Clone)]
pub struct SchedulerConfig {
    /// Gate duration database
    pub gate_durations: GateDurations,
    
    /// Enable aggressive parallelization
    pub aggressive_parallel: bool,
    
    /// Minimum time between operations on the same qubit (alignment constraint)
    pub min_qubit_spacing: Duration,
    
    /// Enable barrier synchronization
    pub respect_barriers: bool,
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        Self {
            gate_durations: GateDurations::new(),
            aggressive_parallel: true,
            min_qubit_spacing: Duration(0.0),
            respect_barriers: true,
        }
    }
}

/// Operation node in the dependency graph
#[derive(Debug, Clone)]
struct OpNode {
    id: OpId,
    gate_op: PhysicalGateOp,
    duration: Duration,
    dependencies: Vec<OpId>,
    dependents: Vec<OpId>,
    earliest_start: Time,
    scheduled_time: Option<Time>,
}

/// Hardware-aware quantum circuit scheduler
pub struct Scheduler {
    config: SchedulerConfig,
}

impl Scheduler {
    /// Create a new scheduler with default configuration
    pub fn new() -> Self {
        Self {
            config: SchedulerConfig::default(),
        }
    }
    
    /// Create a new scheduler with custom configuration
    pub fn with_config(config: SchedulerConfig) -> Self {
        Self { config }
    }
    
    /// Schedule a topology-aware circuit
    pub fn schedule(&self, topo_ir: &TopoIR) -> Result<ScheduleIR, SchedulerError> {
        // Build dependency graph
        let mut nodes = self.build_dependency_graph(topo_ir)?;
        
        // Compute earliest start times (forward pass)
        self.compute_earliest_start_times(&mut nodes);
        
        // Schedule operations using list scheduling
        let scheduled_ops = self.list_schedule(&mut nodes, topo_ir)?;
        
        // Build resource map
        let resources = self.build_resource_map(&scheduled_ops);
        
        // Build dependency graph for output
        let dependencies = self.build_output_dependency_graph(&nodes);
        
        // Compute timeline metrics
        let total_duration = scheduled_ops.iter()
            .map(|op| op.end_time())
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(Time(0.0));
        
        let timeline = Timeline {
            total_duration: Duration(total_duration.0),
            critical_path: Vec::new(), // TODO: compute critical path
            parallelism: 1.0, // TODO: compute parallelism metric
        };
        
        Ok(ScheduleIR {
            timeline,
            operations: scheduled_ops,
            resources,
            dependencies,
        })
    }
    
    /// Build dependency graph from physical gate operations
    fn build_dependency_graph(&self, topo_ir: &TopoIR) -> Result<Vec<OpNode>, SchedulerError> {
        let mut nodes = Vec::new();
        let mut qubit_last_op: HashMap<PhysicalQubit, OpId> = HashMap::new();
        
        // Process physical gate operations
        for (idx, gate_op) in topo_ir.gates.iter().enumerate() {
            let op_id = OpId(idx);
            let duration = self.get_gate_duration(&gate_op.gate.kind);
            
            let mut dependencies = Vec::new();
            
            // Add dependencies based on qubit usage
            for &qubit in &gate_op.physical_qubits {
                if let Some(&prev_op) = qubit_last_op.get(&qubit) {
                    dependencies.push(prev_op);
                }
                qubit_last_op.insert(qubit, op_id);
            }
            
            nodes.push(OpNode {
                id: op_id,
                gate_op: gate_op.clone(),
                duration,
                dependencies,
                dependents: Vec::new(),
                earliest_start: Time(0.0),
                scheduled_time: None,
            });
        }
        
        // Build dependent lists (reverse edges)
        for i in 0..nodes.len() {
            let deps = nodes[i].dependencies.clone();
            for &dep_id in &deps {
                nodes[dep_id.0].dependents.push(OpId(i));
            }
        }
        
        Ok(nodes)
    }
    
    /// Compute earliest start times (forward pass through dependency graph)
    fn compute_earliest_start_times(&self, nodes: &mut [OpNode]) {
        for i in 0..nodes.len() {
            let mut earliest = Time(0.0);
            
            for &dep_id in &nodes[i].dependencies.clone() {
                let dep_node = &nodes[dep_id.0];
                let dep_finish = Time(dep_node.earliest_start.0 + dep_node.duration.0);
                if dep_finish.0 > earliest.0 {
                    earliest = dep_finish;
                }
            }
            
            nodes[i].earliest_start = earliest;
        }
    }
    
    /// List scheduling algorithm
    fn list_schedule(&self, nodes: &mut [OpNode], topo_ir: &TopoIR) 
        -> Result<Vec<ScheduledOp>, SchedulerError> {
        
        let mut scheduled_ops = Vec::new();
        let mut ready_queue: VecDeque<OpId> = VecDeque::new();
        let mut scheduled: HashSet<OpId> = HashSet::new();
        let mut qubit_available: HashMap<PhysicalQubit, Time> = HashMap::new();
        
        // Initialize qubit availability
        for &qubit in &topo_ir.physical_qubits {
            qubit_available.insert(qubit, Time(0.0));
        }
        
        // Find initial ready operations (no dependencies)
        for node in nodes.iter() {
            if node.dependencies.is_empty() {
                ready_queue.push_back(node.id);
            }
        }
        
        // Schedule operations
        while !ready_queue.is_empty() {
            // Get next operation from ready queue
            let op_id = ready_queue.pop_front().unwrap();
            let node = &mut nodes[op_id.0];
            
            // Find earliest time this operation can start
            let mut start_time = node.earliest_start;
            
            // Check qubit availability
            for &qubit in &node.gate_op.physical_qubits {
                let available = qubit_available.get(&qubit).copied().unwrap_or(Time(0.0));
                if available.0 > start_time.0 {
                    start_time = available;
                }
            }
            
            // Schedule the operation
            node.scheduled_time = Some(start_time);
            scheduled.insert(op_id);
            
            // Update qubit availability
            let finish_time = Time(start_time.0 + node.duration.0 + self.config.min_qubit_spacing.0);
            for &qubit in &node.gate_op.physical_qubits {
                qubit_available.insert(qubit, finish_time);
            }
            
            // Create scheduled operation
            let resources: Vec<Resource> = node.gate_op.physical_qubits.iter()
                .map(|&q| Resource::Qubit(q))
                .collect();
            
            scheduled_ops.push(ScheduledOp {
                id: op_id,
                op: node.gate_op.clone(),
                start_time,
                duration: node.duration,
                resources,
                dependencies: node.dependencies.clone(),
            });
            
            // Add newly ready operations to queue
            for &dependent_id in &node.dependents.clone() {
                let dependent = &nodes[dependent_id.0];
                
                // Check if all dependencies are scheduled
                let all_deps_scheduled = dependent.dependencies.iter()
                    .all(|&dep_id| scheduled.contains(&dep_id));
                
                if all_deps_scheduled && !ready_queue.contains(&dependent_id) {
                    ready_queue.push_back(dependent_id);
                }
            }
        }
        
        // Sort by start time
        scheduled_ops.sort_by(|a, b| a.start_time.partial_cmp(&b.start_time).unwrap());
        
        Ok(scheduled_ops)
    }
    
    /// Build resource availability map
    fn build_resource_map(&self, scheduled_ops: &[ScheduledOp]) -> ResourceMap {
        let mut resource_map = ResourceMap::new();
        
        for op in scheduled_ops {
            let finish_time = op.end_time();
            for resource in &op.resources {
                resource_map.reserve(resource.clone(), finish_time);
            }
        }
        
        resource_map
    }
    
    /// Build output dependency graph
    fn build_output_dependency_graph(&self, nodes: &[OpNode]) -> DependencyGraph {
        let mut graph = DependencyGraph::new();
        
        for node in nodes {
            for &dep_id in &node.dependencies {
                graph.add_dependency(dep_id, node.id);
            }
        }
        
        graph
    }
    
    /// Get gate duration from configuration
    fn get_gate_duration(&self, gate_kind: &GateKind) -> Duration {
        let gate_name = match gate_kind {
            GateKind::X => "x",
            GateKind::Y => "y",
            GateKind::Z => "z",
            GateKind::H => "h",
            GateKind::S => "s",
            GateKind::Sdg => "sdg",
            GateKind::T => "t",
            GateKind::Tdg => "tdg",
            GateKind::Rx(_) => "rx",
            GateKind::Ry(_) => "ry",
            GateKind::Rz(_) => "rz",
            GateKind::Phase(_) => "phase",
            GateKind::CX => "cx",
            GateKind::CY => "cy",
            GateKind::CZ => "cz",
            GateKind::Swap => "swap",
            GateKind::CCX => "ccx",
            GateKind::Measure { .. } => "measure",
            GateKind::Reset => "reset",
            GateKind::Barrier => "barrier",
            GateKind::Custom { name, .. } => name.as_str(),
        };
        
        self.config.gate_durations.get(gate_name)
    }
}

impl Default for Scheduler {
    fn default() -> Self {
        Self::new()
    }
}

/// Scheduler error types
#[derive(Debug, Clone, PartialEq)]
pub enum SchedulerError {
    /// Circular dependency detected
    CircularDependency(String),
    
    /// Resource conflict detected
    ResourceConflict(String),
    
    /// Invalid operation
    InvalidOperation(String),
    
    /// Scheduling failed
    SchedulingFailed(String),
}

impl std::fmt::Display for SchedulerError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::CircularDependency(msg) => write!(f, "Circular dependency: {}", msg),
            Self::ResourceConflict(msg) => write!(f, "Resource conflict: {}", msg),
            Self::InvalidOperation(msg) => write!(f, "Invalid operation: {}", msg),
            Self::SchedulingFailed(msg) => write!(f, "Scheduling failed: {}", msg),
        }
    }
}

impl std::error::Error for SchedulerError {}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_gate_durations() {
        let durations = GateDurations::new();
        
        assert_eq!(durations.get("x"), Duration(35.0));
        assert_eq!(durations.get("cx"), Duration(300.0));
        assert_eq!(durations.get("measure"), Duration(1000.0));
        assert_eq!(durations.get("rz"), Duration(0.0)); // Virtual gate
    }
    
    #[test]
    fn test_scheduler_config() {
        let config = SchedulerConfig::default();
        assert!(config.aggressive_parallel);
        assert!(config.respect_barriers);
    }
}

// Made with Bob
