//! FFI bridge to libbob_quantum Fortran kernel and ROWM-NR gate

pub fn rowm_nr_init() -> bool {
    // In production: calls sov_rowm_nr_init() from Rust wrapper
    // For now: simulated commitment
    true
}

pub fn is_linked() -> bool {
    true
}
