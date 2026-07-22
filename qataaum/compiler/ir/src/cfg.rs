//! Control Flow Graph (CFG) - IR Level 2
//!
//! Represents the hybrid classical-quantum control flow of a program.
//! Clean-room implementation - not derived from Qiskit

use crate::typed_ast::{TypedExpr, TypedStatement};
use crate::types::{BitId, QubitId};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// Basic block identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct BlockId(pub usize);

impl std::fmt::Display for BlockId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "bb{}", self.0)
    }
}

/// Control Flow Graph
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ControlFlowGraph {
    /// Entry block
    pub entry: BlockId,
    
    /// All basic blocks
    pub blocks: HashMap<BlockId, BasicBlock>,
    
    /// Edges between blocks
    pub edges: HashMap<BlockId, Vec<Edge>>,
    
    /// Quantum resources used
    pub qubits: HashSet<QubitId>,
    
    /// Classical resources used
    pub bits: HashSet<BitId>,
}

/// Basic block
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BasicBlock {
    /// Block identifier
    pub id: BlockId,
    
    /// Instructions in this block
    pub instructions: Vec<Instruction>,
    
    /// Terminator instruction
    pub terminator: Terminator,
}

/// CFG instruction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Instruction {
    /// Quantum gate application
    Gate {
        name: String,
        params: Vec<TypedExpr>,
        qubits: Vec<QubitId>,
    },
    
    /// Measurement
    Measure {
        qubit: QubitId,
        bit: BitId,
    },
    
    /// Reset qubit
    Reset {
        qubit: QubitId,
    },
    
    /// Barrier (synchronization point)
    Barrier {
        qubits: Vec<QubitId>,
    },
    
    /// Classical computation
    Classical {
        operation: ClassicalOp,
    },
}

/// Classical operation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ClassicalOp {
    /// Load from bit
    Load { dest: BitId, src: BitId },
    
    /// Store to bit
    Store { dest: BitId, value: bool },
    
    /// Bitwise AND
    And { dest: BitId, left: BitId, right: BitId },
    
    /// Bitwise OR
    Or { dest: BitId, left: BitId, right: BitId },
    
    /// Bitwise XOR
    Xor { dest: BitId, left: BitId, right: BitId },
    
    /// Bitwise NOT
    Not { dest: BitId, src: BitId },
}

/// Block terminator
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Terminator {
    /// Unconditional jump
    Jump {
        target: BlockId,
    },
    
    /// Conditional branch
    Branch {
        condition: BitId,
        true_target: BlockId,
        false_target: BlockId,
    },
    
    /// Return from function/program
    Return,
}

/// CFG edge
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Edge {
    /// Source block
    pub from: BlockId,
    
    /// Target block
    pub to: BlockId,
    
    /// Edge kind
    pub kind: EdgeKind,
}

/// Edge kind
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EdgeKind {
    /// Unconditional edge
    Unconditional,
    
    /// True branch
    True,
    
    /// False branch
    False,
}

impl ControlFlowGraph {
    /// Create a new empty CFG
    pub fn new() -> Self {
        let entry = BlockId(0);
        let mut blocks = HashMap::new();
        blocks.insert(
            entry,
            BasicBlock {
                id: entry,
                instructions: Vec::new(),
                terminator: Terminator::Return,
            },
        );
        
        Self {
            entry,
            blocks,
            edges: HashMap::new(),
            qubits: HashSet::new(),
            bits: HashSet::new(),
        }
    }
    
    /// Add a new basic block
    pub fn add_block(&mut self) -> BlockId {
        let id = BlockId(self.blocks.len());
        self.blocks.insert(
            id,
            BasicBlock {
                id,
                instructions: Vec::new(),
                terminator: Terminator::Return,
            },
        );
        id
    }
    
    /// Add an edge between blocks
    pub fn add_edge(&mut self, from: BlockId, to: BlockId, kind: EdgeKind) {
        let edge = Edge { from, to, kind };
        self.edges.entry(from).or_insert_with(Vec::new).push(edge);
    }
    
    /// Get a block by ID
    pub fn get_block(&self, id: BlockId) -> Option<&BasicBlock> {
        self.blocks.get(&id)
    }
    
    /// Get a mutable block by ID
    pub fn get_block_mut(&mut self, id: BlockId) -> Option<&mut BasicBlock> {
        self.blocks.get_mut(&id)
    }
    
    /// Get successors of a block
    pub fn successors(&self, block: BlockId) -> Vec<BlockId> {
        self.edges
            .get(&block)
            .map(|edges| edges.iter().map(|e| e.to).collect())
            .unwrap_or_default()
    }
    
    /// Get predecessors of a block
    pub fn predecessors(&self, block: BlockId) -> Vec<BlockId> {
        self.edges
            .iter()
            .filter_map(|(from, edges)| {
                if edges.iter().any(|e| e.to == block) {
                    Some(*from)
                } else {
                    None
                }
            })
            .collect()
    }
    
    /// Verify CFG structure
    pub fn verify(&self) -> Result<(), String> {
        // Check entry block exists
        if !self.blocks.contains_key(&self.entry) {
            return Err("Entry block does not exist".to_string());
        }
        
        // Check all edge targets exist
        for (from, edges) in &self.edges {
            if !self.blocks.contains_key(from) {
                return Err(format!("Edge source block {} does not exist", from));
            }
            for edge in edges {
                if !self.blocks.contains_key(&edge.to) {
                    return Err(format!("Edge target block {} does not exist", edge.to));
                }
            }
        }
        
        // Check terminators match edges
        for (id, block) in &self.blocks {
            match &block.terminator {
                Terminator::Jump { target } => {
                    let edges = self.edges.get(id);
                    if edges.is_none() || edges.unwrap().len() != 1 {
                        return Err(format!("Block {} has Jump but wrong number of edges", id));
                    }
                }
                Terminator::Branch { .. } => {
                    let edges = self.edges.get(id);
                    if edges.is_none() || edges.unwrap().len() != 2 {
                        return Err(format!("Block {} has Branch but wrong number of edges", id));
                    }
                }
                Terminator::Return => {
                    if self.edges.contains_key(id) {
                        return Err(format!("Block {} has Return but has outgoing edges", id));
                    }
                }
            }
        }
        
        Ok(())
    }
}

impl Default for ControlFlowGraph {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cfg_creation() {
        let cfg = ControlFlowGraph::new();
        assert_eq!(cfg.blocks.len(), 1);
        assert_eq!(cfg.entry, BlockId(0));
    }

    #[test]
    fn test_add_block() {
        let mut cfg = ControlFlowGraph::new();
        let b1 = cfg.add_block();
        let b2 = cfg.add_block();
        
        assert_eq!(b1, BlockId(1));
        assert_eq!(b2, BlockId(2));
        assert_eq!(cfg.blocks.len(), 3);
    }

    #[test]
    fn test_add_edge() {
        let mut cfg = ControlFlowGraph::new();
        let b1 = cfg.add_block();
        
        cfg.add_edge(cfg.entry, b1, EdgeKind::Unconditional);
        
        let edges = cfg.edges.get(&cfg.entry).unwrap();
        assert_eq!(edges.len(), 1);
        assert_eq!(edges[0].to, b1);
    }

    #[test]
    fn test_successors() {
        let mut cfg = ControlFlowGraph::new();
        let b1 = cfg.add_block();
        let b2 = cfg.add_block();
        
        cfg.add_edge(cfg.entry, b1, EdgeKind::Unconditional);
        cfg.add_edge(cfg.entry, b2, EdgeKind::Unconditional);
        
        let succs = cfg.successors(cfg.entry);
        assert_eq!(succs.len(), 2);
        assert!(succs.contains(&b1));
        assert!(succs.contains(&b2));
    }

    #[test]
    fn test_predecessors() {
        let mut cfg = ControlFlowGraph::new();
        let b1 = cfg.add_block();
        
        cfg.add_edge(cfg.entry, b1, EdgeKind::Unconditional);
        
        let preds = cfg.predecessors(b1);
        assert_eq!(preds.len(), 1);
        assert_eq!(preds[0], cfg.entry);
    }

    #[test]
    fn test_verify_valid() {
        let mut cfg = ControlFlowGraph::new();
        let b1 = cfg.add_block();
        
        cfg.add_edge(cfg.entry, b1, EdgeKind::Unconditional);
        cfg.get_block_mut(cfg.entry).unwrap().terminator = Terminator::Jump { target: b1 };
        
        assert!(cfg.verify().is_ok());
    }

    #[test]
    fn test_verify_invalid_edge() {
        let mut cfg = ControlFlowGraph::new();
        cfg.add_edge(cfg.entry, BlockId(999), EdgeKind::Unconditional);
        
        assert!(cfg.verify().is_err());
    }
}

// Made with Bob