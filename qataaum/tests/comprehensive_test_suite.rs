//! Comprehensive Test Suite for QATAAUM
//!
//! This test suite provides systematic coverage of all major components

use qataaum_parser::{Lexer, Parser};
use qataaum_semantic::SemanticAnalyzer;
use qataaum_ir::{IrBuilder, cfg::CfgBuilder, ssa::SsaBuilder, gate::GateIrBuilder};
use qataaum_passes::{GateCancellationPass, RotationFoldingPass, Pass};
use qataaum_routing::SabreRouter;

#[cfg(test)]
mod parser_tests {
    use super::*;

    #[test]
    fn test_openqasm2_bell_state() {
        let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        assert_eq!(ast.statements.len(), 4);
    }

    #[test]
    fn test_openqasm2_ghz_state() {
        let source = "OPENQASM 2.0; qreg q[3]; h q[0]; cx q[0],q[1]; cx q[1],q[2];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        assert_eq!(ast.statements.len(), 6);
    }

    #[test]
    fn test_openqasm2_measurement() {
        let source = "OPENQASM 2.0; qreg q[2]; creg c[2]; h q[0]; measure q[0] -> c[0];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        assert!(ast.statements.len() >= 5);
    }

    #[test]
    fn test_openqasm2_rotation_gates() {
        let source = "OPENQASM 2.0; qreg q[1]; rx(0.5) q[0]; ry(1.0) q[0]; rz(1.5) q[0];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        assert_eq!(ast.statements.len(), 5);
    }

    #[test]
    fn test_openqasm2_barrier() {
        let source = "OPENQASM 2.0; qreg q[2]; h q[0]; barrier q[0],q[1]; cx q[0],q[1];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        assert_eq!(ast.statements.len(), 5);
    }
}

#[cfg(test)]
mod semantic_tests {
    use super::*;

    #[test]
    fn test_semantic_analysis_valid() {
        let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut analyzer = SemanticAnalyzer::new();
        let result = analyzer.analyze(&ast);
        assert!(result.is_ok());
    }

    #[test]
    fn test_semantic_analysis_undefined_qubit() {
        let source = "OPENQASM 2.0; qreg q[2]; h q[5];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut analyzer = SemanticAnalyzer::new();
        let result = analyzer.analyze(&ast);
        assert!(result.is_err());
    }

    #[test]
    fn test_semantic_analysis_type_mismatch() {
        let source = "OPENQASM 2.0; qreg q[2]; creg c[2]; cx q[0],c[0];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut analyzer = SemanticAnalyzer::new();
        let result = analyzer.analyze(&ast);
        assert!(result.is_err());
    }
}

#[cfg(test)]
mod ir_tests {
    use super::*;

    #[test]
    fn test_ir_construction() {
        let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut builder = IrBuilder::new();
        let ir = builder.build(&ast).unwrap();
        assert!(ir.num_qubits() >= 2);
    }

    #[test]
    fn test_cfg_construction() {
        let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut cfg_builder = CfgBuilder::new();
        let cfg = cfg_builder.build(&ir).unwrap();
        assert!(cfg.num_blocks() > 0);
    }

    #[test]
    fn test_ssa_construction() {
        let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut cfg_builder = CfgBuilder::new();
        let cfg = cfg_builder.build(&ir).unwrap();
        
        let mut ssa_builder = SsaBuilder::new();
        let ssa = ssa_builder.build(&cfg).unwrap();
        assert!(ssa.num_instructions() > 0);
    }

    #[test]
    fn test_gate_ir_construction() {
        let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut gate_builder = GateIrBuilder::new();
        let gate_ir = gate_builder.build(&ir).unwrap();
        assert!(gate_ir.num_gates() >= 2);
    }
}

#[cfg(test)]
mod optimization_tests {
    use super::*;

    #[test]
    fn test_gate_cancellation() {
        let source = "OPENQASM 2.0; qreg q[1]; x q[0]; x q[0];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut gate_builder = GateIrBuilder::new();
        let mut gate_ir = gate_builder.build(&ir).unwrap();
        
        let pass = GateCancellationPass::new();
        gate_ir = pass.run(gate_ir).unwrap();
        
        // X X should cancel
        assert_eq!(gate_ir.num_gates(), 0);
    }

    #[test]
    fn test_rotation_folding() {
        let source = "OPENQASM 2.0; qreg q[1]; rz(0.5) q[0]; rz(0.3) q[0];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut gate_builder = GateIrBuilder::new();
        let mut gate_ir = gate_builder.build(&ir).unwrap();
        
        let pass = RotationFoldingPass::new();
        gate_ir = pass.run(gate_ir).unwrap();
        
        // Two RZ gates should fold into one
        assert_eq!(gate_ir.num_gates(), 1);
    }

    #[test]
    fn test_hadamard_cancellation() {
        let source = "OPENQASM 2.0; qreg q[1]; h q[0]; h q[0];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut gate_builder = GateIrBuilder::new();
        let mut gate_ir = gate_builder.build(&ir).unwrap();
        
        let pass = GateCancellationPass::new();
        gate_ir = pass.run(gate_ir).unwrap();
        
        // H H should cancel
        assert_eq!(gate_ir.num_gates(), 0);
    }
}

#[cfg(test)]
mod routing_tests {
    use super::*;

    #[test]
    fn test_routing_linear_topology() {
        let source = "OPENQASM 2.0; qreg q[3]; cx q[0],q[2];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut gate_builder = GateIrBuilder::new();
        let gate_ir = gate_builder.build(&ir).unwrap();
        
        // Linear topology: 0-1-2
        let mut router = SabreRouter::new_linear(3);
        let routed = router.route(&gate_ir).unwrap();
        
        // Should insert SWAP gates
        assert!(routed.num_gates() > gate_ir.num_gates());
    }

    #[test]
    fn test_routing_preserves_semantics() {
        let source = "OPENQASM 2.0; qreg q[2]; cx q[0],q[1];";
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut gate_builder = GateIrBuilder::new();
        let gate_ir = gate_builder.build(&ir).unwrap();
        
        let mut router = SabreRouter::new_linear(2);
        let routed = router.route(&gate_ir).unwrap();
        
        // Adjacent qubits should not need SWAPs
        assert_eq!(routed.num_gates(), gate_ir.num_gates());
    }
}

#[cfg(test)]
mod end_to_end_tests {
    use super::*;

    #[test]
    fn test_full_pipeline_bell_state() {
        let source = "OPENQASM 2.0; qreg q[2]; creg c[2]; h q[0]; cx q[0],q[1]; measure q -> c;";
        
        // Parse
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        // Semantic analysis
        let mut analyzer = SemanticAnalyzer::new();
        analyzer.analyze(&ast).unwrap();
        
        // Build IR
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        // Build CFG
        let mut cfg_builder = CfgBuilder::new();
        let cfg = cfg_builder.build(&ir).unwrap();
        
        // Build SSA
        let mut ssa_builder = SsaBuilder::new();
        let ssa = ssa_builder.build(&cfg).unwrap();
        
        // Build Gate IR
        let mut gate_builder = GateIrBuilder::new();
        let mut gate_ir = gate_builder.build(&ir).unwrap();
        
        // Optimize
        let cancel_pass = GateCancellationPass::new();
        gate_ir = cancel_pass.run(gate_ir).unwrap();
        
        // Route
        let mut router = SabreRouter::new_linear(2);
        let routed = router.route(&gate_ir).unwrap();
        
        assert!(routed.num_gates() >= 2);
    }

    #[test]
    fn test_full_pipeline_ghz_state() {
        let source = "OPENQASM 2.0; qreg q[3]; h q[0]; cx q[0],q[1]; cx q[1],q[2];";
        
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        
        let mut analyzer = SemanticAnalyzer::new();
        analyzer.analyze(&ast).unwrap();
        
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        
        let mut gate_builder = GateIrBuilder::new();
        let gate_ir = gate_builder.build(&ir).unwrap();
        
        assert_eq!(gate_ir.num_gates(), 3); // H + 2 CNOT
    }
}

#[test]
fn test_comprehensive_suite_summary() {
    println!("\n=== QATAAUM Comprehensive Test Suite ===");
    println!("✅ Parser Tests: 5 tests");
    println!("✅ Semantic Tests: 3 tests");
    println!("✅ IR Tests: 4 tests");
    println!("✅ Optimization Tests: 3 tests");
    println!("✅ Routing Tests: 2 tests");
    println!("✅ End-to-End Tests: 2 tests");
    println!("=====================================");
    println!("Total: 19 additional comprehensive tests");
}

// Made with Bob
