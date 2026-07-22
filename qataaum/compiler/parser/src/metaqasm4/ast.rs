//! MetaQASM-4 Abstract Syntax Tree
//!
//! MetaQASM-4 is an ORIGINAL EXPERIMENTAL LANGUAGE designed by the QATAAUM project.
//! It is NOT OpenQASM 4 (which does not exist as a public standard).
//!
//! This AST represents MetaQASM-4 programs with:
//! - Typed effects (CircuitM, MeasureM, DynamicM, PulseM, BackendM, ProofM, ReceiptM)
//! - Linear ownership (owned, borrowed, released)
//! - Refinement types ({x: Type | predicate})
//! - Capability indexing
//! - Proof obligations

use std::fmt;

/// Complete MetaQASM-4 program
#[derive(Debug, Clone, PartialEq)]
pub struct Program {
    pub version: Version,
    pub imports: Vec<Import>,
    pub statements: Vec<Statement>,
}

/// Version declaration: METAQASM 4.0;
#[derive(Debug, Clone, PartialEq)]
pub struct Version {
    pub major: u32,
    pub minor: u32,
}

/// Import declaration: import openqasm3.stdgates;
#[derive(Debug, Clone, PartialEq)]
pub struct Import {
    pub path: Vec<String>,
}

/// Top-level statements
#[derive(Debug, Clone, PartialEq)]
pub enum Statement {
    /// Type alias: type ValidAngle = {θ: angle | 0 <= θ < 2*pi};
    TypeDecl(TypeDecl),
    
    /// Circuit declaration with CircuitM effect
    CircuitDecl(EffectDecl),
    
    /// Measurement declaration with MeasureM effect
    MeasurementDecl(EffectDecl),
    
    /// Dynamic circuit declaration with DynamicM effect
    DynamicDecl(EffectDecl),
    
    /// Pulse declaration with PulseM effect
    PulseDecl(EffectDecl),
    
    /// Backend declaration with BackendM effect
    BackendDecl(EffectDecl),
    
    /// Proof declaration with ProofM effect
    ProofDecl(EffectDecl),
    
    /// Receipt declaration with ReceiptM effect
    ReceiptDecl(EffectDecl),
    
    /// Capability declaration
    CapabilityDecl(CapabilityDecl),
    
    /// Predicate declaration
    PredicateDecl(PredicateDecl),
    
    /// Variable declaration
    VarDecl(VarDecl),
    
    /// Assignment with ownership transfer: q' <- h(q);
    OwnershipTransfer(OwnershipTransfer),
    
    /// Expression statement
    ExprStmt(Expression),
    
    /// Return statement
    Return(Option<Expression>),
    
    /// If statement
    If(IfStatement),
    
    /// For loop
    For(ForLoop),
    
    /// While loop
    While(WhileLoop),
    
    /// Break
    Break,
    
    /// Continue
    Continue,
    
    /// Block
    Block(Vec<Statement>),
}

/// Type declaration
#[derive(Debug, Clone, PartialEq)]
pub struct TypeDecl {
    pub name: String,
    pub type_expr: TypeExpr,
}

/// Effect-typed function declaration
#[derive(Debug, Clone, PartialEq)]
pub struct EffectDecl {
    pub effect: EffectMonad,
    pub name: String,
    pub params: Vec<Parameter>,
    pub return_type: Option<TypeExpr>,
    pub requires: Vec<Predicate>,
    pub ensures: Vec<Predicate>,
    pub invariants: Vec<Predicate>,
    pub body: Vec<Statement>,
}

/// Effect monads
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum EffectMonad {
    CircuitM,   // Pure circuit construction
    MeasureM,   // Measurement effects
    DynamicM,   // Dynamic circuits
    PulseM,     // Pulse-level operations
    BackendM,   // Backend execution
    ProofM,     // Proof obligations
    ReceiptM,   // Execution receipts
}

/// Function parameter with ownership annotation
#[derive(Debug, Clone, PartialEq)]
pub struct Parameter {
    pub name: String,
    pub ownership: Option<Ownership>,
    pub type_expr: TypeExpr,
}

/// Ownership modifiers
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Ownership {
    Owned,
    Borrowed,
    Released,
}

/// Type expressions
#[derive(Debug, Clone, PartialEq)]
pub enum TypeExpr {
    /// Base types: qubit, bit, int, float, etc.
    Base(BaseType),
    
    /// Array type: Qubit[n]
    Array(Box<TypeExpr>, Option<Expression>),
    
    /// Effect type: <CircuitM> Type
    Effect(EffectMonad, Box<TypeExpr>),
    
    /// Refinement type: {x: Type | predicate}
    Refinement {
        var: String,
        base_type: Box<TypeExpr>,
        predicate: Predicate,
    },
    
    /// Linear type: owned Qubit
    Linear(Ownership, Box<TypeExpr>),
    
    /// Capability-indexed type: Backend<DynamicCircuits>
    Capability(String, Vec<String>),
    
    /// Tuple type: (Type1, Type2)
    Tuple(Vec<TypeExpr>),
    
    /// Function type: fn(Type1) -> Type2
    Function(Vec<TypeExpr>, Box<TypeExpr>),
    
    /// Named type reference
    Named(String),
}

/// Base types
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum BaseType {
    Qubit,
    Bit,
    Int,
    UInt,
    Float,
    Angle,
    Duration,
    Bool,
    Complex,
    Stretch,
}

/// Predicate (used in refinement types and contracts)
#[derive(Debug, Clone, PartialEq)]
pub struct Predicate {
    pub expr: Expression,
}

/// Capability declaration
#[derive(Debug, Clone, PartialEq)]
pub struct CapabilityDecl {
    pub name: String,
    pub fields: Vec<CapabilityField>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CapabilityField {
    pub name: String,
    pub type_expr: TypeExpr,
}

/// Predicate declaration
#[derive(Debug, Clone, PartialEq)]
pub struct PredicateDecl {
    pub name: String,
    pub params: Vec<Parameter>,
    pub body: Expression,
}

/// Variable declaration
#[derive(Debug, Clone, PartialEq)]
pub struct VarDecl {
    pub name: String,
    pub type_expr: Option<TypeExpr>,
    pub init: Option<Expression>,
    pub is_const: bool,
}

/// Ownership transfer: q' <- h(q);
#[derive(Debug, Clone, PartialEq)]
pub struct OwnershipTransfer {
    pub target: String,
    pub source: Expression,
}

/// If statement
#[derive(Debug, Clone, PartialEq)]
pub struct IfStatement {
    pub condition: Expression,
    pub then_branch: Vec<Statement>,
    pub else_branch: Option<Vec<Statement>>,
}

/// For loop
#[derive(Debug, Clone, PartialEq)]
pub struct ForLoop {
    pub var: String,
    pub range: Range,
    pub body: Vec<Statement>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Range {
    pub start: Expression,
    pub end: Expression,
}

/// While loop
#[derive(Debug, Clone, PartialEq)]
pub struct WhileLoop {
    pub condition: Expression,
    pub body: Vec<Statement>,
}

/// Expressions
#[derive(Debug, Clone, PartialEq)]
pub enum Expression {
    /// Integer literal
    IntLiteral(i64),
    
    /// Float literal
    FloatLiteral(f64),
    
    /// String literal
    StringLiteral(String),
    
    /// Boolean literal
    BoolLiteral(bool),
    
    /// Hardware qubit: $0
    HardwareQubit(usize),
    
    /// Identifier
    Identifier(String),
    
    /// Binary operation
    Binary {
        op: BinaryOp,
        left: Box<Expression>,
        right: Box<Expression>,
    },
    
    /// Unary operation
    Unary {
        op: UnaryOp,
        operand: Box<Expression>,
    },
    
    /// Function call
    Call {
        name: String,
        args: Vec<Expression>,
    },
    
    /// Array indexing
    Index {
        array: Box<Expression>,
        index: Box<Expression>,
    },
    
    /// Field access: obj.field
    Field {
        object: Box<Expression>,
        field: String,
    },
    
    /// Tuple: (expr1, expr2)
    Tuple(Vec<Expression>),
    
    /// Range: 0..n-1
    Range {
        start: Box<Expression>,
        end: Box<Expression>,
    },
}

/// Binary operators
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BinaryOp {
    // Arithmetic
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Pow,
    
    // Comparison
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    
    // Logical
    And,
    Or,
    
    // Bitwise
    BitAnd,
    BitOr,
    BitXor,
    LeftShift,
    RightShift,
}

/// Unary operators
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum UnaryOp {
    Neg,
    Not,
    BitNot,
}

impl fmt::Display for EffectMonad {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            EffectMonad::CircuitM => write!(f, "CircuitM"),
            EffectMonad::MeasureM => write!(f, "MeasureM"),
            EffectMonad::DynamicM => write!(f, "DynamicM"),
            EffectMonad::PulseM => write!(f, "PulseM"),
            EffectMonad::BackendM => write!(f, "BackendM"),
            EffectMonad::ProofM => write!(f, "ProofM"),
            EffectMonad::ReceiptM => write!(f, "ReceiptM"),
        }
    }
}

impl fmt::Display for Ownership {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Ownership::Owned => write!(f, "owned"),
            Ownership::Borrowed => write!(f, "borrowed"),
            Ownership::Released => write!(f, "released"),
        }
    }
}

impl fmt::Display for BaseType {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            BaseType::Qubit => write!(f, "qubit"),
            BaseType::Bit => write!(f, "bit"),
            BaseType::Int => write!(f, "int"),
            BaseType::UInt => write!(f, "uint"),
            BaseType::Float => write!(f, "float"),
            BaseType::Angle => write!(f, "angle"),
            BaseType::Duration => write!(f, "duration"),
            BaseType::Bool => write!(f, "bool"),
            BaseType::Complex => write!(f, "complex"),
            BaseType::Stretch => write!(f, "stretch"),
        }
    }
}

impl fmt::Display for BinaryOp {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            BinaryOp::Add => write!(f, "+"),
            BinaryOp::Sub => write!(f, "-"),
            BinaryOp::Mul => write!(f, "*"),
            BinaryOp::Div => write!(f, "/"),
            BinaryOp::Mod => write!(f, "%"),
            BinaryOp::Pow => write!(f, "**"),
            BinaryOp::Eq => write!(f, "=="),
            BinaryOp::Ne => write!(f, "!="),
            BinaryOp::Lt => write!(f, "<"),
            BinaryOp::Le => write!(f, "<="),
            BinaryOp::Gt => write!(f, ">"),
            BinaryOp::Ge => write!(f, ">="),
            BinaryOp::And => write!(f, "&&"),
            BinaryOp::Or => write!(f, "||"),
            BinaryOp::BitAnd => write!(f, "&"),
            BinaryOp::BitOr => write!(f, "|"),
            BinaryOp::BitXor => write!(f, "^"),
            BinaryOp::LeftShift => write!(f, "<<"),
            BinaryOp::RightShift => write!(f, ">>"),
        }
    }
}

impl fmt::Display for UnaryOp {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            UnaryOp::Neg => write!(f, "-"),
            UnaryOp::Not => write!(f, "!"),
            UnaryOp::BitNot => write!(f, "~"),
        }
    }
}

// Made with Bob
