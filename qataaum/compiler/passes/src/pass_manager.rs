//! Pass Manager
//!
//! Coordinates multiple optimization passes and tracks overall optimization metrics.

use crate::{GateCancellationPass, RotationFoldingPass};
use qataaum_ir::GateProgram;

/// Statistics from running optimization passes
#[derive(Debug, Clone, Default)]
pub struct OptimizationStats {
    /// Initial gate count
    pub initial_gates: usize,
    
    /// Final gate count
    pub final_gates: usize,
    
    /// Gates removed
    pub gates_removed: usize,
    
    /// Initial circuit depth
    pub initial_depth: usize,
    
    /// Final circuit depth
    pub final_depth: usize,
    
    /// Rotations folded
    pub rotations_folded: usize,
    
    /// Rotations simplified
    pub rotations_simplified: usize,
    
    /// Total passes executed
    pub total_passes: usize,
}

impl OptimizationStats {
    /// Calculate gate reduction percentage
    pub fn gate_reduction_percent(&self) -> f64 {
        if self.initial_gates == 0 {
            return 0.0;
        }
        (self.gates_removed as f64 / self.initial_gates as f64) * 100.0
    }
    
    /// Calculate depth reduction percentage
    pub fn depth_reduction_percent(&self) -> f64 {
        if self.initial_depth == 0 {
            return 0.0;
        }
        let depth_reduction = self.initial_depth.saturating_sub(self.final_depth);
        (depth_reduction as f64 / self.initial_depth as f64) * 100.0
    }
}

/// Manages and coordinates optimization passes
pub struct PassManager {
    /// Enable gate cancellation
    pub enable_gate_cancellation: bool,
    
    /// Enable rotation folding
    pub enable_rotation_folding: bool,
    
    /// Maximum number of optimization iterations
    pub max_iterations: usize,
    
    /// Statistics from last run
    pub stats: OptimizationStats,
}

impl PassManager {
    /// Create a new pass manager with default settings
    pub fn new() -> Self {
        PassManager {
            enable_gate_cancellation: true,
            enable_rotation_folding: true,
            max_iterations: 10,
            stats: OptimizationStats::default(),
        }
    }
    
    /// Create a pass manager with all optimizations enabled
    pub fn all_passes() -> Self {
        Self::new()
    }
    
    /// Create a pass manager with no optimizations
    pub fn no_passes() -> Self {
        PassManager {
            enable_gate_cancellation: false,
            enable_rotation_folding: false,
            max_iterations: 0,
            stats: OptimizationStats::default(),
        }
    }
    
    /// Run all enabled optimization passes on a program
    pub fn optimize(&mut self, program: &mut GateProgram) {
        // Record initial statistics
        program.compute_stats();
        self.stats.initial_gates = program.stats.total_gates;
        self.stats.initial_depth = program.stats.depth;
        
        // Run optimization passes iteratively
        for iteration in 0..self.max_iterations {
            let gates_before = program.stats.total_gates;
            
            // Run gate cancellation
            if self.enable_gate_cancellation {
                let mut pass = GateCancellationPass::new();
                pass.run(program);
                self.stats.gates_removed += pass.gates_removed;
                self.stats.total_passes += pass.passes;
            }
            
            // Run rotation folding
            if self.enable_rotation_folding {
                let mut pass = RotationFoldingPass::new();
                pass.run(program);
                self.stats.rotations_folded += pass.rotations_folded;
                self.stats.rotations_simplified += pass.rotations_simplified;
                self.stats.total_passes += pass.passes;
            }
            
            // Check if we made progress
            program.compute_stats();
            let gates_after = program.stats.total_gates;
            
            if gates_after >= gates_before {
                // No more progress, stop iterating
                break;
            }
            
            // If this is the last iteration, record it
            if iteration == self.max_iterations - 1 {
                break;
            }
        }
        
        // Record final statistics
        program.compute_stats();
        self.stats.final_gates = program.stats.total_gates;
        self.stats.final_depth = program.stats.depth;
    }
    
    /// Get a summary of the optimization results
    pub fn summary(&self) -> String {
        format!(
            "Optimization Summary:\n\
             Initial gates: {}\n\
             Final gates: {}\n\
             Gates removed: {} ({:.1}%)\n\
             Initial depth: {}\n\
             Final depth: {} ({:.1}% reduction)\n\
             Rotations folded: {}\n\
             Rotations simplified: {}\n\
             Total passes: {}",
            self.stats.initial_gates,
            self.stats.final_gates,
            self.stats.gates_removed,
            self.stats.gate_reduction_percent(),
            self.stats.initial_depth,
            self.stats.final_depth,
            self.stats.depth_reduction_percent(),
            self.stats.rotations_folded,
            self.stats.rotations_simplified,
            self.stats.total_passes
        )
    }
}

impl Default for PassManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use qataaum_ir::{Gate, GateKind, QubitId};
    use std::f64::consts::PI;
    
    #[test]
    fn test_optimize_with_cancellation() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add H-H pair (should cancel)
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
        
        let mut manager = PassManager::new();
        manager.optimize(&mut program);
        
        assert_eq!(manager.stats.initial_gates, 3);
        assert_eq!(manager.stats.final_gates, 1);
        assert_eq!(manager.stats.gates_removed, 2);
    }
    
    #[test]
    fn test_optimize_with_folding() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Add Rz(π/4) + Rz(π/4) = Rz(π/2) = S
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q0]));
        
        let mut manager = PassManager::new();
        manager.optimize(&mut program);
        
        assert_eq!(manager.stats.initial_gates, 2);
        assert_eq!(manager.stats.final_gates, 1);
        assert_eq!(manager.stats.rotations_folded, 1);
        assert_eq!(manager.stats.rotations_simplified, 1);
    }
    
    #[test]
    fn test_optimize_combined() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        // Complex circuit with both cancellations and folding
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0])); // Cancels
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::Rz(PI / 4.0), vec![q0])); // Folds to S
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0])); // Cancels
        
        let mut manager = PassManager::new();
        manager.optimize(&mut program);
        
        assert_eq!(manager.stats.initial_gates, 6);
        assert_eq!(manager.stats.final_gates, 1); // Just S gate remains
        assert!(manager.stats.gates_removed >= 4);
    }
    
    #[test]
    fn test_no_passes() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        
        let mut manager = PassManager::no_passes();
        manager.optimize(&mut program);
        
        assert_eq!(manager.stats.initial_gates, 2);
        assert_eq!(manager.stats.final_gates, 2);
        assert_eq!(manager.stats.gates_removed, 0);
    }
    
    #[test]
    fn test_gate_reduction_percent() {
        let stats = OptimizationStats {
            initial_gates: 10,
            final_gates: 6,
            gates_removed: 4,
            initial_depth: 10,
            final_depth: 6,
            rotations_folded: 2,
            rotations_simplified: 1,
            total_passes: 3,
        };
        
        assert!((stats.gate_reduction_percent() - 40.0).abs() < 0.1);
        assert!((stats.depth_reduction_percent() - 40.0).abs() < 0.1);
    }
    
    #[test]
    fn test_summary_format() {
        let mut program = GateProgram::new();
        let q0 = program.add_qubit();
        
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
        
        let mut manager = PassManager::new();
        manager.optimize(&mut program);
        
        let summary = manager.summary();
        assert!(summary.contains("Initial gates: 2"));
        assert!(summary.contains("Final gates: 0"));
    }
}

// Made with Bob
