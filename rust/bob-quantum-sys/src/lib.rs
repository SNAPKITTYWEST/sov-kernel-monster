pub mod spectral;

use std::ffi::c_void;
use std::os::raw::{c_int, c_double};
use std::ptr;
use std::fmt;
use num_complex::Complex;

#[link(name = "bob_quantum")]
extern "C" {
    // Opaque types
    type bob_rng_t;
    type bob_lattice_t;
    type bob_state_t;
    type bob_hamiltonian_t;

    // Error constants
    pub const BOB_SUCCESS: c_int = 0;
    pub const BOB_ERROR_OUT_OF_MEMORY: c_int = -1;
    pub const BOB_ERROR_INVALID_PARAMETER: c_int = -2;
    pub const BOB_ERROR_INVALID_OPERATION: c_int = -3;
    pub const BOB_ERROR_INVALID_GATE: c_int = -4;

    // Function signatures
    pub fn bob_rng_create() -> *mut bob_rng_t;
    pub fn bob_rng_destroy(rng: *mut bob_rng_t);
    pub fn bob_lattice_create() -> *mut bob_lattice_t;
    pub fn bob_lattice_destroy(lattice: *mut bob_lattice_t);
    pub fn bob_state_create() -> *mut bob_state_t;
    pub fn bob_state_destroy(state: *mut bob_state_t);
    pub fn bob_hamiltonian_create() -> *mut bob_hamiltonian_t;
    pub fn bob_hamiltonian_destroy(hamiltonian: *mut bob_hamiltonian_t);
    pub fn bob_rng_generate(rng: *mut bob_rng_t, buffer: *mut c_double, size: c_int) -> c_int;
    pub fn bob_lattice_add_site(lattice: *mut bob_lattice_t, site_id: c_int) -> c_int;
    pub fn bob_state_apply_gate(state: *mut bob_state_t, gate_id: c_int, target: c_int) -> c_int;
    pub fn bob_hamiltonian_add_term(hamiltonian: *mut bob_hamiltonian_t, coefficient: c_double, term: *const c_int, term_size: c_int) -> c_int;
    pub fn bob_state_evolve(state: *mut bob_state_t, hamiltonian: *mut bob_hamiltonian_t, time: c_double) -> c_int;
    pub fn bob_state_get_amplitude(state: *mut bob_state_t, index: c_int, amplitude: *mut Complex