//! OpenQASM 2.0 Parser
//!
//! Clean-room implementation based on public OpenQASM 2.0 specification.
//! NOT derived from Qiskit parser implementation.
//!
//! Public Source: https://github.com/Qiskit/openqasm/tree/OpenQASM2.x

use crate::ast::*;
use crate::error::{ParseError, ParseResult};
use super::lexer::{Token, Lexer};

/// OpenQASM 2.0 Parser
pub struct Parser<'source> {
    lexer: Lexer<'source>,
    current: Option<Token>,
}

impl<'source> Parser<'source> {
    /// Create a new parser from source code
    pub fn new(source: &'source str) -> Self {
        let mut lexer = Lexer::new(source);
        let current = lexer.next().and_then(|r| r.ok());
        
        Self {
            lexer,
            current,
        }
    }
    
    /// Parse a complete OpenQASM 2.0 program
    pub fn parse(&mut self) -> ParseResult<Program> {
        // Parse version declaration
        let version = self.parse_version()?;
        let mut program = Program::new(version);
        
        // Parse includes and statements
        while self.current.is_some() {
            // Skip semicolons
            if self.current() == Some(&Token::Semicolon) {
                self.advance()?;
                continue;
            }
            
            // Parse include or statement
            if self.current() == Some(&Token::Include) {
                program.includes.push(self.parse_include()?);
            } else {
                program.statements.push(self.parse_statement()?);
            }
        }
        
        Ok(program)
    }
    
    /// Parse version declaration: OPENQASM 2.0;
    fn parse_version(&mut self) -> ParseResult<Version> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::OpenQASM)?;
        
        // Parse version number (e.g., 2.0)
        let (major, minor) = match self.current() {
            Some(Token::Real(v)) => {
                // Real number like 2.0
                let version = *v;
                self.advance()?;
                let major = version.floor() as u32;
                let minor = ((version - version.floor()) * 10.0).round() as u32;
                (major, minor)
            }
            Some(Token::Integer(n)) => {
                let maj = *n as u32;
                self.advance()?;
                (maj, 0)
            }
            _ => return Err(ParseError::SyntaxError {
                expected: "version number".to_string(),
                found: format!("{:?}", self.current()),
                line,
                column,
            }),
        };
        
        self.expect(Token::Semicolon)?;
        
        Ok(Version {
            major,
            minor,
            span: Span::new(line, column, 0),
        })
    }
    
    /// Parse include statement: include "filename";
    fn parse_include(&mut self) -> ParseResult<Include> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::Include)?;
        
        let filename = match self.current() {
            Some(Token::String(s)) => {
                let name = s.clone();
                self.advance()?;
                name
            }
            _ => return Err(ParseError::SyntaxError {
                expected: "filename string".to_string(),
                found: format!("{:?}", self.current()),
                line: self.lexer.line(),
                column: self.lexer.column(),
            }),
        };
        
        self.expect(Token::Semicolon)?;
        
        Ok(Include {
            filename,
            span: Span::new(line, column, 0),
        })
    }
    
    /// Parse a statement
    fn parse_statement(&mut self) -> ParseResult<Statement> {
        match self.current() {
            Some(Token::QReg) => self.parse_qreg_decl(),
            Some(Token::CReg) => self.parse_creg_decl(),
            Some(Token::Gate) => self.parse_gate_decl(),
            Some(Token::Opaque) => self.parse_opaque_decl(),
            Some(Token::Measure) => self.parse_measure(),
            Some(Token::Reset) => self.parse_reset(),
            Some(Token::Barrier) => self.parse_barrier(),
            Some(Token::If) => self.parse_if(),
            Some(Token::U) | Some(Token::CX) | Some(Token::Identifier(_)) => {
                self.parse_quantum_op()
            }
            _ => Err(ParseError::SyntaxError {
                expected: "statement".to_string(),
                found: format!("{:?}", self.current()),
                line: self.lexer.line(),
                column: self.lexer.column(),
            }),
        }
    }
    
    /// Parse qreg declaration: qreg name[size];
    fn parse_qreg_decl(&mut self) -> ParseResult<Statement> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::QReg)?;
        let name = self.parse_identifier()?;
        self.expect(Token::LBracket)?;
        let size = self.parse_integer()? as usize;
        self.expect(Token::RBracket)?;
        self.expect(Token::Semicolon)?;
        
        Ok(Statement::QRegDecl(QRegDecl {
            name,
            size,
            span: Span::new(line, column, 0),
        }))
    }
    
    /// Parse creg declaration: creg name[size];
    fn parse_creg_decl(&mut self) -> ParseResult<Statement> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::CReg)?;
        let name = self.parse_identifier()?;
        self.expect(Token::LBracket)?;
        let size = self.parse_integer()? as usize;
        self.expect(Token::RBracket)?;
        self.expect(Token::Semicolon)?;
        
        Ok(Statement::CRegDecl(CRegDecl {
            name,
            size,
            span: Span::new(line, column, 0),
        }))
    }
    
    /// Parse gate declaration
    fn parse_gate_decl(&mut self) -> ParseResult<Statement> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::Gate)?;
        let name = self.parse_identifier()?;
        
        // Parse optional parameters
        let params = if self.current() == Some(&Token::LParen) {
            self.advance()?;
            let params = self.parse_identifier_list()?;
            self.expect(Token::RParen)?;
            params
        } else {
            vec![]
        };
        
        // Parse qubits
        let qubits = self.parse_identifier_list()?;
        
        self.expect(Token::LBrace)?;
        
        // Parse gate body
        let mut body = vec![];
        while self.current() != Some(&Token::RBrace) {
            body.push(self.parse_gate_op()?);
        }
        
        self.expect(Token::RBrace)?;
        
        Ok(Statement::GateDecl(GateDecl {
            name,
            params,
            qubits,
            body,
            span: Span::new(line, column, 0),
        }))
    }
    
    /// Parse opaque declaration
    fn parse_opaque_decl(&mut self) -> ParseResult<Statement> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::Opaque)?;
        let name = self.parse_identifier()?;
        
        // Parse optional parameters
        let params = if self.current() == Some(&Token::LParen) {
            self.advance()?;
            let params = self.parse_identifier_list()?;
            self.expect(Token::RParen)?;
            params
        } else {
            vec![]
        };
        
        // Parse qubits
        let qubits = self.parse_identifier_list()?;
        
        self.expect(Token::Semicolon)?;
        
        Ok(Statement::OpaqueDecl(OpaqueDecl {
            name,
            params,
            qubits,
            span: Span::new(line, column, 0),
        }))
    }
    
    /// Parse measurement: measure qubit -> bit;
    fn parse_measure(&mut self) -> ParseResult<Statement> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::Measure)?;
        let qubit = self.parse_qubit_ref()?;
        self.expect(Token::Arrow)?;
        let bit = self.parse_bit_ref()?;
        self.expect(Token::Semicolon)?;
        
        Ok(Statement::Measure(Measure {
            qubit,
            bit,
            span: Span::new(line, column, 0),
        }))
    }
    
    /// Parse reset: reset qubit;
    fn parse_reset(&mut self) -> ParseResult<Statement> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::Reset)?;
        let qubit = self.parse_qubit_ref()?;
        self.expect(Token::Semicolon)?;
        
        Ok(Statement::Reset(Reset {
            qubit,
            span: Span::new(line, column, 0),
        }))
    }
    
    /// Parse barrier: barrier qubits;
    fn parse_barrier(&mut self) -> ParseResult<Statement> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::Barrier)?;
        let qubits = self.parse_qubit_ref_list()?;
        self.expect(Token::Semicolon)?;
        
        Ok(Statement::Barrier(Barrier {
            qubits,
            span: Span::new(line, column, 0),
        }))
    }
    
    /// Parse conditional: if(creg==value) qop;
    fn parse_if(&mut self) -> ParseResult<Statement> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        self.expect(Token::If)?;
        self.expect(Token::LParen)?;
        let creg = self.parse_identifier()?;
        self.expect(Token::EqEq)?;
        let value = self.parse_integer()?;
        self.expect(Token::RParen)?;
        
        // Parse the quantum operation
        let op = Box::new(self.parse_quantum_op_inner()?);
        
        Ok(Statement::If(If {
            creg,
            value,
            op,
            span: Span::new(line, column, 0),
        }))
    }
    
    /// Parse quantum operation statement
    fn parse_quantum_op(&mut self) -> ParseResult<Statement> {
        let op = self.parse_quantum_op_inner()?;
        self.expect(Token::Semicolon)?;
        Ok(Statement::QuantumOp(op))
    }
    
    /// Parse quantum operation (without trailing semicolon)
    fn parse_quantum_op_inner(&mut self) -> ParseResult<QuantumOp> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        let gate = match self.current() {
            Some(Token::U) => {
                self.advance()?;
                "U".to_string()
            }
            Some(Token::CX) => {
                self.advance()?;
                "CX".to_string()
            }
            Some(Token::Identifier(_)) => self.parse_identifier()?,
            _ => return Err(ParseError::SyntaxError {
                expected: "gate name".to_string(),
                found: format!("{:?}", self.current()),
                line,
                column,
            }),
        };
        
        // Parse optional parameters
        let params = if self.current() == Some(&Token::LParen) {
            self.advance()?;
            let params = self.parse_expr_list()?;
            self.expect(Token::RParen)?;
            params
        } else {
            vec![]
        };
        
        // Parse qubits
        let qubits = self.parse_qubit_ref_list()?;
        
        Ok(QuantumOp {
            gate,
            params,
            qubits,
            span: Span::new(line, column, 0),
        })
    }
    
    /// Parse gate operation (inside gate body)
    fn parse_gate_op(&mut self) -> ParseResult<GateOp> {
        let line = self.lexer.line();
        let column = self.lexer.column();
        
        match self.current() {
            Some(Token::U) => {
                self.advance()?;
                self.expect(Token::LParen)?;
                let theta = self.parse_expr()?;
                self.expect(Token::Comma)?;
                let phi = self.parse_expr()?;
                self.expect(Token::Comma)?;
                let lambda = self.parse_expr()?;
                self.expect(Token::RParen)?;
                let qubit = self.parse_identifier()?;
                self.expect(Token::Semicolon)?;
                
                Ok(GateOp::U(UGate {
                    theta,
                    phi,
                    lambda,
                    qubit,
                    span: Span::new(line, column, 0),
                }))
            }
            Some(Token::CX) => {
                self.advance()?;
                let control = self.parse_identifier()?;
                self.expect(Token::Comma)?;
                let target = self.parse_identifier()?;
                self.expect(Token::Semicolon)?;
                
                Ok(GateOp::CX(CXGate {
                    control,
                    target,
                    span: Span::new(line, column, 0),
                }))
            }
            Some(Token::Barrier) => {
                self.advance()?;
                let qubits = self.parse_identifier_list()?;
                self.expect(Token::Semicolon)?;
                Ok(GateOp::Barrier(qubits))
            }
            _ => {
                let op = self.parse_quantum_op_inner()?;
                self.expect(Token::Semicolon)?;
                Ok(GateOp::Apply(op))
            }
        }
    }
    
    /// Parse expression
    fn parse_expr(&mut self) -> ParseResult<Expr> {
        self.parse_additive_expr()
    }
    
    /// Parse additive expression (+ -)
    fn parse_additive_expr(&mut self) -> ParseResult<Expr> {
        let mut left = self.parse_multiplicative_expr()?;
        
        while matches!(self.current(), Some(Token::Plus) | Some(Token::Minus)) {
            let op = match self.current() {
                Some(Token::Plus) => BinOp::Add,
                Some(Token::Minus) => BinOp::Sub,
                _ => unreachable!(),
            };
            self.advance()?;
            let right = self.parse_multiplicative_expr()?;
            left = Expr::BinOp {
                op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }
    
    /// Parse multiplicative expression (* /)
    fn parse_multiplicative_expr(&mut self) -> ParseResult<Expr> {
        let mut left = self.parse_power_expr()?;
        
        while matches!(self.current(), Some(Token::Star) | Some(Token::Slash)) {
            let op = match self.current() {
                Some(Token::Star) => BinOp::Mul,
                Some(Token::Slash) => BinOp::Div,
                _ => unreachable!(),
            };
            self.advance()?;
            let right = self.parse_power_expr()?;
            left = Expr::BinOp {
                op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }
    
    /// Parse power expression (^)
    fn parse_power_expr(&mut self) -> ParseResult<Expr> {
        let mut left = self.parse_unary_expr()?;
        
        if self.current() == Some(&Token::Caret) {
            self.advance()?;
            let right = self.parse_power_expr()?; // Right associative
            left = Expr::BinOp {
                op: BinOp::Pow,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }
    
    /// Parse unary expression
    fn parse_unary_expr(&mut self) -> ParseResult<Expr> {
        match self.current() {
            Some(Token::Minus) => {
                self.advance()?;
                let expr = self.parse_unary_expr()?;
                Ok(Expr::UnaryOp {
                    op: UnaryOp::Neg,
                    expr: Box::new(expr),
                })
            }
            Some(Token::Identifier(name)) if matches!(name.as_str(), "sin" | "cos" | "tan" | "exp" | "ln" | "sqrt") => {
                let func = name.clone();
                self.advance()?;
                self.expect(Token::LParen)?;
                let arg = self.parse_expr()?;
                self.expect(Token::RParen)?;
                
                let op = match func.as_str() {
                    "sin" => UnaryOp::Sin,
                    "cos" => UnaryOp::Cos,
                    "tan" => UnaryOp::Tan,
                    "exp" => UnaryOp::Exp,
                    "ln" => UnaryOp::Ln,
                    "sqrt" => UnaryOp::Sqrt,
                    _ => unreachable!(),
                };
                
                Ok(Expr::UnaryOp {
                    op,
                    expr: Box::new(arg),
                })
            }
            _ => self.parse_primary_expr(),
        }
    }
    
    /// Parse primary expression
    fn parse_primary_expr(&mut self) -> ParseResult<Expr> {
        match self.current() {
            Some(Token::Integer(n)) => {
                let value = *n;
                self.advance()?;
                Ok(Expr::Int(value))
            }
            Some(Token::Real(v)) => {
                let value = *v;
                self.advance()?;
                Ok(Expr::Real(value))
            }
            Some(Token::Pi) => {
                self.advance()?;
                Ok(Expr::Pi)
            }
            Some(Token::Identifier(name)) => {
                let param = name.clone();
                self.advance()?;
                Ok(Expr::Param(param))
            }
            Some(Token::LParen) => {
                self.advance()?;
                let expr = self.parse_expr()?;
                self.expect(Token::RParen)?;
                Ok(expr)
            }
            _ => Err(ParseError::SyntaxError {
                expected: "expression".to_string(),
                found: format!("{:?}", self.current()),
                line: self.lexer.line(),
                column: self.lexer.column(),
            }),
        }
    }
    
    /// Parse qubit reference
    fn parse_qubit_ref(&mut self) -> ParseResult<QubitRef> {
        let name = self.parse_identifier()?;
        
        if self.current() == Some(&Token::LBracket) {
            self.advance()?;
            let index = self.parse_integer()? as usize;
            self.expect(Token::RBracket)?;
            Ok(QubitRef::Indexed { name, index })
        } else {
            Ok(QubitRef::Register { name })
        }
    }
    
    /// Parse bit reference
    fn parse_bit_ref(&mut self) -> ParseResult<BitRef> {
        let name = self.parse_identifier()?;
        
        if self.current() == Some(&Token::LBracket) {
            self.advance()?;
            let index = self.parse_integer()? as usize;
            self.expect(Token::RBracket)?;
            Ok(BitRef::Indexed { name, index })
        } else {
            Ok(BitRef::Register { name })
        }
    }
    
    /// Parse identifier
    fn parse_identifier(&mut self) -> ParseResult<String> {
        match self.current() {
            Some(Token::Identifier(name)) => {
                let id = name.clone();
                self.advance()?;
                Ok(id)
            }
            _ => Err(ParseError::SyntaxError {
                expected: "identifier".to_string(),
                found: format!("{:?}", self.current()),
                line: self.lexer.line(),
                column: self.lexer.column(),
            }),
        }
    }
    
    /// Parse integer
    fn parse_integer(&mut self) -> ParseResult<i64> {
        match self.current() {
            Some(Token::Integer(n)) => {
                let value = *n;
                self.advance()?;
                Ok(value)
            }
            _ => Err(ParseError::SyntaxError {
                expected: "integer".to_string(),
                found: format!("{:?}", self.current()),
                line: self.lexer.line(),
                column: self.lexer.column(),
            }),
        }
    }
    
    /// Parse comma-separated identifier list
    fn parse_identifier_list(&mut self) -> ParseResult<Vec<String>> {
        let mut ids = vec![self.parse_identifier()?];
        
        while self.current() == Some(&Token::Comma) {
            self.advance()?;
            ids.push(self.parse_identifier()?);
        }
        
        Ok(ids)
    }
    
    /// Parse comma-separated expression list
    fn parse_expr_list(&mut self) -> ParseResult<Vec<Expr>> {
        let mut exprs = vec![self.parse_expr()?];
        
        while self.current() == Some(&Token::Comma) {
            self.advance()?;
            exprs.push(self.parse_expr()?);
        }
        
        Ok(exprs)
    }
    
    /// Parse comma-separated qubit reference list
    fn parse_qubit_ref_list(&mut self) -> ParseResult<Vec<QubitRef>> {
        let mut qubits = vec![self.parse_qubit_ref()?];
        
        while self.current() == Some(&Token::Comma) {
            self.advance()?;
            qubits.push(self.parse_qubit_ref()?);
        }
        
        Ok(qubits)
    }
    
    /// Get current token
    fn current(&self) -> Option<&Token> {
        self.current.as_ref()
    }
    
    /// Advance to next token
    fn advance(&mut self) -> ParseResult<()> {
        self.current = self.lexer.next().and_then(|r| r.ok());
        Ok(())
    }
    
    /// Expect a specific token
    fn expect(&mut self, expected: Token) -> ParseResult<()> {
        if self.current() == Some(&expected) {
            self.advance()?;
            Ok(())
        } else {
            Err(ParseError::SyntaxError {
                expected: format!("{}", expected),
                found: self.current()
                    .map(|t| format!("{}", t))
                    .unwrap_or_else(|| "EOF".to_string()),
                line: self.lexer.line(),
                column: self.lexer.column(),
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parser_creation() {
        let source = "OPENQASM 2.0;";
        let parser = Parser::new(source);
        assert!(parser.current.is_some());
    }
    
    #[test]
    fn test_parse_version() {
        let source = "OPENQASM 2.0;";
        let mut parser = Parser::new(source);
        let result = parser.parse();
        assert!(result.is_ok());
        let program = result.unwrap();
        assert_eq!(program.version.major, 2);
        assert_eq!(program.version.minor, 0);
    }
    
    #[test]
    fn test_parse_qreg() {
        let source = "OPENQASM 2.0;\nqreg q[2];";
        let mut parser = Parser::new(source);
        let result = parser.parse();
        assert!(result.is_ok());
        let program = result.unwrap();
        assert_eq!(program.statements.len(), 1);
        match &program.statements[0] {
            Statement::QRegDecl(qreg) => {
                assert_eq!(qreg.name, "q");
                assert_eq!(qreg.size, 2);
            }
            _ => panic!("Expected QRegDecl"),
        }
    }
    
    #[test]
    fn test_parse_creg() {
        let source = "OPENQASM 2.0;\ncreg c[2];";
        let mut parser = Parser::new(source);
        let result = parser.parse();
        assert!(result.is_ok());
        let program = result.unwrap();
        assert_eq!(program.statements.len(), 1);
    }
    
    #[test]
    fn test_parse_gate_application() {
        let source = "OPENQASM 2.0;\nqreg q[2];\nh q[0];";
        let mut parser = Parser::new(source);
        let result = parser.parse();
        assert!(result.is_ok());
        let program = result.unwrap();
        assert_eq!(program.statements.len(), 2);
    }
    
    #[test]
    fn test_parse_measure() {
        let source = "OPENQASM 2.0;\nqreg q[1];\ncreg c[1];\nmeasure q[0] -> c[0];";
        let mut parser = Parser::new(source);
        let result = parser.parse();
        assert!(result.is_ok());
        let program = result.unwrap();
        assert_eq!(program.statements.len(), 3);
    }
    
    #[test]
    fn test_parse_bell_pair() {
        let source = r#"OPENQASM 2.0;
include "qelib1.inc";
qreg q[2];
creg c[2];
h q[0];
cx q[0], q[1];
measure q[0] -> c[0];
measure q[1] -> c[1];"#;
        let mut parser = Parser::new(source);
        let result = parser.parse();
        assert!(result.is_ok());
        let program = result.unwrap();
        assert_eq!(program.includes.len(), 1);
        assert_eq!(program.statements.len(), 6);
    }
    
    #[test]
    fn test_parse_if_statement() {
        let source = "OPENQASM 2.0;\ncreg c[1];\nqreg q[1];\nif (c == 1) x q[0];";
        let mut parser = Parser::new(source);
        let result = parser.parse();
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_parse_expressions() {
        let source = "OPENQASM 2.0;\nqreg q[1];\nU(pi/2, 0, pi) q[0];";
        let mut parser = Parser::new(source);
        let result = parser.parse();
        assert!(result.is_ok());
    }
}

// Made with Bob
