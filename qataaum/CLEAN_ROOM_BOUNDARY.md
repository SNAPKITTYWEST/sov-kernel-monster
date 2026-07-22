# QATAAUM Quantum Assembly Runtime - Clean Room Boundary

**Project:** QATAAUM AS400-PULSE-MONAD  
**Version:** 1.0  
**Document Created:** 2026-07-21  
**Last Updated:** 2026-07-21

## Executive Summary

This document defines the legal, ethical, and technical boundaries for the QATAAUM Quantum Assembly Runtime project. It establishes clean-room development practices to ensure the implementation is independent, lawful, and based solely on public specifications.

## Governing Principle

**PUBLIC SPECIFICATION IN. INDEPENDENT IMPLEMENTATION OUT. EVIDENCE OR SILENCE.**

---

## 1. Legal Framework

### 1.1 Permitted Sources

The following sources MAY be consulted:

✅ **Public Standards**
- OpenQASM 2.0, 3.0, 3.1 specifications (Apache 2.0)
- OpenPulse grammar (Apache 2.0)
- IEEE, ISO, ANSI standards relevant to quantum computing

✅ **Official Public Documentation**
- IBM Quantum public documentation (https://docs.quantum.ibm.com/)
- IBM i public documentation (https://www.ibm.com/docs/en/i)
- Qiskit public API documentation

✅ **Academic Publications**
- Peer-reviewed papers
- Textbooks (public excerpts)
- Conference proceedings
- ArXiv preprints

✅ **Open Source Projects**
- Qiskit (Apache 2.0) - for interface study only
- MLIR (Apache 2.0)
- LLVM (Apache 2.0)
- Liquid Haskell (BSD-3)
- Lean 4 (Apache 2.0)

✅ **Public Patents**
- Published patent applications
- Granted patents (for understanding, not implementation)

### 1.2 Prohibited Sources

The following sources MUST NOT be consulted:

❌ **Proprietary IBM Materials**
- Internal IBM source code not publicly released
- Confidential IBM documentation
- Internal APIs or protocols
- Private processor specifications
- Proprietary calibration data
- Firmware or microcode
- Internal design documents

❌ **Unauthorized Access**
- Reverse-engineered implementations
- Leaked materials
- Confidential information obtained through employment
- Materials obtained through NDA violation
- Decompiled binaries

❌ **Qiskit Implementation Details**
- Internal Qiskit algorithms beyond public interfaces
- Private optimization heuristics
- Undocumented behavior
- Implementation-specific details not in public API

---

## 2. Clean Room Methodology

### 2.1 Research Phase

**Objective:** Understand public specifications and standards

**Process:**
1. Identify public sources (standards, documentation, papers)
2. Record each source in RESEARCH_LEDGER.md
3. Extract concepts, interfaces, and requirements
4. Document understanding in architecture documents
5. Never copy proprietary code or internal details

**Output:** Architecture specifications, ADRs, capability matrices

### 2.2 Design Phase

**Objective:** Create original architecture based on public knowledge

**Process:**
1. Design independent system architecture
2. Create original intermediate representations
3. Define original language extensions (MetaQASM-4, ShadowRPG-Q)
4. Specify original compiler passes
5. Design original runtime model

**Output:** Specifications, grammars, IR definitions, FSM models

### 2.3 Implementation Phase

**Objective:** Write original code implementing the design

**Process:**
1. Implement from specifications, not from Qiskit source
2. Use independent algorithms and data structures
3. Write original code in Rust, RPG, Haskell, Lean
4. Test against public specifications
5. Verify clean-room compliance

**Output:** Source code, tests, proofs, documentation

---

## 3. Specific Boundaries

### 3.1 Language Boundaries

**OpenQASM 2 and 3:**
- ✅ Implement parsers based on public grammar
- ✅ Support public language features
- ❌ Do not copy Qiskit parser implementation
- ❌ Do not reverse-engineer undocumented behavior

**MetaQASM-4:**
- ✅ Original experimental language
- ✅ Extends OpenQASM 3 concepts
- ❌ NOT OpenQASM 4 (which doesn't exist)
- ❌ Never claim to be an official OpenQASM standard

**ShadowRPG-Q:**
- ✅ Original control language
- ✅ Inspired by IBM i patterns
- ❌ NOT an IBM product
- ❌ Do not use proprietary IBM grammar

### 3.2 Processor Boundaries

**Public Processors:**
- ✅ Use publicly documented specifications
- ✅ Model connectivity from public sources
- ✅ Use public gate sets and capabilities
- ❌ Do not invent processor specifications
- ❌ Do not use confidential calibration data

**Processor Status:**
- Eagle, Osprey, Condor: Historical (public)
- Heron r1, r2, r3: Public revisions
- Nighthawk r1: Public revision (Dec 2025)
- Heron r4, Nighthawk r2+: Hypothetical unless documented

**Unknown Properties:**
- Mark as UNKNOWN or capability variables
- Do not guess or invent specifications
- Wait for public documentation

### 3.3 Compiler Boundaries

**Permitted:**
- ✅ Study public compiler architectures
- ✅ Implement standard algorithms (SSA, CFG, etc.)
- ✅ Use public optimization techniques
- ✅ Design original IR family
- ✅ Implement original pass pipeline

**Prohibited:**
- ❌ Copy Qiskit transpiler implementation
- ❌ Reverse-engineer proprietary optimizations
- ❌ Use undocumented heuristics
- ❌ Copy internal data structures

### 3.4 Runtime Boundaries

**Permitted:**
- ✅ Implement Sampler-like primitive (public interface)
- ✅ Implement Estimator-like primitive (public interface)
- ✅ Use public session/job/batch concepts
- ✅ Design original execution model

**Prohibited:**
- ❌ Copy Qiskit Runtime implementation
- ❌ Use proprietary IBM Quantum service internals
- ❌ Reverse-engineer authentication protocols
- ❌ Access undocumented APIs

### 3.5 Pulse Boundaries

**Permitted:**
- ✅ Use OpenPulse public grammar
- ✅ Implement provider-neutral pulse abstraction
- ✅ Use public calibration concepts

**Prohibited:**
- ❌ Use private IBM calibration values
- ❌ Claim direct hardware pulse support without public API
- ❌ Reverse-engineer pulse sequences
- ❌ Use confidential timing constraints

---

## 4. Trademark and Naming

### 4.1 IBM Trademarks

The following are IBM trademarks referenced for compatibility context only:
- IBM
- IBM Quantum
- IBM i
- AS/400
- Qiskit
- Eagle, Osprey, Condor, Heron, Nighthawk (processor names)

**Usage Rules:**
- ✅ Reference as research targets
- ✅ Use for compatibility statements
- ❌ Never claim to be an IBM product
- ❌ Never imply IBM endorsement
- ❌ Never use in project name

### 4.2 Project Identity

**Official Names:**
- QATAAUM Quantum Assembly Runtime
- AS400-PULSE-MONAD (codename)
- MetaQASM-4 (original language)
- ShadowRPG-Q (original control language)

**Disclaimers Required:**
- "Independent clean-room implementation"
- "Not affiliated with IBM"
- "MetaQASM-4 is not OpenQASM 4"
- "Based on public specifications only"

---

## 5. Python Prohibition

### 5.1 Scope

Python is **PROHIBITED** from:
- Production runtime
- Build orchestration
- Compiler pipeline
- Test runner
- Simulator
- Bindings
- Deployment path

### 5.2 Permitted Use

Python MAY be used for:
- Public API research (reading Qiskit docs)
- Prototype exploration (not production)
- One-off analysis scripts (not committed)

### 5.3 Rationale

- Ensure clean-room independence from Python-based Qiskit
- Use systems languages (Rust, RPG, Haskell, Lean)
- Avoid Python dependency in production

---

## 6. Verification and Compliance

### 6.1 Source Ledger

Every external source must be recorded in RESEARCH_LEDGER.md with:
- Source name and URL
- License
- Date accessed
- Concepts derived

### 6.2 Code Review Checklist

Before accepting any code:
- [ ] No proprietary code copied
- [ ] No confidential information used
- [ ] All sources in research ledger
- [ ] Independent implementation verified
- [ ] No Python in production path
- [ ] Proper disclaimers present

### 6.3 Architecture Review Checklist

Before accepting any design:
- [ ] Based on public specifications
- [ ] Original architecture
- [ ] No invented processor facts
- [ ] Capability unknowns marked
- [ ] ADR documents decisions

### 6.4 Documentation Review Checklist

Before publishing any documentation:
- [ ] Separates fact from inference
- [ ] Cites public sources
- [ ] Includes disclaimers
- [ ] No trademark violations
- [ ] No false claims

---

## 7. Consequences of Violation

### 7.1 Immediate Actions

If a clean-room violation is discovered:
1. **STOP** all related work immediately
2. Document the violation
3. Remove contaminated code/design
4. Assess scope of contamination
5. Redesign from clean sources
6. Update ledger and boundary documents

### 7.2 Rejection Criteria

Code/design MUST be rejected if:
- Source is proprietary or confidential
- Implementation copied from Qiskit internals
- Processor facts are invented
- Python used in production
- Trademarks misused
- Clean-room process violated

---

## 8. Roles and Responsibilities

### 8.1 All Roles

**Must:**
- Follow clean-room methodology
- Record all sources
- Implement independently
- Report violations immediately

**Must Not:**
- Use prohibited sources
- Copy proprietary code
- Invent specifications
- Violate trademarks

### 8.2 ROLE-INTEGRATOR

**Special Responsibilities:**
- Review all contributions for clean-room compliance
- Verify source ledger completeness
- Reject contaminated work
- Maintain boundary documentation
- Final compliance gate

---

## 9. External Collaboration

### 9.1 Contributions

External contributions must:
- Include source provenance
- Be independently written
- Not contain proprietary code
- Include license compatibility statement

### 9.2 Consultation

If consulting external experts:
- Use only public knowledge
- Document consultation in ledger
- Do not solicit confidential information
- Maintain clean-room boundary

---

## 10. Continuous Compliance

### 10.1 Regular Reviews

- Weekly: Source ledger review
- Per-phase: Architecture compliance review
- Pre-release: Full compliance audit

### 10.2 Documentation Updates

This document is updated when:
- New boundaries are identified
- Violations are discovered and resolved
- Methodology is refined
- External guidance is received

---

## 11. Legal Disclaimer

This project is:
- An independent research and development effort
- Based solely on public specifications and standards
- Not affiliated with, endorsed by, or sponsored by IBM
- Not an official implementation of any IBM product
- Subject to all applicable laws and regulations

Users and contributors are responsible for:
- Compliance with applicable licenses
- Proper use of trademarks
- Adherence to terms of service
- Legal use of the software

---

## 12. Contact and Reporting

### 12.1 Violation Reporting

If you discover a clean-room violation:
1. Document the issue
2. Report to project maintainers
3. Do not use contaminated code
4. Assist in remediation

### 12.2 Questions

For clean-room boundary questions:
- Consult this document first
- Review RESEARCH_LEDGER.md
- Escalate to ROLE-INTEGRATOR
- Document resolution

---

## Appendix A: Quick Reference

### ✅ PERMITTED
- Public standards and specifications
- Official public documentation
- Academic publications
- Open-source projects (interface study)
- Independent implementation
- Original design

### ❌ PROHIBITED
- Proprietary IBM code
- Confidential information
- Reverse engineering
- Leaked materials
- Qiskit implementation copying
- Python in production
- Trademark misuse
- Invented specifications

---

**Document Authority:** ROLE-INTEGRATOR  
**Review Frequency:** Continuous  
**Enforcement:** Mandatory for all contributions

**End of Clean Room Boundary Document**