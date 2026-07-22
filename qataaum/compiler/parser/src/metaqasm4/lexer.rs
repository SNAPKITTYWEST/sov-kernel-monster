//! MetaQASM-4 Lexer
//!
//! MetaQASM-4 is an ORIGINAL EXPERIMENTAL LANGUAGE designed by the QATAAUM project.
//! It is NOT OpenQASM 4 (which does not exist as a public standard).
//!
//! This lexer tokenizes MetaQASM-4 source code, which extends OpenQASM 3 with:
//! - Typed effects (CircuitM, MeasureM, DynamicM, PulseM, BackendM, ProofM, ReceiptM)
//! - Linear ownership (owned, borrowed, released)
//! - Refinement types ({x: Type | predicate})
//! - Capability indexing (backend<Capability>)
//! - Proof obligations (requires, ensures, invariant)

use logos::Logos;
use std::fmt;

#[derive(Logos, Debug, Clone, PartialEq)]
#[logos(skip r"[ \t\r\n\f]+")]
#[logos(skip r"//[^\n]*")]
#[logos(skip r"/\*([^*]|\*[^/])*\*/")]
pub enum Token {
    // Version keyword
    #[token("METAQASM")]
    MetaQASM,

    // OpenQASM 3 keywords (inherited)
    #[token("include")]
    Include,
    
    #[token("def")]
    Def,
    
    #[token("gate")]
    Gate,
    
    #[token("opaque")]
    Opaque,
    
    #[token("extern")]
    Extern,
    
    #[token("box")]
    Box,
    
    #[token("let")]
    Let,
    
    #[token("const")]
    Const,

    // Type keywords
    #[token("qubit")]
    Qubit,
    
    #[token("bit")]
    Bit,
    
    #[token("int")]
    Int,
    
    #[token("uint")]
    UInt,
    
    #[token("float")]
    Float,
    
    #[token("angle")]
    Angle,
    
    #[token("duration")]
    Duration,
    
    #[token("bool")]
    Bool,
    
    #[token("complex")]
    Complex,
    
    #[token("stretch")]
    Stretch,

    // Control flow keywords
    #[token("if")]
    If,
    
    #[token("else")]
    Else,
    
    #[token("for")]
    For,
    
    #[token("in")]
    In,
    
    #[token("while")]
    While,
    
    #[token("switch")]
    Switch,
    
    #[token("case")]
    Case,
    
    #[token("default")]
    Default,
    
    #[token("break")]
    Break,
    
    #[token("continue")]
    Continue,
    
    #[token("return")]
    Return,

    // Quantum operation keywords
    #[token("measure")]
    Measure,
    
    #[token("reset")]
    Reset,
    
    #[token("barrier")]
    Barrier,
    
    #[token("delay")]
    Delay,

    // Calibration keywords
    #[token("cal")]
    Cal,
    
    #[token("defcal")]
    DefCal,
    
    #[token("defcalgrammar")]
    DefCalGrammar,

    // MetaQASM-4 NEW keywords - Effect Monad Declarations
    #[token("circuit")]
    Circuit,
    
    #[token("measurement")]
    Measurement,
    
    #[token("dynamic")]
    Dynamic,
    
    #[token("pulse")]
    Pulse,
    
    #[token("backend")]
    Backend,
    
    #[token("proof")]
    Proof,
    
    #[token("receipt")]
    Receipt,

    // MetaQASM-4 NEW keywords - Proof and Refinement
    #[token("requires")]
    Requires,
    
    #[token("ensures")]
    Ensures,
    
    #[token("where")]
    Where,
    
    #[token("forall")]
    Forall,
    
    #[token("exists")]
    Exists,
    
    #[token("refine")]
    Refine,
    
    #[token("capability")]
    Capability,
    
    #[token("invariant")]
    Invariant,
    
    #[token("predicate")]
    Predicate,

    // MetaQASM-4 NEW keywords - Linear Ownership
    #[token("linear")]
    Linear,
    
    #[token("owned")]
    Owned,
    
    #[token("borrowed")]
    Borrowed,
    
    #[token("released")]
    Released,

    // MetaQASM-4 NEW keywords - Effect System
    #[token("effect")]
    Effect,
    
    #[token("monad")]
    Monad,
    
    #[token("witness")]
    Witness,

    // MetaQASM-4 NEW keywords - Type System
    #[token("type")]
    Type,
    
    #[token("import")]
    Import,

    // Effect Monad Names
    #[token("CircuitM")]
    CircuitM,
    
    #[token("MeasureM")]
    MeasureM,
    
    #[token("DynamicM")]
    DynamicM,
    
    #[token("PulseM")]
    PulseM,
    
    #[token("BackendM")]
    BackendM,
    
    #[token("ProofM")]
    ProofM,
    
    #[token("ReceiptM")]
    ReceiptM,

    // Gate modifiers
    #[token("inv")]
    Inv,
    
    #[token("pow")]
    Pow,
    
    #[token("ctrl")]
    Ctrl,
    
    #[token("negctrl")]
    NegCtrl,

    // Input/Output
    #[token("input")]
    Input,
    
    #[token("output")]
    Output,

    // Operators and punctuation
    #[token("+")]
    Plus,
    
    #[token("-")]
    Minus,
    
    #[token("*")]
    Star,
    
    #[token("/")]
    Slash,
    
    #[token("%")]
    Percent,
    
    #[token("**")]
    Power,

    #[token("==")]
    Equal,
    
    #[token("!=")]
    NotEqual,
    
    #[token("<")]
    Less,
    
    #[token("<=")]
    LessEqual,
    
    #[token(">")]
    Greater,
    
    #[token(">=")]
    GreaterEqual,

    #[token("&&")]
    And,
    
    #[token("||")]
    Or,
    
    #[token("!")]
    Not,

    #[token("&")]
    BitAnd,
    
    #[token("|")]
    BitOr,
    
    #[token("^")]
    BitXor,
    
    #[token("~")]
    BitNot,
    
    #[token("<<")]
    LeftShift,
    
    #[token(">>")]
    RightShift,

    #[token("=")]
    Assign,
    
    #[token("+=")]
    PlusAssign,
    
    #[token("-=")]
    MinusAssign,
    
    #[token("*=")]
    StarAssign,
    
    #[token("/=")]
    SlashAssign,

    // MetaQASM-4 type operators
    #[token(":")]
    Colon,
    
    #[token("::")]
    DoubleColon,
    
    #[token("->")]
    Arrow,
    
    #[token("=>")]
    FatArrow,
    
    #[token("<-")]
    LeftArrow,
    
    #[token("@")]
    At,
    
    #[token("#")]
    Hash,

    // Delimiters
    #[token("(")]
    LeftParen,
    
    #[token(")")]
    RightParen,
    
    #[token("[")]
    LeftBracket,
    
    #[token("]")]
    RightBracket,
    
    #[token("{")]
    LeftBrace,
    
    #[token("}")]
    RightBrace,

    #[token(";")]
    Semicolon,
    
    #[token(",")]
    Comma,
    
    #[token(".")]
    Dot,
    
    #[token("..")]
    DotDot,

    // Literals
    #[regex(r"[0-9]+", |lex| lex.slice().parse().ok())]
    IntegerLiteral(i64),

    #[regex(r"[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?", |lex| lex.slice().parse().ok())]
    #[regex(r"[0-9]+[eE][+-]?[0-9]+", |lex| lex.slice().parse().ok())]
    FloatLiteral(f64),

    #[regex(r#""([^"\\]|\\.)*""#, |lex| {
        let s = lex.slice();
        s[1..s.len()-1].to_string()
    })]
    StringLiteral(String),

    #[token("true")]
    #[token("false")]
    BooleanLiteral,

    // Hardware qubit: $0, $1, etc.
    #[regex(r"\$[0-9]+", |lex| {
        lex.slice()[1..].parse().ok()
    })]
    HardwareQubit(usize),

    // Identifiers
    #[regex(r"[a-zA-Z_][a-zA-Z0-9_]*", |lex| lex.slice().to_string())]
    Identifier(String),
}

impl fmt::Display for Token {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Token::MetaQASM => write!(f, "METAQASM"),
            Token::Include => write!(f, "include"),
            Token::Def => write!(f, "def"),
            Token::Gate => write!(f, "gate"),
            Token::Opaque => write!(f, "opaque"),
            Token::Extern => write!(f, "extern"),
            Token::Box => write!(f, "box"),
            Token::Let => write!(f, "let"),
            Token::Const => write!(f, "const"),
            Token::Qubit => write!(f, "qubit"),
            Token::Bit => write!(f, "bit"),
            Token::Int => write!(f, "int"),
            Token::UInt => write!(f, "uint"),
            Token::Float => write!(f, "float"),
            Token::Angle => write!(f, "angle"),
            Token::Duration => write!(f, "duration"),
            Token::Bool => write!(f, "bool"),
            Token::Complex => write!(f, "complex"),
            Token::Stretch => write!(f, "stretch"),
            Token::If => write!(f, "if"),
            Token::Else => write!(f, "else"),
            Token::For => write!(f, "for"),
            Token::In => write!(f, "in"),
            Token::While => write!(f, "while"),
            Token::Switch => write!(f, "switch"),
            Token::Case => write!(f, "case"),
            Token::Default => write!(f, "default"),
            Token::Break => write!(f, "break"),
            Token::Continue => write!(f, "continue"),
            Token::Return => write!(f, "return"),
            Token::Measure => write!(f, "measure"),
            Token::Reset => write!(f, "reset"),
            Token::Barrier => write!(f, "barrier"),
            Token::Delay => write!(f, "delay"),
            Token::Cal => write!(f, "cal"),
            Token::DefCal => write!(f, "defcal"),
            Token::DefCalGrammar => write!(f, "defcalgrammar"),
            Token::Circuit => write!(f, "circuit"),
            Token::Measurement => write!(f, "measurement"),
            Token::Dynamic => write!(f, "dynamic"),
            Token::Pulse => write!(f, "pulse"),
            Token::Backend => write!(f, "backend"),
            Token::Proof => write!(f, "proof"),
            Token::Receipt => write!(f, "receipt"),
            Token::Requires => write!(f, "requires"),
            Token::Ensures => write!(f, "ensures"),
            Token::Where => write!(f, "where"),
            Token::Forall => write!(f, "forall"),
            Token::Exists => write!(f, "exists"),
            Token::Refine => write!(f, "refine"),
            Token::Capability => write!(f, "capability"),
            Token::Invariant => write!(f, "invariant"),
            Token::Predicate => write!(f, "predicate"),
            Token::Linear => write!(f, "linear"),
            Token::Owned => write!(f, "owned"),
            Token::Borrowed => write!(f, "borrowed"),
            Token::Released => write!(f, "released"),
            Token::Effect => write!(f, "effect"),
            Token::Monad => write!(f, "monad"),
            Token::Witness => write!(f, "witness"),
            Token::Type => write!(f, "type"),
            Token::Import => write!(f, "import"),
            Token::CircuitM => write!(f, "CircuitM"),
            Token::MeasureM => write!(f, "MeasureM"),
            Token::DynamicM => write!(f, "DynamicM"),
            Token::PulseM => write!(f, "PulseM"),
            Token::BackendM => write!(f, "BackendM"),
            Token::ProofM => write!(f, "ProofM"),
            Token::ReceiptM => write!(f, "ReceiptM"),
            Token::Inv => write!(f, "inv"),
            Token::Pow => write!(f, "pow"),
            Token::Ctrl => write!(f, "ctrl"),
            Token::NegCtrl => write!(f, "negctrl"),
            Token::Input => write!(f, "input"),
            Token::Output => write!(f, "output"),
            Token::Plus => write!(f, "+"),
            Token::Minus => write!(f, "-"),
            Token::Star => write!(f, "*"),
            Token::Slash => write!(f, "/"),
            Token::Percent => write!(f, "%"),
            Token::Power => write!(f, "**"),
            Token::Equal => write!(f, "=="),
            Token::NotEqual => write!(f, "!="),
            Token::Less => write!(f, "<"),
            Token::LessEqual => write!(f, "<="),
            Token::Greater => write!(f, ">"),
            Token::GreaterEqual => write!(f, ">="),
            Token::And => write!(f, "&&"),
            Token::Or => write!(f, "||"),
            Token::Not => write!(f, "!"),
            Token::BitAnd => write!(f, "&"),
            Token::BitOr => write!(f, "|"),
            Token::BitXor => write!(f, "^"),
            Token::BitNot => write!(f, "~"),
            Token::LeftShift => write!(f, "<<"),
            Token::RightShift => write!(f, ">>"),
            Token::Assign => write!(f, "="),
            Token::PlusAssign => write!(f, "+="),
            Token::MinusAssign => write!(f, "-="),
            Token::StarAssign => write!(f, "*="),
            Token::SlashAssign => write!(f, "/="),
            Token::Colon => write!(f, ":"),
            Token::DoubleColon => write!(f, "::"),
            Token::Arrow => write!(f, "->"),
            Token::FatArrow => write!(f, "=>"),
            Token::LeftArrow => write!(f, "<-"),
            Token::At => write!(f, "@"),
            Token::Hash => write!(f, "#"),
            Token::LeftParen => write!(f, "("),
            Token::RightParen => write!(f, ")"),
            Token::LeftBracket => write!(f, "["),
            Token::RightBracket => write!(f, "]"),
            Token::LeftBrace => write!(f, "{{"),
            Token::RightBrace => write!(f, "}}"),
            Token::Semicolon => write!(f, ";"),
            Token::Comma => write!(f, ","),
            Token::Dot => write!(f, "."),
            Token::DotDot => write!(f, ".."),
            Token::IntegerLiteral(n) => write!(f, "{}", n),
            Token::FloatLiteral(x) => write!(f, "{}", x),
            Token::StringLiteral(s) => write!(f, "\"{}\"", s),
            Token::BooleanLiteral => write!(f, "bool"),
            Token::HardwareQubit(n) => write!(f, "${}", n),
            Token::Identifier(name) => write!(f, "{}", name),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lex(source: &str) -> Vec<Token> {
        Token::lexer(source)
            .filter_map(|result| result.ok())
            .collect()
    }

    #[test]
    fn test_version() {
        let tokens = lex("METAQASM 4.0;");
        assert_eq!(tokens[0], Token::MetaQASM);
        assert_eq!(tokens[1], Token::FloatLiteral(4.0));
        assert_eq!(tokens[2], Token::Semicolon);
    }

    #[test]
    fn test_effect_monads() {
        let tokens = lex("CircuitM MeasureM DynamicM PulseM BackendM ProofM ReceiptM");
        assert_eq!(tokens[0], Token::CircuitM);
        assert_eq!(tokens[1], Token::MeasureM);
        assert_eq!(tokens[2], Token::DynamicM);
        assert_eq!(tokens[3], Token::PulseM);
        assert_eq!(tokens[4], Token::BackendM);
        assert_eq!(tokens[5], Token::ProofM);
        assert_eq!(tokens[6], Token::ReceiptM);
    }

    #[test]
    fn test_ownership_keywords() {
        let tokens = lex("owned borrowed released");
        assert_eq!(tokens[0], Token::Owned);
        assert_eq!(tokens[1], Token::Borrowed);
        assert_eq!(tokens[2], Token::Released);
    }

    #[test]
    fn test_proof_keywords() {
        let tokens = lex("requires ensures invariant predicate witness");
        assert_eq!(tokens[0], Token::Requires);
        assert_eq!(tokens[1], Token::Ensures);
        assert_eq!(tokens[2], Token::Invariant);
        assert_eq!(tokens[3], Token::Predicate);
        assert_eq!(tokens[4], Token::Witness);
    }

    #[test]
    fn test_type_operators() {
        let tokens = lex(": :: -> => <- @ #");
        assert_eq!(tokens[0], Token::Colon);
        assert_eq!(tokens[1], Token::DoubleColon);
        assert_eq!(tokens[2], Token::Arrow);
        assert_eq!(tokens[3], Token::FatArrow);
        assert_eq!(tokens[4], Token::LeftArrow);
        assert_eq!(tokens[5], Token::At);
        assert_eq!(tokens[6], Token::Hash);
    }

    #[test]
    fn test_circuit_declaration() {
        let source = "circuit<CircuitM> bell_pair(q0: owned Qubit) -> owned Qubit";
        let tokens = lex(source);
        assert_eq!(tokens[0], Token::Circuit);
        assert_eq!(tokens[1], Token::Less);
        assert_eq!(tokens[2], Token::CircuitM);
        assert_eq!(tokens[3], Token::Greater);
        assert!(matches!(tokens[4], Token::Identifier(_)));
    }

    #[test]
    fn test_refinement_type() {
        let source = "{x: int | x > 0}";
        let tokens = lex(source);
        assert_eq!(tokens[0], Token::LeftBrace);
        assert!(matches!(tokens[1], Token::Identifier(_)));
        assert_eq!(tokens[2], Token::Colon);
        assert_eq!(tokens[3], Token::Int);
        assert_eq!(tokens[4], Token::BitOr);
    }

    #[test]
    fn test_comments() {
        let source = "// Line comment\nqubit /* block comment */ q;";
        let tokens = lex(source);
        assert_eq!(tokens[0], Token::Qubit);
        assert!(matches!(tokens[1], Token::Identifier(_)));
        assert_eq!(tokens[2], Token::Semicolon);
    }

    #[test]
    fn test_literals() {
        let tokens = lex("42 3.14 \"hello\" true false $5");
        assert_eq!(tokens[0], Token::IntegerLiteral(42));
        assert_eq!(tokens[1], Token::FloatLiteral(3.14));
        assert!(matches!(tokens[2], Token::StringLiteral(_)));
        assert_eq!(tokens[3], Token::BooleanLiteral);
        assert_eq!(tokens[4], Token::BooleanLiteral);
        assert_eq!(tokens[5], Token::HardwareQubit(5));
    }

    #[test]
    fn test_complete_program() {
        let source = r#"
METAQASM 4.0;

type LiveQubit = {q: Qubit | isLive(q)};

circuit<CircuitM> bell_pair(
    q0: owned LiveQubit,
    q1: owned LiveQubit
) -> (owned LiveQubit, owned LiveQubit)
    requires isLive(q0) && isLive(q1)
    ensures isEntangled(result.0, result.1)
{
    q0' <- h(q0);
    (q0'', q1') <- cx(q0', q1);
    return (q0'', q1');
}
"#;
        let tokens = lex(source);
        assert!(tokens.len() > 50);
        assert_eq!(tokens[0], Token::MetaQASM);
        assert_eq!(tokens[2], Token::Semicolon);
    }
}

// Made with Bob
