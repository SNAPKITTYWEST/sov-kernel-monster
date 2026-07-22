// BOB Quantum Civilization Engine - Zig Bindings
// Systems-level quantum simulation with memory safety
// High-performance FFI to C library with zero-copy operations

const std = @import("std");
const c = @cImport({
    @cInclude("bob_quantum.h");
});

/// Error type for quantum operations
pub const QuantumError = error{
    MemoryAllocationFailed,
    InvalidParameter,
    InternalError,
    NotImplemented,
    FileIOError,
    UnknownError,
};

/// Error code mapping
fn errorCodeToError(code: i32) QuantumError!void {
    switch (code) {
        0 => return, // BOB_ERROR_NONE
        1 => return QuantumError.MemoryAllocationFailed,
        2 => return QuantumError.InvalidParameter,
        3 => return QuantumError.InternalError,
        4 => return QuantumError.NotImplemented,
        5 => return QuantumError.FileIOError,
        else => return QuantumError.UnknownError,
    }
}

/// =========================================================================
/// RNG Subsystem
/// =========================================================================

pub const RNG = struct {
    handle: ?*c.bob_rng_handle_t,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, seed: u64) QuantumError!RNG {
        var rng_ptr: ?*c.bob_rng_handle_t = null;
        const err = c.bob_rng_create(&rng_ptr);
        try errorCodeToError(err);

        if (err == 0 and seed > 0) {
            const seed_err = c.bob_rng_seed(rng_ptr, seed);
            try errorCodeToError(seed_err);
        }

        return RNG{
            .handle = rng_ptr,
            .allocator = allocator,
        };
    }

    pub fn destroy(self: *RNG) QuantumError!void {
        if (self.handle != null) {
            const err = c.bob_rng_destroy(self.handle);
            try errorCodeToError(err);
        }
    }

    pub fn seed(self: *RNG, new_seed: u64) QuantumError!void {
        const err = c.bob_rng_seed(self.handle, new_seed);
        try errorCodeToError(err);
    }

    pub fn uniform(self: *RNG) QuantumError!f64 {
        var value: f64 = 0.0;
        const err = c.bob_rng_uniform(self.handle, &value);
        try errorCodeToError(err);
        return value;
    }

    pub fn normal(self: *RNG) QuantumError!f64 {
        var value: f64 = 0.0;
        const err = c.bob_rng_normal(self.handle, &value);
        try errorCodeToError(err);
        return value;
    }

    pub fn integer(self: *RNG, min: i64, max: i64) QuantumError!i64 {
        var value: i64 = 0;
        const err = c.bob_rng_integer(self.handle, min, max, &value);
        try errorCodeToError(err);
        return value;
    }

    pub fn uniformBatch(self: *RNG, allocator: std.mem.Allocator, count: usize) QuantumError![]f64 {
        var values = try allocator.alloc(f64, count);
        errdefer allocator.free(values);

        for (values) |*val| {
            val.* = try self.uniform();
        }
        return values;
    }

    pub fn normalBatch(self: *RNG, allocator: std.mem.Allocator, count: usize) QuantumError![]f64 {
        var values = try allocator.alloc(f64, count);
        errdefer allocator.free(values);

        for (values) |*val| {
            val.* = try self.normal();
        }
        return values;
    }
};

/// =========================================================================
/// Lattice Subsystem
/// =========================================================================

pub const Lattice = struct {
    handle: ?*c.bob_lattice_handle_t,
    nx: i32,
    ny: i32,
    nz: i32,
    coupling: f64,
    allocator: std.mem.Allocator,

    pub fn create(
        allocator: std.mem.Allocator,
        nx: i32,
        ny: i32,
        nz: i32,
        coupling: f64,
        seed: u64,
    ) QuantumError!Lattice {
        var lat_ptr: ?*c.bob_lattice_handle_t = null;
        const err = c.bob_lattice_create(nx, ny, nz, coupling, seed, &lat_ptr);
        try errorCodeToError(err);

        return Lattice{
            .handle = lat_ptr,
            .nx = nx,
            .ny = ny,
            .nz = nz,
            .coupling = coupling,
            .allocator = allocator,
        };
    }

    pub fn destroy(self: *Lattice) QuantumError!void {
        if (self.handle != null) {
            const err = c.bob_lattice_destroy(self.handle);
            try errorCodeToError(err);
        }
    }

    pub fn evolve(self: *Lattice, steps: i32) QuantumError!f64 {
        var energy: f64 = 0.0;
        const err = c.bob_lattice_evolve(self.handle, steps, &energy);
        try errorCodeToError(err);
        return energy;
    }

    pub fn energy(self: *Lattice) QuantumError!f64 {
        var value: f64 = 0.0;
        const err = c.bob_lattice_energy(self.handle, &value);
        try errorCodeToError(err);
        return value;
    }

    pub fn entropy(self: *Lattice) QuantumError!f64 {
        var value: f64 = 0.0;
        const err = c.bob_lattice_entropy(self.handle, &value);
        try errorCodeToError(err);
        return value;
    }

    pub fn correlation(self: *Lattice, distance: i32) QuantumError!f64 {
        var value: f64 = 0.0;
        const err = c.bob_lattice_correlation(self.handle, distance, &value);
        try errorCodeToError(err);
        return value;
    }

    pub fn magnetization(
        self: *Lattice,
        x: i32,
        y: i32,
        z: i32,
    ) QuantumError!f64 {
        var value: f64 = 0.0;
        const err = c.bob_lattice_magnetization(self.handle, x, y, z, &value);
        try errorCodeToError(err);
        return value;
    }

    pub fn applyField(
        self: *Lattice,
        min_x: i32,
        min_y: i32,
        min_z: i32,
        max_x: i32,
        max_y: i32,
        max_z: i32,
        strength: f64,
    ) QuantumError!void {
        const err = c.bob_lattice_apply_field(
            self.handle,
            min_x,
            min_y,
            min_z,
            max_x,
            max_y,
            max_z,
            strength,
        );
        try errorCodeToError(err);
    }
};

/// =========================================================================
/// Quantum State Subsystem
/// =========================================================================

pub const InitialState = enum(i32) {
    zero = 0,
    plus = 1,
    random = 2,
};

pub const QuantumState = struct {
    handle: ?*c.bob_state_handle_t,
    n_qubits: i32,
    allocator: std.mem.Allocator,

    pub fn create(
        allocator: std.mem.Allocator,
        n_qubits: i32,
        initial: InitialState,
    ) QuantumError!QuantumState {
        var state_ptr: ?*c.bob_state_handle_t = null;
        const err = c.bob_state_create(n_qubits, @enumToInt(initial), &state_ptr);
        try errorCodeToError(err);

        return QuantumState{
            .handle = state_ptr,
            .n_qubits = n_qubits,
            .allocator = allocator,
        };
    }

    pub fn destroy(self: *QuantumState) QuantumError!void {
        if (self.handle != null) {
            const err = c.bob_state_destroy(self.handle);
            try errorCodeToError(err);
        }
    }

    pub fn measure(self: *QuantumState, qubit: i32) QuantumError!struct { outcome: i32, prob: f64 } {
        var outcome: i32 = 0;
        var prob: f64 = 0.0;
        const err = c.bob_state_measure(self.handle, qubit, &outcome, &prob);
        try errorCodeToError(err);
        return .{ .outcome = outcome, .prob = prob };
    }

    pub fn applyGate(
        self: *QuantumState,
        gate_type: i32,
        qubit: i32,
        params: ?[]const f64,
    ) QuantumError!void {
        const params_ptr = if (params) |p| @ptrCast(?[*]const f64, p.ptr) else null;
        const n_params = if (params) |p| @intCast(i32, p.len) else 0;

        const err = c.bob_state_apply_gate(
            self.handle,
            gate_type,
            qubit,
            params_ptr,
            n_params,
        );
        try errorCodeToError(err);
    }

    pub fn applyControlledGate(
        self: *QuantumState,
        gate_type: i32,
        control: i32,
        target: i32,
        params: ?[]const f64,
    ) QuantumError!void {
        const params_ptr = if (params) |p| @ptrCast(?[*]const f64, p.ptr) else null;
        const n_params = if (params) |p| @intCast(i32, p.len) else 0;

        const err = c.bob_state_apply_controlled(
            self.handle,
            gate_type,
            control,
            target,
            params_ptr,
            n_params,
        );
        try errorCodeToError(err);
    }

    pub fn normalize(self: *QuantumState) QuantumError!void {
        const err = c.bob_state_normalize(self.handle);
        try errorCodeToError(err);
    }

    pub fn expectation(self: *QuantumState, operator: [*:0]const u8) QuantumError!f64 {
        var value: f64 = 0.0;
        const err = c.bob_state_expectation(self.handle, operator, &value);
        try errorCodeToError(err);
        return value;
    }

    pub fn amplitudes(self: *QuantumState, allocator: std.mem.Allocator) QuantumError![]struct { re: f64, im: f64 } {
        var n: i32 = 0;
        var amps_ptr: ?*anyopaque = null;
        const err = c.bob_state_amplitudes(self.handle, &n, &amps_ptr);
        try errorCodeToError(err);

        if (n <= 0) return allocator.alloc(struct { re: f64, im: f64 }, 0);

        var result = try allocator.alloc(struct { re: f64, im: f64 }, @intCast(usize, n));
        errdefer allocator.free(result);

        const doubles = @ptrCast([*]f64, @alignCast(@alignOf(f64), amps_ptr));
        for (result) |*amp, i| {
            amp.re = doubles[i * 2];
            amp.im = doubles[i * 2 + 1];
        }

        return result;
    }

    pub fn clone(self: *QuantumState) QuantumError!QuantumState {
        var cloned_ptr: ?*c.bob_state_handle_t = null;
        const err = c.bob_state_clone(self.handle, &cloned_ptr);
        try errorCodeToError(err);

        return QuantumState{
            .handle = cloned_ptr,
            .n_qubits = self.n_qubits,
            .allocator = self.allocator,
        };
    }

    pub fn fidelity(self: *QuantumState, other: *QuantumState) QuantumError!f64 {
        var value: f64 = 0.0;
        const err = c.bob_state_fidelity(self.handle, other.handle, &value);
        try errorCodeToError(err);
        return value;
    }
};

/// =========================================================================
/// Hamiltonian Subsystem
/// =========================================================================

pub const HamiltonianType = enum(i32) {
    sparse = 0,
    dense = 1,
    mpo = 2,
};

pub const Hamiltonian = struct {
    handle: ?*c.bob_hamiltonian_handle_t,
    n_qubits: i32,
    allocator: std.mem.Allocator,

    pub fn create(
        allocator: std.mem.Allocator,
        n_qubits: i32,
        ham_type: HamiltonianType,
    ) QuantumError!Hamiltonian {
        var ham_ptr: ?*c.bob_hamiltonian_handle_t = null;
        const err = c.bob_hamiltonian_create(n_qubits, @enumToInt(ham_type), &ham_ptr);
        try errorCodeToError(err);

        return Hamiltonian{
            .handle = ham_ptr,
            .n_qubits = n_qubits,
            .allocator = allocator,
        };
    }

    pub fn destroy(self: *Hamiltonian) QuantumError!void {
        if (self.handle != null) {
            const err = c.bob_hamiltonian_destroy(self.handle);
            try errorCodeToError(err);
        }
    }

    pub fn addTerm(
        self: *Hamiltonian,
        coeff_re: f64,
        coeff_im: f64,
        qubits: []const i32,
    ) QuantumError!void {
        const err = c.bob_hamiltonian_add_term(
            self.handle,
            coeff_re,
            coeff_im,
            @ptrCast(?[*]const i32, qubits.ptr),
            @intCast(i32, qubits.len),
        );
        try errorCodeToError(err);
    }

    pub fn expectation(self: *Hamiltonian, state: *QuantumState) QuantumError!struct { re: f64, im: f64 } {
        var exp_re: f64 = 0.0;
        var exp_im: f64 = 0.0;
        const err = c.bob_hamiltonian_expectation(self.handle, state.handle, &exp_re, &exp_im);
        try errorCodeToError(err);
        return .{ .re = exp_re, .im = exp_im };
    }

    pub fn eigenvalues(self: *Hamiltonian, allocator: std.mem.Allocator, n_vals: i32) QuantumError![]f64 {
        var vals_ptr: ?*f64 = null;
        const err = c.bob_hamiltonian_eigenvalues(self.handle, n_vals, @ptrCast(?*?*f64, &vals_ptr));
        try errorCodeToError(err);

        if (n_vals <= 0) return allocator.alloc(f64, 0);

        var result = try allocator.alloc(f64, @intCast(usize, n_vals));
        errdefer allocator.free(result);

        for (result) |*val, i| {
            val.* = vals_ptr.?[i];
        }

        return result;
    }

    pub fn timeEvolve(
        self: *Hamiltonian,
        state: *QuantumState,
        time: f64,
    ) QuantumError!QuantumState {
        var evolved_ptr: ?*c.bob_state_handle_t = null;
        const err = c.bob_hamiltonian_time_evolve(self.handle, state.handle, time, &evolved_ptr);
        try errorCodeToError(err);

        return QuantumState{
            .handle = evolved_ptr,
            .n_qubits = state.n_qubits,
            .allocator = state.allocator,
        };
    }
};

/// =========================================================================
/// Example Functions
/// =========================================================================

pub fn example_simple_rng(allocator: std.mem.Allocator) !void {
    var rng = try RNG.create(allocator, 12345);
    defer _ = rng.destroy() catch {};

    const u1 = try rng.uniform();
    const n1 = try rng.normal();
    const i1 = try rng.integer(0, 100);

    std.debug.print("Uniform: {}\n", .{u1});
    std.debug.print("Normal: {}\n", .{n1});
    std.debug.print("Integer: {}\n", .{i1});
}

pub fn example_quantum_circuit(allocator: std.mem.Allocator) !void {
    var state = try QuantumState.create(allocator, 2, .zero);
    defer _ = state.destroy() catch {};

    try state.applyGate(0, 0, null); // Hadamard on qubit 0
    const result = try state.measure(0);

    std.debug.print("Measurement: {} with prob {}\n", .{ result.outcome, result.prob });
}

pub fn example_lattice_evolution(allocator: std.mem.Allocator) !void {
    var lattice = try Lattice.create(allocator, 4, 4, 4, 1.0, 42);
    defer _ = lattice.destroy() catch {};

    for (0..10) |i| {
        const energy = try lattice.energy();
        const entropy = try lattice.entropy();
        _ = try lattice.evolve(1);

        std.debug.print("Step {}: E={} S={}\n", .{ i, energy, entropy });
    }
}

pub fn example_vqe_ansatz(allocator: std.mem.Allocator) !void {
    var ham = try Hamiltonian.create(allocator, 2, .sparse);
    defer _ = ham.destroy() catch {};

    var state = try QuantumState.create(allocator, 2, .zero);
    defer _ = state.destroy() catch {};

    const params1 = [_]f64{1.5};
    const params2 = [_]f64{0.7};

    try state.applyGate(7, 0, &params1); // RY on qubit 0
    try state.applyGate(8, 0, &params2); // RZ on qubit 0

    try ham.addTerm(1.0, 0.0, &[_]i32{0});
    try ham.addTerm(1.0, 0.0, &[_]i32{1});

    const exp = try ham.expectation(&state);
    std.debug.print("Expectation: {} + {}i\n", .{ exp.re, exp.im });
}
