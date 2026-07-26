#!/usr/bin/env python3
"""
Intelligent LSP Server for GKN Formal Court
Real-time proof assistance via Language Server Protocol.
"""

import json
from typing import List, Dict, Any, Optional
from dataclasses import dataclass


@dataclass
class Position:
    line: int
    character: int


class IntelligentLSPServer:
    """Language Server Protocol for Lean 4 proofs"""

    def __init__(self, proof_index=None, pattern_analyzer=None):
        self.proof_index = proof_index
        self.pattern_analyzer = pattern_analyzer
        self.open_documents: Dict[str, str] = {}
        self.diagnostics: Dict[str, List[Dict]] = {}

    def hover(self, uri: str, position: Position) -> Optional[Dict[str, Any]]:
        """Hover handler: show similar theorems"""
        if uri not in self.open_documents:
            return None

        content = self.open_documents[uri]
        lines = content.split('\n')

        if position.line >= len(lines):
            return None

        line = lines[position.line]
        word = self._extract_word_at(line, position.character)

        if not word or not self.proof_index:
            return None

        results = self.proof_index.retrieve_similar_proofs(word, top_k=3)
        if results:
            hover_content = "**Similar theorems:**\n"
            for ex in results:
                hover_content += f"- `{ex.proof_name}` (complexity={ex.complexity})\n"

            return {"contents": {"kind": "markdown", "value": hover_content}}

        return None

    def completion(self, uri: str, position: Position) -> Optional[List[Dict]]:
        """Autocomplete handler"""
        if uri not in self.open_documents:
            return None

        content = self.open_documents[uri]
        lines = content.split('\n')

        if position.line >= len(lines):
            return None

        line = lines[position.line]
        line_prefix = line[:position.character]

        if line_prefix.rstrip().endswith(" by"):
            tactics = ["intro", "simp", "ring", "rfl", "exact", "apply"]
            return [{"label": t, "kind": 4} for t in tactics]

        return []

    def did_open(self, uri: str, content: str) -> None:
        """Document opened"""
        self.open_documents[uri] = content
        self.validate_document(uri)

    def did_change(self, uri: str, content: str) -> None:
        """Document changed"""
        self.open_documents[uri] = content
        self.validate_document(uri)

    def did_close(self, uri: str) -> None:
        """Document closed"""
        if uri in self.open_documents:
            del self.open_documents[uri]
        if uri in self.diagnostics:
            del self.diagnostics[uri]

    def validate_document(self, uri: str) -> List[Dict]:
        """Validate and return diagnostics"""
        if uri not in self.open_documents:
            return []

        content = self.open_documents[uri]
        diags = []

        if " sorry" in content:
            diags.append({"message": "Unsolved goal (sorry)", "severity": 1})

        if not self._check_balanced(content):
            diags.append({"message": "Unbalanced syntax", "severity": 2})

        self.diagnostics[uri] = diags
        return diags

    def _extract_word_at(self, line: str, character: int) -> Optional[str]:
        """Extract word at cursor position"""
        if character < 0 or character > len(line):
            return None

        start = character - 1
        while start >= 0 and (line[start].isalnum() or line[start] in '_'):
            start -= 1
        start += 1

        end = character
        while end < len(line) and (line[end].isalnum() or line[end] in '_'):
            end += 1

        if start == end:
            return None

        return line[start:end]

    def _check_balanced(self, code: str) -> bool:
        """Check balanced parentheses"""
        stack = []
        pairs = {'(': ')', '[': ']', '{': '}'}
        for char in code:
            if char in pairs:
                stack.append(char)
            elif char in pairs.values():
                if not stack or pairs[stack.pop()] != char:
                    return False
        return len(stack) == 0
