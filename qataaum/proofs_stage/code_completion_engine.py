#!/usr/bin/env python3
"""
Code Completion Engine
Ranks and suggests proof tactics based on patterns and success rates.
"""

from typing import List, Dict, Tuple, Optional
from collections import defaultdict


class CodeCompletionEngine:
    """Suggest tactics based on pattern frequency and success"""

    def __init__(self):
        self.tactic_success_rate: Dict[str, Tuple[int, int]] = defaultdict(lambda: (0, 0))
        self.tactic_pattern_frequency: Dict[str, Dict[str, int]] = defaultdict(lambda: defaultdict(int))

    def suggest_next_tactic(self, current_proof: str, context: Optional[str] = None) -> List[Tuple[str, float]]:
        """Suggest next tactic ranked by success rate and pattern match"""
        
        last_lines = current_proof.split('\n')[-5:]
        last_text = '\n'.join(last_lines)

        suggestions = {}

        if "intro" not in last_text:
            suggestions["intro"] = 0.8
        if "by_cases" in last_text and "simp" not in last_text:
            suggestions["simp"] = 0.9
        if "mul" in last_text:
            suggestions["ring"] = 0.95
        if "forall" in last_text or "exists" in last_text:
            suggestions["intro"] = 0.85

        result = [(tactic, score) for tactic, score in suggestions.items()]
        result.sort(key=lambda x: x[1], reverse=True)
        return result[:5]

    def suggest_theorem_name(self, description: str) -> List[str]:
        """Suggest theorem names from description"""
        words = description.lower().split()[:4]
        name_parts = [w for w in words if len(w) > 2]
        suggested = '_'.join(name_parts)
        return [suggested, suggested + "_lemma", suggested + "_aux"]

    def suggest_import(self, partial_name: str) -> List[str]:
        """Suggest imports based on partial name"""
        imports = {
            "Moral": "Sovereign.Judge",
            "Verdict": "Sovereign.Judge",
            "Lawful": "Sovereign.Judge",
            "Ring": "Mathlib.Algebra.Ring.Basic",
            "Nat": "Mathlib.Data.Nat.Basic"
        }
        
        result = []
        for key, imp in imports.items():
            if key.lower() in partial_name.lower():
                result.append(imp)
        return result

    def rank_suggestions(self, suggestions: List[str], dev_profile: Optional[Dict] = None) -> List[str]:
        """Rank suggestions based on dev profile preferences"""
        if not dev_profile:
            return suggestions[:5]

        favorite_tactics = [t["tactic"] for t in dev_profile.get("favorite_tactics", [])]
        
        # Sort: favorite tactics first
        ranked = sorted(suggestions, key=lambda x: (x not in favorite_tactics, suggestions.index(x)))
        return ranked[:5]
