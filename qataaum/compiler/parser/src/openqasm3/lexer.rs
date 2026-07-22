//! OpenQASM 3 Lexer
//!
//! Tokenizes OpenQASM 3.x source code based on the public specification.
//! Reference: https://openqasm.com/

use logos::Logos;

/// OpenQASM 3 token types
#[derive(Logos, Debug, Clone, PartialEq)]
#[logos(skip r"[ \t\n\f]+")]
pub enum Token {
    // Version declaration
    #[token("OPENQASM")]
    OpenQASM,

    // Include statement
    #[token("include")]
    Include,

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
    
    #[token("bool")]
    Bool,
    
    #[token("duration")]
    Duration,
    
    #[token("stretch")]
    Stretch,
    
    #[token("complex")]
    Complex,

    // Classical types
    #[token("const")]
    Const,
    
    #[token("mutable")]
    Mutable,
    
    #[token("let")]
    Let,

    // Quantum operations
    #[token("gate")]
    Gate,
    
    #[token("defcal")]
    DefCal,
    
    #[token("defcalgrammar")]
    DefCalGrammar,
    
    #[token("def")]
    Def,
    
    #[token("extern")]
    Extern,

    // Control flow
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
    
    #[token("break")]
    Break,
    
    #[token("continue")]
    Continue,
    
    #[token("return")]
    Return,
    
    #[token("end")]
    End,

    // Measurement and reset
    #[token("measure")]
    Measure,
    
    #[token("reset")]
    Reset,
    
    #[token("barrier")]
    Barrier,
    
    #[token("delay")]
    Delay,

    // Timing
    #[token("box")]
    Box,
    
    #[token("cal")]
    Cal,

    // Modifiers
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

    // Pragma
    #[token("pragma")]
    Pragma,

    // Annotations
    #[regex(r"@[a-zA-Z_][a-zA-Z0-9_]*", |lex| lex.slice()[1..].to_string())]
    Annotation(String),

    // Identifiers
    #[regex(r"[a-zA-Z_][a-zA-Z0-9_]*", |lex| lex.slice().to_string())]
    Identifier(String),

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

    // Boolean literals
    #[token("true")]
    True,
    
    #[token("false")]
    False,

    // Hardware literals
    #[regex(r"\$[0-9]+", |lex| {
        lex.slice()[1..].parse().ok()
    })]
    HardwareQubit(usize),

    // Timing literals
    #[regex(r"[0-9]+(\.[0-9]+)?[a-z]+", |lex| lex.slice().to_string())]
    TimingLiteral(String),

    // Operators
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

    // Bitwise operators
    #[token("&")]
    Ampersand,
    
    #[token("|")]
    Pipe,
    
    #[token("^")]
    Caret,
    
    #[token("~")]
    Tilde,
    
    #[token("<<")]
    LeftShift,
    
    #[token(">>")]
    RightShift,

    // Comparison operators
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

    // Logical operators
    #[token("&&")]
    And,
    
    #[token("||")]
    Or,
    
    #[token("!")]
    Not,

    // Assignment operators
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
    
    #[token("%=")]
    PercentAssign,
    
    #[token("&=")]
    AndAssign,
    
    #[token("|=")]
    OrAssign,
    
    #[token("^=")]
    XorAssign,
    
    #[token("<<=")]
    LeftShiftAssign,
    
    #[token(">>=")]
    RightShiftAssign,

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

    // Punctuation
    #[token(";")]
    Semicolon,
    
    #[token(",")]
    Comma,
    
    #[token(".")]
    Dot,
    
    #[token(":")]
    Colon,
    
    #[token("::")]
    DoubleColon,
    
    #[token("->")]
    Arrow,

    // Range operator
    #[token("...")]
    Ellipsis,

    // Comments (skip)
    #[regex(r"//[^\n]*", logos::skip)]
    #[regex(r"/\*([^*]|\*[^/])*\*/", logos::skip)]
    Comment,

    // Special
    #[token("pi")]
    Pi,
    
    #[token("tau")]
    Tau,
    
    #[token("euler")]
    Euler,

    // Array indexing
    #[token("#")]
    Hash,
}

impl std::fmt::Display for Token {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Token::OpenQASM => write!(f, "OPENQASM"),
            Token::Include => write!(f, "include"),
            Token::Qubit => write!(f, "qubit"),
            Token::Bit => write!(f, "bit"),
            Token::Int => write!(f, "int"),
            Token::UInt => write!(f, "uint"),
            Token::Float => write!(f, "float"),
            Token::Angle => write!(f, "angle"),
            Token::Bool => write!(f, "bool"),
            Token::Duration => write!(f, "duration"),
            Token::Stretch => write!(f, "stretch"),
            Token::Complex => write!(f, "complex"),
            Token::Const => write!(f, "const"),
            Token::Mutable => write!(f, "mutable"),
            Token::Let => write!(f, "let"),
            Token::Gate => write!(f, "gate"),
            Token::DefCal => write!(f, "defcal"),
            Token::DefCalGrammar => write!(f, "defcalgrammar"),
            Token::Def => write!(f, "def"),
            Token::Extern => write!(f, "extern"),
            Token::If => write!(f, "if"),
            Token::Else => write!(f, "else"),
            Token::For => write!(f, "for"),
            Token::In => write!(f, "in"),
            Token::While => write!(f, "while"),
            Token::Break => write!(f, "break"),
            Token::Continue => write!(f, "continue"),
            Token::Return => write!(f, "return"),
            Token::End => write!(f, "end"),
            Token::Measure => write!(f, "measure"),
            Token::Reset => write!(f, "reset"),
            Token::Barrier => write!(f, "barrier"),
            Token::Delay => write!(f, "delay"),
            Token::Box => write!(f, "box"),
            Token::Cal => write!(f, "cal"),
            Token::Inv => write!(f, "inv"),
            Token::Pow => write!(f, "pow"),
            Token::Ctrl => write!(f, "ctrl"),
            Token::NegCtrl => write!(f, "negctrl"),
            Token::Input => write!(f, "input"),
            Token::Output => write!(f, "output"),
            Token::Pragma => write!(f, "pragma"),
            Token::Annotation(s) => write!(f, "@{}", s),
            Token::Identifier(s) => write!(f, "{}", s),
            Token::IntegerLiteral(n) => write!(f, "{}", n),
            Token::FloatLiteral(n) => write!(f, "{}", n),
            Token::StringLiteral(s) => write!(f, "\"{}\"", s),
            Token::True => write!(f, "true"),
            Token::False => write!(f, "false"),
            Token::HardwareQubit(n) => write!(f, "${}", n),
            Token::TimingLiteral(s) => write!(f, "{}", s),
            Token::Plus => write!(f, "+"),
            Token::Minus => write!(f, "-"),
            Token::Star => write!(f, "*"),
            Token::Slash => write!(f, "/"),
            Token::Percent => write!(f, "%"),
            Token::Power => write!(f, "**"),
            Token::Ampersand => write!(f, "&"),
            Token::Pipe => write!(f, "|"),
            Token::Caret => write!(f, "^"),
            Token::Tilde => write!(f, "~"),
            Token::LeftShift => write!(f, "<<"),
            Token::RightShift => write!(f, ">>"),
            Token::Equal => write!(f, "=="),
            Token::NotEqual => write!(f, "!="),
            Token::Less => write!(f, "<"),
            Token::LessEqual => write!(f, "<="),
            Token::Greater => write!(f, ">"),
            Token::GreaterEqual => write!(f, ">="),
            Token::And => write!(f, "&&"),
            Token::Or => write!(f, "||"),
            Token::Not => write!(f, "!"),
            Token::Assign => write!(f, "="),
            Token::PlusAssign => write!(f, "+="),
            Token::MinusAssign => write!(f, "-="),
            Token::StarAssign => write!(f, "*="),
            Token::SlashAssign => write!(f, "/="),
            Token::PercentAssign => write!(f, "%="),
            Token::AndAssign => write!(f, "&="),
            Token::OrAssign => write!(f, "|="),
            Token::XorAssign => write!(f, "^="),
            Token::LeftShiftAssign => write!(f, "<<="),
            Token::RightShiftAssign => write!(f, ">>="),
            Token::LeftParen => write!(f, "("),
            Token::RightParen => write!(f, ")"),
            Token::LeftBracket => write!(f, "["),
            Token::RightBracket => write!(f, "]"),
            Token::LeftBrace => write!(f, "{{"),
            Token::RightBrace => write!(f, "}}"),
            Token::Semicolon => write!(f, ";"),
            Token::Comma => write!(f, ","),
            Token::Dot => write!(f, "."),
            Token::Colon => write!(f, ":"),
            Token::DoubleColon => write!(f, "::"),
            Token::Arrow => write!(f, "->"),
            Token::Ellipsis => write!(f, "..."),
            Token::Comment => write!(f, "//"),
            Token::Pi => write!(f, "pi"),
            Token::Tau => write!(f, "tau"),
            Token::Euler => write!(f, "euler"),
            Token::Hash => write!(f, "#"),
        }
    }
}

/// Lexer for OpenQASM 3
pub struct Lexer<'source> {
    inner: logos::Lexer<'source, Token>,
}

impl<'source> Lexer<'source> {
    /// Create a new lexer from source code
    pub fn new(source: &'source str) -> Self {
        Self {
            inner: Token::lexer(source),
        }
    }

    /// Get the current slice
    pub fn slice(&self) -> &'source str {
        self.inner.slice()
    }

    /// Get the current span
    pub fn span(&self) -> std::ops::Range<usize> {
        self.inner.span()
    }
}

impl<'source> Iterator for Lexer<'source> {
    type Item = (Token, std::ops::Range<usize>);

    fn next(&mut self) -> Option<Self::Item> {
        let token = self.inner.next()?;
        let span = self.inner.span();
        Some((token.ok()?, span))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tokenize(source: &str) -> Vec<Token> {
        Lexer::new(source)
            .map(|(token, _)| token)
            .collect()
    }

    #[test]
    fn test_version() {
        let tokens = tokenize("OPENQASM 3.0;");
        assert_eq!(tokens[0], Token::OpenQASM);
        assert_eq!(tokens[1], Token::FloatLiteral(3.0));
        assert_eq!(tokens[2], Token::Semicolon);
    }

    #[test]
    fn test_qubit_declaration() {
        let tokens = tokenize("qubit[5] q;");
        assert_eq!(tokens[0], Token::Qubit);
        assert_eq!(tokens[1], Token::LeftBracket);
        assert_eq!(tokens[2], Token::IntegerLiteral(5));
        assert_eq!(tokens[3], Token::RightBracket);
        assert_eq!(tokens[4], Token::Identifier("q".to_string()));
        assert_eq!(tokens[5], Token::Semicolon);
    }

    #[test]
    fn test_gate_definition() {
        let tokens = tokenize("gate h q { U(pi/2, 0, pi) q; }");
        assert_eq!(tokens[0], Token::Gate);
        assert_eq!(tokens[1], Token::Identifier("h".to_string()));
        assert_eq!(tokens[2], Token::Identifier("q".to_string()));
        assert_eq!(tokens[3], Token::LeftBrace);
    }

    #[test]
    fn test_control_flow() {
        let tokens = tokenize("if (c == 1) { x q[0]; }");
        assert_eq!(tokens[0], Token::If);
        assert_eq!(tokens[1], Token::LeftParen);
        assert_eq!(tokens[2], Token::Identifier("c".to_string()));
        assert_eq!(tokens[3], Token::Equal);
        assert_eq!(tokens[4], Token::IntegerLiteral(1));
    }

    #[test]
    fn test_hardware_qubits() {
        let tokens = tokenize("$0 $1 $127");
        assert_eq!(tokens[0], Token::HardwareQubit(0));
        assert_eq!(tokens[1], Token::HardwareQubit(1));
        assert_eq!(tokens[2], Token::HardwareQubit(127));
    }

    #[test]
    fn test_timing_literals() {
        let tokens = tokenize("100ns 1.5us 2ms");
        assert_eq!(tokens[0], Token::TimingLiteral("100ns".to_string()));
        assert_eq!(tokens[1], Token::TimingLiteral("1.5us".to_string()));
        assert_eq!(tokens[2], Token::TimingLiteral("2ms".to_string()));
    }

    #[test]
    fn test_annotations() {
        let tokens = tokenize("@deprecated @custom_annotation");
        assert_eq!(tokens[0], Token::Annotation("deprecated".to_string()));
        assert_eq!(tokens[1], Token::Annotation("custom_annotation".to_string()));
    }

    #[test]
    fn test_operators() {
        let tokens = tokenize("+ - * / % ** << >> & | ^ ~");
        assert_eq!(tokens[0], Token::Plus);
        assert_eq!(tokens[1], Token::Minus);
        assert_eq!(tokens[2], Token::Star);
        assert_eq!(tokens[3], Token::Slash);
        assert_eq!(tokens[4], Token::Percent);
        assert_eq!(tokens[5], Token::Power);
        assert_eq!(tokens[6], Token::LeftShift);
        assert_eq!(tokens[7], Token::RightShift);
    }

    #[test]
    fn test_comments() {
        let tokens = tokenize("qubit q; // comment\n/* block */ bit c;");
        assert_eq!(tokens[0], Token::Qubit);
        assert_eq!(tokens[1], Token::Identifier("q".to_string()));
        assert_eq!(tokens[2], Token::Semicolon);
        assert_eq!(tokens[3], Token::Bit);
        assert_eq!(tokens[4], Token::Identifier("c".to_string()));
    }

    #[test]
    fn test_string_literals() {
        let tokens = tokenize(r#""hello" "world""#);
        assert_eq!(tokens[0], Token::StringLiteral("hello".to_string()));
        assert_eq!(tokens[1], Token::StringLiteral("world".to_string()));
    }

    #[test]
    fn test_modifiers() {
        let tokens = tokenize("inv pow(2) ctrl");
        assert_eq!(tokens[0], Token::Inv);
        assert_eq!(tokens[1], Token::Pow);
        assert_eq!(tokens[2], Token::LeftParen);
        assert_eq!(tokens[3], Token::IntegerLiteral(2));
        assert_eq!(tokens[4], Token::RightParen);
        assert_eq!(tokens[5], Token::Ctrl);
    }
}

// Made with Bob
