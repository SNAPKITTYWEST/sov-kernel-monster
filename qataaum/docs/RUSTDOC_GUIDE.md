# Rust API Documentation Guide

**Project:** QATAAUM Quantum Assembly Runtime  
**Version:** 1.0  
**Date:** 2026-07-22

## Generating Documentation

QATAAUM uses Rust's built-in documentation system (`rustdoc`) to generate comprehensive API documentation from source code comments.

### Quick Start

```powershell
# Generate documentation for all workspace crates
cargo doc --no-deps --workspace

# Generate and open in browser
cargo doc --no-deps --workspace --open

# Generate with private items
cargo doc --no-deps --workspace --document-private-items
```

### Documentation Location

Generated documentation is placed in:
```
target/doc/
├── qataaum_parser/
├── qataaum_semantic/
├── qataaum_ir/
├── qataaum_passes/
├── qataaum_routing/
├── qataaum_simulator/
├── shadow_rpg_q/
├── qataaum_ibmi_ffi/
└── index.html
```

## Documentation Standards

### Module-Level Documentation

Every module should have a module-level doc comment:

```rust
//! # Parser Module
//!
//! This module provides lexical analysis and parsing for OpenQASM 2.0, OpenQASM 3.x,
//! and MetaQASM-4 quantum assembly languages.
//!
//! ## Example
//!
//! ```
//! use qataaum_parser::{Lexer, Parser};
//!
//! let source = "OPENQASM 2.0; qreg q[2]; h q[0];";
//! let mut lexer = Lexer::new(source);
//! let tokens = lexer.tokenize()?;
//! let mut parser = Parser::new(tokens);
//! let ast = parser.parse()?;
//! # Ok::<(), Box<dyn std::error::Error>>(())
//! ```
```

### Type Documentation

All public types should be documented:

```rust
/// A lexer for OpenQASM source code.
///
/// The lexer tokenizes source code into a stream of tokens that can be
/// consumed by the parser. It handles:
/// - Keywords and identifiers
/// - Numeric literals (integers and floats)
/// - String literals
/// - Operators and punctuation
/// - Comments (which are discarded)
///
/// # Examples
///
/// ```
/// use qataaum_parser::Lexer;
///
/// let mut lexer = Lexer::new("OPENQASM 2.0;");
/// let tokens = lexer.tokenize()?;
/// assert_eq!(tokens.len(), 3); // OPENQASM, 2.0, ;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
pub struct Lexer<'a> {
    source: &'a str,
    position: usize,
}
```

### Function Documentation

All public functions should be documented:

```rust
/// Tokenize the entire source code.
///
/// This method consumes the lexer and returns a vector of tokens.
/// Comments are discarded during tokenization.
///
/// # Errors
///
/// Returns `LexerError` if:
/// - An unexpected character is encountered
/// - A string literal is not terminated
/// - A numeric literal is malformed
///
/// # Examples
///
/// ```
/// use qataaum_parser::Lexer;
///
/// let mut lexer = Lexer::new("qreg q[2];");
/// let tokens = lexer.tokenize()?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
pub fn tokenize(&mut self) -> Result<Vec<Token>, LexerError> {
    // Implementation
}
```

### Error Documentation

Error types should document all variants:

```rust
/// Errors that can occur during lexical analysis.
#[derive(Debug, thiserror::Error)]
pub enum LexerError {
    /// An unexpected character was encountered.
    ///
    /// The first field is the character, the second is its position.
    #[error("unexpected character '{0}' at position {1}")]
    UnexpectedCharacter(char, usize),
    
    /// A string literal was not terminated before EOF.
    ///
    /// The field is the position where the string started.
    #[error("unterminated string literal at position {0}")]
    UnterminatedString(usize),
}
```

## Documentation Features

### Code Examples

Use triple backticks with language identifier:

```rust
/// # Examples
///
/// ```
/// use qataaum_simulator::StateVectorSimulator;
///
/// let mut sim = StateVectorSimulator::new(2);
/// sim.h(0)?;
/// sim.cx(0, 1)?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
```

### Panics Section

Document when functions can panic:

```rust
/// # Panics
///
/// Panics if `qubit` is greater than or equal to the number of qubits.
pub fn apply_gate(&mut self, qubit: usize) {
    assert!(qubit < self.num_qubits, "qubit index out of bounds");
}
```

### Safety Section

Document unsafe code:

```rust
/// # Safety
///
/// The caller must ensure that `ptr` is valid and points to a properly
/// initialized `QataaumCompiler` instance.
pub unsafe fn qataaum_compiler_free(ptr: *mut QataaumCompiler) {
    if !ptr.is_null() {
        drop(Box::from_raw(ptr));
    }
}
```

### Links

Link to other items:

```rust
/// Parse tokens into an AST.
///
/// See [`Lexer::tokenize`] for token generation.
/// Returns a [`Program`] on success.
pub fn parse(&mut self) -> Result<Program, ParseError> {
    // Implementation
}
```

## Crate-Level Documentation

Each crate should have a `lib.rs` with crate-level documentation:

```rust
//! # QATAAUM Parser
//!
//! This crate provides lexical analysis and parsing for quantum assembly languages.
//!
//! ## Supported Languages
//!
//! - OpenQASM 2.0
//! - OpenQASM 3.x (public revisions)
//! - MetaQASM-4 (experimental)
//!
//! ## Architecture
//!
//! The parser is organized into three main components:
//!
//! 1. **Lexer:** Tokenizes source code
//! 2. **Parser:** Builds abstract syntax trees
//! 3. **AST:** Represents program structure
//!
//! ## Example
//!
//! ```
//! use qataaum_parser::{Lexer, Parser};
//!
//! let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
//! let mut lexer = Lexer::new(source);
//! let tokens = lexer.tokenize()?;
//! let mut parser = Parser::new(tokens);
//! let ast = parser.parse()?;
//! # Ok::<(), Box<dyn std::error::Error>>(())
//! ```
```

## Testing Documentation

Documentation examples are automatically tested:

```rust
/// # Examples
///
/// ```
/// use qataaum_parser::Lexer;
///
/// let mut lexer = Lexer::new("OPENQASM 2.0;");
/// let tokens = lexer.tokenize().unwrap();
/// assert_eq!(tokens.len(), 3);
/// ```
```

Run documentation tests:

```powershell
cargo test --doc
```

## Hidden Documentation

Hide implementation details:

```rust
/// Public function
///
/// # Examples
///
/// ```
/// # use qataaum_parser::Lexer;
/// # let mut lexer = Lexer::new("test");
/// // Hidden setup code above
/// let tokens = lexer.tokenize()?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
```

Lines starting with `#` are hidden in rendered docs but still compiled.

## Documentation Attributes

### `#[doc(hidden)]`

Hide items from documentation:

```rust
#[doc(hidden)]
pub fn internal_helper() {
    // Not shown in public docs
}
```

### `#[doc(alias = "...")]`

Add search aliases:

```rust
#[doc(alias = "CNOT")]
#[doc(alias = "controlled-not")]
pub fn cx(&mut self, control: usize, target: usize) {
    // Searchable by "CNOT" or "controlled-not"
}
```

## Cross-Crate Documentation

Link to items in other crates:

```rust
/// Uses [`qataaum_parser::Parser`] to parse source code.
pub fn compile(source: &str) -> Result<Program, CompileError> {
    // Implementation
}
```

## Documentation Best Practices

1. **Be Concise:** First sentence should be a brief summary
2. **Use Examples:** Show typical usage patterns
3. **Document Errors:** Explain when and why errors occur
4. **Link Related Items:** Help users discover related functionality
5. **Test Examples:** Ensure examples compile and run
6. **Update Regularly:** Keep docs in sync with code changes

## Publishing Documentation

### Local Preview

```powershell
cargo doc --no-deps --workspace --open
```

### CI/CD Integration

Add to GitHub Actions:

```yaml
- name: Generate Documentation
  run: cargo doc --no-deps --workspace
  
- name: Deploy to GitHub Pages
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./target/doc
```

### docs.rs

Documentation is automatically published to docs.rs when crates are published to crates.io.

## Troubleshooting

### Missing Documentation Warnings

Enable warnings:

```powershell
$env:RUSTDOCFLAGS="-D missing-docs"
cargo doc --no-deps --workspace
```

### Broken Links

Check for broken intra-doc links:

```powershell
$env:RUSTDOCFLAGS="-D rustdoc::broken-intra-doc-links"
cargo doc --no-deps --workspace
```

### Private Items

Include private items in documentation:

```powershell
cargo doc --no-deps --workspace --document-private-items
```

## Additional Resources

- [Rust Documentation Guidelines](https://doc.rust-lang.org/rustdoc/)
- [RFC 1574: API Documentation Conventions](https://rust-lang.github.io/rfcs/1574-more-api-documentation-conventions.html)
- [The Rust Book: Documentation](https://doc.rust-lang.org/book/ch14-02-publishing-to-crates-io.html#making-useful-documentation-comments)

---

**Generated:** 2026-07-22  
**Version:** 1.0  
**License:** Apache-2.0