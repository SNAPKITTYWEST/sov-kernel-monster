//! Symbol table for semantic analysis
//!
//! Clean-room implementation - not derived from Qiskit

use std::collections::HashMap;
use qataaum_parser::Span;
use serde::{Deserialize, Serialize};

/// Symbol kind
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum SymbolKind {
    /// Quantum register
    QReg { size: usize },
    
    /// Classical register
    CReg { size: usize },
    
    /// Gate definition
    Gate {
        params: Vec<String>,
        qubits: Vec<String>,
    },
    
    /// Opaque gate
    Opaque {
        params: Vec<String>,
        qubits: Vec<String>,
    },
    
    /// Gate parameter (inside gate body)
    Parameter,
    
    /// Qubit parameter (inside gate body)
    Qubit,
}

/// Symbol table entry
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Symbol {
    pub name: String,
    pub kind: SymbolKind,
    pub span: Span,
}

/// Symbol table with scoping support
#[derive(Debug, Clone)]
pub struct SymbolTable {
    /// Global scope
    global: HashMap<String, Symbol>,
    
    /// Local scopes stack (for gate bodies)
    scopes: Vec<HashMap<String, Symbol>>,
}

impl SymbolTable {
    /// Create a new symbol table
    pub fn new() -> Self {
        Self {
            global: HashMap::new(),
            scopes: Vec::new(),
        }
    }
    
    /// Enter a new scope
    pub fn enter_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }
    
    /// Exit the current scope
    pub fn exit_scope(&mut self) {
        self.scopes.pop();
    }
    
    /// Check if currently in a local scope
    pub fn in_local_scope(&self) -> bool {
        !self.scopes.is_empty()
    }
    
    /// Define a symbol in the current scope
    pub fn define(&mut self, symbol: Symbol) -> Result<(), Symbol> {
        let name = symbol.name.clone();
        
        if let Some(scope) = self.scopes.last_mut() {
            // Local scope
            if let Some(existing) = scope.get(&name) {
                return Err(existing.clone());
            }
            scope.insert(name, symbol);
        } else {
            // Global scope
            if let Some(existing) = self.global.get(&name) {
                return Err(existing.clone());
            }
            self.global.insert(name, symbol);
        }
        
        Ok(())
    }
    
    /// Look up a symbol
    pub fn lookup(&self, name: &str) -> Option<&Symbol> {
        // Search local scopes from innermost to outermost
        for scope in self.scopes.iter().rev() {
            if let Some(symbol) = scope.get(name) {
                return Some(symbol);
            }
        }
        
        // Search global scope
        self.global.get(name)
    }
    
    /// Look up a symbol in global scope only
    pub fn lookup_global(&self, name: &str) -> Option<&Symbol> {
        self.global.get(name)
    }
    
    /// Get all global symbols
    pub fn global_symbols(&self) -> impl Iterator<Item = &Symbol> {
        self.global.values()
    }
    
    /// Get quantum register size
    pub fn get_qreg_size(&self, name: &str) -> Option<usize> {
        self.lookup(name).and_then(|sym| match &sym.kind {
            SymbolKind::QReg { size } => Some(*size),
            _ => None,
        })
    }
    
    /// Get classical register size
    pub fn get_creg_size(&self, name: &str) -> Option<usize> {
        self.lookup(name).and_then(|sym| match &sym.kind {
            SymbolKind::CReg { size } => Some(*size),
            _ => None,
        })
    }
    
    /// Get gate definition
    pub fn get_gate(&self, name: &str) -> Option<(&Vec<String>, &Vec<String>)> {
        self.lookup(name).and_then(|sym| match &sym.kind {
            SymbolKind::Gate { params, qubits } => Some((params, qubits)),
            SymbolKind::Opaque { params, qubits } => Some((params, qubits)),
            _ => None,
        })
    }
    
    /// Check if a symbol is a quantum register
    pub fn is_qreg(&self, name: &str) -> bool {
        matches!(
            self.lookup(name).map(|s| &s.kind),
            Some(SymbolKind::QReg { .. })
        )
    }
    
    /// Check if a symbol is a classical register
    pub fn is_creg(&self, name: &str) -> bool {
        matches!(
            self.lookup(name).map(|s| &s.kind),
            Some(SymbolKind::CReg { .. })
        )
    }
    
    /// Check if a symbol is a gate
    pub fn is_gate(&self, name: &str) -> bool {
        matches!(
            self.lookup(name).map(|s| &s.kind),
            Some(SymbolKind::Gate { .. }) | Some(SymbolKind::Opaque { .. })
        )
    }
}

impl Default for SymbolTable {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_symbol_table_basic() {
        let mut table = SymbolTable::new();
        
        let qreg = Symbol {
            name: "q".to_string(),
            kind: SymbolKind::QReg { size: 2 },
            span: Span::new(1, 0, 0),
        };
        
        assert!(table.define(qreg.clone()).is_ok());
        assert!(table.lookup("q").is_some());
        assert_eq!(table.get_qreg_size("q"), Some(2));
    }

    #[test]
    fn test_symbol_table_duplicate() {
        let mut table = SymbolTable::new();
        
        let qreg1 = Symbol {
            name: "q".to_string(),
            kind: SymbolKind::QReg { size: 2 },
            span: Span::new(1, 0, 0),
        };
        
        let qreg2 = Symbol {
            name: "q".to_string(),
            kind: SymbolKind::QReg { size: 3 },
            span: Span::new(2, 0, 0),
        };
        
        assert!(table.define(qreg1).is_ok());
        assert!(table.define(qreg2).is_err());
    }

    #[test]
    fn test_symbol_table_scoping() {
        let mut table = SymbolTable::new();
        
        // Define in global scope
        let global_sym = Symbol {
            name: "x".to_string(),
            kind: SymbolKind::Parameter,
            span: Span::new(1, 0, 0),
        };
        table.define(global_sym).unwrap();
        
        // Enter local scope
        table.enter_scope();
        
        // Define in local scope (shadows global)
        let local_sym = Symbol {
            name: "x".to_string(),
            kind: SymbolKind::Qubit,
            span: Span::new(2, 0, 0),
        };
        table.define(local_sym).unwrap();
        
        // Should find local symbol
        assert!(matches!(
            table.lookup("x").map(|s| &s.kind),
            Some(SymbolKind::Qubit)
        ));
        
        // Exit local scope
        table.exit_scope();
        
        // Should find global symbol again
        assert!(matches!(
            table.lookup("x").map(|s| &s.kind),
            Some(SymbolKind::Parameter)
        ));
    }

    #[test]
    fn test_register_queries() {
        let mut table = SymbolTable::new();
        
        table.define(Symbol {
            name: "q".to_string(),
            kind: SymbolKind::QReg { size: 5 },
            span: Span::new(1, 0, 0),
        }).unwrap();
        
        table.define(Symbol {
            name: "c".to_string(),
            kind: SymbolKind::CReg { size: 3 },
            span: Span::new(2, 0, 0),
        }).unwrap();
        
        assert!(table.is_qreg("q"));
        assert!(!table.is_creg("q"));
        assert!(table.is_creg("c"));
        assert!(!table.is_qreg("c"));
        
        assert_eq!(table.get_qreg_size("q"), Some(5));
        assert_eq!(table.get_creg_size("c"), Some(3));
    }
}

// Made with Bob