# ADR-009: Pulse Abstraction Layer

**Status**: ACCEPTED  
**Date**: 2026-07-21  
**Deciders**: Bob (ROLE-SYSTEM-ARCHITECT), ROLE-RUST-RUNTIME  
**Related**: ADR-000, ADR-004, ADR-007

---

## Context

Quantum processors execute gates through calibrated pulse sequences:
- **Gates**: High-level operations (H, CNOT, RZ)
- **Pulses**: Low-level waveforms on physical channels

OpenPulse provides a public grammar for pulse programming, but:
1. Calibration data is processor-specific
2. IBM calibrations are proprietary
3. Direct hardware pulse access requires authorization

QATAAUM must:
- Support pulse-level programming
- Remain provider-neutral
- Never ship proprietary calibrations
- Enable simulation and research

## Decision

We implement a **Provider-Neutral Pulse Abstraction Layer** with three levels:

### Level 1: Gate-Level (Default)
**User writes**: Gates (H, CNOT, RZ)  
**System provides**: Abstract gate semantics  
**Backend provides**: Calibrated pulse sequences

### Level 2: Pulse-Level (Simulated)
**User writes**: Pulse programs (OpenPulse-compatible)  
**System provides**: Pulse simulation  
**Backend provides**: Simulated pulse execution

### Level 3: Pulse-Level (Hardware)
**User writes**: Pulse programs  
**System provides**: Pulse validation  
**Backend provides**: Hardware pulse execution (if authorized)

## Pulse IR (QATAAUM-PULSE / IR-7)

### Core Abstractions

```rust
/// Physical channel for pulse delivery
pub struct PulseChannel {
    pub id: ChannelId,
    pub channel_type: ChannelType,
    pub qubit: Option<QubitId>,
}

pub enum ChannelType {
    Drive,      // Single-qubit control
    Control,    // Two-qubit control
    Measure,    // Measurement
    Acquire,    // Acquisition
}

/// Waveform definition
pub struct Waveform {
    pub id: WaveformId,
    pub samples: Vec<Complex<f64>>,
    pub sample_rate: f64,
    pub duration: Duration,
}

/// Pulse instruction
pub enum PulseOp {
    Play {
        channel: ChannelId,
        waveform: WaveformId,
        phase: f64,
        amplitude: f64,
    },
    Delay {
        channel: ChannelId,
        duration: Duration,
    },
    SetPhase {
        channel: ChannelId,
        phase: f64,
    },
    ShiftPhase {
        channel: ChannelId,
        delta: f64,
    },
    SetFrequency {
        channel: ChannelId,
        frequency: f64,
    },
    Capture {
        channel: ChannelId,
        duration: Duration,
        kernel: Option<WaveformId>,
    },
    Barrier {
        channels: Vec<ChannelId>,
    },
}

/// Pulse schedule
pub struct PulseSchedule {
    pub channels: Vec<PulseChannel>,
    pub waveforms: HashMap<WaveformId, Waveform>,
    pub instructions: Vec<TimedPulseOp>,
    pub duration: Duration,
}

pub struct TimedPulseOp {
    pub time: Duration,
    pub op: PulseOp,
}
```

## Pulse Lowering Pipeline

### Gate → Pulse Lowering

```
Gate IR (IR-4)
    ↓
Scheduled Gate IR (IR-6)
    ↓
Pulse IR (IR-7)
    ↓
Backend-Specific Pulse (IR-8)
```

**Process**:
1. **Gate Decomposition**: Break complex gates into native gates
2. **Calibration Lookup**: Map gates to pulse sequences
3. **Pulse Scheduling**: Assign absolute times
4. **Resource Allocation**: Assign physical channels
5. **Validation**: Check timing, phase, amplitude constraints

### Example: H Gate → Pulse

**Gate**:
```qasm
h q[0];
```

**Pulse (Simulated)**:
```
channel d0 = drive(q[0]);
waveform h_pulse = gaussian(duration=40ns, sigma=10ns);

play(d0, h_pulse, phase=0.0, amplitude=0.5);
```

**Pulse Schedule**:
```rust
PulseSchedule {
    channels: vec![
        PulseChannel { id: 0, type: Drive, qubit: Some(0) }
    ],
    waveforms: hashmap! {
        0 => Waveform {
            samples: gaussian_samples(40ns, 10ns),
            sample_rate: 1e9,
            duration: 40ns,
        }
    },
    instructions: vec![
        TimedPulseOp {
            time: 0ns,
            op: Play {
                channel: 0,
                waveform: 0,
                phase: 0.0,
                amplitude: 0.5,
            }
        }
    ],
    duration: 40ns,
}
```

## Calibration Model

### Simulated Calibrations

**Purpose**: Research, development, testing

**Source**: Generic pulse shapes based on public literature

**Example**:
```rust
pub struct SimulatedCalibration {
    pub gate: GateType,
    pub qubits: Vec<QubitId>,
    pub pulse_sequence: Vec<PulseOp>,
    pub duration: Duration,
    pub fidelity: f64,  // Simulated
}
```

**Labeling**: All simulated calibrations marked `SIMULATED`

### Provider Calibrations

**Purpose**: Hardware execution

**Source**: Backend-provided calibration data

**Access**: Through public provider APIs only

**Example**:
```rust
pub struct ProviderCalibration {
    pub provider: String,
    pub processor: String,
    pub gate: GateType,
    pub qubits: Vec<QubitId>,
    pub calibration_data: Vec<u8>,  // Opaque
    pub timestamp: Timestamp,
}
```

**Policy**: Never ship proprietary calibration values

## Pulse Simulation

### Hamiltonian Evolution

**Model**: Time-dependent Schrödinger equation

```
iℏ ∂|ψ⟩/∂t = H(t)|ψ⟩
```

**Hamiltonian**:
```
H(t) = H_drift + Σ_k Ω_k(t) H_drive_k
```

Where:
- `H_drift`: Static system Hamiltonian
- `Ω_k(t)`: Time-dependent pulse envelope
- `H_drive_k`: Drive Hamiltonian for channel k

**Implementation**:
```rust
pub struct PulseSimulator {
    pub drift_hamiltonian: SparseMatrix,
    pub drive_hamiltonians: Vec<SparseMatrix>,
    pub state: StateVector,
}

impl PulseSimulator {
    pub fn evolve(&mut self, schedule: &PulseSchedule) {
        for instruction in &schedule.instructions {
            match &instruction.op {
                PulseOp::Play { channel, waveform, .. } => {
                    self.apply_pulse(channel, waveform, instruction.time);
                }
                PulseOp::Delay { duration, .. } => {
                    self.free_evolution(*duration);
                }
                // ...
            }
        }
    }
}
```

### Noise Modeling

**Decoherence**:
- T1 (amplitude damping)
- T2 (dephasing)

**Control Errors**:
- Amplitude errors
- Phase errors
- Timing jitter

## OpenPulse Compatibility

### Supported Features

✅ **Channels**: Drive, control, measure, acquire  
✅ **Waveforms**: Gaussian, drag, constant, arbitrary  
✅ **Operations**: Play, delay, set_phase, shift_phase  
✅ **Timing**: Absolute and relative  
✅ **Barriers**: Channel synchronization

### Unsupported Features (Initial Release)

⏳ **Conditional pulses**: Requires dynamic circuits  
⏳ **Frequency sweeps**: Complex calibration  
⏳ **Advanced kernels**: Processor-specific

## Rationale

### Why Provider-Neutral?

1. **Portability**: Works with any backend
2. **Research**: Enables pulse-level research
3. **Simulation**: Full pulse simulation
4. **Clean-Room**: No proprietary dependencies

### Why Three Levels?

1. **Accessibility**: Gate-level for most users
2. **Research**: Pulse-level for researchers
3. **Hardware**: Real execution when authorized

### Why Simulated Calibrations?

1. **Development**: Test without hardware
2. **Education**: Learn pulse programming
3. **Research**: Explore pulse optimization
4. **Compliance**: No proprietary data

## Consequences

### Positive

1. **Flexible**: Supports gate and pulse programming
2. **Portable**: Works on any backend
3. **Researchable**: Full pulse simulation
4. **Compliant**: No proprietary calibrations

### Negative

1. **Complexity**: Pulse programming is complex
2. **Performance**: Pulse simulation is expensive
3. **Accuracy**: Simulated calibrations approximate

### Mitigation

- **Documentation**: Comprehensive pulse guide
- **Optimization**: Efficient pulse simulation
- **Validation**: Compare with gate-level results

## Implementation Plan

**Phase 1** (PENDING):
- ⏳ Define pulse IR (IR-7)
- ⏳ Implement pulse parser
- ⏳ Create pulse schedule builder

**Phase 2** (PENDING):
- ⏳ Implement gate → pulse lowering
- ⏳ Create simulated calibrations
- ⏳ Implement pulse validator

**Phase 3** (PENDING):
- ⏳ Implement pulse simulator
- ⏳ Add noise models
- ⏳ Create pulse benchmarks

**Phase 4** (PENDING):
- ⏳ Provider calibration interface
- ⏳ Hardware pulse execution
- ⏳ Pulse optimization passes

## Alternatives Considered

### Alternative 1: Gate-Only
**Rejected**: Limits research and advanced users

### Alternative 2: Copy IBM Calibrations
**Rejected**: Proprietary, violates clean-room

### Alternative 3: No Simulation
**Rejected**: Limits development and testing

## Related Decisions

- **ADR-000**: Architecture Foundation
- **ADR-004**: Hardware Abstraction Layer
- **ADR-007**: Routing and Placement

---

**Decision**: ACCEPTED  
**Architect**: Bob (ROLE-SYSTEM-ARCHITECT)  
**Date**: 2026-07-21

// Made with Bob