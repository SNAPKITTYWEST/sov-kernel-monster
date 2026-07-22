//! Compiler Performance Benchmarks

use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId};
use qataaum_parser::{Lexer, Parser};
use qataaum_semantic::SemanticAnalyzer;
use qataaum_ir::{IrBuilder, cfg::CfgBuilder, ssa::SsaBuilder, gate::GateIrBuilder};
use qataaum_passes::{GateCancellationPass, RotationFoldingPass, Pass};
use qataaum_routing::SabreRouter;

fn benchmark_parser(c: &mut Criterion) {
    let mut group = c.benchmark_group("parser");
    
    let test_cases = vec![
        ("bell_state", "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];"),
        ("ghz_3", "OPENQASM 2.0; qreg q[3]; h q[0]; cx q[0],q[1]; cx q[1],q[2];"),
        ("ghz_5", "OPENQASM 2.0; qreg q[5]; h q[0]; cx q[0],q[1]; cx q[1],q[2]; cx q[2],q[3]; cx q[3],q[4];"),
        ("rotation_chain", "OPENQASM 2.0; qreg q[1]; rx(0.1) q[0]; ry(0.2) q[0]; rz(0.3) q[0]; rx(0.4) q[0]; ry(0.5) q[0];"),
    ];
    
    for (name, source) in test_cases {
        group.bench_with_input(BenchmarkId::new("lexer", name), &source, |b, s| {
            b.iter(|| {
                let mut lexer = Lexer::new(black_box(s));
                lexer.tokenize().unwrap()
            });
        });
        
        group.bench_with_input(BenchmarkId::new("parser", name), &source, |b, s| {
            b.iter(|| {
                let mut lexer = Lexer::new(black_box(s));
                let tokens = lexer.tokenize().unwrap();
                let mut parser = Parser::new(tokens);
                parser.parse().unwrap()
            });
        });
    }
    
    group.finish();
}

fn benchmark_semantic_analysis(c: &mut Criterion) {
    let mut group = c.benchmark_group("semantic");
    
    let source = "OPENQASM 2.0; qreg q[5]; h q[0]; cx q[0],q[1]; cx q[1],q[2]; cx q[2],q[3]; cx q[3],q[4];";
    let mut lexer = Lexer::new(source);
    let tokens = lexer.tokenize().unwrap();
    let mut parser = Parser::new(tokens);
    let ast = parser.parse().unwrap();
    
    group.bench_function("analyze_ghz_5", |b| {
        b.iter(|| {
            let mut analyzer = SemanticAnalyzer::new();
            analyzer.analyze(black_box(&ast)).unwrap()
        });
    });
    
    group.finish();
}

fn benchmark_ir_construction(c: &mut Criterion) {
    let mut group = c.benchmark_group("ir_construction");
    
    let source = "OPENQASM 2.0; qreg q[5]; h q[0]; cx q[0],q[1]; cx q[1],q[2]; cx q[2],q[3]; cx q[3],q[4];";
    let mut lexer = Lexer::new(source);
    let tokens = lexer.tokenize().unwrap();
    let mut parser = Parser::new(tokens);
    let ast = parser.parse().unwrap();
    
    group.bench_function("source_to_typed", |b| {
        b.iter(|| {
            let mut builder = IrBuilder::new();
            builder.build(black_box(&ast)).unwrap()
        });
    });
    
    let mut ir_builder = IrBuilder::new();
    let ir = ir_builder.build(&ast).unwrap();
    
    group.bench_function("typed_to_cfg", |b| {
        b.iter(|| {
            let mut cfg_builder = CfgBuilder::new();
            cfg_builder.build(black_box(&ir)).unwrap()
        });
    });
    
    let mut cfg_builder = CfgBuilder::new();
    let cfg = cfg_builder.build(&ir).unwrap();
    
    group.bench_function("cfg_to_ssa", |b| {
        b.iter(|| {
            let mut ssa_builder = SsaBuilder::new();
            ssa_builder.build(black_box(&cfg)).unwrap()
        });
    });
    
    group.bench_function("ir_to_gate", |b| {
        b.iter(|| {
            let mut gate_builder = GateIrBuilder::new();
            gate_builder.build(black_box(&ir)).unwrap()
        });
    });
    
    group.finish();
}

fn benchmark_optimization_passes(c: &mut Criterion) {
    let mut group = c.benchmark_group("optimization");
    
    // Test gate cancellation
    let cancel_source = "OPENQASM 2.0; qreg q[1]; x q[0]; x q[0]; h q[0]; h q[0]; y q[0]; y q[0];";
    let mut lexer = Lexer::new(cancel_source);
    let tokens = lexer.tokenize().unwrap();
    let mut parser = Parser::new(tokens);
    let ast = parser.parse().unwrap();
    let mut ir_builder = IrBuilder::new();
    let ir = ir_builder.build(&ast).unwrap();
    let mut gate_builder = GateIrBuilder::new();
    let gate_ir = gate_builder.build(&ir).unwrap();
    
    group.bench_function("gate_cancellation", |b| {
        b.iter(|| {
            let pass = GateCancellationPass::new();
            pass.run(black_box(gate_ir.clone())).unwrap()
        });
    });
    
    // Test rotation folding
    let fold_source = "OPENQASM 2.0; qreg q[1]; rz(0.1) q[0]; rz(0.2) q[0]; rz(0.3) q[0]; rz(0.4) q[0];";
    let mut lexer = Lexer::new(fold_source);
    let tokens = lexer.tokenize().unwrap();
    let mut parser = Parser::new(tokens);
    let ast = parser.parse().unwrap();
    let mut ir_builder = IrBuilder::new();
    let ir = ir_builder.build(&ast).unwrap();
    let mut gate_builder = GateIrBuilder::new();
    let gate_ir = gate_builder.build(&ir).unwrap();
    
    group.bench_function("rotation_folding", |b| {
        b.iter(|| {
            let pass = RotationFoldingPass::new();
            pass.run(black_box(gate_ir.clone())).unwrap()
        });
    });
    
    group.finish();
}

fn benchmark_routing(c: &mut Criterion) {
    let mut group = c.benchmark_group("routing");
    
    let test_cases = vec![
        ("linear_3_adjacent", "OPENQASM 2.0; qreg q[3]; cx q[0],q[1];", 3),
        ("linear_3_distant", "OPENQASM 2.0; qreg q[3]; cx q[0],q[2];", 3),
        ("linear_5_chain", "OPENQASM 2.0; qreg q[5]; cx q[0],q[1]; cx q[1],q[2]; cx q[2],q[3]; cx q[3],q[4];", 5),
        ("linear_5_distant", "OPENQASM 2.0; qreg q[5]; cx q[0],q[4];", 5),
    ];
    
    for (name, source, num_qubits) in test_cases {
        let mut lexer = Lexer::new(source);
        let tokens = lexer.tokenize().unwrap();
        let mut parser = Parser::new(tokens);
        let ast = parser.parse().unwrap();
        let mut ir_builder = IrBuilder::new();
        let ir = ir_builder.build(&ast).unwrap();
        let mut gate_builder = GateIrBuilder::new();
        let gate_ir = gate_builder.build(&ir).unwrap();
        
        group.bench_with_input(BenchmarkId::new("sabre", name), &(gate_ir, num_qubits), |b, (g, n)| {
            b.iter(|| {
                let mut router = SabreRouter::new_linear(*n);
                router.route(black_box(g)).unwrap()
            });
        });
    }
    
    group.finish();
}

fn benchmark_full_pipeline(c: &mut Criterion) {
    let mut group = c.benchmark_group("full_pipeline");
    
    let test_cases = vec![
        ("bell_state", "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];"),
        ("ghz_3", "OPENQASM 2.0; qreg q[3]; h q[0]; cx q[0],q[1]; cx q[1],q[2];"),
        ("ghz_5", "OPENQASM 2.0; qreg q[5]; h q[0]; cx q[0],q[1]; cx q[1],q[2]; cx q[2],q[3]; cx q[3],q[4];"),
    ];
    
    for (name, source) in test_cases {
        group.bench_with_input(BenchmarkId::new("parse_to_routed", name), &source, |b, s| {
            b.iter(|| {
                // Parse
                let mut lexer = Lexer::new(black_box(s));
                let tokens = lexer.tokenize().unwrap();
                let mut parser = Parser::new(tokens);
                let ast = parser.parse().unwrap();
                
                // Semantic analysis
                let mut analyzer = SemanticAnalyzer::new();
                analyzer.analyze(&ast).unwrap();
                
                // Build IR
                let mut ir_builder = IrBuilder::new();
                let ir = ir_builder.build(&ast).unwrap();
                
                // Build Gate IR
                let mut gate_builder = GateIrBuilder::new();
                let mut gate_ir = gate_builder.build(&ir).unwrap();
                
                // Optimize
                let cancel_pass = GateCancellationPass::new();
                gate_ir = cancel_pass.run(gate_ir).unwrap();
                
                // Route
                let num_qubits = gate_ir.num_qubits();
                let mut router = SabreRouter::new_linear(num_qubits);
                router.route(&gate_ir).unwrap()
            });
        });
    }
    
    group.finish();
}

criterion_group!(
    benches,
    benchmark_parser,
    benchmark_semantic_analysis,
    benchmark_ir_construction,
    benchmark_optimization_passes,
    benchmark_routing,
    benchmark_full_pipeline
);
criterion_main!(benches);

// Made with Bob
