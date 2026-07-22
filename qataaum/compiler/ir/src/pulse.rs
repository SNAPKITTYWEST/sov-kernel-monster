//! QATAAUM IR Level 7: PULSE
//!
//! Provider-neutral pulse frames, ports, waveforms, captures, delays,
//! phase shifts, and calibration references.

use crate::schedule::{Duration, ScheduleIR};
use crate::topo::PhysicalQubit;
use std::collections::HashMap;

/// Frame identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FrameId(pub usize);

/// Waveform identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct WaveformId(pub usize);

/// Frequency in Hz
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Frequency(pub f64);

/// Phase in radians
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Phase(pub f64);

/// Complex number for waveform samples
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Complex {
    pub re: f64,
    pub im: f64,
}

/// Pulse frame (frequency and phase reference)
#[derive(Debug, Clone, PartialEq)]
pub struct Frame {
    pub id: FrameId,
    pub qubit: PhysicalQubit,
    pub frequency: Frequency,
    pub phase: Phase,
    pub port: String,
}

/// Waveform definition
#[derive(Debug, Clone, PartialEq)]
pub struct Waveform {
    pub id: WaveformId,
    pub samples: Vec<Complex>,
    pub duration: Duration,
    pub name: String,
}

impl Waveform {
    pub fn gaussian(amplitude: f64, duration: Duration, sigma: f64) -> Self {
        let num_samples = (duration.0 / 1.0).ceil() as usize;
        let mut samples = Vec::with_capacity(num_samples);
        
        for i in 0..num_samples {
            let t = i as f64 - (num_samples as f64 / 2.0);
            let value = amplitude * (-t * t / (2.0 * sigma * sigma)).exp();
            samples.push(Complex { re: value, im: 0.0 });
        }
        
        Self {
            id: WaveformId(0),
            samples,
            duration,
            name: "gaussian".to_string(),
        }
    }
    
    pub fn square(amplitude: f64, duration: Duration) -> Self {
        let num_samples = (duration.0 / 1.0).ceil() as usize;
        let samples = vec![Complex { re: amplitude, im: 0.0 }; num_samples];
        
        Self {
            id: WaveformId(0),
            samples,
            duration,
            name: "square".to_string(),
        }
    }
}

/// Pulse operation
#[derive(Debug, Clone, PartialEq)]
pub enum PulseOp {
    Play {
        frame: FrameId,
        waveform: WaveformId,
        duration: Duration,
    },
    Capture {
        frame: FrameId,
        duration: Duration,
    },
    Delay {
        frame: FrameId,
        duration: Duration,
    },
    SetFrequency {
        frame: FrameId,
        frequency: Frequency,
    },
    ShiftPhase {
        frame: FrameId,
        phase: Phase,
    },
    Barrier {
        frames: Vec<FrameId>,
    },
}

/// Calibration data
#[derive(Debug, Clone, PartialEq)]
pub struct CalibrationData {
    pub gate_calibrations: HashMap<String, Vec<PulseOp>>,
    pub readout_calibrations: HashMap<PhysicalQubit, Vec<PulseOp>>,
}

impl CalibrationData {
    pub fn new() -> Self {
        Self {
            gate_calibrations: HashMap::new(),
            readout_calibrations: HashMap::new(),
        }
    }
}

impl Default for CalibrationData {
    fn default() -> Self {
        Self::new()
    }
}

/// IR Level 7: Pulse representation
#[derive(Debug, Clone, PartialEq)]
pub struct PulseIR {
    pub frames: Vec<Frame>,
    pub waveforms: Vec<Waveform>,
    pub pulse_sequence: Vec<PulseOp>,
    pub calibration: CalibrationData,
}

impl PulseIR {
    pub fn new() -> Self {
        Self {
            frames: Vec::new(),
            waveforms: Vec::new(),
            pulse_sequence: Vec::new(),
            calibration: CalibrationData::new(),
        }
    }
    
    pub fn add_frame(&mut self, frame: Frame) -> FrameId {
        let id = FrameId(self.frames.len());
        self.frames.push(frame);
        id
    }
    
    pub fn add_waveform(&mut self, waveform: Waveform) -> WaveformId {
        let id = WaveformId(self.waveforms.len());
        self.waveforms.push(waveform);
        id
    }
    
    pub fn add_pulse_op(&mut self, op: PulseOp) {
        self.pulse_sequence.push(op);
    }
}

impl Default for PulseIR {
    fn default() -> Self {
        Self::new()
    }
}

/// Pulse compiler that converts ScheduleIR to PulseIR
pub struct PulseCompiler;

impl PulseCompiler {
    pub fn new() -> Self {
        Self
    }
    
    pub fn compile(&self, schedule_ir: &ScheduleIR) -> Result<PulseIR, String> {
        let mut pulse_ir = PulseIR::new();
        
        // Create frames for each qubit
        let mut frame_map = HashMap::new();
        for op in &schedule_ir.operations {
            for &qubit in &op.op.physical_qubits {
                if !frame_map.contains_key(&qubit) {
                    let frame = Frame {
                        id: FrameId(0),
                        qubit,
                        frequency: Frequency(5.0e9), // 5 GHz default
                        phase: Phase(0.0),
                        port: format!("q{}", qubit.0),
                    };
                    let frame_id = pulse_ir.add_frame(frame);
                    frame_map.insert(qubit, frame_id);
                }
            }
        }
        
        // Convert gates to pulse sequences (simplified)
        for op in &schedule_ir.operations {
            // For now, just add delays as placeholders
            if let Some(&frame_id) = op.op.physical_qubits.first().and_then(|q| frame_map.get(q)) {
                pulse_ir.add_pulse_op(PulseOp::Delay {
                    frame: frame_id,
                    duration: op.duration,
                });
            }
        }
        
        Ok(pulse_ir)
    }
}

impl Default for PulseCompiler {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_waveform_gaussian() {
        let waveform = Waveform::gaussian(1.0, Duration(100.0), 10.0);
        assert_eq!(waveform.samples.len(), 100);
        assert_eq!(waveform.duration, Duration(100.0));
    }

    #[test]
    fn test_waveform_square() {
        let waveform = Waveform::square(0.5, Duration(50.0));
        assert_eq!(waveform.samples.len(), 50);
        assert!(waveform.samples.iter().all(|s| s.re == 0.5 && s.im == 0.0));
    }

    #[test]
    fn test_pulse_ir_creation() {
        let mut pulse_ir = PulseIR::new();
        
        let frame = Frame {
            id: FrameId(0),
            qubit: PhysicalQubit(0),
            frequency: Frequency(5.0e9),
            phase: Phase(0.0),
            port: "q0".to_string(),
        };
        
        let frame_id = pulse_ir.add_frame(frame);
        assert_eq!(frame_id, FrameId(0));
        assert_eq!(pulse_ir.frames.len(), 1);
    }

    #[test]
    fn test_pulse_operations() {
        let mut pulse_ir = PulseIR::new();
        
        pulse_ir.add_pulse_op(PulseOp::Delay {
            frame: FrameId(0),
            duration: Duration(100.0),
        });
        
        pulse_ir.add_pulse_op(PulseOp::SetFrequency {
            frame: FrameId(0),
            frequency: Frequency(5.1e9),
        });
        
        assert_eq!(pulse_ir.pulse_sequence.len(), 2);
    }
}

// Made with Bob
