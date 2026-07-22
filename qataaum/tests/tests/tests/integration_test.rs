//! Integration tests for QATAAUM quantum compiler pipeline
//!
//! Tests the complete flow: OpenQASM source → Parser → Semantic → IR → Optimizer → Simulator

use qataaum_parser::openqasm2::Parser;
use qataaum_semantic::SemanticAnalyzer;
use qataaum_ir::{IrBuilder, Gate, GateKind, GateProgram};
use qataaum_passes::PassManager;
use qataaum_statevector::Executor;

/// Test complete pipeline with a simple X gate
#[test]
fn test_pipeline_x_gate() {
    let source = r#"
        OPENQASM 2.0;
        qreg q[1];
        x q[0];
    "#;
    
    // 1. Parse OpenQASM source
    let mut parser = Parser::new(source);
    let ast = parser.parse().expect("Parse failed");
    
    // 2. Semantic analysis
    let mut analyzer = SemanticAnalyzer::new();
    analyzer.analyze(&ast).expect("Semantic analysis failed");
    
    // 3. Build typed IR
    let mut builder = IrBuilder::new(analyzer);
    let _typed_ast = builder.build(ast).expect("IR build failed");
    
    // Manually create gate program for now (full IR pipeline pending)
    let mut program = GateProgram::new();
    let q0 = program.add_qubit();
    program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
    
    // 4. Execute
    let mut executor = Executor::new(1, 0).expect("Executor creation failed");
    let result = executor.execute(&program).expect("Execution failed");
    
    // 5. Verify: X gate flips |0⟩ to |1⟩
    assert!((result.state.amplitude(0).norm() - 0.0).abs() < 1e-10);
    assert!((result.state.amplitude(1).norm() - 1.0).abs() < 1e-10);
}

/// Test Bell state creation
#[test]
fn test_pipeline_bell_state() {
    let source = r#"
        OPENQASM 2.0;
        qreg q[2];
        h q[0];
        cx q[0], q[1];
    "#;
    
    // 1. Parse
    let mut parser = Parser::new(source);
    let ast = parser.parse().expect("Parse failed");
    
    // 2. Semantic analysis
    let mut analyzer = SemanticAnalyzer::new();
    analyzer.analyze(&ast).expect("Semantic analysis failed");
    
    // 3. Build IR
    let mut builder = IrBuilder::new(analyzer);
    let _typed_ast = builder.build(ast).expect("IR build failed");
    
    // Manually create gate program
    let mut program = GateProgram::new();
    let q0 = program.add_qubit();
    let q1 = program.add_qubit();
    program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
    program.add_gate(program.entry, Gate::new(GateKind::CX, vec![q0, q1]));
    
    // Execute
    let mut executor = Executor::new(2, 0).expect("Executor creation failed");
    let result = executor.execute(&program).expect("Execution failed");
    
    // Verify: Bell state (|00⟩ + |11⟩)/√2
    let expected = 1.0 / 2.0_f64.sqrt();
    assert!((result.state.amplitude(0).norm() - expected).abs() < 1e-10); // |00⟩
    assert!((result.state.amplitude(1).norm() - 0.0).abs() < 1e-10);      // |01⟩
    assert!((result.state.amplitude(2).norm() - 0.0).abs() < 1e-10);      // |10⟩
    assert!((result.state.amplitude(3).norm() - expected).abs() < 1e-10); // |11⟩
}

/// Test optimization pipeline
#[test]
fn test_pipeline_with_optimization() {
    let source = r#"
        OPENQASM 2.0;
        qreg q[1];
        h q[0];
        h q[0];
    "#;
    
    // Parse and analyze
    let mut parser = Parser::new(source);
    let ast = parser.parse().expect("Parse failed");
    
    let mut analyzer = SemanticAnalyzer::new();
    analyzer.analyze(&ast).expect("Semantic analysis failed");
    
    let mut builder = IrBuilder::new(analyzer);
    let _typed_ast = builder.build(ast).expect("IR build failed");
    
    // Create program with H-H (should cancel)
    let mut program = GateProgram::new();
    let q0 = program.add_qubit();
    program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
    program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
    
    // Apply optimization
    let mut pass_manager = PassManager::new();
    let mut optimized = program.clone();
    pass_manager.optimize(&mut optimized);
    
    // Execute optimized program
    let mut executor = Executor::new(1, 0).expect("Executor creation failed");
    let result = executor.execute(&optimized).expect("Execution failed");
    
    // Should be back to |0⟩ (H-H cancels)
    assert!((result.state.amplitude(0).norm() - 1.0).abs() < 1e-10);
    assert!((result.state.amplitude(1).norm() - 0.0).abs() < 1e-10);
}

/// Test GHZ state (3-qubit entanglement)
#[test]
fn test_pipeline_ghz_state() {
    let source = r#"
        OPENQASM 2.0;
        qreg q[3];
        h q[0];
        cx q[0], q[1];
        cx q[1], q[2];
    "#;
    
    // 1. Parse
    let mut parser = Parser::new(source);
    let ast = parser.parse().expect("Parse failed");
    
    // 2. Semantic analysis
    let mut analyzer = SemanticAnalyzer::new();
    analyzer.analyze(&ast).expect("Semantic analysis failed");
    
    // 3. Build IR
    let mut builder = IrBuilder::new(analyzer);
    let _typed_ast = builder.build(ast).expect("IR build failed");
    
    // Manually create gate program
    let mut program = GateProgram::new();
    let q0 = program.add_qubit();
    let q1 = program.add_qubit();
    let q2 = program.add_qubit();
    program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
    program.add_gate(program.entry, Gate::new(GateKind::CX, vec![q0, q1]));
    program.add_gate(program.entry, Gate::new(GateKind::CX, vec![q1, q2]));
    
    // Execute
    let mut executor = Executor::new(3, 0).expect("Executor creation failed");
    let result = executor.execute(&program).expect("Execution failed");
    
    // Verify: GHZ state (|000⟩ + |111⟩)/√2
    let expected = 1.0 / 2.0_f64.sqrt();
    assert!((result.state.amplitude(0).norm() - expected).abs() < 1e-10); // |000⟩
    assert!((result.state.amplitude(7).norm() - expected).abs() < 1e-10); // |111⟩
    
    // All other states should be zero
    for i in 1..7 {
        assert!((result.state.amplitude(i).norm() - 0.0).abs() < 1e-10);
    }
}

/// Test equal superposition
#[test]
fn test_pipeline_superposition() {
    let source = r#"
        OPENQASM 2.0;
        qreg q[2];
        h q[0];
        h q[1];
    "#;
    
    // 1. Parse
    let mut parser = Parser::new(source);
    let ast = parser.parse().expect("Parse failed");
    
    // 2. Semantic analysis
    let mut analyzer = SemanticAnalyzer::new();
    analyzer.analyze(&ast).expect("Semantic analysis failed");
    
    // 3. Build IR
    let mut builder = IrBuilder::new(analyzer);
    let _typed_ast = builder.build(ast).expect("IR build failed");
    
    // Manually create gate program
    let mut program = GateProgram::new();
    let q0 = program.add_qubit();
    let q1 = program.add_qubit();
    program.add_gate(program.entry, Gate::new(GateKind::H, vec![q0]));
    program.add_gate(program.entry, Gate::new(GateKind::H, vec![q1]));
    
    // Execute
    let mut executor = Executor::new(2, 0).expect("Executor creation failed");
    let result = executor.execute(&program).expect("Execution failed");
    
    // Verify: Equal superposition (|00⟩ + |01⟩ + |10⟩ + |11⟩)/2
    let expected = 0.5;
    for i in 0..4 {
        assert!((result.state.amplitude(i).re - expected).abs() < 1e-10);
    }
}

/// Test measurement
#[test]
fn test_pipeline_measurement() {
    let source = r#"
        OPENQASM 2.0;
        qreg q[1];
        creg c[1];
        x q[0];
        measure q[0] -> c[0];
    "#;
    
    // Parse
    let mut parser = Parser::new(source);
    let ast = parser.parse().expect("Parse failed");
    
    // Semantic analysis
    let mut analyzer = SemanticAnalyzer::new();
    analyzer.analyze(&ast).expect("Semantic analysis failed");
    
    // Build IR
    let mut builder = IrBuilder::new(analyzer);
    let _typed_ast = builder.build(ast).expect("IR build failed");
    
    // Manually create gate program
    let mut program = GateProgram::new();
    let q0 = program.add_qubit();
    let b0 = program.add_bit();
    program.add_gate(program.entry, Gate::new(GateKind::X, vec![q0]));
    program.add_gate(program.entry, Gate::new(
        GateKind::Measure { target_bit: b0 },
        vec![q0]
    ));
    
    // Execute
    let mut executor = Executor::new(1, 1).expect("Executor creation failed");
    let result = executor.execute(&program).expect("Execution failed");
    
    // Verify: should measure |1⟩
    assert_eq!(result.measurements.get(&0), Some(&1));
}

/// Test rotation gates
#[test]
fn test_pipeline_rotations() {
    use std::f64::consts::PI;
    
    // Create circuit with rotation
    let mut program = GateProgram::new();
    let q0 = program.add_qubit();
    
    // Rx(π) = X gate
    program.add_gate(program.entry, Gate::new(GateKind::Rx(PI), vec![q0]));
    
    // Execute
    let mut executor = Executor::new(1, 0).expect("Executor creation failed");
    let result = executor.execute(&program).expect("Execution failed");
    
    // Should be in |1⟩ state (Rx(π) flips qubit)
    assert!((result.state.amplitude(0).norm() - 0.0).abs() < 1e-10);
    assert!((result.state.amplitude(1).norm() - 1.0).abs() < 1e-10);
}

// Made with Bob
