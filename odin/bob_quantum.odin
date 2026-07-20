package bob_quantum

// BOB Quantum Civilization Engine - Odin Bindings
// VR-optimized quantum simulation for game engines
// High-performance lattice visualization and real-time evolution

import "core:c"
import "core:math"
import "core:mem"
import "core:slice"

// =========================================================================
// Constants
// =========================================================================

ERROR_NONE :: 0
ERROR_MEMORY_ALLOCATION_FAILED :: 1
ERROR_INVALID_PARAMETER :: 2
ERROR_INTERNAL_ERROR :: 3
ERROR_NOT_IMPLEMENTED :: 4
ERROR_FILE_IO_ERROR :: 5
ERROR_UNKNOWN_ERROR :: 6

// Gate type codes
GATE_H :: 0
GATE_X :: 1
GATE_Y :: 2
GATE_Z :: 3
GATE_S :: 4
GATE_T :: 5
GATE_RX :: 6
GATE_RY :: 7
GATE_RZ :: 8
GATE_CX :: 9
GATE_CY :: 10
GATE_CZ :: 11

// Initial state codes
INITIAL_ZERO :: 0
INITIAL_PLUS :: 1
INITIAL_RANDOM :: 2

// Hamiltonian type codes
HAM_SPARSE :: 0
HAM_DENSE :: 1
HAM_MPO :: 2

// =========================================================================
// FFI Types
// =========================================================================

RNG_Handle :: distinct rawptr
Lattice_Handle :: distinct rawptr
State_Handle :: distinct rawptr
Hamiltonian_Handle :: distinct rawptr

Quantum_Error :: enum {
    None,
    MemoryAllocationFailed,
    InvalidParameter,
    InternalError,
    NotImplemented,
    FileIOError,
    UnknownError,
}

// =========================================================================
// FFI Foreign Declarations
// =========================================================================

@(default_calling_convention="c")
foreign "libbob_quantum" {
    // RNG functions
    bob_rng_create :: proc(rng: ^RNG_Handle) -> c.int ---
    bob_rng_destroy :: proc(rng: RNG_Handle) -> c.int ---
    bob_rng_seed :: proc(rng: RNG_Handle, seed: c.uint64_t) -> c.int ---
    bob_rng_uniform :: proc(rng: RNG_Handle, value: ^f64) -> c.int ---
    bob_rng_normal :: proc(rng: RNG_Handle, value: ^f64) -> c.int ---
    bob_rng_integer :: proc(rng: RNG_Handle, min: c.int64_t, max: c.int64_t, value: ^c.int64_t) -> c.int ---

    // Lattice functions
    bob_lattice_create :: proc(nx: c.int, ny: c.int, nz: c.int, coupling: f64, seed: c.uint64_t, lat: ^Lattice_Handle) -> c.int ---
    bob_lattice_destroy :: proc(lat: Lattice_Handle) -> c.int ---
    bob_lattice_evolve :: proc(lat: Lattice_Handle, steps: c.int, energy: ^f64) -> c.int ---
    bob_lattice_energy :: proc(lat: Lattice_Handle, energy: ^f64) -> c.int ---
    bob_lattice_entropy :: proc(lat: Lattice_Handle, entropy: ^f64) -> c.int ---
    bob_lattice_correlation :: proc(lat: Lattice_Handle, distance: c.int, corr: ^f64) -> c.int ---
    bob_lattice_magnetization :: proc(lat: Lattice_Handle, x: c.int, y: c.int, z: c.int, mag: ^f64) -> c.int ---
    bob_lattice_apply_field :: proc(lat: Lattice_Handle, min_x: c.int, min_y: c.int, min_z: c.int, max_x: c.int, max_y: c.int, max_z: c.int, strength: f64) -> c.int ---

    // State functions
    bob_state_create :: proc(n_qubits: c.int, initial: c.int, state: ^State_Handle) -> c.int ---
    bob_state_destroy :: proc(state: State_Handle) -> c.int ---
    bob_state_measure :: proc(state: State_Handle, qubit: c.int, outcome: ^c.int, prob: ^f64) -> c.int ---
    bob_state_measure_multi :: proc(state: State_Handle, qubits: [^]c.int, n_qubits: c.int, outcomes: ^c.int, prob: ^f64) -> c.int ---
    bob_state_apply_gate :: proc(state: State_Handle, gate: c.int, qubit: c.int, params: [^]f64, n_params: c.int) -> c.int ---
    bob_state_apply_controlled :: proc(state: State_Handle, gate: c.int, control: c.int, target: c.int, params: [^]f64, n_params: c.int) -> c.int ---
    bob_state_normalize :: proc(state: State_Handle) -> c.int ---
    bob_state_expectation :: proc(state: State_Handle, operator: cstring, value: ^f64) -> c.int ---
    bob_state_amplitudes :: proc(state: State_Handle, n: ^c.int, amps: ^rawptr) -> c.int ---
    bob_state_clone :: proc(state: State_Handle, cloned: ^State_Handle) -> c.int ---
    bob_state_fidelity :: proc(state1: State_Handle, state2: State_Handle, fidelity: ^f64) -> c.int ---

    // Hamiltonian functions
    bob_hamiltonian_create :: proc(n_qubits: c.int, ham_type: c.int, ham: ^Hamiltonian_Handle) -> c.int ---
    bob_hamiltonian_destroy :: proc(ham: Hamiltonian_Handle) -> c.int ---
    bob_hamiltonian_add_term :: proc(ham: Hamiltonian_Handle, coeff_re: f64, coeff_im: f64, qubits: [^]c.int, n_qubits: c.int) -> c.int ---
    bob_hamiltonian_expectation :: proc(ham: Hamiltonian_Handle, state: State_Handle, exp_re: ^f64, exp_im: ^f64) -> c.int ---
    bob_hamiltonian_eigenvalues :: proc(ham: Hamiltonian_Handle, n_vals: c.int, vals: ^rawptr) -> c.int ---
    bob_hamiltonian_time_evolve :: proc(ham: Hamiltonian_Handle, state: State_Handle, time: f64, evolved: ^State_Handle) -> c.int ---
}

// =========================================================================
// Error Handling
// =========================================================================

error_to_odin :: proc(code: c.int) -> Quantum_Error {
    switch code {
    case 0: return .None
    case 1: return .MemoryAllocationFailed
    case 2: return .InvalidParameter
    case 3: return .InternalError
    case 4: return .NotImplemented
    case 5: return .FileIOError
    case: return .UnknownError
    }
}

// =========================================================================
// RNG Context
// =========================================================================

RNG :: struct {
    handle: RNG_Handle,
}

rng_create :: proc(seed: u64 = 42) -> (RNG, Quantum_Error) {
    handle: RNG_Handle
    err := bob_rng_create(&handle)
    if err != ERROR_NONE {
        return {}, error_to_odin(err)
    }
    if seed > 0 {
        seed_err := bob_rng_seed(handle, seed)
        if seed_err != ERROR_NONE {
            return {}, error_to_odin(seed_err)
        }
    }
    return {handle}, .None
}

rng_destroy :: proc(rng: ^RNG) -> Quantum_Error {
    if rng.handle != nil {
        err := bob_rng_destroy(rng.handle)
        if err != ERROR_NONE {
            return error_to_odin(err)
        }
    }
    return .None
}

rng_seed :: proc(rng: ^RNG, seed: u64) -> Quantum_Error {
    err := bob_rng_seed(rng.handle, seed)
    return error_to_odin(err) if err != ERROR_NONE else .None
}

rng_uniform :: proc(rng: ^RNG) -> (f64, Quantum_Error) {
    value: f64
    err := bob_rng_uniform(rng.handle, &value)
    return value, error_to_odin(err) if err != ERROR_NONE else .None
}

rng_normal :: proc(rng: ^RNG) -> (f64, Quantum_Error) {
    value: f64
    err := bob_rng_normal(rng.handle, &value)
    return value, error_to_odin(err) if err != ERROR_NONE else .None
}

rng_integer :: proc(rng: ^RNG, min: i64, max: i64) -> (i64, Quantum_Error) {
    value: c.int64_t
    err := bob_rng_integer(rng.handle, min, max, &value)
    return i64(value), error_to_odin(err) if err != ERROR_NONE else .None
}

rng_uniform_batch :: proc(rng: ^RNG, count: int, allocator := context.allocator) -> ([]f64, Quantum_Error) {
    values := make([]f64, count, allocator)
    for i in 0..<count {
        v, err := rng_uniform(rng)
        if err != .None {
            delete(values, allocator)
            return nil, err
        }
        values[i] = v
    }
    return values, .None
}

// =========================================================================
// Lattice Context
// =========================================================================

Lattice :: struct {
    handle: Lattice_Handle,
    nx: int,
    ny: int,
    nz: int,
    coupling: f64,
}

lattice_create :: proc(nx: int, ny: int, nz: int, coupling: f64, seed: u64 = 42) -> (Lattice, Quantum_Error) {
    handle: Lattice_Handle
    err := bob_lattice_create(c.int(nx), c.int(ny), c.int(nz), coupling, seed, &handle)
    if err != ERROR_NONE {
        return {}, error_to_odin(err)
    }
    return {handle, nx, ny, nz, coupling}, .None
}

lattice_destroy :: proc(lat: ^Lattice) -> Quantum_Error {
    if lat.handle != nil {
        err := bob_lattice_destroy(lat.handle)
        if err != ERROR_NONE {
            return error_to_odin(err)
        }
    }
    return .None
}

lattice_evolve :: proc(lat: ^Lattice, steps: int) -> (f64, Quantum_Error) {
    energy: f64
    err := bob_lattice_evolve(lat.handle, c.int(steps), &energy)
    return energy, error_to_odin(err) if err != ERROR_NONE else .None
}

lattice_energy :: proc(lat: ^Lattice) -> (f64, Quantum_Error) {
    energy: f64
    err := bob_lattice_energy(lat.handle, &energy)
    return energy, error_to_odin(err) if err != ERROR_NONE else .None
}

lattice_entropy :: proc(lat: ^Lattice) -> (f64, Quantum_Error) {
    entropy: f64
    err := bob_lattice_entropy(lat.handle, &entropy)
    return entropy, error_to_odin(err) if err != ERROR_NONE else .None
}

lattice_correlation :: proc(lat: ^Lattice, distance: int) -> (f64, Quantum_Error) {
    corr: f64
    err := bob_lattice_correlation(lat.handle, c.int(distance), &corr)
    return corr, error_to_odin(err) if err != ERROR_NONE else .None
}

lattice_magnetization :: proc(lat: ^Lattice, x: int, y: int, z: int) -> (f64, Quantum_Error) {
    mag: f64
    err := bob_lattice_magnetization(lat.handle, c.int(x), c.int(y), c.int(z), &mag)
    return mag, error_to_odin(err) if err != ERROR_NONE else .None
}

lattice_apply_field :: proc(
    lat: ^Lattice,
    min_x: int, min_y: int, min_z: int,
    max_x: int, max_y: int, max_z: int,
    strength: f64,
) -> Quantum_Error {
    err := bob_lattice_apply_field(
        lat.handle,
        c.int(min_x), c.int(min_y), c.int(min_z),
        c.int(max_x), c.int(max_y), c.int(max_z),
        strength,
    )
    return error_to_odin(err) if err != ERROR_NONE else .None
}

// =========================================================================
// Quantum State Context
// =========================================================================

Quantum_State :: struct {
    handle: State_Handle,
    n_qubits: int,
}

state_create :: proc(n_qubits: int, initial: int = INITIAL_ZERO) -> (Quantum_State, Quantum_Error) {
    handle: State_Handle
    err := bob_state_create(c.int(n_qubits), c.int(initial), &handle)
    if err != ERROR_NONE {
        return {}, error_to_odin(err)
    }
    return {handle, n_qubits}, .None
}

state_destroy :: proc(state: ^Quantum_State) -> Quantum_Error {
    if state.handle != nil {
        err := bob_state_destroy(state.handle)
        if err != ERROR_NONE {
            return error_to_odin(err)
        }
    }
    return .None
}

Measurement :: struct {
    outcome: int,
    probability: f64,
}

state_measure :: proc(state: ^Quantum_State, qubit: int) -> (Measurement, Quantum_Error) {
    outcome: c.int
    prob: f64
    err := bob_state_measure(state.handle, c.int(qubit), &outcome, &prob)
    if err != ERROR_NONE {
        return {}, error_to_odin(err)
    }
    return {int(outcome), prob}, .None
}

state_apply_gate :: proc(state: ^Quantum_State, gate: int, qubit: int, params: []f64 = {}) -> Quantum_Error {
    params_ptr := raw_data(params) if len(params) > 0 else nil
    err := bob_state_apply_gate(state.handle, c.int(gate), c.int(qubit), params_ptr, c.int(len(params)))
    return error_to_odin(err) if err != ERROR_NONE else .None
}

state_apply_controlled :: proc(state: ^Quantum_State, gate: int, control: int, target: int, params: []f64 = {}) -> Quantum_Error {
    params_ptr := raw_data(params) if len(params) > 0 else nil
    err := bob_state_apply_controlled(state.handle, c.int(gate), c.int(control), c.int(target), params_ptr, c.int(len(params)))
    return error_to_odin(err) if err != ERROR_NONE else .None
}

state_normalize :: proc(state: ^Quantum_State) -> Quantum_Error {
    err := bob_state_normalize(state.handle)
    return error_to_odin(err) if err != ERROR_NONE else .None
}

state_expectation :: proc(state: ^Quantum_State, operator: cstring) -> (f64, Quantum_Error) {
    value: f64
    err := bob_state_expectation(state.handle, operator, &value)
    return value, error_to_odin(err) if err != ERROR_NONE else .None
}

Amplitude :: struct {
    re: f64,
    im: f64,
}

state_amplitudes :: proc(state: ^Quantum_State, allocator := context.allocator) -> ([]Amplitude, Quantum_Error) {
    n: c.int
    amps_ptr: rawptr
    err := bob_state_amplitudes(state.handle, &n, &amps_ptr)
    if err != ERROR_NONE {
        return nil, error_to_odin(err)
    }

    if n <= 0 {
        return make([]Amplitude, 0, allocator), .None
    }

    amps := make([]Amplitude, int(n), allocator)
    doubles := cast([^]f64)amps_ptr
    for i in 0..<int(n) {
        amps[i].re = doubles[i * 2]
        amps[i].im = doubles[i * 2 + 1]
    }

    return amps, .None
}

state_clone :: proc(state: ^Quantum_State) -> (Quantum_State, Quantum_Error) {
    handle: State_Handle
    err := bob_state_clone(state.handle, &handle)
    if err != ERROR_NONE {
        return {}, error_to_odin(err)
    }
    return {handle, state.n_qubits}, .None
}

state_fidelity :: proc(state1: ^Quantum_State, state2: ^Quantum_State) -> (f64, Quantum_Error) {
    fidelity: f64
    err := bob_state_fidelity(state1.handle, state2.handle, &fidelity)
    return fidelity, error_to_odin(err) if err != ERROR_NONE else .None
}

// =========================================================================
// Hamiltonian Context
// =========================================================================

Hamiltonian :: struct {
    handle: Hamiltonian_Handle,
    n_qubits: int,
}

hamiltonian_create :: proc(n_qubits: int, ham_type: int = HAM_SPARSE) -> (Hamiltonian, Quantum_Error) {
    handle: Hamiltonian_Handle
    err := bob_hamiltonian_create(c.int(n_qubits), c.int(ham_type), &handle)
    if err != ERROR_NONE {
        return {}, error_to_odin(err)
    }
    return {handle, n_qubits}, .None
}

hamiltonian_destroy :: proc(ham: ^Hamiltonian) -> Quantum_Error {
    if ham.handle != nil {
        err := bob_hamiltonian_destroy(ham.handle)
        if err != ERROR_NONE {
            return error_to_odin(err)
        }
    }
    return .None
}

hamiltonian_add_term :: proc(ham: ^Hamiltonian, coeff_re: f64, coeff_im: f64, qubits: []int) -> Quantum_Error {
    qubits_c := make([]c.int, len(qubits), context.allocator)
    defer delete(qubits_c, context.allocator)
    for i, q in qubits {
        qubits_c[i] = c.int(q)
    }
    err := bob_hamiltonian_add_term(ham.handle, coeff_re, coeff_im, raw_data(qubits_c), c.int(len(qubits_c)))
    return error_to_odin(err) if err != ERROR_NONE else .None
}

Complex :: struct {
    re: f64,
    im: f64,
}

hamiltonian_expectation :: proc(ham: ^Hamiltonian, state: ^Quantum_State) -> (Complex, Quantum_Error) {
    exp_re: f64
    exp_im: f64
    err := bob_hamiltonian_expectation(ham.handle, state.handle, &exp_re, &exp_im)
    return {exp_re, exp_im}, error_to_odin(err) if err != ERROR_NONE else .None
}

hamiltonian_eigenvalues :: proc(ham: ^Hamiltonian, n_vals: int, allocator := context.allocator) -> ([]f64, Quantum_Error) {
    vals_ptr: rawptr
    err := bob_hamiltonian_eigenvalues(ham.handle, c.int(n_vals), &vals_ptr)
    if err != ERROR_NONE {
        return nil, error_to_odin(err)
    }

    if n_vals <= 0 {
        return make([]f64, 0, allocator), .None
    }

    vals := make([]f64, n_vals, allocator)
    doubles := cast([^]f64)vals_ptr
    for i in 0..<n_vals {
        vals[i] = doubles[i]
    }

    return vals, .None
}

hamiltonian_time_evolve :: proc(ham: ^Hamiltonian, state: ^Quantum_State, time: f64) -> (Quantum_State, Quantum_Error) {
    handle: State_Handle
    err := bob_hamiltonian_time_evolve(ham.handle, state.handle, time, &handle)
    if err != ERROR_NONE {
        return {}, error_to_odin(err)
    }
    return {handle, state.n_qubits}, .None
}

// =========================================================================
// Examples
// =========================================================================

example_simple_rng :: proc() {
    rng, err := rng_create(12345)
    if err != .None {
        return
    }
    defer rng_destroy(&rng)

    u, _ := rng_uniform(&rng)
    n, _ := rng_normal(&rng)
    i, _ := rng_integer(&rng, 0, 100)

    fmt.printf("Uniform: %v\n", u)
    fmt.printf("Normal: %v\n", n)
    fmt.printf("Integer: %v\n", i)
}

example_quantum_circuit :: proc() {
    state, err := state_create(2)
    if err != .None {
        return
    }
    defer state_destroy(&state)

    state_apply_gate(&state, GATE_H, 0)
    result, _ := state_measure(&state, 0)

    fmt.printf("Measurement: %d with prob %v\n", result.outcome, result.probability)
}

example_lattice_evolution :: proc() {
    lattice, err := lattice_create(4, 4, 4, 1.0)
    if err != .None {
        return
    }
    defer lattice_destroy(&lattice)

    for i in 0..<10 {
        energy, _ := lattice_energy(&lattice)
        entropy, _ := lattice_entropy(&lattice)
        lattice_evolve(&lattice, 1)

        fmt.printf("Step %d: E=%v S=%v\n", i, energy, entropy)
    }
}

example_vqe :: proc() {
    ham, err := hamiltonian_create(2)
    if err != .None {
        return
    }
    defer hamiltonian_destroy(&ham)

    state, err := state_create(2)
    if err != .None {
        return
    }
    defer state_destroy(&state)

    state_apply_gate(&state, GATE_RY, 0, {1.5})
    state_apply_gate(&state, GATE_RZ, 0, {0.7})

    hamiltonian_add_term(&ham, 1.0, 0.0, {0})
    hamiltonian_add_term(&ham, 1.0, 0.0, {1})

    exp, _ := hamiltonian_expectation(&ham, &state)
    fmt.printf("Expectation: %v + %vi\n", exp.re, exp.im)
}
