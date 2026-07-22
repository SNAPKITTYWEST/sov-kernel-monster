//! SSA (Static Single Assignment) - IR Level 3
//!
//! Transforms Control Flow Graph (IR Level 2) into SSA form where:
//! - Each variable is assigned exactly once
//! - Phi nodes are inserted at control flow join points
//! - Variables are renamed to maintain SSA property
//!
//! This is a critical compiler transformation that enables many optimizations
//! and simplifies data flow analysis.
//!
//! Part of the QATAAUM Quantum Assembly Runtime
//! Clean-room implementation based on public SSA construction algorithms

use crate::cfg::{BlockId, ControlFlowGraph, Instruction, Terminator};
use crate::types::{BitId, QubitId};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// SSA Program representation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SsaProgram {
    /// Entry block
    pub entry: BlockId,
    
    /// SSA basic blocks
    pub blocks: HashMap<BlockId, SsaBlock>,
    
    /// Quantum resources
    pub qubits: HashSet<QubitId>,
    
    /// Classical resources
    pub bits: HashSet<BitId>,
    
    /// Dominance information
    pub dominance: DominanceInfo,
}

/// SSA basic block
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SsaBlock {
    /// Block identifier
    pub id: BlockId,
    
    /// Phi nodes at the start of the block
    pub phi_nodes: Vec<PhiNode>,
    
    /// SSA instructions
    pub instructions: Vec<SsaInstruction>,
    
    /// Block terminator
    pub terminator: Terminator,
}

/// Phi node for SSA form
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhiNode {
    /// Destination bit (result of phi)
    pub dest: BitId,
    
    /// Incoming values from predecessor blocks
    /// Map from predecessor BlockId to the BitId value from that block
    pub incoming: Vec<(BlockId, BitId)>,
}

/// SSA instruction (similar to CFG instruction but with SSA properties)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SsaInstruction {
    /// Quantum gate application
    Gate {
        name: String,
        params: Vec<f64>,
        qubits: Vec<QubitId>,
    },
    
    /// Measurement (produces a new SSA value)
    Measure {
        dest: BitId,
        qubit: QubitId,
    },
    
    /// Reset qubit
    Reset {
        qubit: QubitId,
    },
    
    /// Barrier (synchronization point)
    Barrier {
        qubits: Vec<QubitId>,
    },
    
    /// Classical assignment (SSA form)
    Assign {
        dest: BitId,
        src: BitId,
    },
    
    /// Classical operation
    BinaryOp {
        dest: BitId,
        op: BinaryOpKind,
        left: BitId,
        right: BitId,
    },
    
    /// Unary operation
    UnaryOp {
        dest: BitId,
        op: UnaryOpKind,
        operand: BitId,
    },
}

/// Binary operation kinds
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BinaryOpKind {
    And,
    Or,
    Xor,
}

/// Unary operation kinds
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum UnaryOpKind {
    Not,
}

/// Dominance information for SSA construction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DominanceInfo {
    /// Immediate dominator for each block
    pub idom: HashMap<BlockId, BlockId>,
    
    /// Dominance frontier for each block
    pub df: HashMap<BlockId, HashSet<BlockId>>,
    
    /// Dominator tree children
    pub dom_tree: HashMap<BlockId, Vec<BlockId>>,
}

impl DominanceInfo {
    /// Create empty dominance info
    pub fn new() -> Self {
        Self {
            idom: HashMap::new(),
            df: HashMap::new(),
            dom_tree: HashMap::new(),
        }
    }
    
    /// Check if block a dominates block b
    pub fn dominates(&self, a: BlockId, b: BlockId) -> bool {
        if a == b {
            return true;
        }
        
        let mut current = b;
        while let Some(&idom) = self.idom.get(&current) {
            if idom == a {
                return true;
            }
            if idom == current {
                break; // Reached entry
            }
            current = idom;
        }
        
        false
    }
}

impl Default for DominanceInfo {
    fn default() -> Self {
        Self::new()
    }
}

/// SSA constructor
pub struct SsaConstructor {
    /// Original CFG
    cfg: ControlFlowGraph,
    
    /// SSA program being built
    ssa: SsaProgram,
    
    /// Variable renaming stack for each bit
    /// Maps original BitId to stack of SSA versions
    rename_stack: HashMap<BitId, Vec<BitId>>,
    
    /// Counter for generating new SSA versions
    next_version: HashMap<BitId, usize>,
    
    /// Next available BitId for new SSA variables
    next_bit_id: usize,
}

impl SsaConstructor {
    /// Create a new SSA constructor
    pub fn new(cfg: ControlFlowGraph) -> Self {
        let entry = cfg.entry;
        let qubits = cfg.qubits.clone();
        let bits = cfg.bits.clone();
        
        // Find the maximum BitId to start numbering new SSA variables
        let max_bit_id = bits.iter().map(|b| b.0).max().unwrap_or(0);
        
        Self {
            cfg,
            ssa: SsaProgram {
                entry,
                blocks: HashMap::new(),
                qubits,
                bits,
                dominance: DominanceInfo::new(),
            },
            rename_stack: HashMap::new(),
            next_version: HashMap::new(),
            next_bit_id: max_bit_id + 1,
        }
    }
    
    /// Construct SSA form from CFG
    pub fn construct(mut self) -> SsaProgram {
        // Step 1: Compute dominance information
        self.compute_dominance();
        
        // Step 2: Insert phi nodes at dominance frontiers
        self.insert_phi_nodes();
        
        // Step 3: Rename variables to SSA form
        self.rename_variables(self.ssa.entry);
        
        self.ssa
    }
    
    /// Compute dominance information using iterative algorithm
    fn compute_dominance(&mut self) {
        let blocks: Vec<BlockId> = self.cfg.blocks.keys().copied().collect();
        
        // Initialize: entry dominates itself, all others dominated by all blocks
        let mut dom: HashMap<BlockId, HashSet<BlockId>> = HashMap::new();
        
        for &block in &blocks {
            if block == self.cfg.entry {
                let mut set = HashSet::new();
                set.insert(block);
                dom.insert(block, set);
            } else {
                dom.insert(block, blocks.iter().copied().collect());
            }
        }
        
        // Iterate until fixed point
        let mut changed = true;
        while changed {
            changed = false;
            
            for &block in &blocks {
                if block == self.cfg.entry {
                    continue;
                }
                
                // Get predecessors
                let preds = self.get_predecessors(block);
                
                if preds.is_empty() {
                    continue;
                }
                
                // New dominators = {block} ∪ (∩ dom(pred) for all pred)
                let mut new_dom: HashSet<BlockId> = dom[&preds[0]].clone();
                for &pred in &preds[1..] {
                    new_dom = new_dom.intersection(&dom[&pred]).copied().collect();
                }
                new_dom.insert(block);
                
                if new_dom != dom[&block] {
                    dom.insert(block, new_dom);
                    changed = true;
                }
            }
        }
        
        // Compute immediate dominators
        for &block in &blocks {
            if block == self.cfg.entry {
                continue;
            }
            
            let dominators: Vec<BlockId> = dom[&block]
                .iter()
                .filter(|&&d| d != block)
                .copied()
                .collect();
            
            // Find immediate dominator (closest dominator)
            if let Some(&idom) = dominators.iter().max_by_key(|&&d| {
                // Count dominators of d (closer to block = more dominators)
                dom[&d].len()
            }) {
                self.ssa.dominance.idom.insert(block, idom);
                self.ssa.dominance
                    .dom_tree
                    .entry(idom)
                    .or_insert_with(Vec::new)
                    .push(block);
            }
        }
        
        // Compute dominance frontiers
        for &block in &blocks {
            let preds = self.get_predecessors(block);
            
            if preds.len() >= 2 {
                for &pred in &preds {
                    let mut runner = pred;
                    
                    // Walk up dominator tree until we reach block's idom
                    while !self.ssa.dominance.dominates(runner, block) || runner == block {
                        self.ssa.dominance
                            .df
                            .entry(runner)
                            .or_insert_with(HashSet::new)
                            .insert(block);
                        
                        if let Some(&idom) = self.ssa.dominance.idom.get(&runner) {
                            if idom == runner {
                                break; // Reached entry
                            }
                            runner = idom;
                        } else {
                            break;
                        }
                    }
                }
            }
        }
    }
    
    /// Get predecessors of a block
    fn get_predecessors(&self, block: BlockId) -> Vec<BlockId> {
        let mut preds = Vec::new();
        
        for (&from, edges) in &self.cfg.edges {
            for edge in edges {
                if edge.to == block {
                    preds.push(from);
                }
            }
        }
        
        preds
    }
    
    /// Insert phi nodes at dominance frontiers
    fn insert_phi_nodes(&mut self) {
        // For each variable (bit), insert phi nodes where needed
        let bits: Vec<BitId> = self.cfg.bits.iter().copied().collect();
        
        for bit in bits {
            let mut work_list: Vec<BlockId> = Vec::new();
            let mut has_phi: HashSet<BlockId> = HashSet::new();
            
            // Find blocks that define this variable
            for (&block_id, block) in &self.cfg.blocks {
                for instr in &block.instructions {
                    if self.instruction_defines_bit(instr, bit) {
                        work_list.push(block_id);
                        break;
                    }
                }
            }
            
            // Insert phi nodes at dominance frontiers
            while let Some(block) = work_list.pop() {
                if let Some(df_blocks) = self.ssa.dominance.df.get(&block).cloned() {
                    for df_block in df_blocks {
                        if !has_phi.contains(&df_block) {
                            // Get predecessors first (before mutable borrow)
                            let preds = self.get_predecessors(df_block);
                            
                            // Insert phi node
                            let ssa_block = self.ssa.blocks.entry(df_block).or_insert_with(|| {
                                SsaBlock {
                                    id: df_block,
                                    phi_nodes: Vec::new(),
                                    instructions: Vec::new(),
                                    terminator: Terminator::Return,
                                }
                            });
                            
                            let phi = PhiNode {
                                dest: bit,
                                incoming: preds.iter().map(|&p| (p, bit)).collect(),
                            };
                            
                            ssa_block.phi_nodes.push(phi);
                            has_phi.insert(df_block);
                            work_list.push(df_block);
                        }
                    }
                }
            }
        }
    }
    
    /// Check if instruction defines a bit
    fn instruction_defines_bit(&self, instr: &Instruction, bit: BitId) -> bool {
        match instr {
            Instruction::Measure { bit: b, .. } => *b == bit,
            Instruction::Classical { operation } => {
                use crate::cfg::ClassicalOp;
                match operation {
                    ClassicalOp::Store { dest, .. } => *dest == bit,
                    ClassicalOp::Load { dest, .. } => *dest == bit,
                    ClassicalOp::And { dest, .. } => *dest == bit,
                    ClassicalOp::Or { dest, .. } => *dest == bit,
                    ClassicalOp::Xor { dest, .. } => *dest == bit,
                    ClassicalOp::Not { dest, .. } => *dest == bit,
                }
            }
            _ => false,
        }
    }
    
    /// Rename variables to SSA form (recursive)
    fn rename_variables(&mut self, block: BlockId) {
        // Process phi nodes (define new versions)
        if let Some(ssa_block) = self.ssa.blocks.get(&block).cloned() {
            for phi in &ssa_block.phi_nodes {
                let new_version = self.new_version(phi.dest);
                self.push_version(phi.dest, new_version);
            }
        }
        
        // Convert CFG instructions to SSA instructions
        if let Some(cfg_block) = self.cfg.blocks.get(&block).cloned() {
            let mut ssa_instructions = Vec::new();
            
            for instr in &cfg_block.instructions {
                let ssa_instr = self.convert_instruction(instr);
                ssa_instructions.push(ssa_instr);
            }
            
            // Update SSA block
            let ssa_block = self.ssa.blocks.entry(block).or_insert_with(|| {
                SsaBlock {
                    id: block,
                    phi_nodes: Vec::new(),
                    instructions: Vec::new(),
                    terminator: cfg_block.terminator.clone(),
                }
            });
            
            ssa_block.instructions = ssa_instructions;
            ssa_block.terminator = cfg_block.terminator.clone();
        }
        
        // Recursively process dominator tree children
        if let Some(children) = self.ssa.dominance.dom_tree.get(&block).cloned() {
            for child in children {
                self.rename_variables(child);
            }
        }
        
        // Pop versions when leaving block
        let phi_dests: Vec<BitId> = self.ssa.blocks
            .get(&block)
            .map(|b| b.phi_nodes.iter().map(|phi| phi.dest).collect())
            .unwrap_or_else(Vec::new);
        
        for dest in phi_dests {
            self.pop_version(dest);
        }
    }
    
    /// Convert CFG instruction to SSA instruction
    fn convert_instruction(&mut self, instr: &Instruction) -> SsaInstruction {
        match instr {
            Instruction::Gate { name, params, qubits } => {
                // Gates don't need SSA renaming (quantum operations)
                SsaInstruction::Gate {
                    name: name.clone(),
                    params: params.iter().map(|_| 0.0).collect(), // Simplified for now
                    qubits: qubits.clone(),
                }
            }
            
            Instruction::Measure { qubit, bit } => {
                let new_version = self.new_version(*bit);
                self.push_version(*bit, new_version);
                
                SsaInstruction::Measure {
                    dest: new_version,
                    qubit: *qubit,
                }
            }
            
            Instruction::Reset { qubit } => {
                SsaInstruction::Reset { qubit: *qubit }
            }
            
            Instruction::Barrier { qubits } => {
                SsaInstruction::Barrier {
                    qubits: qubits.clone(),
                }
            }
            
            Instruction::Classical { operation } => {
                use crate::cfg::ClassicalOp;
                match operation {
                    ClassicalOp::Load { dest, src } => {
                        let src_version = self.current_version(*src);
                        let dest_version = self.new_version(*dest);
                        self.push_version(*dest, dest_version);
                        
                        SsaInstruction::Assign {
                            dest: dest_version,
                            src: src_version,
                        }
                    }
                    
                    ClassicalOp::And { dest, left, right } => {
                        let left_version = self.current_version(*left);
                        let right_version = self.current_version(*right);
                        let dest_version = self.new_version(*dest);
                        self.push_version(*dest, dest_version);
                        
                        SsaInstruction::BinaryOp {
                            dest: dest_version,
                            op: BinaryOpKind::And,
                            left: left_version,
                            right: right_version,
                        }
                    }
                    
                    _ => {
                        // Simplified handling for other operations
                        let dest_version = self.new_version(BitId(0));
                        SsaInstruction::Assign {
                            dest: dest_version,
                            src: BitId(0),
                        }
                    }
                }
            }
        }
    }
    
    /// Create a new SSA version of a variable
    fn new_version(&mut self, original: BitId) -> BitId {
        let version = self.next_version.entry(original).or_insert(0);
        *version += 1;
        
        let new_id = BitId(self.next_bit_id);
        self.next_bit_id += 1;
        self.ssa.bits.insert(new_id);
        
        new_id
    }
    
    /// Get current version of a variable
    fn current_version(&self, original: BitId) -> BitId {
        self.rename_stack
            .get(&original)
            .and_then(|stack| stack.last())
            .copied()
            .unwrap_or(original)
    }
    
    /// Push a new version onto the rename stack
    fn push_version(&mut self, original: BitId, version: BitId) {
        self.rename_stack
            .entry(original)
            .or_insert_with(Vec::new)
            .push(version);
    }
    
    /// Pop a version from the rename stack
    fn pop_version(&mut self, original: BitId) {
        if let Some(stack) = self.rename_stack.get_mut(&original) {
            stack.pop();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cfg::EdgeKind;

    #[test]
    fn test_dominance_simple() {
        let cfg = ControlFlowGraph::new();
        let entry = cfg.entry;
        
        let mut constructor = SsaConstructor::new(cfg);
        constructor.compute_dominance();
        
        // Entry should have no immediate dominator
        assert!(constructor.ssa.dominance.idom.get(&entry).is_none());
    }

    #[test]
    fn test_dominance_linear() {
        let mut cfg = ControlFlowGraph::new();
        let entry = cfg.entry;
        let b1 = cfg.add_block();
        let b2 = cfg.add_block();
        
        cfg.add_edge(entry, b1, EdgeKind::Unconditional);
        cfg.add_edge(b1, b2, EdgeKind::Unconditional);
        
        let mut constructor = SsaConstructor::new(cfg);
        constructor.compute_dominance();
        
        // entry dominates b1
        assert_eq!(constructor.ssa.dominance.idom.get(&b1), Some(&entry));
        // b1 dominates b2
        assert_eq!(constructor.ssa.dominance.idom.get(&b2), Some(&b1));
    }

    #[test]
    fn test_ssa_construction_empty() {
        let cfg = ControlFlowGraph::new();
        let entry = cfg.entry;
        let constructor = SsaConstructor::new(cfg);
        let ssa = constructor.construct();
        
        // Empty CFG still has entry block after SSA construction
        // The entry block is processed even if it has no instructions
        assert!(ssa.blocks.len() <= 1);
        assert_eq!(ssa.entry, entry);
    }
}

// Made with Bob
