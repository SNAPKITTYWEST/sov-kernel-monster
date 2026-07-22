//! OpenQASM 3 Abstract Syntax Tree
//!
//! This module defines the AST types for OpenQASM 3.x based on the public
//! specification from openqasm.com. This is a clean-room implementation.

use std::fmt;

/// Source location information
#[derive(Debug, Clone, PartialEq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    pub fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }
}

/// OpenQASM 3 program
#[derive(Debug, Clone, PartialEq)]
pub struct Program {
    pub version: Version,
    pub statements: Vec<Statement>,
    pub span: Span,
}

/// Version declaration
#[derive(Debug, Clone, PartialEq)]
pub struct Version {
    pub major: u32,
    pub minor: u32,
    pub span: Span,
}

/// Top-level statement
#[derive(Debug, Clone, PartialEq)]
pub enum Statement {
    /// Include statement: include "filename";
    Include(Include),
    
    /// Quantum register declaration: qubit[n] name;
    QubitDeclaration(QubitDeclaration),
    
    /// Classical register declaration: bit[n] name;
    ClassicalDeclaration(ClassicalDeclaration),
    
    /// Constant declaration: const type name = value;
    ConstDeclaration(ConstDeclaration),
    
    /// Input declaration: input type name;
    InputDeclaration(InputDeclaration),
    
    /// Output declaration: output type name;
    OutputDeclaration(OutputDeclaration),
    
    /// Gate definition
    GateDefinition(GateDefinition),
    
    /// Defcal definition
    DefCalDefinition(DefCalDefinition),
    
    /// Function definition
    FunctionDefinition(FunctionDefinition),
    
    /// Extern declaration
    ExternDeclaration(ExternDeclaration),
    
    /// Quantum operation (gate application, measurement, etc.)
    QuantumOperation(QuantumOperation),
    
    /// Classical assignment
    Assignment(Assignment),
    
    /// If statement
    If(IfStatement),
    
    /// For loop
    For(ForLoop),
    
    /// While loop
    While(WhileLoop),
    
    /// Break statement
    Break(Span),
    
    /// Continue statement
    Continue(Span),
    
    /// Return statement
    Return(ReturnStatement),
    
    /// Barrier
    Barrier(Barrier),
    
    /// Delay
    Delay(Delay),
    
    /// TimingBox (timing block)
    TimingBox(TimingBox),
    
    /// Pragma
    Pragma(Pragma),
    
    /// Expression statement
    Expression(Expression),
}

/// Include statement
#[derive(Debug, Clone, PartialEq)]
pub struct Include {
    pub filename: String,
    pub span: Span,
}

/// Qubit declaration
#[derive(Debug, Clone, PartialEq)]
pub struct QubitDeclaration {
    pub name: String,
    pub size: Option<Expression>,
    pub span: Span,
}

/// Classical declaration
#[derive(Debug, Clone, PartialEq)]
pub struct ClassicalDeclaration {
    pub typ: ClassicalType,
    pub name: String,
    pub size: Option<Expression>,
    pub initializer: Option<Expression>,
    pub span: Span,
}

/// Constant declaration
#[derive(Debug, Clone, PartialEq)]
pub struct ConstDeclaration {
    pub typ: ClassicalType,
    pub name: String,
    pub value: Expression,
    pub span: Span,
}

/// Input declaration
#[derive(Debug, Clone, PartialEq)]
pub struct InputDeclaration {
    pub typ: ClassicalType,
    pub name: String,
    pub span: Span,
}

/// Output declaration
#[derive(Debug, Clone, PartialEq)]
pub struct OutputDeclaration {
    pub typ: ClassicalType,
    pub name: String,
    pub span: Span,
}

/// Classical type
#[derive(Debug, Clone, PartialEq)]
pub enum ClassicalType {
    Bit,
    Int(Option<u32>),      // int[size]
    UInt(Option<u32>),     // uint[size]
    Float(Option<u32>),    // float[size]
    Angle(Option<u32>),    // angle[size]
    Bool,
    Duration,
    Stretch,
    Complex(Option<Box<ClassicalType>>),
}

/// Gate definition
#[derive(Debug, Clone, PartialEq)]
pub struct GateDefinition {
    pub name: String,
    pub parameters: Vec<String>,
    pub qubits: Vec<String>,
    pub body: Vec<GateOperation>,
    pub span: Span,
}

/// Gate operation (inside gate definition)
#[derive(Debug, Clone, PartialEq)]
pub enum GateOperation {
    /// Gate application
    GateCall {
        name: String,
        modifiers: Vec<GateModifier>,
        arguments: Vec<Expression>,
        qubits: Vec<String>,
        span: Span,
    },
    
    /// Barrier
    Barrier {
        qubits: Vec<String>,
        span: Span,
    },
}

/// Gate modifier
#[derive(Debug, Clone, PartialEq)]
pub enum GateModifier {
    Inv,
    Pow(Expression),
    Ctrl(Option<Expression>),
    NegCtrl(Option<Expression>),
}

/// Defcal definition
#[derive(Debug, Clone, PartialEq)]
pub struct DefCalDefinition {
    pub name: String,
    pub parameters: Vec<String>,
    pub qubits: Vec<QubitTarget>,
    pub return_type: Option<ClassicalType>,
    pub body: Vec<Statement>,
    pub span: Span,
}

/// Function definition
#[derive(Debug, Clone, PartialEq)]
pub struct FunctionDefinition {
    pub name: String,
    pub parameters: Vec<Parameter>,
    pub return_type: Option<ClassicalType>,
    pub body: Vec<Statement>,
    pub span: Span,
}

/// Function parameter
#[derive(Debug, Clone, PartialEq)]
pub struct Parameter {
    pub typ: ClassicalType,
    pub name: String,
    pub span: Span,
}

/// Extern declaration
#[derive(Debug, Clone, PartialEq)]
pub struct ExternDeclaration {
    pub name: String,
    pub parameters: Vec<ClassicalType>,
    pub return_type: Option<ClassicalType>,
    pub span: Span,
}

/// Quantum operation
#[derive(Debug, Clone, PartialEq)]
pub enum QuantumOperation {
    /// Gate application
    GateCall {
        name: String,
        modifiers: Vec<GateModifier>,
        arguments: Vec<Expression>,
        qubits: Vec<QubitTarget>,
        span: Span,
    },
    
    /// Measurement
    Measure {
        qubit: QubitTarget,
        target: Option<ClassicalTarget>,
        span: Span,
    },
    
    /// Reset
    Reset {
        qubit: QubitTarget,
        span: Span,
    },
}

/// Qubit target
#[derive(Debug, Clone, PartialEq)]
pub enum QubitTarget {
    /// Named qubit: q
    Identifier(String),
    
    /// Indexed qubit: q[0]
    Indexed {
        name: String,
        index: Expression,
    },
    
    /// Hardware qubit: $0
    Hardware(u32),
}

/// Classical target
#[derive(Debug, Clone, PartialEq)]
pub enum ClassicalTarget {
    /// Named classical register: c
    Identifier(String),
    
    /// Indexed classical register: c[0]
    Indexed {
        name: String,
        index: Expression,
    },
}

/// Assignment
#[derive(Debug, Clone, PartialEq)]
pub struct Assignment {
    pub target: ClassicalTarget,
    pub op: AssignmentOp,
    pub value: Expression,
    pub span: Span,
}

/// Assignment operator
#[derive(Debug, Clone, PartialEq)]
pub enum AssignmentOp {
    Assign,      // =
    PlusAssign,  // +=
    MinusAssign, // -=
    StarAssign,  // *=
    SlashAssign, // /=
    PercentAssign, // %=
    AndAssign,   // &=
    OrAssign,    // |=
    XorAssign,   // ^=
    LeftShiftAssign,  // <<=
    RightShiftAssign, // >>=
}

/// If statement
#[derive(Debug, Clone, PartialEq)]
pub struct IfStatement {
    pub condition: Expression,
    pub then_body: Vec<Statement>,
    pub else_body: Option<Vec<Statement>>,
    pub span: Span,
}

/// For loop
#[derive(Debug, Clone, PartialEq)]
pub struct ForLoop {
    pub variable: String,
    pub range: Range,
    pub body: Vec<Statement>,
    pub span: Span,
}

/// Range expression
#[derive(Debug, Clone, PartialEq)]
pub struct Range {
    pub start: Expression,
    pub end: Expression,
    pub step: Option<Expression>,
    pub span: Span,
}

/// While loop
#[derive(Debug, Clone, PartialEq)]
pub struct WhileLoop {
    pub condition: Expression,
    pub body: Vec<Statement>,
    pub span: Span,
}

/// Return statement
#[derive(Debug, Clone, PartialEq)]
pub struct ReturnStatement {
    pub value: Option<Expression>,
    pub span: Span,
}

/// Barrier
#[derive(Debug, Clone, PartialEq)]
pub struct Barrier {
    pub qubits: Vec<QubitTarget>,
    pub span: Span,
}

/// Delay
#[derive(Debug, Clone, PartialEq)]
pub struct Delay {
    pub duration: Expression,
    pub qubits: Vec<QubitTarget>,
    pub span: Span,
}

/// TimingBox (timing block)
#[derive(Debug, Clone, PartialEq)]
pub struct TimingBox {
    pub duration: Option<Expression>,
    pub body: Vec<Statement>,
    pub span: Span,
}

/// Pragma
#[derive(Debug, Clone, PartialEq)]
pub struct Pragma {
    pub content: String,
    pub span: Span,
}

/// Expression
#[derive(Debug, Clone, PartialEq)]
pub enum Expression {
    /// Integer literal
    IntegerLiteral(i64),
    
    /// Float literal
    FloatLiteral(f64),
    
    /// Boolean literal
    BooleanLiteral(bool),
    
    /// String literal
    StringLiteral(String),
    
    /// Duration literal (value, unit)
    DurationLiteral(f64, DurationUnit),
    
    /// Identifier
    Identifier(String),
    
    /// Indexed access: name[index]
    Index {
        name: String,
        index: Box<Expression>,
    },
    
    /// Function call
    FunctionCall {
        name: String,
        arguments: Vec<Expression>,
    },
    
    /// Unary operation
    Unary {
        op: UnaryOp,
        operand: Box<Expression>,
    },
    
    /// Binary operation
    Binary {
        op: BinaryOp,
        left: Box<Expression>,
        right: Box<Expression>,
    },
    
    /// Cast
    Cast {
        typ: ClassicalType,
        value: Box<Expression>,
    },
    
    /// Durationof
    DurationOf {
        body: Vec<Statement>,
    },
}

/// Duration unit
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DurationUnit {
    Nanosecond,  // ns
    Microsecond, // us
    Millisecond, // ms
    Second,      // s
    DT,          // dt (sample time)
}

impl fmt::Display for DurationUnit {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            DurationUnit::Nanosecond => write!(f, "ns"),
            DurationUnit::Microsecond => write!(f, "us"),
            DurationUnit::Millisecond => write!(f, "ms"),
            DurationUnit::Second => write!(f, "s"),
            DurationUnit::DT => write!(f, "dt"),
        }
    }
}

/// Unary operator
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnaryOp {
    Neg,   // -
    Not,   // !
    BitNot, // ~
}

/// Binary operator
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinaryOp {
    // Arithmetic
    Add,      // +
    Sub,      // -
    Mul,      // *
    Div,      // /
    Mod,      // %
    Power,    // **
    
    // Bitwise
    BitAnd,   // &
    BitOr,    // |
    BitXor,   // ^
    LeftShift,  // <<
    RightShift, // >>
    
    // Comparison
    Equal,    // ==
    NotEqual, // !=
    Less,     // <
    LessEqual, // <=
    Greater,  // >
    GreaterEqual, // >=
    
    // Logical
    And,      // &&
    Or,       // ||
}

// Made with Bob