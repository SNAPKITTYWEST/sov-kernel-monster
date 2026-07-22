//! Type system for QATAAUM IR
//!
//! Clean-room implementation - not derived from Qiskit

use serde::{Deserialize, Serialize};
use std::fmt;

/// Quantum and classical types
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Type {
    /// Quantum bit
    Qubit,
    
    /// Classical bit
    Bit,
    
    /// Boolean
    Bool,
    
    /// Signed integer
    Int { bits: u32 },
    
    /// Unsigned integer
    UInt { bits: u32 },
    
    /// Floating point
    Float { bits: u32 },
    
    /// Angle (for rotations)
    Angle,
    
    /// Duration (for timing)
    Duration,
    
    /// Array type
    Array {
        element: Box<Type>,
        size: usize,
    },
    
    /// Quantum register
    QReg { size: usize },
    
    /// Classical register
    CReg { size: usize },
    
    /// Void (no value)
    Void,
}

impl Type {
    /// Check if type is quantum
    pub fn is_quantum(&self) -> bool {
        matches!(self, Type::Qubit | Type::QReg { .. })
    }
    
    /// Check if type is classical
    pub fn is_classical(&self) -> bool {
        !self.is_quantum()
    }
    
    /// Get size in bits (for classical types)
    pub fn size_bits(&self) -> Option<u32> {
        match self {
            Type::Bit | Type::Bool => Some(1),
            Type::Int { bits } | Type::UInt { bits } | Type::Float { bits } => Some(*bits),
            Type::CReg { size } => Some(*size as u32),
            _ => None,
        }
    }
    
    /// Get array element type
    pub fn element_type(&self) -> Option<&Type> {
        match self {
            Type::Array { element, .. } => Some(element),
            _ => None,
        }
    }
    
    /// Get array or register size
    pub fn size(&self) -> Option<usize> {
        match self {
            Type::Array { size, .. } | Type::QReg { size } | Type::CReg { size } => Some(*size),
            _ => None,
        }
    }
}

impl fmt::Display for Type {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Type::Qubit => write!(f, "qubit"),
            Type::Bit => write!(f, "bit"),
            Type::Bool => write!(f, "bool"),
            Type::Int { bits } => write!(f, "i{}", bits),
            Type::UInt { bits } => write!(f, "u{}", bits),
            Type::Float { bits } => write!(f, "f{}", bits),
            Type::Angle => write!(f, "angle"),
            Type::Duration => write!(f, "duration"),
            Type::Array { element, size } => write!(f, "{}[{}]", element, size),
            Type::QReg { size } => write!(f, "qreg[{}]", size),
            Type::CReg { size } => write!(f, "creg[{}]", size),
            Type::Void => write!(f, "void"),
        }
    }
}

/// Value in the IR
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Value {
    /// Qubit reference
    Qubit(QubitId),
    
    /// Bit reference
    Bit(BitId),
    
    /// Boolean constant
    Bool(bool),
    
    /// Integer constant
    Int(i64),
    
    /// Unsigned integer constant
    UInt(u64),
    
    /// Float constant
    Float(f64),
    
    /// Angle constant (in radians)
    Angle(f64),
    
    /// Duration constant (in seconds)
    Duration(f64),
    
    /// Register reference
    Register(RegisterId),
    
    /// Undefined/uninitialized
    Undef,
}

impl Value {
    /// Get the type of this value
    pub fn ty(&self) -> Type {
        match self {
            Value::Qubit(_) => Type::Qubit,
            Value::Bit(_) => Type::Bit,
            Value::Bool(_) => Type::Bool,
            Value::Int(_) => Type::Int { bits: 64 },
            Value::UInt(_) => Type::UInt { bits: 64 },
            Value::Float(_) => Type::Float { bits: 64 },
            Value::Angle(_) => Type::Angle,
            Value::Duration(_) => Type::Duration,
            Value::Register(reg) => match reg {
                RegisterId::Quantum { .. } => Type::Qubit,
                RegisterId::Classical { .. } => Type::Bit,
            },
            Value::Undef => Type::Void,
        }
    }
}

/// Qubit identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct QubitId(pub usize);

impl fmt::Display for QubitId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "q{}", self.0)
    }
}

/// Bit identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct BitId(pub usize);

impl fmt::Display for BitId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "c{}", self.0)
    }
}

/// Register identifier
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RegisterId {
    Quantum { name: String, index: Option<usize> },
    Classical { name: String, index: Option<usize> },
}

impl fmt::Display for RegisterId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RegisterId::Quantum { name, index: Some(i) } => write!(f, "{}[{}]", name, i),
            RegisterId::Quantum { name, index: None } => write!(f, "{}", name),
            RegisterId::Classical { name, index: Some(i) } => write!(f, "{}[{}]", name, i),
            RegisterId::Classical { name, index: None } => write!(f, "{}", name),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_type_is_quantum() {
        assert!(Type::Qubit.is_quantum());
        assert!(Type::QReg { size: 2 }.is_quantum());
        assert!(!Type::Bit.is_quantum());
        assert!(!Type::CReg { size: 2 }.is_quantum());
    }

    #[test]
    fn test_type_size() {
        assert_eq!(Type::Bit.size_bits(), Some(1));
        assert_eq!(Type::Int { bits: 32 }.size_bits(), Some(32));
        assert_eq!(Type::CReg { size: 8 }.size_bits(), Some(8));
        assert_eq!(Type::Qubit.size_bits(), None);
    }

    #[test]
    fn test_type_display() {
        assert_eq!(Type::Qubit.to_string(), "qubit");
        assert_eq!(Type::Int { bits: 32 }.to_string(), "i32");
        assert_eq!(Type::QReg { size: 5 }.to_string(), "qreg[5]");
    }

    #[test]
    fn test_value_type() {
        assert_eq!(Value::Bool(true).ty(), Type::Bool);
        assert_eq!(Value::Int(42).ty(), Type::Int { bits: 64 });
        assert_eq!(Value::Qubit(QubitId(0)).ty(), Type::Qubit);
    }

    #[test]
    fn test_qubit_id_display() {
        assert_eq!(QubitId(0).to_string(), "q0");
        assert_eq!(QubitId(42).to_string(), "q42");
    }

    #[test]
    fn test_register_id_display() {
        let qreg = RegisterId::Quantum {
            name: "q".to_string(),
            index: Some(0),
        };
        assert_eq!(qreg.to_string(), "q[0]");
        
        let creg = RegisterId::Classical {
            name: "c".to_string(),
            index: None,
        };
        assert_eq!(creg.to_string(), "c");
    }
}

// Made with Bob