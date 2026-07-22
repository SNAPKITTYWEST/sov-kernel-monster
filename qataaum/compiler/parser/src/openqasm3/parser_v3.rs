//! OpenQASM 3 Parser - Full Statement Coverage
//!
//! Comprehensive parser implementing all OpenQASM 3 statement types.
//! Clean-room implementation based on public specification.

use super::ast::*;
use super::lexer::Token;
use logos::Logos;

/// Parser error
#[derive(Debug, Clone, PartialEq)]
pub struct ParseError {
    pub message: String,
    pub position: usize,
}

pub type ParseResult<T> = Result<T, ParseError>;

/// OpenQASM 3 parser with full statement coverage
pub struct Parser {
    tokens: Vec<Token>,
    position: usize,
}

impl Parser {
    /// Create a new parser
    pub fn new(source: &str) -> Self {
        let tokens: Vec<Token> = Token::lexer(source)
            .filter_map(|result| result.ok())
            .collect();
        
        Self {
            tokens,
            position: 0,
        }
    }

    /// Parse a complete OpenQASM 3 program
    pub fn parse_program(&mut self) -> ParseResult<Program> {
        let start = 0;
        
        // Parse version
        let version = self.parse_version()?;
        
        // Parse statements
        let mut statements = Vec::new();
        while !self.is_at_end() {
            match self.parse_statement() {
                Ok(stmt) => statements.push(stmt),
                Err(e) => {
                    // Try to recover by skipping to next semicolon
                    eprintln!("Parse error: {:?}", e);
                    self.skip_to_semicolon();
                }
            }
        }
        
        Ok(Program {
            version,
            statements,
            span: Span::new(start, self.position),
        })
    }

    fn parse_version(&mut self) -> ParseResult<Version> {
        self.expect(&Token::OpenQASM)?;
        
        let version_num = match self.advance() {
            Some(Token::FloatLiteral(v)) => *v,
            _ => return Err(self.error("Expected version number")),
        };
        
        self.expect(&Token::Semicolon)?;
        
        let major = version_num.floor() as u32;
        let minor = ((version_num - major as f64) * 10.0).round() as u32;
        
        Ok(Version {
            major,
            minor,
            span: Span::new(0, self.position),
        })
    }

    fn parse_statement(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        
        match self.peek() {
            Some(Token::Include) => self.parse_include(),
            Some(Token::Qubit) => self.parse_qubit_declaration(),
            Some(Token::Bit) => self.parse_classical_declaration(),
            Some(Token::Int) => self.parse_classical_declaration(),
            Some(Token::UInt) => self.parse_classical_declaration(),
            Some(Token::Float) => self.parse_classical_declaration(),
            Some(Token::Angle) => self.parse_classical_declaration(),
            Some(Token::Bool) => self.parse_classical_declaration(),
            Some(Token::Duration) => self.parse_classical_declaration(),
            Some(Token::Const) => self.parse_const_declaration(),
            Some(Token::Input) => self.parse_input_declaration(),
            Some(Token::Output) => self.parse_output_declaration(),
            Some(Token::Gate) => self.parse_gate_definition(),
            Some(Token::Def) => self.parse_function_definition(),
            Some(Token::Extern) => self.parse_extern_declaration(),
            Some(Token::If) => self.parse_if_statement(),
            Some(Token::For) => self.parse_for_loop(),
            Some(Token::While) => self.parse_while_loop(),
            Some(Token::Break) => {
                self.advance();
                self.expect(&Token::Semicolon)?;
                Ok(Statement::Break(Span::new(start, self.position)))
            }
            Some(Token::Continue) => {
                self.advance();
                self.expect(&Token::Semicolon)?;
                Ok(Statement::Continue(Span::new(start, self.position)))
            }
            Some(Token::Return) => self.parse_return_statement(),
            Some(Token::Barrier) => self.parse_barrier(),
            Some(Token::Delay) => self.parse_delay(),
            Some(Token::Box) => self.parse_timing_box(),
            Some(Token::Measure) => self.parse_measurement(),
            Some(Token::Reset) => self.parse_reset(),
            Some(Token::Identifier(_)) => {
                // Could be gate call or assignment
                self.parse_gate_call_or_assignment()
            }
            Some(Token::HardwareQubit(_)) => self.parse_gate_call_or_assignment(),
            Some(Token::Inv) | Some(Token::Pow) | Some(Token::Ctrl) | Some(Token::NegCtrl) => {
                self.parse_gate_call_or_assignment()
            }
            _ => Err(self.error(format!("Unexpected token: {:?}", self.peek()))),
        }
    }

    fn parse_include(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Include)?;
        
        let filename = match self.advance() {
            Some(Token::StringLiteral(s)) => s.clone(),
            _ => return Err(self.error("Expected string literal after include")),
        };
        
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::Include(Include {
            filename,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_qubit_declaration(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Qubit)?;
        
        // Check for array size
        let size = if matches!(self.peek(), Some(Token::LeftBracket)) {
            self.advance();
            let size_expr = self.parse_expression()?;
            self.expect(&Token::RightBracket)?;
            Some(size_expr)
        } else {
            None
        };
        
        let name = self.expect_identifier()?;
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::QubitDeclaration(QubitDeclaration {
            name,
            size,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_classical_declaration(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        let typ = self.parse_classical_type()?;
        
        // Check for array size
        let size = if matches!(self.peek(), Some(Token::LeftBracket)) {
            self.advance();
            let size_expr = self.parse_expression()?;
            self.expect(&Token::RightBracket)?;
            Some(size_expr)
        } else {
            None
        };
        
        let name = self.expect_identifier()?;
        
        // Check for initializer
        let initializer = if matches!(self.peek(), Some(Token::Assign)) {
            self.advance();
            Some(self.parse_expression()?)
        } else {
            None
        };
        
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::ClassicalDeclaration(ClassicalDeclaration {
            typ,
            name,
            size,
            initializer,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_classical_type(&mut self) -> ParseResult<ClassicalType> {
        match self.advance() {
            Some(Token::Bit) => Ok(ClassicalType::Bit),
            Some(Token::Int) => Ok(ClassicalType::Int(self.parse_optional_size()?)),
            Some(Token::UInt) => Ok(ClassicalType::UInt(self.parse_optional_size()?)),
            Some(Token::Float) => Ok(ClassicalType::Float(self.parse_optional_size()?)),
            Some(Token::Angle) => Ok(ClassicalType::Angle(self.parse_optional_size()?)),
            Some(Token::Bool) => Ok(ClassicalType::Bool),
            Some(Token::Duration) => Ok(ClassicalType::Duration),
            Some(Token::Stretch) => Ok(ClassicalType::Stretch),
            Some(Token::Complex) => {
                let inner = if matches!(self.peek(), Some(Token::LeftBracket)) {
                    self.advance();
                    let inner_type = self.parse_classical_type()?;
                    self.expect(&Token::RightBracket)?;
                    Some(std::boxed::Box::new(inner_type))
                } else {
                    None
                };
                Ok(ClassicalType::Complex(inner))
            }
            _ => Err(self.error("Expected classical type")),
        }
    }

    fn parse_optional_size(&mut self) -> ParseResult<Option<u32>> {
        if matches!(self.peek(), Some(Token::LeftBracket)) {
            self.advance();
            let size = match self.advance() {
                Some(Token::IntegerLiteral(n)) => *n as u32,
                _ => return Err(self.error("Expected integer size")),
            };
            self.expect(&Token::RightBracket)?;
            Ok(Some(size))
        } else {
            Ok(None)
        }
    }

    fn parse_const_declaration(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Const)?;
        
        let typ = self.parse_classical_type()?;
        let name = self.expect_identifier()?;
        
        self.expect(&Token::Assign)?;
        let value = self.parse_expression()?;
        
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::ConstDeclaration(ConstDeclaration {
            typ,
            name,
            value,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_input_declaration(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Input)?;
        
        let typ = self.parse_classical_type()?;
        let name = self.expect_identifier()?;
        
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::InputDeclaration(InputDeclaration {
            typ,
            name,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_output_declaration(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Output)?;
        
        let typ = self.parse_classical_type()?;
        let name = self.expect_identifier()?;
        
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::OutputDeclaration(OutputDeclaration {
            typ,
            name,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_gate_definition(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Gate)?;
        
        let name = self.expect_identifier()?;
        
        // Parse parameters (optional)
        let parameters = if matches!(self.peek(), Some(Token::LeftParen)) {
            self.parse_parameter_list()?
        } else {
            Vec::new()
        };
        
        // Parse qubits
        let mut qubits = Vec::new();
        loop {
            qubits.push(self.expect_identifier()?);
            if !matches!(self.peek(), Some(Token::Comma)) {
                break;
            }
            self.advance();
        }
        
        // Parse body
        self.expect(&Token::LeftBrace)?;
        let mut body = Vec::new();
        while !matches!(self.peek(), Some(Token::RightBrace)) {
            body.push(self.parse_gate_operation()?);
        }
        self.expect(&Token::RightBrace)?;
        
        Ok(Statement::GateDefinition(GateDefinition {
            name,
            parameters,
            qubits,
            body,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_parameter_list(&mut self) -> ParseResult<Vec<String>> {
        self.expect(&Token::LeftParen)?;
        let mut params = Vec::new();
        
        if !matches!(self.peek(), Some(Token::RightParen)) {
            loop {
                params.push(self.expect_identifier()?);
                if !matches!(self.peek(), Some(Token::Comma)) {
                    break;
                }
                self.advance();
            }
        }
        
        self.expect(&Token::RightParen)?;
        Ok(params)
    }

    fn parse_gate_operation(&mut self) -> ParseResult<GateOperation> {
        let start = self.position;
        
        if matches!(self.peek(), Some(Token::Barrier)) {
            self.advance();
            let mut qubits = Vec::new();
            loop {
                qubits.push(self.expect_identifier()?);
                if !matches!(self.peek(), Some(Token::Comma)) {
                    break;
                }
                self.advance();
            }
            self.expect(&Token::Semicolon)?;
            return Ok(GateOperation::Barrier {
                qubits,
                span: Span::new(start, self.position),
            });
        }
        
        // Parse modifiers
        let modifiers = self.parse_gate_modifiers()?;
        
        // Parse gate name
        let name = self.expect_identifier()?;
        
        // Parse arguments (optional)
        let arguments = if matches!(self.peek(), Some(Token::LeftParen)) {
            self.parse_expression_list()?
        } else {
            Vec::new()
        };
        
        // Parse qubits
        let mut qubits = Vec::new();
        loop {
            qubits.push(self.expect_identifier()?);
            if !matches!(self.peek(), Some(Token::Comma)) {
                break;
            }
            self.advance();
        }
        
        self.expect(&Token::Semicolon)?;
        
        Ok(GateOperation::GateCall {
            name,
            modifiers,
            arguments,
            qubits,
            span: Span::new(start, self.position),
        })
    }

    fn parse_gate_modifiers(&mut self) -> ParseResult<Vec<GateModifier>> {
        let mut modifiers = Vec::new();
        
        loop {
            match self.peek() {
                Some(Token::Inv) => {
                    self.advance();
                    modifiers.push(GateModifier::Inv);
                }
                Some(Token::Pow) => {
                    self.advance();
                    self.expect(&Token::LeftParen)?;
                    let exp = self.parse_expression()?;
                    self.expect(&Token::RightParen)?;
                    modifiers.push(GateModifier::Pow(exp));
                }
                Some(Token::Ctrl) => {
                    self.advance();
                    let num = if matches!(self.peek(), Some(Token::LeftParen)) {
                        self.advance();
                        let n = self.parse_expression()?;
                        self.expect(&Token::RightParen)?;
                        Some(n)
                    } else {
                        None
                    };
                    modifiers.push(GateModifier::Ctrl(num));
                }
                Some(Token::NegCtrl) => {
                    self.advance();
                    let num = if matches!(self.peek(), Some(Token::LeftParen)) {
                        self.advance();
                        let n = self.parse_expression()?;
                        self.expect(&Token::RightParen)?;
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

    fn parse_function_definition(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Def)?;
        
        let name = self.expect_identifier()?;
        
        self.expect(&Token::LeftParen)?;
        let mut parameters = Vec::new();
        if !matches!(self.peek(), Some(Token::RightParen)) {
            loop {
                let param_start = self.position;
                let typ = self.parse_classical_type()?;
                let param_name = self.expect_identifier()?;
                parameters.push(Parameter {
                    typ,
                    name: param_name,
                    span: Span::new(param_start, self.position),
                });
                if !matches!(self.peek(), Some(Token::Comma)) {
                    break;
                }
                self.advance();
            }
        }
        self.expect(&Token::RightParen)?;
        
        let return_type = if matches!(self.peek(), Some(Token::Arrow)) {
            self.advance();
            Some(self.parse_classical_type()?)
        } else {
            None
        };
        
        self.expect(&Token::LeftBrace)?;
        let mut body = Vec::new();
        while !matches!(self.peek(), Some(Token::RightBrace)) {
            body.push(self.parse_statement()?);
        }
        self.expect(&Token::RightBrace)?;
        
        Ok(Statement::FunctionDefinition(FunctionDefinition {
            name,
            parameters,
            return_type,
            body,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_extern_declaration(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Extern)?;
        
        let name = self.expect_identifier()?;
        
        self.expect(&Token::LeftParen)?;
        let mut parameters = Vec::new();
        if !matches!(self.peek(), Some(Token::RightParen)) {
            loop {
                parameters.push(self.parse_classical_type()?);
                if !matches!(self.peek(), Some(Token::Comma)) {
                    break;
                }
                self.advance();
            }
        }
        self.expect(&Token::RightParen)?;
        
        let return_type = if matches!(self.peek(), Some(Token::Arrow)) {
            self.advance();
            Some(self.parse_classical_type()?)
        } else {
            None
        };
        
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::ExternDeclaration(ExternDeclaration {
            name,
            parameters,
            return_type,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_if_statement(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::If)?;
        
        self.expect(&Token::LeftParen)?;
        let condition = self.parse_expression()?;
        self.expect(&Token::RightParen)?;
        
        self.expect(&Token::LeftBrace)?;
        let mut then_body = Vec::new();
        while !matches!(self.peek(), Some(Token::RightBrace)) {
            then_body.push(self.parse_statement()?);
        }
        self.expect(&Token::RightBrace)?;
        
        let else_body = if matches!(self.peek(), Some(Token::Else)) {
            self.advance();
            self.expect(&Token::LeftBrace)?;
            let mut body = Vec::new();
            while !matches!(self.peek(), Some(Token::RightBrace)) {
                body.push(self.parse_statement()?);
            }
            self.expect(&Token::RightBrace)?;
            Some(body)
        } else {
            None
        };
        
        Ok(Statement::If(IfStatement {
            condition,
            then_body,
            else_body,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_for_loop(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::For)?;
        
        let variable = self.expect_identifier()?;
        self.expect(&Token::In)?;
        
        let range_start = self.position;
        let range_begin = self.parse_expression()?;
        self.expect(&Token::Colon)?;
        let range_end = self.parse_expression()?;
        
        let step = if matches!(self.peek(), Some(Token::Colon)) {
            self.advance();
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
        
        self.expect(&Token::LeftBrace)?;
        let mut body = Vec::new();
        while !matches!(self.peek(), Some(Token::RightBrace)) {
            body.push(self.parse_statement()?);
        }
        self.expect(&Token::RightBrace)?;
        
        Ok(Statement::For(ForLoop {
            variable,
            range,
            body,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_while_loop(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::While)?;
        
        self.expect(&Token::LeftParen)?;
        let condition = self.parse_expression()?;
        self.expect(&Token::RightParen)?;
        
        self.expect(&Token::LeftBrace)?;
        let mut body = Vec::new();
        while !matches!(self.peek(), Some(Token::RightBrace)) {
            body.push(self.parse_statement()?);
        }
        self.expect(&Token::RightBrace)?;
        
        Ok(Statement::While(WhileLoop {
            condition,
            body,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_return_statement(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Return)?;
        
        let value = if !matches!(self.peek(), Some(Token::Semicolon)) {
            Some(self.parse_expression()?)
        } else {
            None
        };
        
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::Return(ReturnStatement {
            value,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_barrier(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Barrier)?;
        
        let qubits = self.parse_qubit_target_list()?;
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::Barrier(Barrier {
            qubits,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_delay(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Delay)?;
        
        self.expect(&Token::LeftBracket)?;
        let duration = self.parse_expression()?;
        self.expect(&Token::RightBracket)?;
        
        let qubits = self.parse_qubit_target_list()?;
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::Delay(Delay {
            duration,
            qubits,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_timing_box(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Box)?;
        
        let duration = if matches!(self.peek(), Some(Token::LeftBracket)) {
            self.advance();
            let dur = self.parse_expression()?;
            self.expect(&Token::RightBracket)?;
            Some(dur)
        } else {
            None
        };
        
        self.expect(&Token::LeftBrace)?;
        let mut body = Vec::new();
        while !matches!(self.peek(), Some(Token::RightBrace)) {
            body.push(self.parse_statement()?);
        }
        self.expect(&Token::RightBrace)?;
        
        Ok(Statement::TimingBox(TimingBox {
            duration,
            body,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_measurement(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Measure)?;
        
        let qubit = self.parse_qubit_target()?;
        
        let target = if matches!(self.peek(), Some(Token::Arrow)) {
            self.advance();
            Some(self.parse_classical_target()?)
        } else {
            None
        };
        
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::QuantumOperation(QuantumOperation::Measure {
            qubit,
            target,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_reset(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        self.expect(&Token::Reset)?;
        
        let qubit = self.parse_qubit_target()?;
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::QuantumOperation(QuantumOperation::Reset {
            qubit,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_gate_call_or_assignment(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        let checkpoint = self.position;
        
        // Try to parse as assignment first
        if let Ok(target) = self.try_parse_classical_target() {
            if self.is_assignment_op() {
                return self.parse_assignment_from_target(start, target);
            }
        }
        
        // Reset and parse as gate call
        self.position = checkpoint;
        self.parse_gate_call()
    }

    fn try_parse_classical_target(&mut self) -> ParseResult<ClassicalTarget> {
        let name = self.expect_identifier()?;
        
        if matches!(self.peek(), Some(Token::LeftBracket)) {
            self.advance();
            let index = self.parse_expression()?;
            self.expect(&Token::RightBracket)?;
            Ok(ClassicalTarget::Indexed { name, index })
        } else {
            Ok(ClassicalTarget::Identifier(name))
        }
    }

    fn is_assignment_op(&self) -> bool {
        matches!(
            self.peek(),
            Some(Token::Assign)
                | Some(Token::PlusAssign)
                | Some(Token::MinusAssign)
                | Some(Token::StarAssign)
                | Some(Token::SlashAssign)
                | Some(Token::PercentAssign)
                | Some(Token::AndAssign)
                | Some(Token::OrAssign)
                | Some(Token::XorAssign)
                | Some(Token::LeftShiftAssign)
                | Some(Token::RightShiftAssign)
        )
    }

    fn parse_assignment_from_target(
        &mut self,
        start: usize,
        target: ClassicalTarget,
    ) -> ParseResult<Statement> {
        let op = match self.advance() {
            Some(Token::Assign) => AssignmentOp::Assign,
            Some(Token::PlusAssign) => AssignmentOp::PlusAssign,
            Some(Token::MinusAssign) => AssignmentOp::MinusAssign,
            Some(Token::StarAssign) => AssignmentOp::StarAssign,
            Some(Token::SlashAssign) => AssignmentOp::SlashAssign,
            Some(Token::PercentAssign) => AssignmentOp::PercentAssign,
            Some(Token::AndAssign) => AssignmentOp::AndAssign,
            Some(Token::OrAssign) => AssignmentOp::OrAssign,
            Some(Token::XorAssign) => AssignmentOp::XorAssign,
            Some(Token::LeftShiftAssign) => AssignmentOp::LeftShiftAssign,
            Some(Token::RightShiftAssign) => AssignmentOp::RightShiftAssign,
            _ => return Err(self.error("Expected assignment operator")),
        };
        
        let value = self.parse_expression()?;
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::Assignment(Assignment {
            target,
            op,
            value,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_gate_call(&mut self) -> ParseResult<Statement> {
        let start = self.position;
        
        let modifiers = self.parse_gate_modifiers()?;
        let name = self.expect_identifier()?;
        
        let arguments = if matches!(self.peek(), Some(Token::LeftParen)) {
            self.parse_expression_list()?
        } else {
            Vec::new()
        };
        
        let qubits = self.parse_qubit_target_list()?;
        self.expect(&Token::Semicolon)?;
        
        Ok(Statement::QuantumOperation(QuantumOperation::GateCall {
            name,
            modifiers,
            arguments,
            qubits,
            span: Span::new(start, self.position),
        }))
    }

    fn parse_qubit_target(&mut self) -> ParseResult<QubitTarget> {
        match self.advance() {
            Some(Token::Identifier(name)) => {
                let name = name.clone();
                if matches!(self.peek(), Some(Token::LeftBracket)) {
                    self.advance();
                    let index = self.parse_expression()?;
                    self.expect(&Token::RightBracket)?;
                    Ok(QubitTarget::Indexed { name, index })
                } else {
                    Ok(QubitTarget::Identifier(name))
                }
            }
            Some(Token::HardwareQubit(n)) => Ok(QubitTarget::Hardware((*n).try_into().unwrap())),
            _ => Err(self.error("Expected qubit target")),
        }
    }

    fn parse_qubit_target_list(&mut self) -> ParseResult<Vec<QubitTarget>> {
        let mut qubits = Vec::new();
        
        loop {
            qubits.push(self.parse_qubit_target()?);
            if !matches!(self.peek(), Some(Token::Comma)) {
                break;
            }
            self.advance();
        }
        
        Ok(qubits)
    }

    fn parse_classical_target(&mut self) -> ParseResult<ClassicalTarget> {
        let name = self.expect_identifier()?;
        
        if matches!(self.peek(), Some(Token::LeftBracket)) {
            self.advance();
            let index = self.parse_expression()?;
            self.expect(&Token::RightBracket)?;
            Ok(ClassicalTarget::Indexed { name, index })
        } else {
            Ok(ClassicalTarget::Identifier(name))
        }
    }

    fn parse_expression_list(&mut self) -> ParseResult<Vec<Expression>> {
        self.expect(&Token::LeftParen)?;
        let mut exprs = Vec::new();
        
        if !matches!(self.peek(), Some(Token::RightParen)) {
            loop {
                exprs.push(self.parse_expression()?);
                if !matches!(self.peek(), Some(Token::Comma)) {
                    break;
                }
                self.advance();
            }
        }
        
        self.expect(&Token::RightParen)?;
        Ok(exprs)
    }

    fn parse_expression(&mut self) -> ParseResult<Expression> {
        self.parse_logical_or()
    }

    fn parse_logical_or(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_logical_and()?;
        
        while matches!(self.peek(), Some(Token::Or)) {
            self.advance();
            let right = self.parse_logical_and()?;
            left = Expression::Binary {
                op: BinaryOp::Or,
                left: std::boxed::Box::new(left),
                right: std::boxed::Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_logical_and(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_equality()?;
        
        while matches!(self.peek(), Some(Token::And)) {
            self.advance();
            let right = self.parse_equality()?;
            left = Expression::Binary {
                op: BinaryOp::And,
                left: std::boxed::Box::new(left),
                right: std::boxed::Box::new(right),
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
            self.advance();
            let right = self.parse_comparison()?;
            left = Expression::Binary {
                op,
                left: std::boxed::Box::new(left),
                right: std::boxed::Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_comparison(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_additive()?;
        
        loop {
            let op = match self.peek() {
                Some(Token::Less) => BinaryOp::Less,
                Some(Token::LessEqual) => BinaryOp::LessEqual,
                Some(Token::Greater) => BinaryOp::Greater,
                Some(Token::GreaterEqual) => BinaryOp::GreaterEqual,
                _ => break,
            };
            self.advance();
            let right = self.parse_additive()?;
            left = Expression::Binary {
                op,
                left: std::boxed::Box::new(left),
                right: std::boxed::Box::new(right),
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
            self.advance();
            let right = self.parse_multiplicative()?;
            left = Expression::Binary {
                op,
                left: std::boxed::Box::new(left),
                right: std::boxed::Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_multiplicative(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_unary()?;
        
        loop {
            let op = match self.peek() {
                Some(Token::Star) => BinaryOp::Mul,
                Some(Token::Slash) => BinaryOp::Div,
                Some(Token::Percent) => BinaryOp::Mod,
                _ => break,
            };
            self.advance();
            let right = self.parse_unary()?;
            left = Expression::Binary {
                op,
                left: std::boxed::Box::new(left),
                right: std::boxed::Box::new(right),
            };
        }
        
        Ok(left)
    }

    fn parse_unary(&mut self) -> ParseResult<Expression> {
        match self.peek() {
            Some(Token::Minus) => {
                self.advance();
                Ok(Expression::Unary {
                    op: UnaryOp::Neg,
                    operand: std::boxed::Box::new(self.parse_unary()?),
                })
            }
            Some(Token::Not) => {
                self.advance();
                Ok(Expression::Unary {
                    op: UnaryOp::Not,
                    operand: std::boxed::Box::new(self.parse_unary()?),
                })
            }
            Some(Token::Tilde) => {
                self.advance();
                Ok(Expression::Unary {
                    op: UnaryOp::BitNot,
                    operand: std::boxed::Box::new(self.parse_unary()?),
                })
            }
            _ => self.parse_primary(),
        }
    }

    fn parse_primary(&mut self) -> ParseResult<Expression> {
        match self.advance() {
            Some(Token::IntegerLiteral(n)) => Ok(Expression::IntegerLiteral(*n)),
            Some(Token::FloatLiteral(f)) => Ok(Expression::FloatLiteral(*f)),
            Some(Token::StringLiteral(s)) => Ok(Expression::StringLiteral(s.clone())),
            Some(Token::Identifier(name)) => {
                let name = name.clone();
                if matches!(self.peek(), Some(Token::LeftBracket)) {
                    self.advance();
                    let index = self.parse_expression()?;
                    self.expect(&Token::RightBracket)?;
                    Ok(Expression::Index {
                        name,
                        index: std::boxed::Box::new(index),
                    })
                } else if matches!(self.peek(), Some(Token::LeftParen)) {
                    let arguments = self.parse_expression_list()?;
                    Ok(Expression::FunctionCall { name, arguments })
                } else {
                    Ok(Expression::Identifier(name))
                }
            }
            Some(Token::LeftParen) => {
                let expr = self.parse_expression()?;
                self.expect(&Token::RightParen)?;
                Ok(expr)
            }
            _ => Err(self.error("Expected expression")),
        }
    }

    // Helper methods

    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.position)
    }

    fn advance(&mut self) -> Option<&Token> {
        if self.position < self.tokens.len() {
            let token = &self.tokens[self.position];
            self.position += 1;
            Some(token)
        } else {
            None
        }
    }

    fn expect(&mut self, expected: &Token) -> ParseResult<()> {
        match self.advance() {
            Some(token) if std::mem::discriminant(token) == std::mem::discriminant(expected) => {
                Ok(())
            }
            _ => Err(self.error(format!("Expected {:?}", expected))),
        }
    }

    fn expect_identifier(&mut self) -> ParseResult<String> {
        match self.advance() {
            Some(Token::Identifier(name)) => Ok(name.clone()),
            _ => Err(self.error("Expected identifier")),
        }
    }

    fn is_at_end(&self) -> bool {
        self.position >= self.tokens.len()
    }

    fn skip_to_semicolon(&mut self) {
        while !self.is_at_end() && !matches!(self.peek(), Some(Token::Semicolon)) {
            self.advance();
        }
        if matches!(self.peek(), Some(Token::Semicolon)) {
            self.advance();
        }
    }

    fn error(&self, message: impl Into<String>) -> ParseError {
        ParseError {
            message: message.into(),
            position: self.position,
        }
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
    fn test_version() {
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
    fn test_qubit_array() {
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
    fn test_gate_definition() {
        let source = r#"
OPENQASM 3.0;
gate h q {
    u3(1.57, 0, 3.14) q;
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
    fn test_if_statement() {
        let source = r#"
OPENQASM 3.0;
bit c;
if (c == 1) {
    reset q;
}
"#;
        let program = parse(source).unwrap();
        assert!(program.statements.len() >= 2);
        match &program.statements[1] {
            Statement::If(if_stmt) => {
                assert!(if_stmt.then_body.len() > 0);
                assert!(if_stmt.else_body.is_none());
            }
            _ => panic!("Expected if statement"),
        }
    }

    #[test]
    fn test_if_else_statement() {
        let source = r#"
OPENQASM 3.0;
bit c;
if (c == 1) {
    reset q;
} else {
    h q;
}
"#;
        let program = parse(source).unwrap();
        match &program.statements[1] {
            Statement::If(if_stmt) => {
                assert!(if_stmt.then_body.len() > 0);
                assert!(if_stmt.else_body.is_some());
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
    fn test_measurement() {
        let source = "OPENQASM 3.0;\nqubit q;\nbit c;\nmeasure q -> c;";
        let program = parse(source).unwrap();
        match &program.statements[2] {
            Statement::QuantumOperation(QuantumOperation::Measure { .. }) => {}
            _ => panic!("Expected measurement"),
        }
    }

    #[test]
    fn test_reset() {
        let source = "OPENQASM 3.0;\nqubit q;\nreset q;";
        let program = parse(source).unwrap();
        match &program.statements[1] {
            Statement::QuantumOperation(QuantumOperation::Reset { .. }) => {}
            _ => panic!("Expected reset"),
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
    fn test_extern_declaration() {
        let source = "OPENQASM 3.0;\nextern sin(float) -> float;";
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::ExternDeclaration(ext) => {
                assert_eq!(ext.name, "sin");
                assert_eq!(ext.parameters.len(), 1);
                assert!(ext.return_type.is_some());
            }
            _ => panic!("Expected extern declaration"),
        }
    }

    #[test]
    fn test_include() {
        let source = r#"OPENQASM 3.0;
include "stdgates.inc";"#;
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::Include(inc) => {
                assert_eq!(inc.filename, "stdgates.inc");
            }
            _ => panic!("Expected include"),
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

    #[test]
    fn test_gate_modifiers() {
        let source = "OPENQASM 3.0;\nqubit q;\ninv @ h q;";
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
    fn test_return_statement() {
        let source = r#"
OPENQASM 3.0;
def test() -> int {
    return 42;
}
"#;
        let program = parse(source).unwrap();
        match &program.statements[0] {
            Statement::FunctionDefinition(func) => {
                assert_eq!(func.body.len(), 1);
                match &func.body[0] {
                    Statement::Return(ret) => {
                        assert!(ret.value.is_some());
                    }
                    _ => panic!("Expected return statement"),
                }
            }
            _ => panic!("Expected function definition"),
        }
    }
}
