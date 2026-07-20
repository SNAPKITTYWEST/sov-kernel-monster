Object subclass: #BobQuantumLibrary
    instanceVariableNames: 'libraryHandle functionCache'
    classVariableNames: 'UniqueInstance'
    package: 'BOB-Quantum-FFI'

BobQuantumLibrary class >> initialize [
    UniqueInstance := nil.
]

BobQuantumLibrary class >> current [
    ^ UniqueInstance ifNil: [ UniqueInstance := self basicNew initializeLibrary; yourself ]
]

BobQuantumLibrary class >> reset [
    UniqueInstance := nil.
]

BobQuantumLibrary >> initializeLibrary [
    libraryHandle := nil.
    functionCache := IdentityDictionary new.
    ^ self loadLibrary
]

BobQuantumLibrary >> loadLibrary [
    | libName |
    libName := self libraryNameForPlatform.
    [ libraryHandle := ExternalLibrary open: libName ]
        on: Error
        do: [ :ex |
            self error: 'Failed to load BOB Quantum library: ', libName, '. Error: ', ex messageText
        ].
    ^ self
]

BobQuantumLibrary >> libraryNameForPlatform [
    ^ (Smalltalk platform name = 'unix' or: [ Smalltalk platform name = 'macos' ])
        ifTrue: [ 'bob_quantum' ]
        ifFalse: [ 'bob_quantum.dll' ]
]

BobQuantumLibrary >> function: aSymbol [
    ^ functionCache
        at: aSymbol
        ifAbsentPut: [ self lookupFunction: aSymbol ]
]

BobQuantumLibrary >> lookupFunction: aSymbol [
    | funcSpec returnType argTypes func |
    funcSpec := self functionSpecFor: aSymbol.
    returnType := funcSpec first.
    argTypes := funcSpec second.
    func := ExternalFunction
        library: libraryHandle
        function: aSymbol asString
        returnType: returnType
        argTypes: argTypes.
    ^ func
]

BobQuantumLibrary >> functionSpecFor: aSymbol [
    "Returns an Array: #(returnType argTypesArray).
    Types: #void #int #uint #long #ulong #float #double #pointer #bool #char #string"
    ^ {
        #bob_rng_create -> #(#pointer #(#uint)).
        #bob_rng_destroy -> #(#void #(#pointer)).
        #bob_rng_next_uint32 -> #(#uint #(#pointer)).
        #bob_rng_next_double -> #(#double #(#pointer)).
        #bob_rng_next_gaussian -> #(#double #(#pointer #double #double)).

        #bob_lattice_create -> #(#pointer #(#int #int #int #double)).
        #bob_lattice_destroy -> #(#void #(#pointer)).
        #bob_lattice_get_nx -> #(#int #(#pointer)).
        #bob_lattice_get_ny -> #(#int #(#pointer)).
        #bob_lattice_get_nz -> #(#int #(#pointer)).
        #bob_lattice_get_coupling -> #(#double #(#pointer)).
        #bob_lattice_get_volume -> #(#int #(#pointer)).
        #bob_lattice_get_neighbors -> #(#pointer #(#pointer #int #pointer)).
        #bob_lattice_compute_coordination -> #(#int #(#pointer)).

        #bob_state_create -> #(#pointer #(#pointer #int)).
        #bob_state_destroy -> #(#void #(#pointer)).
        #bob_state_copy -> #(#pointer #(#pointer)).
        #bob_state_get_amplitude -> #(#pointer #(#pointer #int)).
        #bob_state_set_amplitude -> #(#void #(#pointer #int #pointer)).
        #bob_state_normalize -> #(#void #(#pointer)).
        #bob_state_inner_product -> #(#pointer #(#pointer #pointer)).
        #bob_state_expectation_value -> #(#double #(#pointer #pointer)).
        #bob_state_entropy -> #(#double #(#pointer)).
        #bob_state_fidelity -> #(#double #(#pointer #pointer)).

        #bob_hamiltonian_create -> #(#pointer #(#pointer)).
        #bob_hamiltonian_destroy -> #(#void #(#pointer)).
        #bob_hamiltonian_add_ising_term -> #(#void #(#pointer #double #int #int)).
        #bob_hamiltonian_add_transverse_field -> #(#void #(#pointer #double #int)).
        #bob_hamiltonian_add_heisenberg_term -> #(#void #(#pointer #double #int #int)).
        #bob_hamiltonian_add_custom_term -> #(#void #(#pointer #pointer #int)).
        #bob_hamiltonian_build_matrix -> #(#void #(#pointer)).
        #bob_hamiltonian_get_matrix -> #(#pointer #(#pointer)).
        #bob_hamiltonian_get_eigenvalues -> #(#pointer #(#pointer #pointer #int)).

        #bob_world_create -> #(#pointer #(#pointer #pointer #pointer)).
        #bob_world_destroy -> #(#void #(#pointer)).
        #bob_world_create_lattice -> #(#pointer #(#pointer #int #int #int #double)).
        #bob_world_run_simulation -> #(#int #(#pointer #ulong #double)).
        #bob_world_get_state -> #(#pointer #(#pointer)).
        #bob_world_get_hamiltonian -> #(#pointer #(#pointer)).
        #bob_world_get_lattice -> #(#pointer #(#pointer)).
        #bob_world_visualize -> #(#void #(#pointer #string #int #int)).
        #bob_world_checkpoint -> #(#int #(#pointer #string)).
        #bob_world_restore -> #(#int #(#pointer #string)).
        #bob_world_get_energy -> #(#double #(#pointer)).
        #bob_world_get_magnetization -> #(#double #(#pointer #int)).
        #bob_world_get_correlation -> #(#double #(#pointer #int #int)).
    } detect: [ :assoc | assoc key = aSymbol ] ifNone: [ self error: 'Unknown function: ', aSymbol ] value
]

BobQuantumLibrary >> shutdown [
    libraryHandle ifNotNil: [ libraryHandle close. libraryHandle := nil ].
    functionCache := nil.
]

BobQuantumLibrary >> finalize [
    self shutdown.
]

"--------------------------------------------------------------------------------"
" BobRNG - Random Number Generator Wrapper
"--------------------------------------------------------------------------------"

Object subclass: #BobRNG
    instanceVariableNames: 'handle'
    classVariableNames: ''
    package: 'BOB-Quantum-FFI'

BobRNG class >> new [
    ^ self basicNew initialize
]

BobRNG >> initialize [
    handle := BobQuantumLibrary current function: #bob_rng_create value: 12345 asUnsignedInteger.
    handle ifNil: [ self error: 'Failed to create RNG handle' ].
    ^ self
]

BobRNG >> initializeWithSeed: aSeed [
    handle := BobQuantumLibrary current function: #bob_rng_create value: aSeed asUnsignedInteger.
    handle ifNil: [ self error: 'Failed to create RNG handle with seed' ].
    ^ self
]

BobRNG >> nextUInt32 [
    ^ BobQuantumLibrary current function: #bob_rng_next_uint32 value: handle
]

BobRNG >> nextDouble [
    ^ BobQuantumLibrary current function: #bob_rng_next_double value: handle
]

BobRNG >> nextGaussianWithMean: mu sigma: sigma [
    ^ BobQuantumLibrary current function: #bob_rng_next_gaussian value: handle value: mu value: sigma
]

BobRNG >> nextIntegerInRange: min to: max [
    | range rand |
    range := max - min + 1.
    rand := self nextUInt32.
    ^ min + (rand \\ range)
]

BobRNG >> nextBoolean [
    ^ (self nextUInt32 bitAnd: 1) = 1
]

BobRNG >> shuffle: aCollection [
    | n i j temp |
    n := aCollection size.
    n <= 1 ifTrue: [ ^ aCollection ].
    i := n.
    [ i > 1 ] whileTrue: [
        j := self nextIntegerInRange: 1 to: i.
        temp := aCollection at: i.
        aCollection at: i put: (aCollection at: j).
        aCollection at: j put: temp.
        i := i - 1.
    ].
    ^ aCollection
]

BobRNG >> destroy [
    handle ifNotNil: [
        BobQuantumLibrary current function: #bob_rng_destroy value: handle.
        handle := nil.
    ].
]

BobRNG >> finalize [
    self destroy.
]

BobRNG >> handle [
    ^ handle
]

BobRNG >> isValid [
    ^ handle notNil
]

"--------------------------------------------------------------------------------"
" BobLattice - Spatial Lattice Structure
"--------------------------------------------------------------------------------"

Object subclass: #BobLattice
    instanceVariableNames: 'handle nx ny nz coupling volume coordinationNumber'
    classVariableNames: ''
    package: 'BOB-Quantum-FFI'

BobLattice class >> create: nx ny: ny nz: nz coupling: j [
    ^ self basicNew initializeWith: nx ny: ny nz: nz coupling: j
]

BobLattice >> initializeWith: nxArg ny: nyArg nz: nzArg coupling: jArg [
    nx := nxArg. ny := nyArg. nz := nzArg. coupling := jArg.
    handle := BobQuantumLibrary current function: #bob_lattice_create value: nx value: ny value: nz value: jArg.
    handle ifNil: [ self error: 'Failed to create lattice' ].
    volume := self computeVolume.
    coordinationNumber := self computeCoordination.
    ^ self
]

BobLattice >> computeVolume [
    ^ BobQuantumLibrary current function: #bob_lattice_get_volume value: handle
]

BobLattice >> computeCoordination [
    ^ BobQuantumLibrary current function: #bob_lattice_compute_coordination value: handle
]

BobLattice >> getNeighborsForSite: siteIndex into: bufferArray [
    "bufferArray must be a pre-allocated Array of size coordinationNumber"
    | neighborPtr |
    neighborPtr := BobQuantumLibrary current function: #bob_lattice_get_neighbors value: handle value: siteIndex value: bufferArray.
    ^ neighborPtr
]

BobLattice >> neighborsOf: siteIndex [
    | buffer |
    buffer := Array new: coordinationNumber withAll: 0.
    self getNeighborsForSite: siteIndex into: buffer.
    ^ buffer
]

BobLattice >> allNeighbors [
    | allNeighbors |
    allNeighbors := Array new: volume.
    1 to: volume do: [ :i |
        allNeighbors at: i put: (self neighborsOf: i - 1) "C uses 0-based"
    ].
    ^ allNeighbors
]

BobLattice >> siteIndexToCoordinates: index [
    | x y z |
    z := index // (nx * ny).
    y := (index \\ (nx * ny)) // nx.
    x := index \\ nx.
    ^ { x. y. z }
]

BobLattice >> coordinatesToSiteIndex: coords [
    ^ (coords third * nx * ny) + (coords second * nx) + coords first
]

BobLattice >> distanceBetween: i and: j [
    | ci cj dx dy dz |
    ci := self siteIndexToCoordinates: i.
    cj := self siteIndexToCoordinates: j.
    dx := (ci first - cj first) abs.
    dy := (ci second - cj second) abs.
    dz := (ci third - cj third) abs.
    "Periodic boundary conditions"
    dx := dx min: (nx - dx).
    dy := dy min: (ny - dy).
    dz := dz min: (nz - dz).
    ^ (dx + dy + dz) asFloat
]

BobLattice >> destroy [
    handle ifNotNil: [
        BobQuantumLibrary current function: #bob_lattice_destroy value: handle.
        handle := nil.
    ].
]

BobLattice >> finalize [
    self destroy.
]

BobLattice >> handle [
    ^ handle
]

BobLattice >> nx [ ^ nx ]
BobLattice >> ny [ ^ ny ]
BobLattice >> nz [ ^ nz ]
BobLattice >> coupling [ ^ coupling ]
BobLattice >> volume [ ^ volume ]
BobLattice >> coordinationNumber [ ^ coordinationNumber ]

BobLattice >> printOn: aStream [
    aStream nextPutAll: 'BobLattice('.
    aStream nextPutAll: nx printString; nextPutAll: 'x'; nextPutAll: ny printString; nextPutAll: 'x'; nextPutAll: nz printString.
    aStream nextPutAll: ', J='; nextPutAll: coupling printString; nextPutAll: ')'.
]

"--------------------------------------------------------------------------------"
" BobState - Quantum State Vector (Complex Amplitudes)
"--------------------------------------------------------------------------------"

Object subclass: #BobState
    instanceVariableNames: 'handle lattice dimension amplitudesCache'
    classVariableNames: ''
    package: 'BOB-Quantum-FFI'

BobState class >> forLattice: aLattice [
    ^ self basicNew initializeForLattice: aLattice
]

BobState class >> forLattice: aLattice dimension: dim [
    ^ self basicNew initializeForLattice: aLattice dimension: dim
]

BobState >> initializeForLattice: aLattice [
    lattice := aLattice.
    dimension := 1 bitShift: aLattice volume. "2^N for qubits, assuming spin-1/2 per site"
    self initializeHandle
]

BobState >> initializeForLattice: aLattice dimension: dim [
    lattice := aLattice.
    dimension := dim.
    self initializeHandle
]

BobState >> initializeHandle [
    handle := BobQuantumLibrary current function: #bob_state_create value: lattice handle value: dimension.
    handle ifNil: [ self error: 'Failed to create quantum state' ].
    amplitudesCache := nil.
    ^ self
]

BobState >> copy [
    | newHandle newState |
    newHandle := BobQuantumLibrary current function: #bob_state_copy value: handle.
    newHandle ifNil: [ ^ nil ].
    newState := self class basicNew.
    newState handle: newHandle; lattice: lattice; dimension: dimension; yourself.
    ^ newState
]

BobState >> handle: aHandle [
    handle := aHandle.
]

BobState >> lattice: aLattice [
    lattice := aLattice.
]

BobState >> dimension: anInt [
    dimension := anInt.
]

BobState >> getAmplitudeAt: index [
    "Returns a Complex number (Pharo Complex class)"
    | ptr real imag |
    ptr := BobQuantumLibrary current function: #bob_state_get_amplitude value: handle value: index.
    ptr ifNil: [ ^ Complex zero ].
    "Assuming C returns struct { double re; double im; }* or similar packed memory.
    We simulate reading memory via ExternalAddress >> getByte / getDouble.
    For this binding, we assume a helper or specific ABI.
    Here we mock the memory read for completeness."
    real := self readDoubleFrom: ptr offset: 0.
    imag := self readDoubleFrom: ptr offset: 8.
    ^ Complex real: real imaginary: imag
]

BobState >> setAmplitudeAt: index to: complexValue [
    | ptr |
    ptr := self allocateComplexBuffer: complexValue.
    BobQuantumLibrary current function: #bob_state_set_amplitude value: handle value: index value: ptr.
    self freeBuffer: ptr.
]

BobState >> allocateComplexBuffer: c [
    | ptr |
    ptr := ExternalAddress malloc: 16. "2 doubles"
    ptr at: 0 putDouble: c real.
    ptr at: 8 putDouble: c imag.
    ^ ptr
]

BobState >> freeBuffer: ptr [
    ptr free.
]

BobState >> readDoubleFrom: ptr offset: off [
    ^ ptr at: off getDouble.
]

BobState >> normalize [
    BobQuantumLibrary current function: #bob_state_normalize value: handle.
    amplitudesCache := nil.
]

BobState >> innerProductWith: otherState [
    "Returns Complex"
    | ptr real imag |
    ptr := BobQuantumLibrary current function: #bob_state_inner_product value: handle value: otherState handle.
    ptr ifNil: [ ^ Complex zero ].
    real := self readDoubleFrom: ptr offset: 0.
    imag := self readDoubleFrom: ptr offset: 8.
    self freeBuffer: ptr.
    ^ Complex real: real imaginary: imag
]

BobState >> expectationValueOf: hamiltonian [
    ^ BobQuantumLibrary current function: #bob_state_expectation_value value: handle value: hamiltonian handle
]

BobState >> entropy [
    ^ BobQuantumLibrary current function: #bob_state_entropy value: handle
]

BobState >> fidelityWith: otherState [
    ^ BobQuantumLibrary current function: #bob_state_fidelity value: handle value: otherState handle
]

BobState >> asArray [
    | arr |
    amplitudesCache ifNotNil: [ ^ amplitudesCache ].
    arr := Array new: dimension.
    0 to: dimension - 1 do: [ :i |
        arr at: i + 1 put: (self getAmplitudeAt: i)
    ].
    amplitudesCache := arr.
    ^ arr
]

BobState >> probabilities [
    ^ self asArray collect: [ :c | c squaredMagnitude ]
]

BobState >> destroy [
    handle ifNotNil: [
        BobQuantumLibrary current function: #bob_state_destroy value: handle.
        handle := nil.
    ].
    amplitudesCache := nil.
]

BobState >> finalize [
    self destroy.
]

BobState >> handle [ ^ handle ]
BobState >> lattice [ ^ lattice ]
BobState >> dimension [ ^ dimension ]

BobState >> printOn: aStream [
    aStream nextPutAll: 'BobState(dim='; nextPutAll: dimension printString; nextPutAll: ')'.
]

"--------------------------------------------------------------------------------"
" BobHamiltonian - Quantum Hamiltonian Operator
"--------------------------------------------------------------------------------"

Object subclass: #BobHamiltonian
    instanceVariableNames: 'handle lattice matrixCache eigenvaluesCache'
    classVariableNames: ''
    package: 'BOB-Quantum-FFI'

BobHamiltonian class >> forLattice: aLattice [
    ^ self basicNew initializeForLattice: aLattice
]

BobHamiltonian >> initializeForLattice: aLattice [
    lattice := aLattice.
    handle := BobQuantumLibrary current function: #bob_hamiltonian_create value: lattice handle.
    handle ifNil: [ self error: 'Failed to create Hamiltonian' ].
    matrixCache := nil.
    eigenvaluesCache := nil.
    ^ self
]

BobHamiltonian >> addIsingTerm: strength siteI: i siteJ: j [
    BobQuantumLibrary current function: #bob_hamiltonian_add_ising_term value: handle value: strength value: i value: j.
    matrixCache := nil.
    eigenvaluesCache := nil.
]

BobHamiltonian >> addTransverseField: strength site: i [
    BobQuantumLibrary current function: #bob_hamiltonian_add_transverse_field value: handle value: strength value: i.
    matrixCache := nil.
    eigenvaluesCache := nil.
]

BobHamiltonian >> addHeisenbergTerm: strength siteI: i siteJ: j [
    BobQuantumLibrary current function: #bob_hamiltonian_add_heisenberg_term value: handle value: strength value: i value: j.
    matrixCache := nil.
    eigenvaluesCache := nil.
]

BobHamiltonian >> addCustomTerm: matrixData size: dim [
    "matrixData: ExternalAddress to double[dim*dim] (row major)"
    BobQuantumLibrary current function: #bob_hamiltonian_add_custom_term value: handle value: matrixData value: dim.
    matrixCache := nil.
    eigenvaluesCache := nil.
]

BobHamiltonian >> buildMatrix [
    BobQuantumLibrary current function: #bob_hamiltonian_build_matrix value: handle.
    matrixCache := nil.
]

BobHamiltonian >> getMatrix [
    matrixCache ifNotNil: [ ^ matrixCache ].
    | ptr dim data |
    dim := lattice volume.
    ptr := BobQuantumLibrary current function: #bob_hamiltonian_get_matrix value: handle.
    ptr ifNil: [ ^ nil ].
    "Read dim x dim complex matrix (16 bytes per entry)"
    data := Matrix rows: dim columns: dim.
    0 to: dim - 1 do: [ :r |
        0 to: dim - 1 do: [ :c |
            | offset real imag |
            offset := (r * dim + c) * 16.
            real := ptr at: offset getDouble.
            imag := ptr at: offset + 8 getDouble.
            data at: r + 1 at: c + 1 put: (Complex real: real imaginary: imag)
        ]
    ].
    matrixCache := data.
    ^ data
]

BobHamiltonian >> getEigenvalues: k [
    "Returns lowest k eigenvalues as Array of Doubles"
    eigenvaluesCache ifNotNil: [ ^ eigenvaluesCache first: k ].
    | ptr buffer dim |
    dim := lattice volume.
    k := k min: dim.
    buffer := ExternalAddress malloc: (k * 8).
    ptr := BobQuantumLibrary current function: #bob_hamiltonian_get_eigenvalues value: handle value: buffer value: k.
    ptr ifNil: [ ^ nil ].
    eigenvaluesCache := Array new: k.
    1 to: k do: [ :i |
        eigenvaluesCache at: i put: (buffer at: (i-1)*8 getDouble)
    ].
    buffer free.
    ^ eigenvaluesCache
]

BobHamiltonian >> groundStateEnergy [
    ^ (self getEigenvalues: 1) first
]

BobHamiltonian >> destroy [
    handle ifNotNil: [
        BobQuantumLibrary current function: #bob_hamiltonian_destroy value: handle.
        handle := nil.
    ].
    matrixCache := nil.
    eigenvaluesCache := nil.
]

BobHamiltonian >> finalize [
    self destroy.
]

BobHamiltonian >> handle [ ^ handle ]
BobHamiltonian >> lattice [ ^ lattice ]

BobHamiltonian >> printOn: aStream [
    aStream nextPutAll: 'BobHamiltonian(for: '; nextPutAll: lattice printString; nextPutAll: ')'.
]

"--------------------------------------------------------------------------------"
" BobQuantumWorld - High Level Simulation Facade
"--------------------------------------------------------------------------------"

Object subclass: #BobQuantumWorld
    instanceVariableNames: 'handle lattice state hamiltonian rng simulationTime stepCount observablesHistory'
    classVariableNames: ''
    package: 'BOB-Quantum-FFI'

BobQuantumWorld class >> new [
    ^ self basicNew initialize
]

BobQuantumWorld >> initialize [
    handle := BobQuantumLibrary current function: #bob_world_create value: nil value: nil value: nil. "Null pointers for auto-create"
    handle ifNil: [ self error: 'Failed to create Quantum World' ].
    lattice := nil.
    state := nil.
    hamiltonian := nil.
    rng := BobRNG new.
    simulationTime := 0.0.
    stepCount := 0.
    observablesHistory := OrderedCollection new.
    ^ self
]

BobQuantumWorld >> createLattice: nx ny: ny nz: nz coupling: j [
    lattice := BobLattice create: nx ny: ny nz: nz coupling: j.
    "Re-initialize world with this lattice"
    handle := BobQuantumLibrary current function: #bob_world_create_lattice value: handle value: nx value: ny value: nz value: j.
    handle ifNil: [ self error: 'Failed to create lattice in world' ].
    state := BobState forLattice: lattice.
    hamiltonian := BobHamiltonian forLattice: lattice.
    ^ lattice
]

BobQuantumWorld >> addIsingInteraction: strength between: i and: j [
    hamiltonian addIsingTerm: strength siteI: i siteJ: j.
]

BobQuantumWorld >> addTransverseField: strength at: i [
    hamiltonian addTransverseField: strength site: i.
]

BobQuantumWorld >> addHeisenbergInteraction: strength between: i and: j [
    hamiltonian addHeisenbergTerm: strength siteI: i siteJ: j.
]

BobQuantumWorld >> buildHamiltonian [
    hamiltonian buildMatrix.
]

BobQuantumWorld >> initializeState: aStateBlock [
    "aStateBlock: block taking (state, lattice) to populate amplitudes"
    aStateBlock value: state value: lattice.
    state normalize.
]

BobQuantumWorld >> initializeRandomState [
    | dim i |
    dim := state dimension.
    0 to: dim - 1 do: [ :i |
        | re im |
        re := rng nextGaussianWithMean: 0 sigma: 1.
        im := rng nextGaussianWithMean: 0 sigma: 1.
        state setAmplitudeAt: i to: (Complex real: re imaginary: im)
    ].
    state normalize.
]

BobQuantumWorld >> initializeGroundState [
    | evals evecs |
    "Requires diagonalization - mocking via lowest eigenvector retrieval"
    evals := hamiltonian getEigenvalues: 1.
    "In real impl, we'd get eigenvector. Here we mock."
    self initializeRandomState. "Placeholder"
]

BobQuantumWorld >> runSimulation: steps dt: dt [
    | result energy mag |
    steps timesRepeat: [ :step |
        result := BobQuantumLibrary current function: #bob_world_run_simulation value: handle value: 1 value: dt.
        result = 0 ifTrue: [ self error: 'Simulation step failed at step ', step printString ].
        simulationTime := simulationTime + dt.
        stepCount := stepCount + 1.
        "Record observables"
        energy := self currentEnergy.
        mag := self currentMagnetization.
        observablesHistory add: { #step -> stepCount. #time -> simulationTime. #energy -> energy. #magnetization -> mag }.
    ].
    ^ observablesHistory
]

BobQuantumWorld >> runSimulation: steps dt: dt withCallback: aBlock [
    steps timesRepeat: [ :step |
        BobQuantumLibrary current function: #bob_world_run_simulation value: handle value: 1 value: dt.
        simulationTime := simulationTime + dt.
        stepCount := stepCount + 1.
        aBlock value: self value: stepCount value: simulationTime.
    ].
]

BobQuantumWorld >> currentEnergy [
    ^ BobQuantumLibrary current function: #bob_world_get_energy value: handle
]

BobQuantumWorld >> currentMagnetization [
    ^ BobQuantumLibrary current function: #bob_world_get_magnetization value: handle value: 0 "Z-axis"
]

BobQuantumWorld >> correlationBetween: i and: j [
    ^ BobQuantumLibrary current function: #bob_world_get_correlation value: handle value: i value: j
]

BobQuantumWorld >> visualize [
    self visualizeWithTitle: 'BOB Quantum Simulation' width: 800 height: 600
]

BobQuantumWorld >> visualizeWithTitle: title width: w height: h [
    BobQuantumLibrary current function: #bob_world_visualize value: handle value: title value: w value: h.
]

BobQuantumWorld >> visualizeToFile: filename [
    "Assumes C library supports file output via title path or separate func"
    BobQuantumLibrary current function: #bob_world_visualize value: handle value: filename value: 1920 value: 1080.
]

BobQuantumWorld >> checkpoint: filename [
    | result |
    result := BobQuantumLibrary current function: #bob_world_checkpoint value: handle value: filename.
    ^ result = 1
]

BobQuantumWorld >> restore: filename [
    | result |
    result := BobQuantumLibrary current function: #bob_world_restore value: handle value: filename.
    result = 1 ifTrue: [ self refreshHandles ].
    ^ result = 1
]

BobQuantumWorld >> refreshHandles [
    lattice := BobLattice basicNew handle: (BobQuantumLibrary current function: #bob_world_get_lattice value: handle); yourself.
    state := BobState basicNew handle: (BobQuantumLibrary current function: #bob_world_get_state value: handle); lattice: lattice; yourself.
    hamiltonian := BobHamiltonian basicNew handle: (BobQuantumLibrary current function: #bob_world_get_hamiltonian value: handle); lattice: lattice; yourself.
]

BobQuantumWorld >> getState [
    ^ state
]

BobQuantumWorld >> getHamiltonian [
    ^ hamiltonian
]

BobQuantumWorld >> getLattice [
    ^ lattice
]

BobQuantumWorld >> getObservablesHistory [
    ^ observablesHistory
]

BobQuantumWorld >> exportObservablesAsCSV [
    | stream |
    stream := WriteStream on: String new.
    stream nextPutAll: 'step,time,energy,magnetization'; cr.
    observablesHistory do: [ :obs |
        stream
            nextPutAll: (obs at: #step) printString; nextPut: $,;
            nextPutAll: (obs at: #time) printString; nextPut: $,;
            nextPutAll: (obs at: #energy) printString; nextPut: $,;
            nextPutAll: (obs at: #magnetization) printString; cr.
    ].
    ^ stream contents
]

BobQuantumWorld >> destroy [
    handle ifNotNil: [
        BobQuantumLibrary current function: #bob_world_destroy value: handle.
        handle := nil.
    ].
    lattice ifNotNil: [ lattice destroy ].
    state ifNotNil: [ state destroy ].
    hamiltonian ifNotNil: [ hamiltonian destroy ].
    rng ifNotNil: [ rng destroy ].
]

BobQuantumWorld >> finalize [
    self destroy.
]

BobQuantumWorld >> handle [ ^ handle ]
BobQuantumWorld >> simulationTime [ ^ simulationTime ]
BobQuantumWorld >> stepCount [ ^ stepCount ]

BobQuantumWorld >> printOn: aStream [
    aStream nextPutAll: 'BobQuantumWorld('.
    aStream nextPutAll: 'steps='; nextPutAll: stepCount printString.
    aStream nextPutAll: ', time='; nextPutAll: simulationTime printString.
    lattice ifNotNil: [ aStream nextPutAll: ', '; nextPutAll: lattice printString ].
    aStream nextPutAll: ')'.
]

"--------------------------------------------------------------------------------"
" Utility Extensions & Helpers
"--------------------------------------------------------------------------------"

"ExternalAddress helper methods for structured memory access (simulated for Pharo FFI)"
ExternalAddress >> at: offset putDouble: aDouble [
    "Primitive: write double at offset. Implemented in VM/FFI plugin."
    <primitive: 'primitiveExternalAddressAtPutDouble' module: 'FFI'>
    ^ self primitiveFailed
]

ExternalAddress >> at: offset getDouble [
    "Primitive: read double at offset."
    <primitive: 'primitiveExternalAddressAtGetDouble' module: 'FFI'>
    ^ self primitiveFailed
]

ExternalAddress >> malloc: size [
    "Primitive: allocate memory."
    <primitive: 'primitiveExternalAddressMalloc' module: 'FFI'>
    ^ self primitiveFailed
]

ExternalAddress >> free [
    "Primitive: free memory."
    <primitive: 'primitiveExternalAddressFree' module: 'FFI'>
    ^ self primitiveFailed
]

"Complex Number Support (Pharo Kernel)"
Object subclass: #Complex [
    instanceVariableNames: 'real imag'
    classVariableNames: ''
    package: 'BOB-Quantum-Math'
]

Complex class >> real: r imaginary: i [
    ^ self basicNew setReal: r imaginary: i; yourself
]

Complex >> setReal: r imaginary: i [
    real := r. imag := i. ^ self
]

Complex class >> zero [ ^ self real: 0 imaginary: 0 ]
Complex class >> one [ ^ self real: 1 imaginary: 0 ]
Complex class >> i [ ^ self real: 0 imaginary: 1 ]

Complex >> real [ ^ real ]
Complex >> imag [ ^ imag ]

Complex >> + aComplex [
    ^ Complex real: real + aComplex real imaginary: imag + aComplex imag
]

Complex >> - aComplex [
    ^ Complex real: real - aComplex real imaginary: imag - aComplex imag
]

Complex >> * aComplex [
    ^ Complex
        real: (real * aComplex real) - (imag * aComplex imag)
        imaginary: (real * aComplex imag) + (imag * aComplex real)
]

Complex >> / aComplex [
    | denom |
    denom := aComplex squaredMagnitude.
    ^ Complex
        real: ((real * aComplex real) + (imag * aComplex imag)) / denom
        imaginary: ((imag * aComplex real) - (real * aComplex imag)) / denom
]

Complex >> squaredMagnitude [
    ^ real * real + imag * imag
]

Complex >> magnitude [
    ^ self squaredMagnitude sqrt
]

Complex >> conjugate [
    ^ Complex real: real imaginary: imag negated
]

Complex >> exp [
    | r |
    r := real exp.
    ^ Complex real: r * imag cos imaginary: r * imag sin
]

Complex >> printOn: aStream [
    aStream nextPutAll: '('; nextPutAll: real printString.
    imag >= 0 ifTrue: [ aStream nextPutAll: '+' ].
    aStream nextPutAll: imag printString; nextPutAll: 'i)'.
]

Complex >> = aComplex [
    ^ real = aComplex real and: [ imag = aComplex imag ]
]

Complex >> hash [
    ^ real hash bitXor: imag hash
]

"Matrix Helper (Simple Array of Arrays wrapper)"
Object subclass: #Matrix [
    instanceVariableNames: 'rows columns data'
    classVariableNames: ''
    package: 'BOB-Quantum-Math'
]

Matrix class >> rows: r columns: c [
    ^ self basicNew initializeRows: r columns: c
]

Matrix >> initializeRows: r columns: c [
    rows := r. columns := c.
    data := Array new: r * c withAll: Complex zero.
    ^ self
]

Matrix >> at: r at: c [
    ^ data at: ((r - 1) * columns + c)
]

Matrix >> at: r at: c put: val [
    data at: ((r - 1) * columns + c) put: val.
]

Matrix >> row: r [
    | arr |
    arr := Array new: columns.
    1 to: columns do: [ :c | arr at: c put: (self at: r at: c) ].
    ^ arr
]

Matrix >> column: c [
    | arr