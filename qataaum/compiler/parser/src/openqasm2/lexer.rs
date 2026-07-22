//! OpenQASM 2.0 Lexer
//!
//! Clean-room implementation based on public OpenQASM 2.0 specification.
//! NOT derived from Qiskit lexer implementation.
//!
//! Public Source: https://github.com/Qiskit/openqasm/tree/OpenQASM2.x
//! Specification: OpenQASM 2.0 grammar
//!
//! Token types derived from public grammar specification.

use logos::Logos;

/// OpenQASM 2.0 Token
#[derive(Logos, Debug, Clone, PartialEq)]
#[logos(skip r"[ \t\n\f]+")]  // Skip whitespace
#[logos(skip r"//[^\n]*")]     // Skip single-line comments
pub enum Token {
    // Keywords
    #[token("OPENQASM")]
    OpenQASM,
    
    #[token("include")]
    Include,
    
    #[token("qreg")]
    QReg,
    
    #[token("creg")]
    CReg,
    
    #[token("gate")]
    Gate,
    
    #[token("opaque")]
    Opaque,
    
    #[token("measure")]
    Measure,
    
    #[token("reset")]
    Reset,
    
    #[token("barrier")]
    Barrier,
    
    #[token("if")]
    If,
    
    #[token("U")]
    U,
    
    #[token("CX")]
    CX,
    
    #[token("pi")]
    Pi,
    
    #[token("sin")]
    Sin,
    
    #[token("cos")]
    Cos,
    
    #[token("tan")]
    Tan,
    
    #[token("exp")]
    Exp,
    
    #[token("ln")]
    Ln,
    
    #[token("sqrt")]
    Sqrt,
    
    // Literals
    #[regex(r"[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?", |lex| lex.slice().parse::<f64>().ok())]
    #[regex(r"[0-9]+[eE][+-]?[0-9]+", |lex| lex.slice().parse::<f64>().ok())]
    Real(f64),
    
    #[regex(r"[0-9]+", |lex| lex.slice().parse::<i64>().ok())]
    Integer(i64),
    
    #[regex(r#""[^"]*""#, |lex| {
        let s = lex.slice();
        Some(s[1..s.len()-1].to_string())
    })]
    String(String),
    
    // Identifiers
    #[regex(r"[a-z][a-zA-Z0-9_]*", |lex| lex.slice().to_string())]
    Identifier(String),
    
    // Operators and Delimiters
    #[token(";")]
    Semicolon,
    
    #[token(",")]
    Comma,
    
    #[token("(")]
    LParen,
    
    #[token(")")]
    RParen,
    
    #[token("[")]
    LBracket,
    
    #[token("]")]
    RBracket,
    
    #[token("{")]
    LBrace,
    
    #[token("}")]
    RBrace,
    
    #[token("+")]
    Plus,
    
    #[token("-")]
    Minus,
    
    #[token("*")]
    Star,
    
    #[token("/")]
    Slash,
    
    #[token("^")]
    Caret,
    
    #[token("->")]
    Arrow,
    
    #[token("==")]
    EqEq,
    
    // End of file
    Eof,
}

impl std::fmt::Display for Token {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Token::OpenQASM => write!(f, "OPENQASM"),
            Token::Include => write!(f, "include"),
            Token::QReg => write!(f, "qreg"),
            Token::CReg => write!(f, "creg"),
            Token::Gate => write!(f, "gate"),
            Token::Opaque => write!(f, "opaque"),
            Token::Measure => write!(f, "measure"),
            Token::Reset => write!(f, "reset"),
            Token::Barrier => write!(f, "barrier"),
            Token::If => write!(f, "if"),
            Token::U => write!(f, "U"),
            Token::CX => write!(f, "CX"),
            Token::Pi => write!(f, "pi"),
            Token::Sin => write!(f, "sin"),
            Token::Cos => write!(f, "cos"),
            Token::Tan => write!(f, "tan"),
            Token::Exp => write!(f, "exp"),
            Token::Ln => write!(f, "ln"),
            Token::Sqrt => write!(f, "sqrt"),
            Token::Real(r) => write!(f, "{}", r),
            Token::Integer(i) => write!(f, "{}", i),
            Token::String(s) => write!(f, "\"{}\"", s),
            Token::Identifier(id) => write!(f, "{}", id),
            Token::Semicolon => write!(f, ";"),
            Token::Comma => write!(f, ","),
            Token::LParen => write!(f, "("),
            Token::RParen => write!(f, ")"),
            Token::LBracket => write!(f, "["),
            Token::RBracket => write!(f, "]"),
            Token::LBrace => write!(f, "{{"),
            Token::RBrace => write!(f, "}}"),
            Token::Plus => write!(f, "+"),
            Token::Minus => write!(f, "-"),
            Token::Star => write!(f, "*"),
            Token::Slash => write!(f, "/"),
            Token::Caret => write!(f, "^"),
            Token::Arrow => write!(f, "->"),
            Token::EqEq => write!(f, "=="),
            Token::Eof => write!(f, "EOF"),
        }
    }
}

/// Lexer for OpenQASM 2.0
pub struct Lexer<'source> {
    inner: logos::Lexer<'source, Token>,
    line: usize,
    column: usize,
}

impl<'source> Lexer<'source> {
    /// Create a new lexer from source code
    pub fn new(source: &'source str) -> Self {
        Self {
            inner: Token::lexer(source),
            line: 1,
            column: 1,
        }
    }
    
    /// Get the current line number
    pub fn line(&self) -> usize {
        self.line
    }
    
    /// Get the current column number
    pub fn column(&self) -> usize {
        self.column
    }
    
    /// Get the current span
    pub fn span(&self) -> std::ops::Range<usize> {
        self.inner.span()
    }
    
    /// Get the current slice
    pub fn slice(&self) -> &'source str {
        self.inner.slice()
    }
}

impl<'source> Iterator for Lexer<'source> {
    type Item = Result<Token, String>;
    
    fn next(&mut self) -> Option<Self::Item> {
        match self.inner.next() {
            Some(Ok(token)) => {
                // Update line and column tracking
                let slice = self.inner.slice();
                for ch in slice.chars() {
                    if ch == '\n' {
                        self.line += 1;
                        self.column = 1;
                    } else {
                        self.column += 1;
                    }
                }
                Some(Ok(token))
            }
            Some(Err(_)) => {
                Some(Err(format!(
                    "Invalid token at {}:{}: '{}'",
                    self.line,
                    self.column,
                    self.inner.slice()
                )))
            }
            None => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keywords() {
        let source = "OPENQASM include qreg creg gate measure";
        let mut lexer = Lexer::new(source);
        
        assert_eq!(lexer.next(), Some(Ok(Token::OpenQASM)));
        assert_eq!(lexer.next(), Some(Ok(Token::Include)));
        assert_eq!(lexer.next(), Some(Ok(Token::QReg)));
        assert_eq!(lexer.next(), Some(Ok(Token::CReg)));
        assert_eq!(lexer.next(), Some(Ok(Token::Gate)));
        assert_eq!(lexer.next(), Some(Ok(Token::Measure)));
        assert_eq!(lexer.next(), None);
    }

    #[test]
    fn test_numbers() {
        let source = "42 3.14 1.5e-10";
        let mut lexer = Lexer::new(source);
        
        assert_eq!(lexer.next(), Some(Ok(Token::Integer(42))));
        assert_eq!(lexer.next(), Some(Ok(Token::Real(3.14))));
        assert!(matches!(lexer.next(), Some(Ok(Token::Real(_)))));
        assert_eq!(lexer.next(), None);
    }

    #[test]
    fn test_identifiers() {
        let source = "q0 qubit_reg my_gate";
        let mut lexer = Lexer::new(source);
        
        assert_eq!(lexer.next(), Some(Ok(Token::Identifier("q0".to_string()))));
        assert_eq!(lexer.next(), Some(Ok(Token::Identifier("qubit_reg".to_string()))));
        assert_eq!(lexer.next(), Some(Ok(Token::Identifier("my_gate".to_string()))));
        assert_eq!(lexer.next(), None);
    }

    #[test]
    fn test_operators() {
        let source = "+ - * / ^ -> ==";
        let mut lexer = Lexer::new(source);
        
        assert_eq!(lexer.next(), Some(Ok(Token::Plus)));
        assert_eq!(lexer.next(), Some(Ok(Token::Minus)));
        assert_eq!(lexer.next(), Some(Ok(Token::Star)));
        assert_eq!(lexer.next(), Some(Ok(Token::Slash)));
        assert_eq!(lexer.next(), Some(Ok(Token::Caret)));
        assert_eq!(lexer.next(), Some(Ok(Token::Arrow)));
        assert_eq!(lexer.next(), Some(Ok(Token::EqEq)));
        assert_eq!(lexer.next(), None);
    }

    #[test]
    fn test_delimiters() {
        let source = "( ) [ ] { } ; ,";
        let mut lexer = Lexer::new(source);
        
        assert_eq!(lexer.next(), Some(Ok(Token::LParen)));
        assert_eq!(lexer.next(), Some(Ok(Token::RParen)));
        assert_eq!(lexer.next(), Some(Ok(Token::LBracket)));
        assert_eq!(lexer.next(), Some(Ok(Token::RBracket)));
        assert_eq!(lexer.next(), Some(Ok(Token::LBrace)));
        assert_eq!(lexer.next(), Some(Ok(Token::RBrace)));
        assert_eq!(lexer.next(), Some(Ok(Token::Semicolon)));
        assert_eq!(lexer.next(), Some(Ok(Token::Comma)));
        assert_eq!(lexer.next(), None);
    }

    #[test]
    fn test_string_literal() {
        let source = r#""qelib1.inc""#;
        let mut lexer = Lexer::new(source);
        
        assert_eq!(lexer.next(), Some(Ok(Token::String("qelib1.inc".to_string()))));
        assert_eq!(lexer.next(), None);
    }

    #[test]
    fn test_comments() {
        let source = "qreg // this is a comment\ncreg";
        let mut lexer = Lexer::new(source);
        
        assert_eq!(lexer.next(), Some(Ok(Token::QReg)));
        assert_eq!(lexer.next(), Some(Ok(Token::CReg)));
        assert_eq!(lexer.next(), None);
    }

    #[test]
    fn test_bell_pair_program() {
        let source = r#"
            OPENQASM 2.0;
            include "qelib1.inc";
            qreg q[2];
            creg c[2];
            h q[0];
            cx q[0], q[1];
            measure q -> c;
        "#;
        
        let mut lexer = Lexer::new(source);
        let tokens: Vec<_> = lexer.collect();
        
        // Should successfully tokenize without errors
        assert!(tokens.iter().all(|t| t.is_ok()));
        
        // Check first few tokens
        assert_eq!(tokens[0], Ok(Token::OpenQASM));
        assert_eq!(tokens[1], Ok(Token::Real(2.0)));
        assert_eq!(tokens[2], Ok(Token::Semicolon));
        assert_eq!(tokens[3], Ok(Token::Include));
    }
}

// Made with Bob
