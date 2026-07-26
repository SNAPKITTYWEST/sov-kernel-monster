#!/usr/bin/env python3
"""
FORGE Code Generator - Extended for GKN Formal Court
Generates new theorems and proofs using retrieved examples and templates.
"""

import json
import re
from dataclasses import dataclass
from typing import List, Dict, Optional, Tuple, Any
from datetime import datetime


@dataclass
class ProofTemplate:
    """A reusable proof skeleton"""
    name: str
    pattern_type: str
    template: str
    tactics: List[str]
    complexity: str
    example_proof_name: Optional[str] = None


class TemplateManager:
    """Load, render, and manage proof templates"""

    def __init__(self):
        self.templates: Dict[str, ProofTemplate] = {}
        self._init_builtin_templates()

    def _init_builtin_templates(self) -> None:
        """Initialize built-in templates for common patterns"""

        self.templates['lawfulness_basic'] = ProofTemplate(
            name='lawfulness_basic',
            pattern_type='lawfulness',
            template="""theorem {name} (a : MoralAction) :
    {statement} := by
  intro h
  unfold {definition} at h
  by_cases h_check : {predicate}
  . {success_case}
  . {failure_case}""",
            tactics=['intro', 'unfold', 'by_cases', 'simp'],
            complexity='easy',
            example_proof_name='approved_is_lawful'
        )

        self.templates['induction_nat'] = ProofTemplate(
            name='induction_nat',
            pattern_type='induction',
            template="""theorem {name} {params} : {statement} := by
  induction {var} with
  | zero => {base_case}
  | succ n ih => {inductive_case}""",
            tactics=['induction', 'cases'],
            complexity='medium',
            example_proof_name=None
        )

        self.templates['ring_closure'] = ProofTemplate(
            name='ring_closure',
            pattern_type='ring_tactic',
            template="""theorem {name} {params} : {statement} := by
  intro {vars}
  simp [{definitions}]
  ring""",
            tactics=['intro', 'simp', 'ring'],
            complexity='easy',
            example_proof_name=None
        )

    def render_template(self, template_name: str, context: Dict[str, str]) -> str:
        if template_name not in self.templates:
            raise ValueError(f"Unknown template: {template_name}")

        template = self.templates[template_name]
        result = template.template

        for key, value in context.items():
            result = result.replace(f"{{{key}}}", value)

        return result

    def get_template_by_pattern(self, pattern_type: str) -> Optional[ProofTemplate]:
        for template in self.templates.values():
            if template.pattern_type == pattern_type:
                return template
        return None

    def list_templates(self) -> List[ProofTemplate]:
        return list(self.templates.values())


class ForgeCodeGenerator:
    """Main API for generating Lean 4 proofs"""

    def __init__(self, proof_index=None):
        self.proof_index = proof_index
        self.template_manager = TemplateManager()
        self.generation_log: List[Dict[str, Any]] = []

    def generate_theorem(self, description: str, pattern_type: Optional[str] = None) -> str:
        theorem_name = self._extract_theorem_name(description)
        theorem_statement = self._extract_statement(description)

        if not pattern_type:
            pattern_type = self._infer_pattern_type(description)

        template = self.template_manager.get_template_by_pattern(pattern_type)
        if not template:
            template = self.template_manager.get_template_by_pattern('lawfulness_basic')

        context = {
            'name': theorem_name,
            'statement': theorem_statement,
            'params': '',
            'definition': 'unknown',
            'predicate': 'true'
        }

        skeleton = self.template_manager.render_template(template.name, context)
        return skeleton

    def validate_against_gkn(self, generated_code: str) -> Tuple[bool, List[str]]:
        errors = []
        if "sorry" in generated_code:
            errors.append("GKN-001: Unsolved goals (sorry remains)")
        if not self._check_balanced_syntax(generated_code):
            errors.append("GKN-002: Unbalanced syntax")
        if not re.search(r'theorem|lemma', generated_code):
            errors.append("GKN-003: Missing theorem or lemma")
        return len(errors) == 0, errors

    def _extract_theorem_name(self, description: str) -> str:
        match = re.search(r'"(\w+)"', description)
        if match:
            return match.group(1)
        words = description.lower().split()[:3]
        name = '_'.join([w for w in words if len(w) > 2])
        return name or "theorem_auto"

    def _extract_statement(self, description: str) -> str:
        if ":" in description:
            return description.split(":")[-1].strip()
        return "true"

    def _infer_pattern_type(self, description: str) -> str:
        description_lower = description.lower()
        if any(word in description_lower for word in ['induct', 'recursive', 'case']):
            return 'induction'
        elif any(word in description_lower for word in ['ring', 'algebraic', 'multiply']):
            return 'ring_tactic'
        else:
            return 'lawfulness'

    def _check_balanced_syntax(self, code: str) -> bool:
        stack = []
        pairs = {'(': ')', '[': ']', '{': '}'}
        for char in code:
            if char in pairs:
                stack.append(char)
            elif char in pairs.values():
                if not stack or pairs[stack.pop()] != char:
                    return False
        return len(stack) == 0

    def get_generation_stats(self) -> Dict[str, Any]:
        return {'total_generations': len(self.generation_log)}
