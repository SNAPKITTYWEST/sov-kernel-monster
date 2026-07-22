//! IR Builder - Transforms untyped AST to typed IR
//!
//! Clean-room implementation - not derived from Qiskit

use crate::typed_ast::*;
use crate::types::Type;
use qataaum_parser::{
    Barrier, BinOp as ParserBinOp, BitRef as ParserBitRef, Expr,
    GateOp, If as ParserIf, Measure as ParserMeasure, Program,
    QuantumOp, QubitRef as ParserQubitRef,
    Reset as ParserReset, Span, Statement, UnaryOp as ParserUnaryOp,
};
use qataaum_semantic::{SemanticAnalyzer, SemanticError};

/// IR builder
pub struct IrBuilder {
    type_checker: TypeChecker,
}

impl IrBuilder {
    /// Create a new IR builder
    pub fn new(analyzer: SemanticAnalyzer) -> Self {
        Self {
            type_checker: TypeChecker::new(analyzer.symbol_table().clone()),
        }
    }

    /// Build typed program from untyped AST
    pub fn build(&mut self, program: Program) -> Result<TypedProgram, SemanticError> {
        let mut qregs = Vec::new();
        let mut cregs = Vec::new();
        let mut gates = Vec::new();
        let mut opaques = Vec::new();
        let mut statements = Vec::new();

        // Process all statements
        for stmt in program.statements {
            match stmt {
                Statement::QRegDecl(qreg) => {
                    qregs.push(QRegDecl {
                        name: qreg.name,
                        size: qreg.size,
                        span: qreg.span,
                    });
                }
                Statement::CRegDecl(creg) => {
                    cregs.push(CRegDecl {
                        name: creg.name,
                        size: creg.size,
                        span: creg.span,
                    });
                }
                Statement::GateDecl(gate) => {
                    let typed_body = self.build_gate_body(gate.body)?;
                    gates.push(GateDecl {
                        name: gate.name,
                        params: gate.params,
                        qubits: gate.qubits,
                        body: typed_body,
                        span: gate.span,
                    });
                }
                Statement::OpaqueDecl(opaque) => {
                    opaques.push(OpaqueDecl {
                        name: opaque.name,
                        params: opaque.params,
                        qubits: opaque.qubits,
                        span: opaque.span,
                    });
                }
                _ => {
                    statements.push(self.build_statement(stmt)?);
                }
            }
        }

        Ok(TypedProgram {
            version: format!("{}.{}", program.version.major, program.version.minor),
            qregs,
            cregs,
            gates,
            opaques,
            statements,
            symbols: self.type_checker.symbols.clone(),
            types: self.type_checker.types.clone(),
        })
    }

    /// Build a typed statement
    fn build_statement(&mut self, stmt: Statement) -> Result<TypedStatement, SemanticError> {
        match stmt {
            Statement::QuantumOp(qop) => self.build_quantum_op(qop),
            Statement::Measure(measure) => self.build_measure(measure),
            Statement::Reset(reset) => self.build_reset(reset),
            Statement::Barrier(barrier) => self.build_barrier(barrier),
            Statement::If(if_stmt) => self.build_if(if_stmt),
            _ => Err(SemanticError::UndefinedSymbol {
                name: "Unexpected statement type".to_string(),
                span: Span::new(0, 0, 0),
            }),
        }
    }

    /// Build quantum operation
    fn build_quantum_op(&mut self, qop: QuantumOp) -> Result<TypedStatement, SemanticError> {
        let params = qop
            .params
            .into_iter()
            .map(|expr| self.build_expression(expr))
            .collect::<Result<Vec<_>, _>>()?;

        let qubits = qop
            .qubits
            .into_iter()
            .map(|qref| self.build_qubit_ref(qref))
            .collect::<Result<Vec<_>, _>>()?;

        Ok(TypedStatement::Gate {
            name: qop.gate,
            params,
            qubits,
            span: qop.span,
        })
    }

    /// Build measure statement
    fn build_measure(&mut self, measure: ParserMeasure) -> Result<TypedStatement, SemanticError> {
        let qubit = self.build_qubit_ref(measure.qubit)?;
        let bit = self.build_bit_ref(measure.bit)?;

        Ok(TypedStatement::Measure {
            qubit,
            bit,
            span: measure.span,
        })
    }

    /// Build reset statement
    fn build_reset(&mut self, reset: ParserReset) -> Result<TypedStatement, SemanticError> {
        let qubit = self.build_qubit_ref(reset.qubit)?;
        Ok(TypedStatement::Reset {
            qubit,
            span: reset.span,
        })
    }

    /// Build barrier statement
    fn build_barrier(&mut self, barrier: Barrier) -> Result<TypedStatement, SemanticError> {
        let qubits = barrier
            .qubits
            .into_iter()
            .map(|qref| self.build_qubit_ref(qref))
            .collect::<Result<Vec<_>, _>>()?;

        Ok(TypedStatement::Barrier {
            qubits,
            span: barrier.span,
        })
    }

    /// Build if statement
    fn build_if(&mut self, if_stmt: ParserIf) -> Result<TypedStatement, SemanticError> {
        let typed_body = Box::new(self.build_quantum_op(*if_stmt.op)?);

        Ok(TypedStatement::If {
            register: if_stmt.creg,
            value: if_stmt.value as u64,
            body: typed_body,
            span: if_stmt.span,
        })
    }

    /// Build gate body
    fn build_gate_body(&mut self, body: Vec<GateOp>) -> Result<Vec<TypedStatement>, SemanticError> {
        body.into_iter()
            .map(|op| match op {
                GateOp::Apply(qop) => self.build_quantum_op(qop),
                GateOp::Barrier(qubits) => {
                    // Convert string qubit names to QubitRefs
                    let qubit_refs: Result<Vec<_>, _> = qubits
                        .into_iter()
                        .map(|name| {
                            self.type_checker.check_qubit(
                                &name,
                                None,
                                Span::new(0, 0, 0),
                            )
                        })
                        .collect();
                    
                    Ok(TypedStatement::Barrier {
                        qubits: qubit_refs?,
                        span: Span::new(0, 0, 0),
                    })
                }
                _ => Err(SemanticError::UndefinedSymbol {
                    name: "U and CX gates not yet supported in IR".to_string(),
                    span: Span::new(0, 0, 0),
                }),
            })
            .collect()
    }

    /// Build qubit reference
    fn build_qubit_ref(&mut self, qref: ParserQubitRef) -> Result<QubitRef, SemanticError> {
        match qref {
            ParserQubitRef::Indexed { name, index } => {
                self.type_checker.check_qubit(&name, Some(index), Span::new(0, 0, 0))
            }
            ParserQubitRef::Register { name } => {
                self.type_checker.check_qubit(&name, None, Span::new(0, 0, 0))
            }
        }
    }

    /// Build bit reference
    fn build_bit_ref(&mut self, bref: ParserBitRef) -> Result<BitRef, SemanticError> {
        match bref {
            ParserBitRef::Indexed { name, index } => {
                self.type_checker.check_bit(&name, Some(index), Span::new(0, 0, 0))
            }
            ParserBitRef::Register { name } => {
                self.type_checker.check_bit(&name, None, Span::new(0, 0, 0))
            }
        }
    }

    /// Build expression
    fn build_expression(&mut self, expr: Expr) -> Result<TypedExpr, SemanticError> {
        match expr {
            Expr::Real(value) => Ok(TypedExpr::Real {
                value,
                ty: Type::Float { bits: 64 },
                span: Span::new(0, 0, 0),
            }),
            Expr::Int(value) => Ok(TypedExpr::Integer {
                value,
                ty: Type::Int { bits: 64 },
                span: Span::new(0, 0, 0),
            }),
            Expr::Pi => Ok(TypedExpr::Pi {
                ty: Type::Float { bits: 64 },
                span: Span::new(0, 0, 0),
            }),
            Expr::Param(name) => Ok(TypedExpr::Parameter {
                name,
                ty: Type::Angle,
                span: Span::new(0, 0, 0),
            }),
            Expr::BinOp { op, left, right } => {
                let left_typed = Box::new(self.build_expression(*left)?);
                let right_typed = Box::new(self.build_expression(*right)?);
                let ty = left_typed.ty().clone();

                let typed_op = match op {
                    ParserBinOp::Add => BinaryOp::Add,
                    ParserBinOp::Sub => BinaryOp::Sub,
                    ParserBinOp::Mul => BinaryOp::Mul,
                    ParserBinOp::Div => BinaryOp::Div,
                    ParserBinOp::Pow => BinaryOp::Pow,
                };

                Ok(TypedExpr::Binary {
                    op: typed_op,
                    left: left_typed,
                    right: right_typed,
                    ty,
                    span: Span::new(0, 0, 0),
                })
            }
            Expr::UnaryOp { op, expr } => {
                let expr_typed = Box::new(self.build_expression(*expr)?);
                let ty = Type::Float { bits: 64 };

                match op {
                    ParserUnaryOp::Neg => Ok(TypedExpr::Unary {
                        op: UnaryOp::Neg,
                        expr: expr_typed,
                        ty,
                        span: Span::new(0, 0, 0),
                    }),
                    ParserUnaryOp::Sin => Ok(TypedExpr::Call {
                        func: Function::Sin,
                        arg: expr_typed,
                        ty,
                        span: Span::new(0, 0, 0),
                    }),
                    ParserUnaryOp::Cos => Ok(TypedExpr::Call {
                        func: Function::Cos,
                        arg: expr_typed,
                        ty,
                        span: Span::new(0, 0, 0),
                    }),
                    ParserUnaryOp::Tan => Ok(TypedExpr::Call {
                        func: Function::Tan,
                        arg: expr_typed,
                        ty,
                        span: Span::new(0, 0, 0),
                    }),
                    ParserUnaryOp::Exp => Ok(TypedExpr::Call {
                        func: Function::Exp,
                        arg: expr_typed,
                        ty,
                        span: Span::new(0, 0, 0),
                    }),
                    ParserUnaryOp::Ln => Ok(TypedExpr::Call {
                        func: Function::Ln,
                        arg: expr_typed,
                        ty,
                        span: Span::new(0, 0, 0),
                    }),
                    ParserUnaryOp::Sqrt => Ok(TypedExpr::Call {
                        func: Function::Sqrt,
                        arg: expr_typed,
                        ty,
                        span: Span::new(0, 0, 0),
                    }),
                }
            }
            Expr::Call { func, args } => {
                if args.len() != 1 {
                    return Err(SemanticError::UndefinedSymbol {
                        name: format!("Function {} requires exactly 1 argument", func),
                        span: Span::new(0, 0, 0),
                    });
                }

                let arg_typed = Box::new(self.build_expression(args.into_iter().next().unwrap())?);
                let ty = Type::Float { bits: 64 };

                let typed_func = match func.as_str() {
                    "sin" => Function::Sin,
                    "cos" => Function::Cos,
                    "tan" => Function::Tan,
                    "exp" => Function::Exp,
                    "ln" => Function::Ln,
                    "sqrt" => Function::Sqrt,
                    _ => {
                        return Err(SemanticError::UndefinedSymbol {
                            name: func,
                            span: Span::new(0, 0, 0),
                        })
                    }
                };

                Ok(TypedExpr::Call {
                    func: typed_func,
                    arg: arg_typed,
                    ty,
                    span: Span::new(0, 0, 0),
                })
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use qataaum_parser::openqasm2::Parser;

    #[test]
    fn test_build_simple_program() {
        let source = r#"
            OPENQASM 2.0;
            qreg q[2];
            creg c[2];
            h q[0];
            cx q[0], q[1];
            measure q -> c;
        "#;

        let program = Parser::new(source).parse().unwrap();
        let mut analyzer = SemanticAnalyzer::new();
        analyzer.analyze(&program).unwrap();

        let mut builder = IrBuilder::new(analyzer);
        let typed = builder.build(program).unwrap();

        assert_eq!(typed.qregs.len(), 1);
        assert_eq!(typed.cregs.len(), 1);
        assert_eq!(typed.statements.len(), 3);
    }

    #[test]
    fn test_build_gate_with_params() {
        let source = r#"
            OPENQASM 2.0;
            gate mygate(theta) q { }
            qreg q[1];
            mygate(pi/2) q[0];
        "#;

        let program = Parser::new(source).parse().unwrap();
        let mut analyzer = SemanticAnalyzer::new();
        analyzer.analyze(&program).unwrap();

        let mut builder = IrBuilder::new(analyzer);
        let typed = builder.build(program).unwrap();

        // Should have 1 statement (the gate application)
        assert_eq!(typed.statements.len(), 1);
        match &typed.statements[0] {
            TypedStatement::Gate { name, params, .. } => {
                assert_eq!(name, "mygate");
                assert_eq!(params.len(), 1);
            }
            _ => panic!("Expected gate statement"),
        }
    }

    #[test]
    fn test_build_conditional() {
        let source = r#"
            OPENQASM 2.0;
            qreg q[1];
            creg c[1];
            measure q[0] -> c[0];
            if (c == 1) x q[0];
        "#;

        let program = Parser::new(source).parse().unwrap();
        let mut analyzer = SemanticAnalyzer::new();
        analyzer.analyze(&program).unwrap();

        let mut builder = IrBuilder::new(analyzer);
        let typed = builder.build(program).unwrap();

        assert_eq!(typed.statements.len(), 2);
        match &typed.statements[1] {
            TypedStatement::If { .. } => {}
            _ => panic!("Expected if statement"),
        }
    }
}

// Made with Bob