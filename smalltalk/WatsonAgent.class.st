Object subclass: #WatsonAgent
    instanceVariableNames: 'id knowledgeGraph goals beliefs confidence rng lattice'
    classVariableNames: 'AgentCount'
    package: 'RBG-FS-Civilization-Cognitive'

WatsonAgent class >> initialize
    AgentCount := 0.

WatsonAgent class >> newWithId: anId lattice: aLattice
    ^ self new initId: anId lattice: aLattice

WatsonAgent >> initId: anId lattice: aLattice
    AgentCount := AgentCount + 1.
    id := anId.
    lattice := aLattice.
    knowledgeGraph := Dictionary new.
    goals := OrderedCollection new.
    beliefs := Dictionary new.
    confidence := 0.5.
    rng := BobRNG new seed: anId * 1234567.
    ^ self

WatsonAgent >> perceive
    "Ingest environmental deltas from local vortex"
    | vortex |
    vortex := lattice vortices
        at: (rng integerFrom: 1 to: lattice size first)
        at: (rng integerFrom: 1 to: lattice size second).
    knowledgeGraph at: 'vortex_energy' put: vortex energy.
    knowledgeGraph at: 'vortex_winding' put: vortex windingNumber.
    ^ self

WatsonAgent >> reason
    "Evaluate inputs against knowledge graph and belief constraints"
    | energy winding |
    energy := knowledgeGraph at: 'vortex_energy' ifAbsent: [0.0].
    winding := knowledgeGraph at: 'vortex_winding' ifAbsent: [0].
    beliefs at: 'high_energy' put: (energy > 0.5).
    beliefs at: 'nonzero_winding' put: (winding ~= 0).
    ^ self

WatsonAgent >> learn
    "Update confidence from observations"
    | gain |
    gain := (beliefs at: 'high_energy' ifAbsent: [false]) ifTrue: [0.01] ifFalse: [0].
    confidence := confidence * 0.99 + gain.
    ^ self

WatsonAgent >> decide
    "Select operational trajectory via goal management"
    goals add: #explore.
    (beliefs at: 'nonzero_winding' ifAbsent: [false]) ifTrue: [goals add: #entangle].
    goals add: #measure.
    ^ self

WatsonAgent >> act
    "Execute action from goal queue"
    | action |
    goals isEmpty ifTrue: [^ self].
    action := goals removeFirst.
    action = #explore  ifTrue: [self explore].
    action = #entangle ifTrue: [self entangle].
    action = #measure  ifTrue: [self measure].
    ^ self

WatsonAgent >> explore
    "Random walk on lattice"
    | x y z |
    x := rng integerFrom: 1 to: lattice size first.
    y := rng integerFrom: 1 to: lattice size second.
    z := rng integerFrom: 1 to: (lattice size third ifNil: [1]).
    knowledgeGraph at: 'last_position' put: {x. y. z}.

WatsonAgent >> entangle
    "Entangle current vortex with a neighbor"
    | pos vortex neighbors |
    pos := knowledgeGraph at: 'last_position' ifAbsent: [{1. 1. 1}].
    vortex := lattice vortices at: (pos first) at: (pos second).
    neighbors := vortex entangledNeighbors.
    neighbors isEmpty ifFalse: [
        vortex entangleWith: neighbors anyOne.
    ].

WatsonAgent >> measure
    "Quantum measurement via Born rule"
    | pos vortex outcome |
    pos := knowledgeGraph at: 'last_position' ifAbsent: [{1. 1. 1}].
    vortex := lattice vortices at: (pos first) at: (pos second).
    outcome := vortex measure.
    knowledgeGraph at: 'last_measurement' put: outcome.

WatsonAgent >> reflect
    "Metacognitive audit — clamp confidence, prune stale goals"
    confidence := (confidence max: 0.1) min: 1.0.
    goals size > 10 ifTrue: [goals removeLast].
    ^ self

WatsonAgent >> cognitiveCycle
    self perceive; reason; learn; decide; act; reflect.
    ^ self

WatsonAgent >> id
    ^ id

WatsonAgent >> confidence
    ^ confidence

WatsonAgent >> knowledgeGraph
    ^ knowledgeGraph
