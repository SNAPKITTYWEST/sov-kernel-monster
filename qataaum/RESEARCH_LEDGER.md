# QATAAUM Quantum Assembly Runtime - Research Ledger

**Project:** QATAAUM AS400-PULSE-MONAD  
**Version:** 1.0  
**Ledger Initialized:** 2026-07-21  
**Last Updated:** 2026-07-21

## Purpose

This ledger records every external public source consulted during the research, design, and implementation of the QATAAUM Quantum Assembly Runtime. It serves as evidence of clean-room development practices and ensures all knowledge is derived from legitimate public sources.

## Governing Principle

**PUBLIC SPECIFICATION IN. INDEPENDENT IMPLEMENTATION OUT. EVIDENCE OR SILENCE.**

## Legal Framework

All sources listed here must be:
- Publicly available without authentication
- Licensed for research and reference
- Official standards, academic publications, or open-source projects
- Not proprietary IBM internal documentation
- Not reverse-engineered or leaked materials

---

## Research Sources

### OpenQASM Standards

| Source | Type | License | Date Accessed | URL | Concepts Derived |
|--------|------|---------|---------------|-----|------------------|
| OpenQASM 2.0 Specification | Standard | Apache 2.0 | 2026-07-21 | https://github.com/Qiskit/openqasm/tree/OpenQASM2.x | Gate syntax, qubit declarations, measurement semantics |
| OpenQASM 3.0 Specification | Standard | Apache 2.0 | 2026-07-21 | https://openqasm.com/ | Classical types, control flow, timing, pulse grammar |
| OpenQASM 3.1 Updates | Standard | Apache 2.0 | 2026-07-21 | https://openqasm.com/ | Minor revisions and clarifications |

### IBM Quantum Public Documentation

| Source | Type | License | Date Accessed | URL | Concepts Derived |
|--------|------|---------|---------------|-----|------------------|
| IBM Quantum Documentation | Public Docs | IBM Terms | 2026-07-21 | https://docs.quantum.ibm.com/ | Processor families, public API concepts |
| IBM Quantum Composer | Public Tool | IBM Terms | 2026-07-21 | https://quantum-computing.ibm.com/ | Circuit visualization, gate sets |

### Qiskit Open Source (Interface Study Only)

| Source | Type | License | Date Accessed | URL | Concepts Derived |
|--------|------|---------|---------------|-----|------------------|
| Qiskit GitHub Repository | Open Source | Apache 2.0 | 2026-07-21 | https://github.com/Qiskit/qiskit | Public API patterns, primitive abstractions |
| Qiskit Runtime Documentation | Public Docs | Apache 2.0 | 2026-07-21 | https://docs.quantum.ibm.com/api/qiskit-ibm-runtime | Sampler/Estimator interfaces, session model |

**IMPORTANT:** Qiskit source code is studied only to understand public interfaces and standards. Implementation is independently designed and written.

### Academic Publications

| Source | Type | License | Date Accessed | URL | Concepts Derived |
|--------|------|---------|---------------|-----|------------------|
| *To be added as research progresses* | | | | | |

### Compiler and IR Research

| Source | Type | License | Date Accessed | URL | Concepts Derived |
|--------|------|---------|---------------|-----|------------------|
| MLIR Documentation | Public Docs | Apache 2.0 | 2026-07-21 | https://mlir.llvm.org/ | Dialect design, region concepts, pass infrastructure |
| LLVM Documentation | Public Docs | Apache 2.0 | 2026-07-21 | https://llvm.org/docs/ | SSA form, optimization passes, code generation |

### IBM i and RPG Research

| Source | Type | License | Date Accessed | URL | Concepts Derived |
|--------|------|---------|---------------|-----|------------------|
| IBM i Documentation | Public Docs | IBM Terms | 2026-07-21 | https://www.ibm.com/docs/en/i | ILE concepts, service programs, journaling |
| RPG Reference | Public Docs | IBM Terms | 2026-07-21 | https://www.ibm.com/docs/en/i/7.5?topic=languages-ile-rpg | Free-form syntax, data structures, procedures |

### Formal Methods

| Source | Type | License | Date Accessed | URL | Concepts Derived |
|--------|------|---------|---------------|-----|------------------|
| Liquid Haskell Documentation | Public Docs | BSD-3 | 2026-07-21 | https://ucsd-progsys.github.io/liquidhaskell/ | Refinement types, SMT integration |
| Lean 4 Documentation | Public Docs | Apache 2.0 | 2026-07-21 | https://lean-lang.org/ | Theorem proving, dependent types, tactics |

### Quantum Computing Theory

| Source | Type | License | Date Accessed | URL | Concepts Derived |
|--------|------|---------|---------------|-----|------------------|
| Nielsen & Chuang (public excerpts) | Textbook | Academic | 2026-07-21 | Various | Quantum gates, measurement, entanglement |

---

## Processor Research

### IBM Quantum Processors (Public Information Only)

| Processor | Status | Qubits | Topology | Public Source | Date |
|-----------|--------|--------|----------|---------------|------|
| Eagle r1 | Historical | 127 | Heavy-hex | IBM Quantum Blog | 2021 |
| Osprey | Historical | 433 | Heavy-hex | IBM Quantum Blog | 2022 |
| Condor | Historical | 1121 | Heavy-hex | IBM Quantum Blog | 2023 |
| Heron r1 | Public | 133 | Heavy-hex | IBM Quantum Docs | 2023 |
| Heron r2 | Public | 133 | Heavy-hex | IBM Quantum Docs | 2024 |
| Heron r3 | Public | 133 | Heavy-hex | IBM Quantum Docs | 2025 |
| Nighthawk r1 | Public | 120 | TBD | IBM Quantum Docs | 2025-12 |

**Note:** Any Heron r4 or Nighthawk r2+ references are explicitly hypothetical modeling exercises unless publicly documented.

---

## Original Contributions (Not Derived from External Sources)

### MetaQASM-4 Language Design
- **Status:** Original experimental language
- **Not:** OpenQASM 4 (which does not exist as a public standard)
- **Purpose:** Extend OpenQASM 3 concepts with typed effects, monadic execution, refinement constraints

### ShadowRPG-Q Control Language
- **Status:** Original project-specific language
- **Inspiration:** IBM i operational patterns, fixed-format business languages
- **Not:** An IBM product or proprietary IBM grammar

### QATAAUM IR Family
- **Status:** Original intermediate representation design
- **Levels:** 9 IR levels from source AST to executable package
- **Purpose:** Clean-room compiler infrastructure

### Hybrid FSM Model
- **Status:** Original state machine design
- **Purpose:** Coordinate classical IBM i control with quantum execution states

---

## Prohibited Sources

The following are **NEVER** consulted:
- IBM proprietary source code not publicly released
- Internal IBM APIs or documentation
- Confidential processor specifications
- Private calibration data
- Leaked materials
- Reverse-engineered implementations
- Qiskit implementation details beyond public interfaces

---

## Research Methodology

1. **Public First:** Only consult publicly available sources
2. **Document Everything:** Record source, date, license, and concepts
3. **Independent Design:** Use public knowledge to inform original design
4. **No Copying:** Never copy proprietary code or internal details
5. **Verify Licensing:** Ensure all sources permit research use

---

## Verification

This ledger is maintained throughout the project lifecycle. Any external knowledge claim must be traceable to an entry in this ledger.

**Ledger Maintainer:** ROLE-SYSTEM-ARCHITECT  
**Review Frequency:** After each research phase  
**Audit Trail:** Git commit history

---

## Appendix: Research Questions Log

### Open Questions
- [ ] What is the exact connectivity graph for Nighthawk r1?
- [ ] What are the public timing constraints for Heron r3?
- [ ] What pulse-level access is available through public APIs?

### Resolved Questions
- *To be populated as research progresses*

---

**End of Research Ledger**  
*This document is continuously updated throughout the project.*