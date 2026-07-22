#!/usr/bin/env python3
"""
Dev Pattern Analyzer - Track and learn developer coding patterns
"""

import json
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field, asdict
from datetime import datetime
from collections import defaultdict


@dataclass
class DevProfile:
    dev_id: str
    total_proofs: int = 0
    avg_proof_length: float = 0.0
    favorite_tactics: List[Dict[str, Any]] = field(default_factory=list)
    common_mistakes: List[str] = field(default_factory=list)
    personalized_suggestions: List[str] = field(default_factory=list)
    success_rate: float = 0.0
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())


class DevPatternAnalyzer:
    """Track and learn developer coding patterns"""

    def __init__(self, storage_path: Optional[str] = None):
        self.storage_path = storage_path or "dev_patterns.json"
        self.dev_profiles: Dict[str, DevProfile] = {}
        self.tactic_history: Dict[str, List[str]] = defaultdict(list)
        self.proof_outcomes: Dict[str, List[bool]] = defaultdict(list)
        self.load()

    def record_proof_attempt(
        self,
        dev_id: str,
        proof_text: str,
        tactics_used: List[str],
        succeeded: bool,
        proof_length: int
    ) -> None:
        """Record a proof attempt for pattern learning"""
        if dev_id not in self.dev_profiles:
            self.dev_profiles[dev_id] = DevProfile(dev_id=dev_id)

        profile = self.dev_profiles[dev_id]
        profile.total_proofs += 1
        profile.avg_proof_length = (profile.avg_proof_length * (profile.total_proofs - 1) + proof_length) / profile.total_proofs

        self.tactic_history[dev_id].extend(tactics_used)
        self.proof_outcomes[dev_id].append(succeeded)
        profile.success_rate = sum(self.proof_outcomes[dev_id]) / len(self.proof_outcomes[dev_id])

        self._update_favorite_tactics(dev_id)
        self._detect_common_mistakes(dev_id, proof_text, succeeded)
        self._generate_suggestions(dev_id)
        self.save()

    def _update_favorite_tactics(self, dev_id: str) -> None:
        """Update favorite tactics for a dev"""
        profile = self.dev_profiles[dev_id]
        tactics = self.tactic_history[dev_id]

        if not tactics:
            return

        tactic_counts = {}
        for tactic in tactics:
            tactic_counts[tactic] = tactic_counts.get(tactic, 0) + 1

        favorite = sorted(tactic_counts.items(), key=lambda x: x[1], reverse=True)[:5]
        profile.favorite_tactics = [
            {"tactic": name, "frequency": count / len(tactics)}
            for name, count in favorite
        ]

    def _detect_common_mistakes(self, dev_id: str, proof_text: str, succeeded: bool) -> None:
        """Detect common mistakes from failed proofs"""
        profile = self.dev_profiles[dev_id]

        if succeeded:
            return

        mistakes = []
        if "MoralAction" in proof_text and "Sovereign.Judge" not in proof_text:
            mistakes.append("forgot_moral_import")
        if proof_text.count("sorry") > 2:
            mistakes.append("too_many_unsolved_goals")

        profile.common_mistakes.extend(mistakes)

    def _generate_suggestions(self, dev_id: str) -> None:
        """Generate personalized suggestions"""
        profile = self.dev_profiles[dev_id]
        suggestions = []

        if profile.favorite_tactics:
            top_tactic = profile.favorite_tactics[0]["tactic"]
            suggestions.append(f"You prefer '{top_tactic}' — try it first")

        if "forgot_moral_import" in profile.common_mistakes:
            suggestions.append("Check: Do you need Sovereign.Judge import?")

        profile.personalized_suggestions = suggestions[:2]

    def get_profile(self, dev_id: str) -> Optional[DevProfile]:
        """Get developer profile"""
        return self.dev_profiles.get(dev_id)

    def get_team_stats(self) -> Dict[str, Any]:
        """Get team-wide statistics"""
        if not self.dev_profiles:
            return {}

        all_tactics = []
        for tactics in self.tactic_history.values():
            all_tactics.extend(tactics)

        tactic_counts = {}
        for tactic in all_tactics:
            tactic_counts[tactic] = tactic_counts.get(tactic, 0) + 1

        team_favorite = sorted(tactic_counts.items(), key=lambda x: x[1], reverse=True)[:5]

        return {
            "total_developers": len(self.dev_profiles),
            "team_favorite_tactics": [{"tactic": t, "count": c} for t, c in team_favorite],
            "avg_success_rate": sum(p.success_rate for p in self.dev_profiles.values()) / len(self.dev_profiles) if self.dev_profiles else 0
        }

    def save(self) -> None:
        """Persist profiles to JSON"""
        data = {
            "profiles": {k: asdict(v) for k, v in self.dev_profiles.items()},
            "timestamp": datetime.now().isoformat()
        }
        with open(self.storage_path, 'w') as f:
            json.dump(data, f, indent=2)

    def load(self) -> None:
        """Load profiles from JSON"""
        try:
            with open(self.storage_path, 'r') as f:
                data = json.load(f)
            for name, profile_dict in data.get("profiles", {}).items():
                self.dev_profiles[name] = DevProfile(**profile_dict)
        except:
            pass
