//! MetaQASM-4 Parser
//!
//! MetaQASM-4 is an ORIGINAL EXPERIMENTAL LANGUAGE designed by the QATAAUM project.
//! It is NOT OpenQASM 4 (which does not exist as a public standard).
//!
//! This parser implements recursive descent parsing for MetaQASM-4 with:
//! - Typed effects
//! - Linear ownership
//! - Refinement types
//! - Capability indexing
//! - Proof obligations

use super::ast::*;
use super::lexer::Token;
use logos::Logos;

pub type ParseResult<T> = Result<T, ParseError>;

#[derive(Debug, Clone, PartialEq)]
pub struct ParseError {
    pub message: String,
}

impl ParseError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

pub struct Parser {
    tokens: Vec<Token>,
    position: usize,
}

impl Parser {
    pub fn new(source: &str) -> Self {
        let tokens: Vec<Token> = Token::lexer(source)
            .filter_map(|result| result.ok())
            .collect();
        
        Self {
            tokens,
            position: 0,
        }
    }
    
    pub fn parse(&mut self) -> ParseResult<Program> {
        let version = self.parse_version()?;
        let mut imports = Vec::new();
        let mut statements = Vec::new();
        
        while self.peek().is_some() {
            if matches!(self.peek(), Some(Token::Import)) {
                imports.push(self.parse_import()?);
            } else {
                statements.push(self.parse_statement()?);
            }
        }
        
        Ok(Program {
            version,
            imports,
            statements,
        })
    }
    
    fn parse_version(&mut self) -> ParseResult<Version> {
        self.expect(&Token::MetaQASM)?;
        
        if let Some(Token::FloatLiteral(v)) = self.advance() {
            let major = v.floor() as u32;
            let minor = ((v - v.floor()) * 10.0).round() as u32;
            self.expect(&Token::Semicolon)?;
            Ok(Version { major, minor })
        } else {
            Err(self.error("Expected version number"))
        }
    }
    
    fn parse_import(&mut self) -> ParseResult<Import> {
        self.expect(&Token::Import)?;
        let mut path = vec![self.expect_identifier()?];
        
        while matches!(self.peek(), Some(Token::Dot)) {
            self.advance();
            path.push(self.expect_identifier()?);
        }
        
        self.expect(&Token::Semicolon)?;
        Ok(Import { path })
    }
    
    fn parse_statement(&mut self) -> ParseResult<Statement> {
        match self.peek() {
            Some(Token::Type) => Ok(Statement::TypeDecl(self.parse_type_decl()?)),
            Some(Token::Circuit) => Ok(Statement::CircuitDecl(self.parse_effect_decl(EffectMonad::CircuitM)?)),
            Some(Token::Measurement) => Ok(Statement::MeasurementDecl(self.parse_effect_decl(EffectMonad::MeasureM)?)),
            Some(Token::Dynamic) => Ok(Statement::DynamicDecl(self.parse_effect_decl(EffectMonad::DynamicM)?)),
            Some(Token::Pulse) => Ok(Statement::PulseDecl(self.parse_effect_decl(EffectMonad::PulseM)?)),
            Some(Token::Backend) => Ok(Statement::BackendDecl(self.parse_effect_decl(EffectMonad::BackendM)?)),
            Some(Token::Proof) => Ok(Statement::ProofDecl(self.parse_effect_decl(EffectMonad::ProofM)?)),
            Some(Token::Receipt) => Ok(Statement::ReceiptDecl(self.parse_effect_decl(EffectMonad::ReceiptM)?)),
            Some(Token::Capability) => Ok(Statement::CapabilityDecl(self.parse_capability_decl()?)),
            Some(Token::Predicate) => Ok(Statement::PredicateDecl(self.parse_predicate_decl()?)),
            Some(Token::Qubit) | Some(Token::Bit) | Some(Token::Int) | Some(Token::Float) => {
                Ok(Statement::VarDecl(self.parse_var_decl()?))
            }
            Some(Token::Const) => Ok(Statement::VarDecl(self.parse_const_decl()?)),
            Some(Token::Return) => Ok(Statement::Return(self.parse_return()?)),
            Some(Token::If) => Ok(Statement::If(self.parse_if()?)),
            Some(Token::For) => Ok(Statement::For(self.parse_for()?)),
            Some(Token::While) => Ok(Statement::While(self.parse_while()?)),
            Some(Token::Break) => {
                self.advance();
                self.expect(&Token::Semicolon)?;
                Ok(Statement::Break)
            }
            Some(Token::Continue) => {
                self.advance();
                self.expect(&Token::Semicolon)?;
                Ok(Statement::Continue)
            }
            Some(Token::LeftBrace) => Ok(Statement::Block(self.parse_block()?)),
            Some(Token::Identifier(_)) => {
                // Could be ownership transfer or expression
                let start_pos = self.position;
                let name = self.expect_identifier()?;
                
                if matches!(self.peek(), Some(Token::LeftArrow)) {
                    self.advance();
                    let source = self.parse_expression()?;
                    self.expect(&Token::Semicolon)?;
                    Ok(Statement::OwnershipTransfer(OwnershipTransfer {
                        target: name,
                        source,
                    }))
                } else {
                    // Backtrack and parse as expression
                    self.position = start_pos;
                    let expr = self.parse_expression()?;
                    self.expect(&Token::Semicolon)?;
                    Ok(Statement::ExprStmt(expr))
                }
            }
            _ => {
                let expr = self.parse_expression()?;
                self.expect(&Token::Semicolon)?;
                Ok(Statement::ExprStmt(expr))
            }
        }
    }
    
    fn parse_type_decl(&mut self) -> ParseResult<TypeDecl> {
        self.expect(&Token::Type)?;
        let name = self.expect_identifier()?;
        self.expect(&Token::Assign)?;
        let type_expr = self.parse_type_expr()?;
        self.expect(&Token::Semicolon)?;
        
        Ok(TypeDecl { name, type_expr })
    }
    
    fn parse_effect_decl(&mut self, effect: EffectMonad) -> ParseResult<EffectDecl> {
        // Skip effect keyword (circuit, measurement, etc.)
        self.advance();
        
        // Expect <EffectM>
        self.expect(&Token::Less)?;
        self.expect_effect_monad(&effect)?;
        self.expect(&Token::Greater)?;
        
        let name = self.expect_identifier()?;
        
        // Parameters
        self.expect(&Token::LeftParen)?;
        let params = self.parse_parameter_list()?;
        self.expect(&Token::RightParen)?;
        
        // Return type
        let return_type = if matches!(self.peek(), Some(Token::Arrow)) {
            self.advance();
            Some(self.parse_type_expr()?)
        } else {
            None
        };
        
        // Contracts
        let mut requires = Vec::new();
        let mut ensures = Vec::new();
        let mut invariants = Vec::new();
        
        while matches!(self.peek(), Some(Token::Requires) | Some(Token::Ensures) | Some(Token::Invariant)) {
            match self.advance() {
                Some(Token::Requires) => {
                    requires.push(Predicate {
                        expr: self.parse_expression()?,
                    });
                }
                Some(Token::Ensures) => {
                    ensures.push(Predicate {
                        expr: self.parse_expression()?,
                    });
                }
                Some(Token::Invariant) => {
                    invariants.push(Predicate {
                        expr: self.parse_expression()?,
                    });
                }
                _ => unreachable!(),
            }
        }
        
        // Body
        let body = self.parse_block()?;
        
        Ok(EffectDecl {
            effect,
            name,
            params,
            return_type,
            requires,
            ensures,
            invariants,
            body,
        })
    }
    
    fn parse_parameter_list(&mut self) -> ParseResult<Vec<Parameter>> {
        let mut params = Vec::new();
        
        if matches!(self.peek(), Some(Token::RightParen)) {
            return Ok(params);
        }
        
        loop {
            params.push(self.parse_parameter()?);
            if !matches!(self.peek(), Some(Token::Comma)) {
                break;
            }
            self.advance();
        }
        
        Ok(params)
    }
    
    fn parse_parameter(&mut self) -> ParseResult<Parameter> {
        let name = self.expect_identifier()?;
        self.expect(&Token::Colon)?;
        
        let ownership = match self.peek() {
            Some(Token::Owned) => {
                self.advance();
                Some(Ownership::Owned)
            }
            Some(Token::Borrowed) => {
                self.advance();
                Some(Ownership::Borrowed)
            }
            Some(Token::Released) => {
                self.advance();
                Some(Ownership::Released)
            }
            _ => None,
        };
        
        let type_expr = self.parse_type_expr()?;
        
        Ok(Parameter {
            name,
            ownership,
            type_expr,
        })
    }
    
    fn parse_type_expr(&mut self) -> ParseResult<TypeExpr> {
        match self.peek() {
            Some(Token::LeftBrace) => self.parse_refinement_type(),
            Some(Token::Less) => self.parse_effect_type(),
            Some(Token::Owned) | Some(Token::Borrowed) | Some(Token::Released) => {
                self.parse_linear_type()
            }
            Some(Token::LeftParen) => self.parse_tuple_or_function_type(),
            _ => self.parse_base_or_named_type(),
        }
    }
    
    fn parse_refinement_type(&mut self) -> ParseResult<TypeExpr> {
        self.expect(&Token::LeftBrace)?;
        let var = self.expect_identifier()?;
        self.expect(&Token::Colon)?;
        let base_type = Box::new(self.parse_type_expr()?);
        self.expect(&Token::BitOr)?;
        let predicate = Predicate {
            expr: self.parse_expression()?,
        };
        self.expect(&Token::RightBrace)?;
        
        Ok(TypeExpr::Refinement {
            var,
            base_type,
            predicate,
        })
    }
    
    fn parse_effect_type(&mut self) -> ParseResult<TypeExpr> {
        self.expect(&Token::Less)?;
        let effect = self.parse_effect_monad()?;
        self.expect(&Token::Greater)?;
        let inner = Box::new(self.parse_type_expr()?);
        
        Ok(TypeExpr::Effect(effect, inner))
    }
    
    fn parse_linear_type(&mut self) -> ParseResult<TypeExpr> {
        let ownership = match self.advance() {
            Some(Token::Owned) => Ownership::Owned,
            Some(Token::Borrowed) => Ownership::Borrowed,
            Some(Token::Released) => Ownership::Released,
            _ => return Err(self.error("Expected ownership modifier")),
        };
        
        let inner = Box::new(self.parse_type_expr()?);
        Ok(TypeExpr::Linear(ownership, inner))
    }
    
    fn parse_tuple_or_function_type(&mut self) -> ParseResult<TypeExpr> {
        self.expect(&Token::LeftParen)?;
        let mut types = Vec::new();
        
        if !matches!(self.peek(), Some(Token::RightParen)) {
            loop {
                types.push(self.parse_type_expr()?);
                if !matches!(self.peek(), Some(Token::Comma)) {
                    break;
                }
                self.advance();
            }
        }
        
        self.expect(&Token::RightParen)?;
        
        if matches!(self.peek(), Some(Token::Arrow)) {
            self.advance();
            let return_type = Box::new(self.parse_type_expr()?);
            Ok(TypeExpr::Function(types, return_type))
        } else {
            Ok(TypeExpr::Tuple(types))
        }
    }
    
    fn parse_base_or_named_type(&mut self) -> ParseResult<TypeExpr> {
        let base = match self.peek() {
            Some(Token::Qubit) => {
                self.advance();
                TypeExpr::Base(BaseType::Qubit)
            }
            Some(Token::Bit) => {
                self.advance();
                TypeExpr::Base(BaseType::Bit)
            }
            Some(Token::Int) => {
                self.advance();
                TypeExpr::Base(BaseType::Int)
            }
            Some(Token::UInt) => {
                self.advance();
                TypeExpr::Base(BaseType::UInt)
            }
            Some(Token::Float) => {
                self.advance();
                TypeExpr::Base(BaseType::Float)
            }
            Some(Token::Angle) => {
                self.advance();
                TypeExpr::Base(BaseType::Angle)
            }
            Some(Token::Duration) => {
                self.advance();
                TypeExpr::Base(BaseType::Duration)
            }
            Some(Token::Bool) => {
                self.advance();
                TypeExpr::Base(BaseType::Bool)
            }
            Some(Token::Complex) => {
                self.advance();
                TypeExpr::Base(BaseType::Complex)
            }
            Some(Token::Stretch) => {
                self.advance();
                TypeExpr::Base(BaseType::Stretch)
            }
            Some(Token::Identifier(_)) => {
                let name = self.expect_identifier()?;
                
                // Check for capability indexing: Backend<Capability>
                if matches!(self.peek(), Some(Token::Less)) {
                    self.advance();
                    let mut caps = vec![self.expect_identifier()?];
                    while matches!(self.peek(), Some(Token::Comma)) {
                        self.advance();
                        caps.push(self.expect_identifier()?);
                    }
                    self.expect(&Token::Greater)?;
                    TypeExpr::Capability(name, caps)
                } else {
                    TypeExpr::Named(name)
                }
            }
            _ => return Err(self.error("Expected type")),
        };
        
        // Check for array suffix
        if matches!(self.peek(), Some(Token::LeftBracket)) {
            self.advance();
            let size = if matches!(self.peek(), Some(Token::RightBracket)) {
                None
            } else {
                Some(self.parse_expression()?)
            };
            self.expect(&Token::RightBracket)?;
            Ok(TypeExpr::Array(Box::new(base), size))
        } else {
            Ok(base)
        }
    }
    
    fn parse_effect_monad(&mut self) -> ParseResult<EffectMonad> {
        match self.advance() {
            Some(Token::CircuitM) => Ok(EffectMonad::CircuitM),
            Some(Token::MeasureM) => Ok(EffectMonad::MeasureM),
            Some(Token::DynamicM) => Ok(EffectMonad::DynamicM),
            Some(Token::PulseM) => Ok(EffectMonad::PulseM),
            Some(Token::BackendM) => Ok(EffectMonad::BackendM),
            Some(Token::ProofM) => Ok(EffectMonad::ProofM),
            Some(Token::ReceiptM) => Ok(EffectMonad::ReceiptM),
            _ => Err(self.error("Expected effect monad")),
        }
    }
    
    fn parse_capability_decl(&mut self) -> ParseResult<CapabilityDecl> {
        self.expect(&Token::Capability)?;
        let name = self.expect_identifier()?;
        self.expect(&Token::LeftBrace)?;
        
        let mut fields = Vec::new();
        while !matches!(self.peek(), Some(Token::RightBrace)) {
            let field_name = self.expect_identifier()?;
            self.expect(&Token::Colon)?;
            let type_expr = self.parse_type_expr()?;
            self.expect(&Token::Comma)?;
            
            fields.push(CapabilityField {
                name: field_name,
                type_expr,
            });
        }
        
        self.expect(&Token::RightBrace)?;
        
        Ok(CapabilityDecl { name, fields })
    }
    
    fn parse_predicate_decl(&mut self) -> ParseResult<PredicateDecl> {
        self.expect(&Token::Predicate)?;
        let name = self.expect_identifier()?;
        self.expect(&Token::LeftParen)?;
        let params = self.parse_parameter_list()?;
        self.expect(&Token::RightParen)?;
        self.expect(&Token::LeftBrace)?;
        let body = self.parse_expression()?;
        self.expect(&Token::RightBrace)?;
        
        Ok(PredicateDecl { name, params, body })
    }
    
    fn parse_var_decl(&mut self) -> ParseResult<VarDecl> {
        let type_expr = Some(self.parse_type_expr()?);
        let name = self.expect_identifier()?;
        
        let init = if matches!(self.peek(), Some(Token::Assign)) {
            self.advance();
            Some(self.parse_expression()?)
        } else {
            None
        };
        
        self.expect(&Token::Semicolon)?;
        
        Ok(VarDecl {
            name,
            type_expr,
            init,
            is_const: false,
        })
    }
    
    fn parse_const_decl(&mut self) -> ParseResult<VarDecl> {
        self.expect(&Token::Const)?;
        let name = self.expect_identifier()?;
        self.expect(&Token::Assign)?;
        let init = Some(self.parse_expression()?);
        self.expect(&Token::Semicolon)?;
        
        Ok(VarDecl {
            name,
            type_expr: None,
            init,
            is_const: true,
        })
    }
    
    fn parse_return(&mut self) -> ParseResult<Option<Expression>> {
        self.expect(&Token::Return)?;
        
        let expr = if matches!(self.peek(), Some(Token::Semicolon)) {
            None
        } else {
            Some(self.parse_expression()?)
        };
        
        self.expect(&Token::Semicolon)?;
        Ok(expr)
    }
    
    fn parse_if(&mut self) -> ParseResult<IfStatement> {
        self.expect(&Token::If)?;
        let condition = self.parse_expression()?;
        let then_branch = self.parse_block()?;
        
        let else_branch = if matches!(self.peek(), Some(Token::Else)) {
            self.advance();
            Some(self.parse_block()?)
        } else {
            None
        };
        
        Ok(IfStatement {
            condition,
            then_branch,
            else_branch,
        })
    }
    
    fn parse_for(&mut self) -> ParseResult<ForLoop> {
        self.expect(&Token::For)?;
        let var = self.expect_identifier()?;
        self.expect(&Token::In)?;
        
        let start = self.parse_expression()?;
        self.expect(&Token::DotDot)?;
        let end = self.parse_expression()?;
        
        let body = self.parse_block()?;
        
        Ok(ForLoop {
            var,
            range: Range { start, end },
            body,
        })
    }
    
    fn parse_while(&mut self) -> ParseResult<WhileLoop> {
        self.expect(&Token::While)?;
        let condition = self.parse_expression()?;
        let body = self.parse_block()?;
        
        Ok(WhileLoop { condition, body })
    }
    
    fn parse_block(&mut self) -> ParseResult<Vec<Statement>> {
        self.expect(&Token::LeftBrace)?;
        let mut statements = Vec::new();
        
        while !matches!(self.peek(), Some(Token::RightBrace)) {
            statements.push(self.parse_statement()?);
        }
        
        self.expect(&Token::RightBrace)?;
        Ok(statements)
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
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }
    
    fn parse_logical_and(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_comparison()?;
        
        while matches!(self.peek(), Some(Token::And)) {
            self.advance();
            let right = self.parse_comparison()?;
            left = Expression::Binary {
                op: BinaryOp::And,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }
    
    fn parse_comparison(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_additive()?;
        
        while let Some(op) = self.peek() {
            let binary_op = match op {
                Token::Equal => BinaryOp::Eq,
                Token::NotEqual => BinaryOp::Ne,
                Token::Less => BinaryOp::Lt,
                Token::LessEqual => BinaryOp::Le,
                Token::Greater => BinaryOp::Gt,
                Token::GreaterEqual => BinaryOp::Ge,
                _ => break,
            };
            
            self.advance();
            let right = self.parse_additive()?;
            left = Expression::Binary {
                op: binary_op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }
    
    fn parse_additive(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_multiplicative()?;
        
        while let Some(op) = self.peek() {
            let binary_op = match op {
                Token::Plus => BinaryOp::Add,
                Token::Minus => BinaryOp::Sub,
                _ => break,
            };
            
            self.advance();
            let right = self.parse_multiplicative()?;
            left = Expression::Binary {
                op: binary_op,
                left: Box::new(left),
                right: Box::new(right),
            };
        }
        
        Ok(left)
    }
    
    fn parse_multiplicative(&mut self) -> ParseResult<Expression> {
        let mut left = self.parse_unary()?;
        
        while let Some(op) = self.peek() {
            let binary_op = match op {
                Token::Star => BinaryOp::Mul,
                Token::Slash => BinaryOp::Div,
                Token::Percent => BinaryOp::Mod,
                _ => break,
            };
            
            self.advance();
            let right = self.parse_unary()?;
            left = Expression::Binary {
                op: binary_op,
                left: Box::new(left),
                right: Box::new(right),
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
                    operand: Box::new(self.parse_unary()?),
                })
            }
            Some(Token::Not) => {
                self.advance();
                Ok(Expression::Unary {
                    op: UnaryOp::Not,
                    operand: Box::new(self.parse_unary()?),
                })
            }
            Some(Token::BitNot) => {
                self.advance();
                Ok(Expression::Unary {
                    op: UnaryOp::BitNot,
                    operand: Box::new(self.parse_unary()?),
                })
            }
            _ => self.parse_postfix(),
        }
    }
    
    fn parse_postfix(&mut self) -> ParseResult<Expression> {
        let mut expr = self.parse_primary()?;
        
        loop {
            match self.peek() {
                Some(Token::LeftParen) => {
                    // Function call
                    if let Expression::Identifier(name) = expr {
                        self.advance();
                        let args = self.parse_expression_list()?;
                        self.expect(&Token::RightParen)?;
                        expr = Expression::Call { name, args };
                    } else {
                        break;
                    }
                }
                Some(Token::LeftBracket) => {
                    // Array indexing
                    self.advance();
                    let index = self.parse_expression()?;
                    self.expect(&Token::RightBracket)?;
                    expr = Expression::Index {
                        array: Box::new(expr),
                        index: Box::new(index),
                    };
                }
                Some(Token::Dot) => {
                    // Field access
                    self.advance();
                    let field = self.expect_identifier()?;
                    expr = Expression::Field {
                        object: Box::new(expr),
                        field,
                    };
                }
                _ => break,
            }
        }
        
        Ok(expr)
    }
    
    fn parse_primary(&mut self) -> ParseResult<Expression> {
        match self.advance() {
            Some(Token::IntegerLiteral(n)) => Ok(Expression::IntLiteral(*n)),
            Some(Token::FloatLiteral(x)) => Ok(Expression::FloatLiteral(*x)),
            Some(Token::StringLiteral(s)) => Ok(Expression::StringLiteral(s.clone())),
            Some(Token::BooleanLiteral) => {
                // Need to check which boolean it was
                Ok(Expression::BoolLiteral(true)) // Simplified
            }
            Some(Token::HardwareQubit(n)) => Ok(Expression::HardwareQubit(*n)),
            Some(Token::Identifier(name)) => Ok(Expression::Identifier(name.clone())),
            Some(Token::LeftParen) => {
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
                
                if exprs.len() == 1 {
                    Ok(exprs.into_iter().next().unwrap())
                } else {
                    Ok(Expression::Tuple(exprs))
                }
            }
            _ => Err(self.error("Expected expression")),
        }
    }
    
    fn parse_expression_list(&mut self) -> ParseResult<Vec<Expression>> {
        let mut exprs = Vec::new();
        
        if matches!(self.peek(), Some(Token::RightParen)) {
            return Ok(exprs);
        }
        
        loop {
            exprs.push(self.parse_expression()?);
            if !matches!(self.peek(), Some(Token::Comma)) {
                break;
            }
            self.advance();
        }
        
        Ok(exprs)
    }
    
    // Helper methods
    
    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.position)
    }
    
    fn advance(&mut self) -> Option<&Token> {
        let token = self.tokens.get(self.position);
        if token.is_some() {
            self.position += 1;
        }
        token
    }
    
    fn expect(&mut self, expected: &Token) -> ParseResult<()> {
        if self.peek() == Some(expected) {
            self.advance();
            Ok(())
        } else {
            Err(self.error(format!("Expected {:?}", expected)))
        }
    }
    
    fn expect_effect_monad(&mut self, expected: &EffectMonad) -> ParseResult<()> {
        let token = self.peek();
        let matches = match (expected, token) {
            (EffectMonad::CircuitM, Some(Token::CircuitM)) => true,
            (EffectMonad::MeasureM, Some(Token::MeasureM)) => true,
            (EffectMonad::DynamicM, Some(Token::DynamicM)) => true,
            (EffectMonad::PulseM, Some(Token::PulseM)) => true,
            (EffectMonad::BackendM, Some(Token::BackendM)) => true,
            (EffectMonad::ProofM, Some(Token::ProofM)) => true,
            (EffectMonad::ReceiptM, Some(Token::ReceiptM)) => true,
            _ => false,
        };
        
        if matches {
            self.advance();
            Ok(())
        } else {
            Err(self.error(format!("Expected {}", expected)))
        }
    }
    
    fn expect_identifier(&mut self) -> ParseResult<String> {
        match self.advance() {
            Some(Token::Identifier(name)) => Ok(name.clone()),
            _ => Err(self.error("Expected identifier")),
        }
    }
    
    fn error(&self, message: impl Into<String>) -> ParseError {
        ParseError::new(format!("Parse error at position {}: {}", self.position, message.into()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version() {
        let mut parser = Parser::new("METAQASM 4.0;");
        let version = parser.parse_version().unwrap();
        assert_eq!(version.major, 4);
        assert_eq!(version.minor, 0);
    }

    #[test]
    fn test_import() {
        let mut parser = Parser::new("import openqasm3.stdgates;");
        parser.position = 0; // Reset after version
        let import = parser.parse_import().unwrap();
        assert_eq!(import.path, vec!["openqasm3", "stdgates"]);
    }

    #[test]
    fn test_type_decl() {
        let source = "type ValidAngle = {theta: angle | theta >= 0};";
        let mut parser = Parser::new(source);
        let type_decl = parser.parse_type_decl().unwrap();
        assert_eq!(type_decl.name, "ValidAngle");
    }

    #[test]
    fn test_circuit_decl() {
        let source = r#"
circuit<CircuitM> bell_pair(q0: owned Qubit, q1: owned Qubit) -> (owned Qubit, owned Qubit)
    requires isLive(q0)
{
    return (q0, q1);
}
"#;
        let mut parser = Parser::new(source);
        let decl = parser.parse_effect_decl(EffectMonad::CircuitM).unwrap();
        assert_eq!(decl.name, "bell_pair");
        assert_eq!(decl.params.len(), 2);
        assert_eq!(decl.requires.len(), 1);
    }

    #[test]
    fn test_ownership_transfer() {
        let source = "q_prime <- h(q);";
        let mut parser = Parser::new(source);
        let stmt = parser.parse_statement().unwrap();
        assert!(matches!(stmt, Statement::OwnershipTransfer(_)));
    }

    #[test]
    fn test_refinement_type() {
        let source = "{x: int | x > 0}";
        let mut parser = Parser::new(source);
        let type_expr = parser.parse_type_expr().unwrap();
        assert!(matches!(type_expr, TypeExpr::Refinement { .. }));
    }

    #[test]
    fn test_effect_type() {
        let source = "<CircuitM> Qubit";
        let mut parser = Parser::new(source);
        let type_expr = parser.parse_type_expr().unwrap();
        assert!(matches!(type_expr, TypeExpr::Effect(EffectMonad::CircuitM, _)));
    }

    #[test]
    fn test_linear_type() {
        let source = "owned Qubit";
        let mut parser = Parser::new(source);
        let type_expr = parser.parse_type_expr().unwrap();
        assert!(matches!(type_expr, TypeExpr::Linear(Ownership::Owned, _)));
    }

    #[test]
    fn test_complete_program() {
        let source = r#"
METAQASM 4.0;

import openqasm3.stdgates;

type LiveQubit = {q: Qubit | isLive(q)};

circuit<CircuitM> bell_pair(
    q0: owned LiveQubit,
    q1: owned LiveQubit
) -> (owned LiveQubit, owned LiveQubit)
    requires isLive(q0)
    ensures isEntangled(q0, q1)
{
    q0_prime <- h(q0);
    return (q0_prime, q1);
}
"#;
        let mut parser = Parser::new(source);
        let program = parser.parse().unwrap();
        assert_eq!(program.version.major, 4);
        assert_eq!(program.imports.len(), 1);
        assert_eq!(program.statements.len(), 2);
    }
}

// Made with Bob
