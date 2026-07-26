#!/usr/bin/env python3
"""
Metrics & Dashboard - Real-time visualization and analytics
"""

import json
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field, asdict
from datetime import datetime
from collections import defaultdict


@dataclass
class MetricSnapshot:
    timestamp: str
    code_generation_success_rate: float
    editor_suggestion_adoption_rate: float
    time_saved_minutes: float
    most_retrieved_patterns: List[str]
    dev_productivity: Dict[str, float]
    proofs_per_hour: float
    compile_rate: float


class PatternMetricsDashboard:
    """Collect and visualize metrics for the intelligent system"""

    def __init__(self, storage_path: Optional[str] = None):
        self.storage_path = storage_path or "metrics.json"
        self.snapshots: List[MetricSnapshot] = []
        self.generation_attempts: int = 0
        self.generation_successes: int = 0
        self.suggestion_offers: int = 0
        self.suggestion_accepts: int = 0
        self.pattern_retrievals: Dict[str, int] = defaultdict(int)
        self.compile_successes: int = 0
        self.total_compiles: int = 0
        self.load()

    def record_generation_attempt(self, succeeded: bool) -> None:
        """Record proof generation attempt"""
        self.generation_attempts += 1
        if succeeded:
            self.generation_successes += 1

    def record_suggestion_offer(self, accepted: bool) -> None:
        """Record suggestion offered to user"""
        self.suggestion_offers += 1
        if accepted:
            self.suggestion_accepts += 1

    def record_pattern_retrieval(self, pattern_type: str) -> None:
        """Record pattern retrieval"""
        self.pattern_retrievals[pattern_type] += 1

    def record_compile(self, succeeded: bool) -> None:
        """Record compilation attempt"""
        self.total_compiles += 1
        if succeeded:
            self.compile_successes += 1

    def get_current_metrics(self) -> Dict[str, Any]:
        """Get current metrics snapshot"""
        gen_success_rate = (
            self.generation_successes / self.generation_attempts 
            if self.generation_attempts > 0 else 0
        )
        
        suggestion_adoption_rate = (
            self.suggestion_accepts / self.suggestion_offers 
            if self.suggestion_offers > 0 else 0
        )

        compile_rate = (
            self.compile_successes / self.total_compiles 
            if self.total_compiles > 0 else 0
        )

        top_patterns = sorted(
            self.pattern_retrievals.items(), 
            key=lambda x: x[1], 
            reverse=True
        )[:5]

        return {
            "code_generation_success_rate": gen_success_rate,
            "editor_suggestion_adoption_rate": suggestion_adoption_rate,
            "most_retrieved_patterns": [p[0] for p in top_patterns],
            "compile_rate": compile_rate,
            "total_generations": self.generation_attempts,
            "total_suggestions_offered": self.suggestion_offers,
            "suggestion_adoption_count": self.suggestion_accepts,
            "timestamp": datetime.now().isoformat()
        }

    def save_snapshot(self) -> MetricSnapshot:
        """Save current metrics as a snapshot"""
        metrics = self.get_current_metrics()
        snapshot = MetricSnapshot(
            timestamp=metrics["timestamp"],
            code_generation_success_rate=metrics["code_generation_success_rate"],
            editor_suggestion_adoption_rate=metrics["editor_suggestion_adoption_rate"],
            time_saved_minutes=metrics["total_suggestions_offered"] * 2.5,  # Estimate 2.5 min saved per suggestion
            most_retrieved_patterns=metrics["most_retrieved_patterns"],
            dev_productivity={},
            proofs_per_hour=0,
            compile_rate=metrics["compile_rate"]
        )
        self.snapshots.append(snapshot)
        self.save()
        return snapshot

    def get_trend(self, metric_name: str, num_snapshots: int = 10) -> List[float]:
        """Get metric trend over time"""
        recent = self.snapshots[-num_snapshots:]
        
        if metric_name == "generation_success_rate":
            return [s.code_generation_success_rate for s in recent]
        elif metric_name == "adoption_rate":
            return [s.editor_suggestion_adoption_rate for s in recent]
        elif metric_name == "compile_rate":
            return [s.compile_rate for s in recent]
        
        return []

    def export_csv(self, output_path: str) -> None:
        """Export metrics to CSV"""
        import csv
        
        with open(output_path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                "timestamp",
                "generation_success_rate",
                "adoption_rate",
                "compile_rate",
                "time_saved_minutes"
            ])
            
            for snapshot in self.snapshots:
                writer.writerow([
                    snapshot.timestamp,
                    snapshot.code_generation_success_rate,
                    snapshot.editor_suggestion_adoption_rate,
                    snapshot.compile_rate,
                    snapshot.time_saved_minutes
                ])

    def save(self) -> None:
        """Persist metrics to JSON"""
        data = {
            "snapshots": [asdict(s) for s in self.snapshots],
            "current_counters": {
                "generation_attempts": self.generation_attempts,
                "generation_successes": self.generation_successes,
                "suggestion_offers": self.suggestion_offers,
                "suggestion_accepts": self.suggestion_accepts,
                "compile_successes": self.compile_successes,
                "total_compiles": self.total_compiles
            },
            "timestamp": datetime.now().isoformat()
        }
        with open(self.storage_path, 'w') as f:
            json.dump(data, f, indent=2)

    def load(self) -> None:
        """Load metrics from JSON"""
        try:
            with open(self.storage_path, 'r') as f:
                data = json.load(f)
            
            for snap_dict in data.get("snapshots", []):
                snapshot = MetricSnapshot(**snap_dict)
                self.snapshots.append(snapshot)
            
            counters = data.get("current_counters", {})
            self.generation_attempts = counters.get("generation_attempts", 0)
            self.generation_successes = counters.get("generation_successes", 0)
            self.suggestion_offers = counters.get("suggestion_offers", 0)
            self.suggestion_accepts = counters.get("suggestion_accepts", 0)
            self.compile_successes = counters.get("compile_successes", 0)
            self.total_compiles = counters.get("total_compiles", 0)
        except:
            pass
