//! OpenQASM 3 Parser
//!
//! Recursive descent parser for OpenQASM 3.x based on the public specification.
//! This is a clean-room implementation.

use super::ast::*;
use super::lexer::{Lexer, Token};
use logos::Logos;
use std::iter::Peekable;
use std::ops::Range;

/// Parser error
#[derive(Debug, Clone, PartialEq)]
pub struct ParseError {
    pub message: String,
    pub position: usize,
}

impl ParseError {
    fn new(message: impl Into<String>, position: usize) -> Self {
        Self {
            message: message.into(),
            position,
        }
    }
}

pub type ParseResult<T> = Result<T, ParseError>;

/// OpenQASM 3 parser
pub struct Parser<'a> {
    lexer: Peekable<logos::Lexer<'a, Token>>,
    source: &'a str,
    position: usize,
}

impl<'a> Parser<'a> {
    /// Create a new parser
    pub fn new(source: &'a str) -> Self {
        Self {
            lexer: Token::lexer(source).peekable(),
            source,
            position: 0,
        }
    }

    /// Parse a complete OpenQASM 3 program
    pub fn parse_program(&mut self) -> ParseResult<Program> {
        let start = self.position;
        
        // Parse version declaration
        let version = self.parse_version()?;
        
        // Parse statements
        let mut statements = Vec::new();
        while self.peek().is_some() {
            statements.push(self.parse_statement()?);
        }
        
        let end = self.position;
        
        Ok(Program {
            version,
            statements,
            span: Span::new(start, end),
        })
    }

    /// Parse version declaration
    fn parse_version(&mut self) -> ParseResult<Version> {
        let start = self.position;
        
        self.expect(Token::OpenQASM)?;
        
        let version_str = match self.next()? {
            Token::FloatLiteral(v) => v,
            _ => return Err(self.error("Expected version number")),
        };
        
        self.expect(Token::Semicolon)?;
        
        // Parse version as major.minor
        let parts: Vec<&str> = version_str.to_string().split('.').collect();
        let major = parts.get(0)
            .and_then(|s| s.parse().ok())
            .ok_or_else(|| self.error("Invalid version format"))?;
        let minor = parts.get(1)
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        
        let end = self.position;
        
        Ok(Version {
            major,
            minor,
            span: Span::new(start, end),
        })
    }

    /// Parse a statement
    fn parse_statement(&mut self) -> ParseResult<Statement> {
        let token = self.peek().ok_or_else(|| self.error("Unexpected end of input"))?;
        
        match token {
            Token::Include => Ok(Statement::Include(self.parse_include()?)),
            Token::Qubit => Ok(Statement::QubitDeclaration(self.parse_qubit_declaration()?)),
            Token::Bit | Token::Int | Token::UInt | Token::Float | 
            Token::Angle | Token::Bool | Token::Duration | Token::Stretch | Token::Complex => {
                Ok(Statement::ClassicalDeclaration(self.parse_classical_declaration()?))
            }
            Token::Const => Ok(Statement::ConstDeclaration(self.parse_const_declaration()?)),
            Token::Input => Ok(Statement::InputDeclaration(self.parse_input_declaration()?)),
            Token::Output => Ok(Statement::OutputDeclaration(self.parse_output_declaration()?)),
            Token::Gate => Ok(Statement::GateDefinition(self.parse_gate_definition()?)),
            Token::DefCal => Ok(Statement::DefCalDefinition(self.parse_defcal_definition()?)),
            Token::Def => Ok(Statement::FunctionDefinition(self.parse_function_definition()?)),
            Token::Extern => Ok(Statement::ExternDeclaration(self.parse_extern_declaration()?)),
            Token::If => Ok(Statement::If(self.parse_if_statement()?)),
            Token::For => Ok(Statement::For(self.parse_for_loop()?)),
            Token::While => Ok(Statement::While(self.parse_while_loop()?)),
            Token::Break => {
                let start = self.position;
                self.next()?;
                self.expect(Token::Semicolon)?;
                Ok(Statement::Break(Span::new(start, self.position)))
            }
            Token::Continue => {
                let start = self.position;
                self.next()?;
                self.expect(Token::Semicolon)?;
                Ok(Statement::Continue(Span::new(start, self.position)))
            }
            Token::Return => Ok(Statement::Return(self.parse_return_statement()?)),
            Token::Barrier => Ok(Statement::Barrier(self.parse_barrier()?)),
            Token::Delay => Ok(Statement::Delay(self.parse_delay()?)),
            Token::Box => Ok(Statement::Box(self.parse_box()?)),
            Token::Pragma => Ok(Statement::Pragma(self.parse_pragma()?)),
            Token::Measure => Ok(Statement::QuantumOperation(self.parse_quantum_operation()?)),
            Token::Reset => Ok(Statement::QuantumOperation(self.parse_quantum_operation()?)),
            Token::Identifier(_) => {
                // Could be assignment or gate call
                if self.is_assignment() {
                    Ok(Statement::Assignment(self.parse_assignment()?))
                } else {
                    Ok(Statement::QuantumOperation(self.parse_quantum_operation()?))
                }
            }
            _ => Err(self.error("Unexpected token in statement")),
        }
    }

    /// Parse include statement
    fn parse_include(&mut self) -> ParseResult<Include> {
        let start = self.position;
        self.expect(Token::Include)?;
        
        let filename = match self.next()? {
            Token::StringLiteral(s) => s,
            _ => return Err(self.error("Expected string literal after include")),
        };
        
        self.expect(Token::Semicolon)?;
        
        Ok(Include {
            filename,
            span: Span::new(start, self.position),
        })
    }

    /// Parse qubit declaration
    fn parse_qubit_declaration(&mut self) -> ParseResult<QubitDeclaration> {
        let start = self.position;
        self.expect(Token::Qubit)?;
        
        let size = if self.peek() == Some(&Token::LeftBracket) {
            self.next()?;
            let size = self.parse_expression()?;
            self.expect(Token::RightBracket)?;
            Some(size)
        } else {
            None
        };
        
        let name = self.expect_identifier()?;
        self.expect(Token::Semicolon)?;
        
        Ok(QubitDeclaration {
            name,
            size,
            span: Span::new(start, self.position),
        })
    }

    /// Parse classical declaration
    fn parse_classical_declaration(&mut self) -> ParseResult<ClassicalDeclaration> {
        let start = self.position;
        let typ = self.parse_classical_type()?;
        let name = self.expect_identifier()?;
        
        let size = if self.peek() == Some(&Token::LeftBracket) {
            self.next()?;
            let size = self.parse_expression()?;
            self.expect(Token::RightBracket)?;
            Some(size)
        } else {
            None
        };
        
        let initializer = if self.peek() == Some(&Token::Assign) {
            self.next()?;
            Some(self.parse_expression()?)
        } else {
            None
        };
        
        self.expect(Token::Semicolon)?;
        
        Ok(ClassicalDeclaration {
            typ,
            name,
            size,
            initializer,
            span: Span::new(start, self.position),
        })
    }

    /// Parse const declaration
    fn parse_const_declaration(&mut self) -> ParseResult<ConstDeclaration> {
        let start = self.position;
        self.expect(Token::Const)?;
        
        let typ = self.parse_classical_type()?;
        let name = self.expect_identifier()?;
        
        self.expect(Token::Assign)?;
        let value = self.parse_expression()?;
        
        self.expect(Token::Semicolon)?;
        
        Ok(ConstDeclaration {
            typ,
            name,
            value,
            span: Span::new(start, self.position),
        })
    }

    /// Parse input declaration
    fn parse_input_declaration(&mut self) -> ParseResult<InputDeclaration> {
        let start = self.position;
        self.expect(Token::Input)?;
        
        let typ = self.parse_classical_type()?;
        let name = self.expect_identifier()?;
        
        self.expect(Token::Semicolon)?;
        
        Ok(InputDeclaration {
            typ,
            name,
            span: Span::new(start, self.position),
        })
    }

    /// Parse output declaration
    fn parse_output_declaration(&mut self) -> ParseResult<OutputDeclaration> {
        let start = self.position;
        self.expect(Token::Output)?;
        
        let typ = self.parse_classical_type()?;
        let name = self.expect_identifier()?;
        
        self.expect(Token::Semicolon)?;
        
        Ok(OutputDeclaration {
            typ,
            name,
            span: Span::new(start, self.position),
        })
    }

    /// Parse classical type
    fn parse_classical_type(&mut self) -> ParseResult<ClassicalType> {
        let token = self.next()?;
        
        match token {
            Token::Bit => Ok(ClassicalType::Bit),
            Token::Int => {
                let size = self.parse_optional_size()?;
                Ok(ClassicalType::Int(size))
            }
            Token::UInt => {
                let size = self.parse_optional_size()?;
                Ok(ClassicalType::UInt(size))
            }
            Token::Float => {
                let size = self.parse_optional_size()?;
                Ok(ClassicalType::Float(size))
            }
            Token::Angle => {
                let size = self.parse_optional_size()?;
                Ok(ClassicalType::Angle(size))
            }
            Token::Bool => Ok(ClassicalType::Bool),
            Token::Duration => Ok(ClassicalType::Duration),
            Token::Stretch => Ok(ClassicalType::Stretch),
            Token::Complex => {
                let inner = if self.peek() == Some(&Token::LeftBracket) {
                    self.next()?;
                    let inner_type = self.parse_classical_type()?;
                    self.expect(Token::RightBracket)?;
                    Some(Box::new(inner_type))
                } else {
                    None
                };
                Ok(ClassicalType::Complex(inner))
            }
            _ => Err(self.error("Expected classical type")),
        }
    }

    /// Parse optional size specifier [n]
    fn parse_optional_size(&mut self) -> ParseResult<Option<u32>> {
        if self.peek() == Some(&Token::LeftBracket) {
            self.next()?;
            let size = match self.next()? {
                Token::IntegerLiteral(n) => n as u32,
                _ => return Err(self.error("Expected integer size")),
            };
            self.expect(Token::RightBracket)?;
            Ok(Some(size))
        } else {
            Ok(None)
        }
    }

    /// Parse gate definition
    fn parse_gate_definition(&mut self) -> ParseResult<GateDefinition> {
        let start = self.position;
        self.expect(Token::Gate)?;
        
        let name = self.expect_identifier()?;
        
        // Parse parameters
        let parameters = if self.peek() == Some(&Token::LeftParen) {
            self.parse_parameter_list()?
        } else {
            Vec::new()
        };
        
        // Parse qubits
        let qubits = self.parse_qubit_parameter_list()?;
        
        // Parse body
        self.expect(Token::LeftBrace)?;
        let mut body = Vec::new();
        while self.peek() != Some(&Token::RightBrace) {
            body.push(self.parse_gate_operation()?);
        }
        self.expect(Token::RightBrace)?;
        
        Ok(GateDefinition {
            name,
            parameters,
            qubits,
            body,
            span: Span::new(start, self.position),
        })
    }

    /// Parse parameter list (a, b, c)
    fn parse_parameter_list(&mut self) -> ParseResult<Vec<String>> {
        self.expect(Token::LeftParen)?;
        let mut params = Vec::new();
        
        if self.peek() != Some(&Token::RightParen) {
            loop {
                params.push(self.expect_identifier()?);
                if self.peek() != Some(&Token::Comma) {
                    break;
                }
                self.next()?;
            }
        }
        
        self.expect(Token::RightParen)?;
        Ok(params)
    }

    /// Parse qubit parameter list q, r
    fn parse_qubit_parameter_list(&mut self) -> ParseResult<Vec<String>> {
        let mut qubits = Vec::new();
        
        loop {
            qubits.push(self.expect_identifier()?);
            if self.peek() != Some(&Token::Comma) {
                break;
            }
            self.next()?;
        }
        
        Ok(qubits)
    }

    /// Parse gate operation (inside gate definition)
    fn parse_gate_operation(&mut self) -> ParseResult<GateOperation> {
        let start = self.position;
        
        if self.peek() == Some(&Token::Barrier) {
            self.next()?;
            let qubits = self.parse_qubit_parameter_list()?;
            self.expect(Token::Semicolon)?;
            return Ok(GateOperation::Barrier {
                qubits,
                span: Span::new(start, self.position),
            });
        }
        
        // Parse modifiers
        let modifiers = self.parse_gate_modifiers()?;
        
        // Parse gate name
        let name = self.expect_identifier()?;
        
        // Parse arguments
        let arguments = if self.peek() == Some(&Token::LeftParen) {
            self.parse_expression_list()?
        } else {
            Vec::new()
        };
        
        // Parse qubits
        let qubits = self.parse_qubit_parameter_list()?;
        
        self.expect(Token::Semicolon)?;
        
        Ok(GateOperation::GateCall {
            name,
            modifiers,
            arguments,
            qubits,
            span: Span::new(start, self.position),
        })
    }

    /// Parse gate modifiers
    fn parse_gate_modifiers(&mut self) -> ParseResult<Vec<GateModifier>> {
        let mut modifiers = Vec::new();
        
        loop {
            match self.peek() {
                Some(Token::Inv) => {
                    self.next()?;
                    modifiers.push(GateModifier::Inv);
                }
                Some(Token::Pow) => {
                    self.next()?;
                    self.expect(Token::LeftParen)?;
                    let exp = self.parse_expression()?;
                    self.expect(Token::RightParen)?;
                    modifiers.push(GateModifier::Pow(exp));
                }
                Some(Token::Ctrl) => {
                    self.next()?;
                    let num = if self.peek() == Some(&Token::LeftParen) {
                        self.next()?;
                        let n = self.parse_expression()?;
                        self.expect(Token::RightParen)?;
                        Some(n)
                    } else {
                        None
                    };
                    modifiers.push(GateModifier::Ctrl(num));
                }
                Some(Token::NegCtrl) => {
                    self.next()?;
                    let num = if self.peek() == Some(&Token::LeftParen) {
                        self.next()?;
                        let n = self.parse_expression()?;
                        self.expect(Token::RightParen)?;
                        Some(n)
                    } else {
                        None
                    };
                    modifiers.push(GateModifier::NegCtrl(num));
                }
                _ => break,
            }
        }
        
        Ok(modifiers)
    }

    /// Parse expression list (a, b, c)
    fn parse_expression_list(&mut self) -> ParseResult<Vec<Expression>> {
        self.expect(Token::LeftParen)?;
        let mut exprs = Vec::new();
        
        if self.peek() != Some(&Token::RightParen) {
            loop {
                exprs.push(self.parse_expression()?);
                if self.peek() != Some(&Token::Comma) {
                    break;
                }
                self.next()?;
            }
        }
        
        self.expect(Token::RightParen)?;
        Ok(exprs)
    }

    /// Parse defcal definition (stub - full implementation would be more complex)
    fn parse_defcal_definition(&mut self) -> ParseResult<DefCalDefinition> {
        let start = self.position;
        self.expect(Token::DefCal)?;
        
        let name = self.expect_identifier()?;
        
        let parameters = if self.peek() == Some(&Token::LeftParen) {
            self.parse_parameter_list()?
        } else {
            Vec::new()
        };
        
        let qubits = self.parse_qubit_target_list()?;
        
        let return_type = if self.peek() == Some(&Token::Arrow) {
            self.next()?;
            Some(self.parse_classical_type()?)
        } else {
            None
        };
        
        self.expect(Token::LeftBrace)?;
        let mut body = Vec::new();
        while self.peek() != Some(&Token::RightBrace) {
            body.push(self.parse_statement()?);
        }
        self.expect(Token::RightBrace)?;
        
        Ok(DefCalDefinition {
            name,
            parameters,
            qubits,
            return_type,
            body,
            span: Span::new(start, self.position),
        })
    }

    /// Parse function definition
    fn parse_function_definition(&mut self) -> ParseResult<FunctionDefinition> {
        let start = self.position;
        self.expect(Token::Def)?;
        
        let name = self.expect_identifier()?;
        
        self.expect(Token::LeftParen)?;
        let mut parameters = Vec::new();
        if self.peek() != Some(&Token::RightParen) {
            loop {
                let param_start = self.position;
                let typ = self.parse_classical_type()?;
                let param_name = self.expect_identifier()?;
                parameters.push(Parameter {
                    typ,
                    name: param_name,
                    span: Span::new(param_start, self.position),
                });
                if self.peek() != Some(&Token::Comma) {
                    break;
                }
                self.next()?;
            }
        }
        self.expect(Token::RightParen)?;
        
        let return_type = if self.peek() == Some(&Token::Arrow) {
            self.next()?;
            Some(self.parse_classical_type()?)
        } else {
            None
        };
        
        self.expect(Token::LeftBrace)?;
        let mut body = Vec::new();
        while self.peek() != Some(&Token::RightBrace) {
            body.push(self.parse_statement()?);
        }
        self.expect(Token::RightBrace)?;
        
        Ok(FunctionDefinition {
            name,
            parameters,
            return_type,
            body,
            span: Span::new(start, self.position),
        })
    }

    /// Parse extern declaration
    fn parse_extern_declaration(&mut self) -> ParseResult<ExternDeclaration> {
        let start = self.position;
        self.expect(Token::Extern)?;
        
        let name = self.expect_identifier()?;
        
        self.expect(Token::LeftParen)?;
        let mut parameters = Vec::new();
        if self.peek() != Some(&Token::RightParen) {
            loop {
                parameters.push(self.parse_classical_type()?);
                if self.peek() != Some(&Token::Comma) {
                    break;
                }
                self.next()?;
            }
        }
        self.expect(Token::RightParen)?;
        
        let return_type = if self.peek() == Some(&Token::Arrow) {
            self.next()?;
            Some(self.parse_classical_type()?)
        } else {
            None
        };
        
        self.expect(Token::Semicolon)?;
        
        Ok(ExternDeclaration {
            name,
            parameters,
            return_type,
            span: Span::new(start, self.position),
        })
    }

    /// Parse quantum operation
    fn parse_quantum_operation(&mut self) -> ParseResult<QuantumOperation> {
        let start = self.position;
        
        match self.peek() {
            Some(Token::Measure) => {
                self.next()?;
                let qubit = self.parse_qubit_target()?;
                
                let target = if self.peek() == Some(&Token::Arrow) {
                    self.next()?;
                    Some(self.parse_classical_target()?)
                } else {
                    None
                };
                
                self.expect(Token::Semicolon)?;
                
                Ok(QuantumOperation::Measure {
                    qubit,
                    target,
                    span: Span::new(start, self.position),
                })
            }
            Some(Token::Reset) => {
                self.next()?;
                let qubit = self.parse_qubit_target()?;
                self.expect(Token::Semicolon)?;
                
                Ok(QuantumOperation::Reset {
                    qubit,
                    span: Span::new(start, self.position),
                })
            }
            _ => {
                // Gate call
                let modifiers = self.parse_gate_modifiers()?;
                let name = self.expect_identifier()?;
                
                let arguments = if self.peek() == Some(&Token::LeftParen) {
                    self.parse_expression_list()?
                } else {
                    Vec::new()
                };
                
                let qubits = self.parse_qubit_target_list()?;
                self.expect(Token::Semicolon)?;
                
                Ok(QuantumOperation::GateCall {
                    name,
                    modifiers,
                    arguments,
                    qubits,
                    span: Span::new(start, self.position),
                })
            }
        }
    }

    /// Parse qubit target
    fn parse_qubit_target(&mut self) -> ParseResult<QubitTarget> {
        match self.next()? {
            Token::Identifier(name) => {
                if self.peek() == Some(&Token::LeftBracket) {
                    self.next()?;
                    let index = self.parse_expression()?;
                    self.expect(Token::RightBracket)?;
                    Ok(QubitTarget::Indexed { name, index })
                } else {
                    Ok(QubitTarget::Identifier(name))
                }
            }
            Token::HardwareQubit(n) => Ok(QubitTarget::Hardware(n)),
            _ => Err(self.error("Expected qubit target")),
        }
    }

    /// Parse qubit target list
    fn parse_qubit_target_list(&mut self) -> ParseResult<Vec<QubitTarget>> {
        let mut qubits = Vec::new();
        
        loop {
            qubits.push(self.parse_qubit_target()?);
            if self.peek() != Some(&Token::Comma) {
                break;
            }
            self.next()?;
        }
        
        Ok(qubits)
    }

    /// Parse classical target
    fn parse_classical_target(&mut self) -> ParseResult<ClassicalTarget> {
        let name = self.expect_identifier()?;
        
        if self.peek() == Some(&Token::LeftBracket) {
            self.next()?;
            let index = self.parse_expression()?;
            self.expect(Token::RightBracket)?;
            Ok(ClassicalTarget::Indexed { name, index })
        } else {
            Ok(ClassicalTarget::Identifier(name))
        }
    }

    /// Check if next tokens form an assignment
    fn is_assignment(&mut self) -> bool {
        // Simple heuristic: identifier followed by assignment operator
        matches!(self.peek(), Some(Token::Identifier(_)))
    }

    /// Parse assignment
    fn parse_assignment(&mut self) -> ParseResult<Assignment> {
        let start = self.position;
        let target = self.parse_classical_target()?;
        
        let op = match self.next()? {
            Token::Assign => AssignmentOp::Assign,
            Token::PlusAssign => AssignmentOp::PlusAssign,
            Token::MinusAssign => AssignmentOp::MinusAssign,
            Token::StarAssign => AssignmentOp::StarAssign,
            Token::SlashAssign => AssignmentOp::SlashAssign,
            Token::PercentAssign => AssignmentOp::PercentAssign,
            Token::AndAssign => AssignmentOp::AndAssign,
            Token::OrAssign => AssignmentOp::OrAssign,
            Token::XorAssign => AssignmentOp::XorAssign,
            Token::LeftShiftAssign => AssignmentOp::LeftShiftAssign,
            Token::RightShiftAssign => AssignmentOp::RightShiftAssign,
            _ => return Err(self.error("Expected assignment operator")),
        };
        
        let value = self.parse_expression()?;
        self.expect(Token::Semicolon)?;
        
        Ok(Assignment {
            target,
            op,
            value,
            span: Span::new(start, self.position),
        })
    }

    /// Parse if statement
    fn parse_if_statement(&mut self) -> ParseResult<IfStatement> {
        let start = self.position;
        self.expect(Token::If)?;
        
        self.expect(Token::LeftParen)?;
        let condition = self.parse_expression()?;
        self.expect(Token::RightParen)?;
        
        self.expect(Token::LeftBrace)?;
        let mut then_body = Vec::new();
        while self.peek() != Some(&Token::RightBrace) {
            then_body.push(self.parse_statement()?);
        }
        self.expect(Token::RightBrace)?;
        
        let else_body = if self.peek() == Some(&Token::Else) {
            self.next()?;
            self.expect(Token::LeftBrace)?;
            let mut body = Vec::new();
            while self.peek() != Some(&Token::RightBrace) {
                body.push(self.parse_statement()?);
            }
            self.expect(Token::RightBrace)?;
            Some(body)
        } else {
            None
        };
        
        Ok(IfStatement {
            condition,
            then_body,
            else_body,
            span: Span::new(start, self.position),
        })
    }

    /// Parse for loop
    fn parse_for_loop(&mut self) -> ParseResult<ForLoop> {
        let start = self.position;
        self.expect(Token::For)?;
        
        let variable = self.expect_identifier()?;
        self.expect(Token::In)?;
        
        let range_start = self.position;
        let range_begin = self.parse_expression()?;
        self.expect(Token::Colon)?;
        let range_end = self.parse_expression()?;
        
        let step = if self.peek() == Some(&Token::Colon) {
            self.next()?;
            Some(self.parse_expression()?)
        } else {
            None
        };
        
        let range = Range {
            start: range_begin,
            end: range_end,
            step,
            span: Span::new(range_start, self.position),
        };
        
        self.expect(Token::LeftBrace)?;
        let mut body = Vec::new();
        while self.peek() != Some(&Token::RightBrace) {
            body.push(self.parse_statement()?);
        }
        self.expect(Token::RightBrace)?;
        
        Ok(ForLoop {
            variable,
            range,
            body,
            span: Span::new(start, self.position),
        })
    }

    /// Parse while loop
    fn parse_while_loop(&mut self) -> ParseResult<WhileLoop> {
        let start = self.position;
        self.expect(Token::While)?;
        
        self.expect(Token::LeftParen)?;
        let condition = self.parse_expression()?;
        self.expect(Token::RightParen)?;
        
        self.expect(Token::LeftBrace)?;
        let mut body = Vec::new();
        while self.peek() != Some(&Token::RightBrace) {
            body.push(self.parse_statement()?);
        }
        self.expect(Token::RightBrace)?;
        
        Ok(WhileLoop {
            condition,
            body,
            span: Span::new(start, self.position),
        })
    }

    /// Parse return statement
    fn parse_return_statement(&mut self) -> ParseResult<ReturnStatement> {
        let start = self.position;
        self.expect(Token::Return)?;
        
        let value = if self.peek() != Some(&Token::Semicolon) {
            Some(self.parse_expression()?)
        } else {
            None
        };
        
        self.expect(Token::Semicolon)?;
        
        Ok(ReturnStatement {
            value,
            span: Span::new(start, self.position),
        })
    }

    /// Parse barrier
    fn parse_barrier(&mut self) -> ParseResult<Barrier> {
        let start = self.position;
        self.expect(Token::Barrier)?;
        
        let qubits = self.parse_qubit_target_list()?;
        self.expect(Token::Semicolon)?;
        
        Ok(Barrier {
            qubits,
            span: Span::new(start, self.position),
        })
    }

    /// Parse delay
    fn parse_delay(&mut self) -> ParseResult<Delay> {
        let start = self.position;
        self.expect(Token::Delay)?;
        
        self.expect(Token::LeftBracket)?;
        let duration = self.parse_expression()?;
        self.expect(Token::RightBracket)?;
        
        let qubits = self.parse_qubit_target_list()?;
        self.expect(Token::Semicolon)?;
        
        Ok(Delay {
            duration,
            qubits,
            span: Span::new(start, self.position),
        })
    }

    /// Parse box
    fn parse_box(&mut self) -> ParseResult<Box> {
        let start = self.position;
        self.expect(Token::Box)?;
        
        let duration = if self.peek() == Some(&Token::LeftBracket) {
            self.next()?;
            let dur = self.parse_expression()?;
            self.expect(Token::RightBracket)?;
            Some(dur)
        } else {
            None
        };
        
        self.expect(Token::LeftBrace)?;
        let mut body = Vec::new();
        while self.peek() != Some(&Token::RightBrace) {
            body.push(self.parse_statement()?);
        }
        self.expect(Token::RightBrace)?;
        
        Ok(Box {
            duration,
            body,
            span: Span::new(start, self.position),
        })
    }

    /// Parse pragma
    fn parse_pragma(&mut self) -> ParseResult<Pragma> {
        let start = self.position;
        self.expect(Token::Pragma)?;
        
        // Collect all tokens until semicolon
        let mut content = String::new();
        while self.peek() != Some(&Token::Semicolon) {
            if let Some(token) = self.peek() {
                content.push_str(&format!("{:?} ", token));
                self.next()?;
            } else {
                break;
            }
        }
        
        self.expect(Token::Semicolon)?;
        
        Ok(Pragma {
            content,
            span: Span::new(start, self.position),
        })
    }

    /// Parse expression (simplified - full precedence climbing would be more robust)
    fn parse_expression(&mut self) -> ParseResult<Expression> {
        self.parse_logical_or()
    }

    fn parse_logical_or(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_logical_and()?;
        
        while self.peek() == Some(&Token::Or) {
            self.next()?;
            let right = self.parse_logical_and()?;
            left = Expression::Binary {
                op: BinaryOp::Or,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_logical_and(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_bitwise_or()?;
        
        while self.peek() == Some(&Token::And) {
            self.next()?;
            let right = self.parse_bitwise_or()?;
            left = Expression::Binary {
                op: BinaryOp::And,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_bitwise_or(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_bitwise_xor()?;
        
        while self.peek() == Some(&Token::Pipe) {
            self.next()?;
            let right = self.parse_bitwise_xor()?;
            left = Expression::Binary {
                op: BinaryOp::BitOr,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_bitwise_xor(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_bitwise_and()?;
        
        while self.peek() == Some(&Token::Caret) {
            self.next()?;
            let right = self.parse_bitwise_and()?;
            left = Expression::Binary {
                op: BinaryOp::BitXor,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_bitwise_and(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_equality()?;
        
        while self.peek() == Some(&Token::Ampersand) {
            self.next()?;
            let right = self.parse_equality()?;
            left = Expression::Binary {
                op: BinaryOp::BitAnd,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_equality(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_comparison()?;
        
        loop {
            let op = match self.peek() {
                Some(Token::Equal) => BinaryOp::Equal,
                Some(Token::NotEqual) => BinaryOp::NotEqual,
                _ => break,
            };
            self.next()?;
            let right = self.parse_comparison()?;
            left = Expression::Binary {
                op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_comparison(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_shift()?;
        
        loop {
            let op = match self.peek() {
                Some(Token::Less) => BinaryOp::Less,
                Some(Token::LessEqual) => BinaryOp::LessEqual,
                Some(Token::Greater) => BinaryOp::Greater,
                Some(Token::GreaterEqual) => BinaryOp::GreaterEqual,
                _ => break,
            };
            self.next()?;
            let right = self.parse_shift()?;
            left = Expression::Binary {
                op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_shift(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_additive()?;
        
        loop {
            let op = match self.peek() {
                Some(Token::LeftShift) => BinaryOp::LeftShift,
                Some(Token::RightShift) => BinaryOp::RightShift,
                _ => break,
            };
            self.next()?;
            let right = self.parse_additive()?;
            left = Expression::Binary {
                op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_additive(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_multiplicative()?;
        
        loop {
            let op = match self.peek() {
                Some(Token::Plus) => BinaryOp::Add,
                Some(Token::Minus) => BinaryOp::Sub,
                _ => break,
            };
            self.next()?;
            let right = self.parse_multiplicative()?;
            left = Expression::Binary {
                op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_multiplicative(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_power()?;
        
        loop {
            let op = match self.peek() {
                Some(Token::Star) => BinaryOp::Mul,
                Some(Token::Slash) => BinaryOp::Div,
                Some(Token::Percent) => BinaryOp::Mod,
                _ => break,
            };
            self.next()?;
            let right = self.parse_power()?;
            left = Expression::Binary {
                op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_power(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_unary()?;
        
        if self.peek() == Some(&Token::Power) {
            self.next()?;
            let right = self.parse_power()?; // Right associative
            left = Expression::Binary {
                op: BinaryOp::Power,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_unary(&mut self) -> ParseResult<Expression> {
        match self.peek() {
            Some(Token::Minus) => {
                self.next()?;
                Ok(Expression::Unary {
                    op: UnaryOp::Neg,
                    operand: Box::new(self.parse_unary()?),
                })
            }
            Some(Token::Not) => {
                self.next()?;
                Ok(Expression::Unary {
                    op: UnaryOp::Not,
                    operand: Box::new(self.parse_unary()?),
                })
            }
            Some(Token::Tilde) => {
                self.next()?;
                Ok(Expression::Unary {
                    op: UnaryOp::BitNot,
                    operand: Box::new(self.parse_unary()?),
                })
            }
            _ => self.parse_primary(),
        }
    }

    fn parse_primary(&mut self) -> ParseResult<Expression> {
        match self.next()? {
            Token::IntegerLiteral(n) => Ok(Expression::IntegerLiteral(n)),
            Token::FloatLiteral(f) => Ok(Expression::FloatLiteral(f)),
            Token::BooleanLiteral(b) => Ok(Expression::BooleanLiteral(b)),
            Token::StringLiteral(s) => Ok(Expression::StringLiteral(s)),
            Token::DurationLiteral(value, unit) => {
                let duration_unit = match unit.as_str() {
                    "ns" => DurationUnit::Nanosecond,
                    "us" => DurationUnit::Microsecond,
                    "ms" => DurationUnit::Millisecond,
                    "s" => DurationUnit::Second,
                    "dt" => DurationUnit::DT,
                    _ => return Err(self.error("Invalid duration unit")),
                };
                Ok(Expression::DurationLiteral(value, duration_unit))
            }
            Token::Identifier(name) => {
                if self.peek() == Some(&Token::LeftBracket) {
                    self.next()?;
                    let index = self.parse_expression()?;
                    self.expect(Token::RightBracket)?;
                    Ok(Expression::Index {
                        name,
                        index: Box::new(index),
                    })
                } else if self.peek() == Some(&Token::LeftParen) {
                    let arguments = self.parse_expression_list()?;
                    Ok(Expression::FunctionCall { name, arguments })
                } else {
                    Ok(Expression::Identifier(name))
                }
            }
            Token::LeftParen => {
                let expr = self.parse_expression()?;
                self.expect(Token::RightParen)?;
                Ok(expr)
            }
            _ => Err(self.error("Expected expression")),
        }
    }

    // Helper methods

    fn peek(&mut self) -> Option<&Token> {
        self.lexer.peek()
    }

    fn next(&mut self) -> ParseResult<Token> {
        self.lexer.next()
            .ok_or_else(|| self.error("Unexpected end of input"))
    }

    fn expect(&mut self, expected: Token) -> ParseResult<()> {
        let token = self.next()?;
        if token == expected {
            Ok(())
        } else {
            Err(self.error(format!("Expected {:?}, found {:?}", expected, token)))
        }
    }

    fn expect_identifier(&mut self) -> ParseResult<String> {
        match self.next()? {
            Token::Identifier(name) => Ok(name),
            token => Err(self.error(format!("Expected identifier, found {:?}", token))),
        }
    }

    fn error(&self, message: impl Into<String>) -> ParseError {
        ParseError::new(message, self.position)
    }
}

// Made with Bob
#[cfg(test)]
mod tests {
    use super::*;

    fn parse(source: &str) -> ParseResult<Program> {
        Parser::new(source).parse_program()
    }

    #[test]
    fn test_version_declaration() {
        let source = "OPENQASM 3.0;";
        let program = parse(source).unwrap();
        assert_eq!(program.version.major, 3);
        assert_eq!(program.version.minor, 0);
    }

    #[test]
    fn test_qubit_declaration() {
        let source = "OPENQASM 3.0;\nqubit q;";
        let program = parse(source).unwrap();
        assert_eq!(program.statements.len(), 1);
        match &program.statements[0] {
            Statement::QubitDeclaration(decl) => {
                assert_eq!(decl.name, "q");
                assert!(decl.size.is_none());
            }
            _ => panic!("Expected qubit declaration"),
        }
    }

    #[test]
    fn test_qubit_array_declaration() {
        let source = "OPENQASM 3.0;\nqubit[5] q;";
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::QubitDeclaration(decl) => {
                assert_eq!(decl.name, "q");
                assert!(decl.size.is_some());
            }
            _ => panic!("Expected qubit declaration"),
        }
    }

    #[test]
    fn test_classical_declaration() {
        let source = "OPENQASM 3.0;\nbit[5] c;";
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::ClassicalDeclaration(decl) => {
                assert_eq!(decl.name, "c");
                assert!(matches!(decl.typ, ClassicalType::Bit));
            }
            _ => panic!("Expected classical declaration"),
        }
    }

    #[test]
    fn test_gate_definition() {
        let source = r#"
OPENQASM 3.0;
gate h q {
    u3(pi/2, 0, pi) q;
}
"#;
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::GateDefinition(gate) => {
                assert_eq!(gate.name, "h");
                assert_eq!(gate.qubits.len(), 1);
                assert_eq!(gate.body.len(), 1);
            }
            _ => panic!("Expected gate definition"),
        }
    }

    #[test]
    fn test_gate_application() {
        let source = "OPENQASM 3.0;\nqubit q;\nh q;";
        let program = parse(source).unwrap();
        assert_eq!(program.statements.len(), 2);
        match &program.statements[1] {
            Statement::QuantumOperation(QuantumOperation::GateCall { name, .. }) => {
                assert_eq!(name, "h");
            }
            _ => panic!("Expected gate call"),
        }
    }

    #[test]
    fn test_measurement() {
        let source = "OPENQASM 3.0;\nqubit q;\nbit c;\nmeasure q -> c;";
        let program = parse(source).unwrap();
        match &program.statements[2] {
            Statement::QuantumOperation(QuantumOperation::Measure { .. }) => {}
            _ => panic!("Expected measurement"),
        }
    }

    #[test]
    fn test_if_statement() {
        let source = r#"
OPENQASM 3.0;
bit c;
if (c == 1) {
    reset q;
}
"#;
        let program = parse(source).unwrap();
        match &program.statements[1] {
            Statement::If(if_stmt) => {
                assert!(if_stmt.then_body.len() > 0);
                assert!(if_stmt.else_body.is_none());
            }
            _ => panic!("Expected if statement"),
        }
    }

    #[test]
    fn test_for_loop() {
        let source = r#"
OPENQASM 3.0;
for i in 0:10 {
    h q[i];
}
"#;
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::For(for_loop) => {
                assert_eq!(for_loop.variable, "i");
                assert!(for_loop.body.len() > 0);
            }
            _ => panic!("Expected for loop"),
        }
    }

    #[test]
    fn test_while_loop() {
        let source = r#"
OPENQASM 3.0;
int i = 0;
while (i < 10) {
    i += 1;
}
"#;
        let program = parse(source).unwrap();
        match &program.statements[1] {
            Statement::While(while_loop) => {
                assert!(while_loop.body.len() > 0);
            }
            _ => panic!("Expected while loop"),
        }
    }

    #[test]
    fn test_barrier() {
        let source = "OPENQASM 3.0;\nqubit[2] q;\nbarrier q[0], q[1];";
        let program = parse(source).unwrap();
        match &program.statements[1] {
            Statement::Barrier(barrier) => {
                assert_eq!(barrier.qubits.len(), 2);
            }
            _ => panic!("Expected barrier"),
        }
    }

    #[test]
    fn test_delay() {
        let source = "OPENQASM 3.0;\nqubit q;\ndelay[100ns] q;";
        let program = parse(source).unwrap();
        match &program.statements[1] {
            Statement::Delay(delay) => {
                assert_eq!(delay.qubits.len(), 1);
            }
            _ => panic!("Expected delay"),
        }
    }

    #[test]
    fn test_gate_modifiers() {
        let source = "OPENQASM 3.0;\nqubit[2] q;\ninv @ h q[0];";
        let program = parse(source).unwrap();
        match &program.statements[1] {
            Statement::QuantumOperation(QuantumOperation::GateCall { modifiers, .. }) => {
                assert_eq!(modifiers.len(), 1);
                assert!(matches!(modifiers[0], GateModifier::Inv));
            }
            _ => panic!("Expected gate call with modifiers"),
        }
    }

    #[test]
    fn test_hardware_qubit() {
        let source = "OPENQASM 3.0;\nh $0;";
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::QuantumOperation(QuantumOperation::GateCall { qubits, .. }) => {
                assert!(matches!(qubits[0], QubitTarget::Hardware(0)));
            }
            _ => panic!("Expected gate call with hardware qubit"),
        }
    }

    #[test]
    fn test_expression_arithmetic() {
        let source = "OPENQASM 3.0;\nint x = 2 + 3 * 4;";
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::ClassicalDeclaration(decl) => {
                assert!(decl.initializer.is_some());
            }
            _ => panic!("Expected classical declaration"),
        }
    }

    #[test]
    fn test_function_definition() {
        let source = r#"
OPENQASM 3.0;
def add(int a, int b) -> int {
    return a + b;
}
"#;
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::FunctionDefinition(func) => {
                assert_eq!(func.name, "add");
                assert_eq!(func.parameters.len(), 2);
                assert!(func.return_type.is_some());
            }
            _ => panic!("Expected function definition"),
        }
    }

    #[test]
    fn test_const_declaration() {
        let source = "OPENQASM 3.0;\nconst int N = 10;";
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::ConstDeclaration(decl) => {
                assert_eq!(decl.name, "N");
            }
            _ => panic!("Expected const declaration"),
        }
    }

    #[test]
    fn test_complex_program() {
        let source = r#"
OPENQASM 3.0;
include "stdgates.inc";

qubit[2] q;
bit[2] c;

h q[0];
cx q[0], q[1];
measure q -> c;
"#;
        let program = parse(source).unwrap();
        assert!(program.statements.len() >= 5);
    }
}
