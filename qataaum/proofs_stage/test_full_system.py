#!/usr/bin/env python3
"""Test suite for GKN Formal Court system"""

import sys
from datetime import datetime


class GKNTestSuite:
    """Full integration test suite"""

    def __init__(self):
        self.test_results = []
        self.passed = 0
        self.failed = 0

    def test_proof_index(self):
        """Test 1: Code Example Index (System 1)"""
        try:
            from gkn_code_example_index import ProofIndex
            index = ProofIndex("test_index.json")
            proof = "theorem test := by intro; simp; exact h"
            ex = index.index_theorem_proof(
                proof_name="test_proof",
                proof_text=proof,
                pattern_type="lawfulness",
                tactics_used=["intro", "simp", "exact"],
                complexity=2,
                dependencies=1,
                source_file="test.lean"
            )
            assert ex.proof_name == "test_proof"
            self.passed += 1
            self.test_results.append(("System 1: Proof Index", "PASS"))
        except Exception as e:
            self.failed += 1
            self.test_results.append(("System 1: Proof Index", "FAIL"))

    def test_forge_generator(self):
        """Test 2: FORGE Code Generator (System 2)"""
        try:
            from forge_code_generator import ForgeCodeGenerator
            forge = ForgeCodeGenerator()
            skeleton = forge.generate_theorem("Prove lawful", pattern_type="lawfulness")
            assert "theorem" in skeleton or "by" in skeleton
            is_valid, errors = forge.validate_against_gkn(skeleton)
            assert isinstance(is_valid, bool)
            self.passed += 1
            self.test_results.append(("System 2: FORGE Generator", "PASS"))
        except Exception as e:
            self.failed += 1
            self.test_results.append(("System 2: FORGE Generator", "FAIL"))

    def test_lsp_server(self):
        """Test 3: Intelligent LSP Server (System 3)"""
        try:
            from intelligent_editor_lsp import IntelligentLSPServer
            lsp = IntelligentLSPServer()
            uri = "file:///test.lean"
            content = "theorem foo := by intro; simp"
            lsp.did_open(uri, content)
            assert uri in lsp.open_documents
            diags = lsp.validate_document(uri)
            assert isinstance(diags, list)
            lsp.did_close(uri)
            assert uri not in lsp.open_documents
            self.passed += 1
            self.test_results.append(("System 3: LSP Server", "PASS"))
        except Exception as e:
            self.failed += 1
            self.test_results.append(("System 3: LSP Server", "FAIL"))

    def test_pattern_analyzer(self):
        """Test 4: Dev Pattern Analyzer (System 4)"""
        try:
            from dev_pattern_analyzer import DevPatternAnalyzer
            analyzer = DevPatternAnalyzer("test_patterns.json")
            analyzer.record_proof_attempt(
                dev_id="dev_alice",
                proof_text="theorem test := by intro; simp; ring",
                tactics_used=["intro", "simp", "ring"],
                succeeded=True,
                proof_length=3
            )
            profile = analyzer.get_profile("dev_alice")
            assert profile is not None
            assert profile.dev_id == "dev_alice"
            self.passed += 1
            self.test_results.append(("System 4: Pattern Analyzer", "PASS"))
        except Exception as e:
            self.failed += 1
            self.test_results.append(("System 4: Pattern Analyzer", "FAIL"))

    def test_completion_engine(self):
        """Test 5: Code Completion Engine (System 5)"""
        try:
            from code_completion_engine import CodeCompletionEngine
            engine = CodeCompletionEngine()
            proof = "theorem foo := by intro"
            suggestions = engine.suggest_next_tactic(proof)
            # System may return 0 suggestions legitimately
            assert isinstance(suggestions, list)
            names = engine.suggest_theorem_name("Prove something")
            assert isinstance(names, list) and len(names) > 0
            self.passed += 1
            self.test_results.append(("System 5: Completion Engine", "PASS"))
        except Exception as e:
            self.failed += 1
            self.test_results.append(("System 5: Completion Engine", "FAIL"))

    def test_metrics_dashboard(self):
        """Test 7: Metrics Dashboard (System 7)"""
        try:
            from pattern_metrics_dashboard import PatternMetricsDashboard
            dashboard = PatternMetricsDashboard("test_metrics.json")
            dashboard.record_generation_attempt(succeeded=True)
            dashboard.record_suggestion_offer(accepted=True)
            dashboard.record_compile(succeeded=True)
            metrics = dashboard.get_current_metrics()
            assert metrics["code_generation_success_rate"] == 1.0
            self.passed += 1
            self.test_results.append(("System 7: Metrics Dashboard", "PASS"))
        except Exception as e:
            self.failed += 1
            self.test_results.append(("System 7: Metrics Dashboard", "FAIL"))

    def test_integration(self):
        """Test 8: Full Integration (All 7 + System)"""
        try:
            from gkn_formal_court_system import GKNFormalCourtSystem
            court = GKNFormalCourtSystem()
            result = court.generate_proof("test_user", "Prove lawfulness", pattern_type="lawfulness")
            assert result is not None
            assert "generated_code" in result
            assert "is_valid" in result
            self.passed += 1
            self.test_results.append(("System 8: Full Integration", "PASS"))
        except Exception as e:
            self.failed += 1
            self.test_results.append(("System 8: Full Integration", "FAIL"))

    def run_all_tests(self):
        print("\n" + "="*70)
        print("GKN FORMAL COURT - INTEGRATION TEST SUITE")
        print("="*70 + "\n")
        
        self.test_proof_index()
        self.test_forge_generator()
        self.test_lsp_server()
        self.test_pattern_analyzer()
        self.test_completion_engine()
        self.test_metrics_dashboard()
        self.test_integration()
        
        print("TEST RESULTS:")
        print("-"*70)
        for test_name, result in self.test_results:
            status = "[PASS]" if "PASS" in result else "[FAIL]"
            print(f"{status} {test_name:40} {result}")
        print()
        print(f"SUMMARY: {self.passed} passed, {self.failed} failed")
        print("="*70 + "\n")
        
        return self.failed == 0


if __name__ == "__main__":
    suite = GKNTestSuite()
    success = suite.run_all_tests()
    sys.exit(0 if success else 1)
