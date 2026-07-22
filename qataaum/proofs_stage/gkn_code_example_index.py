#!/usr/bin/env python3
"""
GKN Formal Court — Code Example Index System
Retrieves, indexes, and searches theorem proofs by semantic similarity.

Module: gkn_code_example_index.py
Size: 500 lines
Purpose: Extract, embed, and retrieve proof patterns from Lean 4 source files

Architecture:
- ProofExample: Named proof with metadata (pattern type, tactics, complexity)
- VectorStore: FAISS-based semantic search backed by embeddings
- ProofIndex: Main API for indexing and retrieval
- Patterns: "scaling_law", "induction", "ring_tactic", "lawfulness", "bridge"

Example usage:
    index = ProofIndex()
    index.index_theorem_proof("I4_homogeneous", proof_text, pattern_type="scaling_law")
    results = index.retrieve_similar_proofs("prove scaling under scalar multiplication", top_k=3)
"""

import json
import hashlib
import re
from dataclasses import dataclass, asdict, field
from typing import List, Dict, Optional, Tuple, Any
from pathlib import Path
from datetime import datetime
import logging

# Minimal embedding simulation — in production, use sentence-transformers or OpenAI embeddings
class SimpleEmbedder:
    """Lightweight embedding for semantic similarity (production: use sentence-transformers)"""

    def embed(self, text: str, dim: int = 384) -> List[float]:
        """
        Generate a simple embedding by hashing and expanding.
        Production: use SentenceTransformer('all-MiniLM-L6-v2') or similar.
        """
        # Hash the text to get deterministic pseudo-randomness
        hash_obj = hashlib.sha256(text.encode())
        hash_int = int(hash_obj.hexdigest(), 16)

        # Generate dim-dimensional embedding using hash bits
        embedding = []
        for i in range(dim):
            # Use different bits of the hash for each dimension
            bit_pos = (hash_int >> (i % 256)) & 0xFF
            embedding.append((bit_pos - 128) / 128.0)  # Normalize to [-1, 1]

        return embedding


class VectorStore:
    """In-memory vector store using cosine similarity (FAISS in production)"""

    def __init__(self, embedding_dim: int = 384):
        self.embedder = SimpleEmbedder()
        self.embedding_dim = embedding_dim
        self.vectors: List[List[float]] = []
        self.ids: List[str] = []

    def add(self, vector_id: str, text: str) -> None:
        """Add a text to the store by computing and storing its embedding"""
        embedding = self.embedder.embed(text, self.embedding_dim)
        self.vectors.append(embedding)
        self.ids.append(vector_id)

    def search(self, query_text: str, top_k: int = 5) -> List[Tuple[str, float]]:
        """
        Search by query text, return top_k results with similarity scores.
        Returns: [(vector_id, similarity_score), ...]
        """
        if not self.vectors:
            return []

        query_vector = self.embedder.embed(query_text, self.embedding_dim)

        # Compute cosine similarity with all stored vectors
        similarities = []
        for i, stored_vector in enumerate(self.vectors):
            sim = self._cosine_similarity(query_vector, stored_vector)
            similarities.append((self.ids[i], sim))

        # Sort by similarity descending
        similarities.sort(key=lambda x: x[1], reverse=True)
        return similarities[:top_k]

    @staticmethod
    def _cosine_similarity(v1: List[float], v2: List[float]) -> float:
        """Compute cosine similarity between two vectors"""
        dot_product = sum(a * b for a, b in zip(v1, v2))
        mag_v1 = sum(a ** 2 for a in v1) ** 0.5
        mag_v2 = sum(b ** 2 for b in v2) ** 0.5

        if mag_v1 == 0 or mag_v2 == 0:
            return 0.0
        return dot_product / (mag_v1 * mag_v2)


@dataclass
class ProofExample:
    """A single proof example with metadata and embedding"""
    proof_name: str
    pattern_type: str  # "scaling_law", "induction", "ring_tactic", "lawfulness", "bridge"
    proof_text: str
    tactics_used: List[str]
    complexity: int  # 1 (trivial) to 5 (very complex)
    dependencies: int  # Number of lemmas/definitions required
    source_file: str
    line_start: int
    line_end: int
    embedding: List[float] = field(default_factory=list)
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())

    def to_dict(self) -> Dict[str, Any]:
        """Serialize to dict for JSON storage"""
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict[str, Any]) -> "ProofExample":
        """Deserialize from dict"""
        return cls(**d)


class ProofIndex:
    """Main API for indexing and retrieving proof examples"""

    def __init__(self, storage_path: Optional[str] = None):
        self.storage_path = Path(storage_path or "gkn_proof_index.json")
        self.vector_store = VectorStore(embedding_dim=384)
        self.examples: Dict[str, ProofExample] = {}
        self.pattern_index: Dict[str, List[str]] = {}  # pattern_type -> [proof_names]
        self._load()

    def index_theorem_proof(
        self,
        proof_name: str,
        proof_text: str,
        pattern_type: str,
        tactics_used: List[str],
        complexity: int = 3,
        dependencies: int = 1,
        source_file: str = "unknown.lean",
        line_start: int = 0,
        line_end: int = 0
    ) -> ProofExample:
        """
        Index a theorem proof with all metadata.

        Args:
            proof_name: Name of the theorem
            proof_text: Full proof code
            pattern_type: Category (scaling_law, induction, ring_tactic, lawfulness, bridge)
            tactics_used: List of tactics used (simp, ring, intro, etc.)
            complexity: 1-5 scale
            dependencies: Number of imported definitions
            source_file: Path to Lean file
            line_start: First line in file
            line_end: Last line in file

        Returns:
            ProofExample with embedding computed
        """
        # Compute embedding
        embedder = SimpleEmbedder()
        embedding = embedder.embed(proof_text, 384)

        example = ProofExample(
            proof_name=proof_name,
            pattern_type=pattern_type,
            proof_text=proof_text,
            tactics_used=tactics_used,
            complexity=complexity,
            dependencies=dependencies,
            source_file=source_file,
            line_start=line_start,
            line_end=line_end,
            embedding=embedding
        )

        self.examples[proof_name] = example
        self.vector_store.add(proof_name, proof_text)

        # Index by pattern type
        if pattern_type not in self.pattern_index:
            self.pattern_index[pattern_type] = []
        if proof_name not in self.pattern_index[pattern_type]:
            self.pattern_index[pattern_type].append(proof_name)

        self._save()
        return example

    def retrieve_similar_proofs(
        self,
        query: str,
        top_k: int = 5,
        pattern_filter: Optional[str] = None
    ) -> List[ProofExample]:
        """
        Retrieve proofs similar to a query.

        Args:
            query: Natural language description or proof snippet
            top_k: Number of results to return
            pattern_filter: Optional pattern type to filter by

        Returns:
            List of ProofExample, sorted by relevance (highest first)
        """
        # Search vector store
        results = self.vector_store.search(query, top_k=top_k * 2)  # Get extra to filter

        retrieved = []
        for proof_name, similarity in results:
            if proof_name not in self.examples:
                continue

            example = self.examples[proof_name]
            if pattern_filter and example.pattern_type != pattern_filter:
                continue

            retrieved.append(example)
            if len(retrieved) >= top_k:
                break

        return retrieved

    def retrieve_pattern(self, pattern_type: str) -> List[ProofExample]:
        """
        Retrieve all proofs matching a specific pattern type.

        Args:
            pattern_type: One of: scaling_law, induction, ring_tactic, lawfulness, bridge

        Returns:
            List of ProofExample matching the pattern
        """
        if pattern_type not in self.pattern_index:
            return []

        proof_names = self.pattern_index[pattern_type]
        return [self.examples[name] for name in proof_names if name in self.examples]

    def extract_tactics_from_text(self, proof_text: str) -> List[str]:
        """
        Parse a Lean proof to extract used tactics.
        Example: "by intro x; simp; ring" -> ["intro", "simp", "ring"]
        """
        # Pattern: match Lean tactics
        tactic_pattern = r'\b(intro|simp|ring|rfl|cases|induction|exact|apply|unfold|by_cases|have|show)\b'
        matches = re.findall(tactic_pattern, proof_text, re.IGNORECASE)
        return list(set(matches))  # Unique tactics

    def analyze_proof_complexity(self, proof_text: str) -> int:
        """
        Estimate proof complexity (1-5 scale) based on:
        - Number of lines
        - Number of tactics
        - Nesting depth
        """
        lines = len(proof_text.strip().split('\n'))
        tactics = self.extract_tactics_from_text(proof_text)
        nesting = proof_text.count('(') + proof_text.count('begin')

        # Simple heuristic
        score = min(5, 1 + (lines // 5) + (len(tactics) // 3) + (nesting // 5))
        return max(1, score)

    def auto_index_file(self, lean_file_path: str) -> List[ProofExample]:
        """
        Automatically extract and index all theorems from a Lean file.

        Returns:
            List of indexed ProofExample
        """
        indexed = []
        try:
            with open(lean_file_path, 'r') as f:
                content = f.read()
                lines = content.split('\n')

            # Pattern: match "theorem <name> ... := by" or "lemma <name> ... := by"
            theorem_pattern = r'(theorem|lemma)\s+(\w+)[^:]*:=\s*by\s*(.+?)(?=\n(?:theorem|lemma|end|def|inductive)\b|\Z)'
            matches = re.finditer(theorem_pattern, content, re.DOTALL)

            for match in matches:
                keyword, name, proof_body = match.groups()
                proof_text = f"{keyword} {name} := by {proof_body[:200]}"  # Truncate for storage

                tactics = self.extract_tactics_from_text(proof_body)
                complexity = self.analyze_proof_complexity(proof_body)

                # Try to infer pattern type from proof content
                pattern_type = self._infer_pattern_type(proof_body)

                # Calculate line numbers
                text_before = content[:match.start()]
                line_start = text_before.count('\n') + 1
                line_end = line_start + proof_text.count('\n')

                example = self.index_theorem_proof(
                    proof_name=name,
                    proof_text=proof_text,
                    pattern_type=pattern_type,
                    tactics_used=tactics,
                    complexity=complexity,
                    dependencies=1,  # TODO: parse imports
                    source_file=lean_file_path,
                    line_start=line_start,
                    line_end=line_end
                )
                indexed.append(example)

        except Exception as e:
            logging.warning(f"Failed to auto-index {lean_file_path}: {e}")

        return indexed

    def _infer_pattern_type(self, proof_text: str) -> str:
        """Heuristically infer the pattern type from proof content"""
        if 'induction' in proof_text:
            return 'induction'
        elif 'ring' in proof_text:
            return 'ring_tactic'
        elif 'lawful' in proof_text or 'judge' in proof_text:
            return 'lawfulness'
        elif 'moral' in proof_text or 'verdict' in proof_text:
            return 'bridge'
        elif any(word in proof_text for word in ['scale', 'homogeneous', 'scalar']):
            return 'scaling_law'
        else:
            return 'general'

    def _save(self) -> None:
        """Persist index to JSON"""
        data = {
            'examples': {name: ex.to_dict() for name, ex in self.examples.items()},
            'pattern_index': self.pattern_index,
            'timestamp': datetime.now().isoformat()
        }
        with open(self.storage_path, 'w') as f:
            json.dump(data, f, indent=2)

    def _load(self) -> None:
        """Load index from JSON if it exists"""
        if not self.storage_path.exists():
            return

        try:
            with open(self.storage_path, 'r') as f:
                data = json.load(f)

            for name, ex_dict in data.get('examples', {}).items():
                self.examples[name] = ProofExample.from_dict(ex_dict)
                self.vector_store.add(name, ex_dict['proof_text'])

            self.pattern_index = data.get('pattern_index', {})
        except Exception as e:
            logging.warning(f"Failed to load index: {e}")

    def get_stats(self) -> Dict[str, Any]:
        """Return index statistics"""
        return {
            'total_proofs': len(self.examples),
            'pattern_types': {ptype: len(proofs) for ptype, proofs in self.pattern_index.items()},
            'avg_complexity': sum(ex.complexity for ex in self.examples.values()) / max(1, len(self.examples)),
            'avg_tactics_per_proof': sum(len(ex.tactics_used) for ex in self.examples.values()) / max(1, len(self.examples))
        }


# ── CLI Integration ──────────────────────────────────────────────────────────

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    # Example: Create and populate index
    index = ProofIndex("gkn_proof_index.json")

    # Example 1: Manual indexing
    proof_1 = """theorem approved_is_lawful (a : MoralAction) :
        judge a = .approve → lawful a = true := by
      intro h
      unfold judge at h
      by_cases hl : lawful a = true
      · exact hl
      · simp [hl] at h"""

    index.index_theorem_proof(
        proof_name="approved_is_lawful",
        proof_text=proof_1,
        pattern_type="lawfulness",
        tactics_used=["intro", "unfold", "by_cases", "simp"],
        complexity=2,
        dependencies=2,
        source_file="SovereignJudge.lean",
        line_start=180,
        line_end=186
    )

    # Example 2: Retrieve similar proofs
    results = index.retrieve_similar_proofs("how do I prove lawfulness?", top_k=3)
    print(f"\nRetrieved {len(results)} similar proofs:")
    for ex in results:
        print(f"  - {ex.proof_name} ({ex.pattern_type}): tactics={ex.tactics_used}, complexity={ex.complexity}")

    # Example 3: Retrieve by pattern
    lawfulness_proofs = index.retrieve_pattern("lawfulness")
    print(f"\nAll lawfulness proofs: {[ex.proof_name for ex in lawfulness_proofs]}")

    # Example 4: Stats
    print(f"\nIndex stats: {json.dumps(index.get_stats(), indent=2)}")
