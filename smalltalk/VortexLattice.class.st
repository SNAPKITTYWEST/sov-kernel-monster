Object subclass: #VortexLattice
    instanceVariableNames: 'size vortices couplingStrength time dt periodicBoundary rng'
    classVariableNames: ''
    package: 'RBG-FS-Civilization-Primitives'

VortexLattice class >> nx: nx ny: ny nz: nz coupling: coupling seed: seed periodic: periodic
    ^ self new initNx: nx ny: ny nz: nz coupling: coupling seed: seed periodic: periodic

VortexLattice >> initNx: nx ny: ny nz: nz coupling: coupling seed: seed periodic: periodic
    size := {nx. ny. nz}.
    couplingStrength := coupling.
    time := 0.0.
    dt := 0.01.
    periodicBoundary := periodic.
    rng := BobRNG new seed: seed.
    vortices := Array2D rows: nx columns: ny.
    1 to: nx do: [:i |
        1 to: ny do: [:j |
            | vortex |
            vortex := QuantumVortex new.
            vortex
                position: {i. j. 1}
                winding: (rng integerFrom: -1 to: 1)
                phase: ((rng normal) + (rng normal) i) normalized
                energy: (rng uniform * 2 - 1).
            vortices at: i at: j put: vortex.
        ].
    ].
    self createEntanglement.
    ^ self

VortexLattice >> createEntanglement
    1 to: (size first) do: [:i |
        1 to: (size second) do: [:j |
            | neighbors |
            neighbors := self neighborsOf: i y: j z: 1.
            neighbors do: [:each |
                (vortices at: i at: j) entangleWith: each.
            ].
        ].
    ].

VortexLattice >> neighborsOf: x y: y z: z
    | neighbors offsets |
    neighbors := OrderedCollection new.
    offsets := #(#(1 0 0) #(-1 0 0) #(0 1 0) #(0 -1 0) #(0 0 1) #(0 0 -1)).
    offsets do: [:offset |
        | ni nj nk |
        ni := x + (offset at: 1).
        nj := y + (offset at: 2).
        nk := z + (offset at: 3).
        periodicBoundary ifTrue: [
            ni := ((ni - 1) \\ (size first)) + 1.
            nj := ((nj - 1) \\ (size second)) + 1.
            nk := ((nk - 1) \\ (size third)) + 1.
        ].
        ((ni between: 1 and: (size first)) and: [
            (nj between: 1 and: (size second)) and: [
                nk between: 1 and: (size third)
            ]
        ]) ifTrue: [
            neighbors add: (vortices at: ni at: nj).
        ].
    ].
    ^ neighbors

VortexLattice >> evolve: aDt
    dt := aDt.
    1 to: (size first) do: [:i |
        1 to: (size second) do: [:j |
            | hamiltonian evolutionFactor |
            hamiltonian := self hamiltonianAt: i y: j z: 1.
            evolutionFactor := (0 - (hamiltonian * dt) i) exp.
            (vortices at: i at: j) phase: ((vortices at: i at: j) phase * evolutionFactor).
            (vortices at: i at: j) energy: hamiltonian.
        ].
    ].
    time := time + dt.

VortexLattice >> hamiltonianAt: x y: y z: z
    | vortex kinetic interaction neighbors |
    vortex := vortices at: x at: y.
    kinetic := vortex windingNumber squared asFloat.
    interaction := 0.0.
    neighbors := self neighborsOf: x y: y z: z.
    neighbors do: [:neighbor |
        interaction := interaction + (vortex phase * neighbor phase conjugate) real.
    ].
    interaction := couplingStrength negated * interaction.
    ^ kinetic + interaction

VortexLattice >> totalEnergy
    | energy |
    energy := 0.0.
    vortices do: [:each | energy := energy + each energy].
    ^ energy

VortexLattice >> entanglementEntropy
    | total max |
    total := 0.
    vortices do: [:each | total := total + each entangledNeighbors size].
    max := vortices size * 6.
    ^ max > 0 ifTrue: [total asFloat / max] ifFalse: [0.0]

VortexLattice >> applyErrorCorrection
    | corrected |
    corrected := 0.
    vortices do: [:each | each applyErrorCorrection. corrected := corrected + 1].
    ^ corrected

VortexLattice >> vortices
    ^ vortices

VortexLattice >> size
    ^ size

VortexLattice >> time
    ^ time
