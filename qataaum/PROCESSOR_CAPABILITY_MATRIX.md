# QATAAUM Processor Capability Matrix

**Project:** QATAAUM AS400-PULSE-MONAD  
**Version:** 1.0  
**Last Updated:** 2026-07-21  
**Status:** Research Phase

---

## Purpose

This document catalogs publicly documented quantum processor capabilities from IBM Quantum and other providers. All information is derived from public sources documented in RESEARCH_LEDGER.md.

## Governing Principle

**PUBLIC SPECIFICATION IN. INDEPENDENT IMPLEMENTATION OUT. EVIDENCE OR SILENCE.**

---

## IBM Quantum Processors

### Historical Processors (Public Documentation)

#### Eagle r1

**Status:** Historical (2021)  
**Public Source:** IBM Quantum Blog, IBM Research announcements

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | 127 | Public announcement |
| **Topology** | Heavy-hex | Public documentation |
| **Processor Family** | Eagle | Public naming |
| **Revision** | r1 | Public designation |
| **Native Gates** | UNKNOWN | Requires further research |
| **Connectivity** | Heavy-hex lattice | Public topology description |
| **Measurement** | UNKNOWN | Requires further research |
| **Dynamic Circuits** | UNKNOWN | Requires further research |
| **Timing Resolution** | UNKNOWN | Not publicly documented |
| **Pulse Access** | UNKNOWN | Requires further research |
| **Error Rates** | UNKNOWN | Not publicly documented in detail |
| **Coherence Times** | UNKNOWN | Not publicly documented in detail |

**Notes:**
- First 127-qubit processor announced by IBM
- Heavy-hex topology provides improved connectivity
- Detailed specifications require additional public source research

---

#### Osprey

**Status:** Historical (2022)  
**Public Source:** IBM Quantum Blog, IBM Research announcements

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | 433 | Public announcement |
| **Topology** | Heavy-hex | Public documentation |
| **Processor Family** | Osprey | Public naming |
| **Revision** | (unspecified) | Single revision |
| **Native Gates** | UNKNOWN | Requires further research |
| **Connectivity** | Heavy-hex lattice | Public topology description |
| **Measurement** | UNKNOWN | Requires further research |
| **Dynamic Circuits** | UNKNOWN | Requires further research |
| **Timing Resolution** | UNKNOWN | Not publicly documented |
| **Pulse Access** | UNKNOWN | Requires further research |
| **Error Rates** | UNKNOWN | Not publicly documented in detail |
| **Coherence Times** | UNKNOWN | Not publicly documented in detail |

**Notes:**
- 433-qubit processor announced in 2022
- Continued heavy-hex topology
- Represented significant scaling milestone
- Detailed specifications require additional public source research

---

#### Condor

**Status:** Historical (2023)  
**Public Source:** IBM Quantum Blog, IBM Research announcements

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | 1,121 | Public announcement |
| **Topology** | Heavy-hex | Public documentation |
| **Processor Family** | Condor | Public naming |
| **Revision** | (unspecified) | Single revision |
| **Native Gates** | UNKNOWN | Requires further research |
| **Connectivity** | Heavy-hex lattice | Public topology description |
| **Measurement** | UNKNOWN | Requires further research |
| **Dynamic Circuits** | UNKNOWN | Requires further research |
| **Timing Resolution** | UNKNOWN | Not publicly documented |
| **Pulse Access** | UNKNOWN | Requires further research |
| **Error Rates** | UNKNOWN | Not publicly documented in detail |
| **Coherence Times** | UNKNOWN | Not publicly documented in detail |

**Notes:**
- 1,121-qubit processor announced in 2023
- Largest qubit count in historical series
- Heavy-hex topology maintained
- Detailed specifications require additional public source research

---

### Current Processors (Public Documentation)

#### Heron r1

**Status:** Public (2023)  
**Public Source:** IBM Quantum Documentation, IBM Quantum Blog

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | 133 | Public documentation |
| **Topology** | Heavy-hex | Public documentation |
| **Processor Family** | Heron | Public naming |
| **Revision** | r1 | Public designation |
| **Native Gates** | id, rz, sx, x, cx | Public gate set (requires verification) |
| **Connectivity** | Heavy-hex lattice | Public topology description |
| **Measurement** | Simultaneous, mid-circuit | Public capability (requires verification) |
| **Dynamic Circuits** | Supported | Public capability (requires verification) |
| **Timing Resolution** | ~0.222 ns | Public specification (requires verification) |
| **Pulse Access** | Calibrated | Public access level (requires verification) |
| **Error Rates** | UNKNOWN | Not publicly documented in detail |
| **Coherence Times** | UNKNOWN | Not publicly documented in detail |
| **Max Circuit Depth** | UNKNOWN | Requires further research |
| **Max Shots** | UNKNOWN | Requires further research |

**Notes:**
- First Heron revision
- Represents shift to utility-scale quantum computing
- Dynamic circuit support is key feature
- Many detailed specifications require verification from public sources

---

#### Heron r2

**Status:** Public (2024)  
**Public Source:** IBM Quantum Documentation

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | 133 | Public documentation |
| **Topology** | Heavy-hex | Public documentation |
| **Processor Family** | Heron | Public naming |
| **Revision** | r2 | Public designation |
| **Native Gates** | id, rz, sx, x, cx | Public gate set (requires verification) |
| **Connectivity** | Heavy-hex lattice | Public topology description |
| **Measurement** | Simultaneous, mid-circuit | Public capability (requires verification) |
| **Dynamic Circuits** | Supported | Public capability (requires verification) |
| **Timing Resolution** | ~0.222 ns | Public specification (requires verification) |
| **Pulse Access** | Calibrated | Public access level (requires verification) |
| **Error Rates** | UNKNOWN | Not publicly documented in detail |
| **Coherence Times** | UNKNOWN | Not publicly documented in detail |
| **Improvements over r1** | UNKNOWN | Requires further research |

**Notes:**
- Second Heron revision
- Likely improvements in error rates and coherence
- Specific improvements require public source verification

---

#### Heron r3

**Status:** Public (2025)  
**Public Source:** IBM Quantum Documentation

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | 133 | Public documentation |
| **Topology** | Heavy-hex | Public documentation |
| **Processor Family** | Heron | Public naming |
| **Revision** | r3 | Public designation |
| **Native Gates** | id, rz, sx, x, cx | Public gate set (requires verification) |
| **Connectivity** | Heavy-hex lattice | Public topology description |
| **Measurement** | Simultaneous, mid-circuit | Public capability (requires verification) |
| **Dynamic Circuits** | Supported | Public capability (requires verification) |
| **Timing Resolution** | ~0.222 ns | Public specification (requires verification) |
| **Pulse Access** | Calibrated | Public access level (requires verification) |
| **Error Rates** | UNKNOWN | Not publicly documented in detail |
| **Coherence Times** | UNKNOWN | Not publicly documented in detail |
| **Improvements over r2** | UNKNOWN | Requires further research |

**Notes:**
- Third Heron revision (current as of 2025)
- Continued refinement of utility-scale architecture
- Specific improvements require public source verification

---

#### Nighthawk r1

**Status:** Public (December 2025)  
**Public Source:** IBM Quantum Documentation (December 2025 announcement)

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | 120 | Public documentation (December 2025) |
| **Topology** | UNKNOWN | Requires further research |
| **Processor Family** | Nighthawk | Public naming |
| **Revision** | r1 | Public designation |
| **Native Gates** | UNKNOWN | Requires further research |
| **Connectivity** | UNKNOWN | Requires further research |
| **Measurement** | UNKNOWN | Requires further research |
| **Dynamic Circuits** | UNKNOWN | Requires further research |
| **Timing Resolution** | UNKNOWN | Requires further research |
| **Pulse Access** | UNKNOWN | Requires further research |
| **Error Rates** | UNKNOWN | Not publicly documented in detail |
| **Coherence Times** | UNKNOWN | Not publicly documented in detail |

**Notes:**
- Announced December 2025
- 120-qubit processor
- Topology and detailed specifications require public source research
- May represent new architectural direction

---

### Hypothetical Processors (Not Yet Publicly Documented)

#### Heron r4

**Status:** HYPOTHETICAL (unless publicly documented)  
**Public Source:** NONE

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | UNKNOWN | Not publicly documented |
| **Topology** | UNKNOWN | Not publicly documented |
| **Processor Family** | Heron (hypothetical) | Extrapolation |
| **Revision** | r4 (hypothetical) | Extrapolation |
| **All Properties** | UNKNOWN | Not publicly documented |

**Notes:**
- **HYPOTHETICAL PROCESSOR**
- No public documentation exists as of 2026-07-21
- Must not be used in production profiles
- If publicly documented in future, move to "Current Processors" section

---

#### Nighthawk r2 and later

**Status:** HYPOTHETICAL (unless publicly documented)  
**Public Source:** NONE

| Property | Value | Evidence |
|----------|-------|----------|
| **Qubit Count** | UNKNOWN | Not publicly documented |
| **Topology** | UNKNOWN | Not publicly documented |
| **Processor Family** | Nighthawk (hypothetical) | Extrapolation |
| **Revision** | r2+ (hypothetical) | Extrapolation |
| **All Properties** | UNKNOWN | Not publicly documented |

**Notes:**
- **HYPOTHETICAL PROCESSOR**
- No public documentation exists as of 2026-07-21
- Must not be used in production profiles
- If publicly documented in future, move to "Current Processors" section

---

## Heavy-Hex Topology

### Description

The heavy-hex topology is a publicly documented qubit connectivity pattern used in IBM Quantum processors.

**Key Characteristics:**
- Hexagonal lattice structure
- Higher connectivity than linear or grid topologies
- Enables more efficient two-qubit gate routing
- Reduces SWAP overhead in many algorithms

**Connectivity Pattern:**
```
    q0 --- q1 --- q2
   /  \   /  \   /  \
  q3   q4    q5    q6
   \  /  \  /  \  /
    q7 --- q8 --- q9
```

**Public Sources:**
- IBM Quantum documentation
- Academic papers on quantum processor architecture
- IBM Research publications

**Implementation Notes:**
- Connectivity graph must be derived from public processor specifications
- Edge weights (if any) require public documentation
- Routing algorithms must account for topology constraints

---

## Native Gate Sets

### Common IBM Quantum Native Gates (Requires Verification)

Based on public documentation, IBM Quantum processors typically support:

| Gate | Description | Parameters | Public Source |
|------|-------------|------------|---------------|
| **id** | Identity | qubit | Public gate set |
| **rz** | Z-axis rotation | angle, qubit | Public gate set |
| **sx** | √X gate | qubit | Public gate set |
| **x** | Pauli-X (NOT) | qubit | Public gate set |
| **cx** | CNOT (controlled-X) | control, target | Public gate set |

**Notes:**
- Gate set requires verification from official public documentation
- Pulse-level implementations are calibration-dependent
- Custom gates may be available through pulse programming
- Gate fidelities are processor-specific and time-dependent

---

## Dynamic Circuits

### Public Capabilities (Requires Verification)

**Mid-Circuit Measurement:**
- Measure qubits during circuit execution
- Use measurement results in classical control flow
- Supported on recent processors (Heron family)

**Classical Feedback:**
- Conditional gates based on measurement outcomes
- Real-time classical computation
- Limited branching depth (processor-dependent)

**Timing Constraints:**
- Measurement duration
- Classical processing latency
- Alignment requirements

**Public Sources:**
- IBM Quantum documentation on dynamic circuits
- OpenQASM 3 specification (control flow)
- Academic papers on dynamic quantum circuits

---

## Pulse-Level Access

### Public Access Levels

**Calibrated:**
- Use pre-calibrated pulse schedules
- Access through OpenPulse grammar
- Processor-specific calibration data

**Custom:**
- Define custom pulse waveforms
- Requires understanding of hardware constraints
- May require special access or permissions

**Public Sources:**
- OpenPulse specification
- IBM Quantum pulse programming documentation
- Qiskit Pulse public API documentation

**Implementation Notes:**
- Pulse access level varies by processor and provider
- Calibration data may not be publicly available
- Custom pulses require validation and may have restrictions

---

## Capability Flags

### Processor Capability Schema

For implementation, each processor profile should include:

```json
{
  "provider": "ibm-quantum",
  "family": "heron",
  "revision": "r3",
  "qubit_count": 133,
  "topology": {
    "type": "heavy-hex",
    "connectivity": [[0,1], [1,2], ...]
  },
  "native_gates": ["id", "rz", "sx", "x", "cx"],
  "capabilities": {
    "measurement": {
      "simultaneous": true,
      "mid_circuit": true,
      "max_shots": "UNKNOWN"
    },
    "dynamic_circuits": {
      "supported": true,
      "max_branches": "UNKNOWN",
      "classical_feedback": true
    },
    "timing": {
      "resolution_ns": 0.222,
      "alignment_ns": 16,
      "max_duration_ns": "UNKNOWN"
    },
    "pulse": {
      "access_level": "calibrated",
      "custom_waveforms": "UNKNOWN"
    }
  },
  "public_evidence": [
    "https://docs.quantum.ibm.com/...",
    "https://research.ibm.com/blog/..."
  ],
  "unknown_properties": [
    "error_rates",
    "coherence_times",
    "max_circuit_depth",
    "max_shots",
    "gate_durations"
  ]
}
```

---

## Research Gaps

### Properties Requiring Further Public Source Research

1. **Detailed Gate Sets**
   - Complete native gate inventory per processor
   - Gate parameter ranges
   - Gate duration specifications

2. **Connectivity Graphs**
   - Complete edge lists for each processor
   - Connectivity weights (if applicable)
   - Topology variations between revisions

3. **Timing Specifications**
   - Gate durations
   - Measurement durations
   - Classical processing latencies
   - Alignment constraints

4. **Error Characteristics**
   - Gate error rates (if publicly available)
   - Measurement error rates
   - Coherence times (T1, T2)
   - Crosstalk characteristics

5. **Operational Constraints**
   - Maximum circuit depth
   - Maximum shot count
   - Maximum circuit size
   - Queue and execution policies

6. **Nighthawk Architecture**
   - Topology details
   - Native gate set
   - Dynamic circuit capabilities
   - Timing specifications

---

## Update Policy

This document must be updated when:
1. New processors are publicly announced
2. Additional public specifications are discovered
3. Processor revisions are publicly documented
4. Research gaps are filled from public sources

All updates must:
- Reference public sources in RESEARCH_LEDGER.md
- Mark hypothetical processors explicitly
- Use UNKNOWN for undocumented properties
- Never invent specifications

---

## References

See RESEARCH_LEDGER.md for complete source provenance.

**Key Public Sources:**
- IBM Quantum Documentation: https://docs.quantum.ibm.com/
- IBM Research Blog: https://research.ibm.com/blog/
- OpenQASM Specification: https://openqasm.com/
- Academic publications on IBM Quantum processors

---

**Document Status:** INITIAL DRAFT - Requires verification from public sources  
**Next Update:** After Phase R1 public source research  
**Maintained By:** ROLE-SYSTEM-ARCHITECT

**End of Processor Capability Matrix**