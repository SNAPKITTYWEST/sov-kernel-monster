Object subclass: #QuantumVortex
    instanceVariableNames: 'position windingNumber phase energy entangledNeighbors measurementCount creationTime'
    classVariableNames: ''
    package: 'RBG-FS-Civilization-Primitives'

QuantumVortex >> initialize
    super initialize.
    position := Array new: 3.
    windingNumber := 0.
    phase := 0 + 0i.
    energy := 0.0.
    entangledNeighbors := OrderedCollection new.
    measurementCount := 0.
    creationTime := Timestamp now.

QuantumVortex >> position: aPosition winding: aWinding phase: aPhase energy: anEnergy
    position := aPosition.
    windingNumber := aWinding.
    phase := aPhase.
    energy := anEnergy.
    ^ self

QuantumVortex >> entangleWith: anotherVortex
    (entangledNeighbors includes: anotherVortex) ifFalse: [
        entangledNeighbors add: anotherVortex.
        anotherVortex entangleWith: self.
        "Create entangled state: (|ψ₁⟩ + |ψ₂⟩)/√2"
        | combinedPhase |
        combinedPhase := (phase + anotherVortex phase) * (1 / 2 sqrt).
        phase := combinedPhase.
        anotherVortex phase: combinedPhase.
    ].

QuantumVortex >> applyErrorCorrection
    | magnitude |
    magnitude := phase abs.
    magnitude < 0.1 ifTrue: [
        "Phase flip (X gate)"
        phase := phase negated.
    ].
    magnitude > 0 ifTrue: [
        phase := phase / magnitude.
    ].

QuantumVortex >> measure
    "Born rule: probability = |phase|²"
    | prob |
    measurementCount := measurementCount + 1.
    prob := phase abs squared.
    ^ (Random next) < prob

QuantumVortex >> phase
    ^ phase

QuantumVortex >> phase: aPhase
    phase := aPhase

QuantumVortex >> energy
    ^ energy

QuantumVortex >> windingNumber
    ^ windingNumber

QuantumVortex >> entangledNeighbors
    ^ entangledNeighbors

QuantumVortex >> printOn: aStream
    aStream
        nextPutAll: 'QuantumVortex(';
        nextPutAll: position printString;
        nextPutAll: ', w=';
        nextPutAll: windingNumber printString;
        nextPutAll: ', phase=';
        nextPutAll: phase printString;
        nextPutAll: ', E=';
        nextPutAll: energy printString;
        nextPutAll: ')'.
