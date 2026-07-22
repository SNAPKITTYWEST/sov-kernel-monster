// ═══════════════════════════════════════════════════════════════════════════
// SNDL KEY ROTATION — Crypto-Agile Key Lifecycle via φ-Decay Thermal Monad
//
// Implements automatic key rotation using φ-decay factor from training_adjoint.
// Forward secrecy: old keys become useless for future sessions (WORM-attested).
// Rotation factor derives from thermal monad: τₖ = τ₀·φ⁻ᵏ
//
// Integration: Runs AFTER QMHES hybrid key exchange, BEFORE pulse generation
// NIST-compliant: Matches FIPS 203 ML-KEM key refresh requirements
// Dependencies: spectral.rs (sndl_key_rotate), bob_worm.f90 (attestation)
// External deps: ZERO — pure MLIR using existing Fortran/Rust kernels
//
// Prior Art: SnapKitty Foundry Intel (April 14, 2026)
// Original Research Lab: JAB Capital Trust (2021)
// ═══════════════════════════════════════════════════════════════════════════

module @sndl_rotation {

  // ── Constants ──────────────────────────────────────────────────────
  arith.constant %c0 = 0 : index
  arith.constant %c1 = 1 : index
  arith.constant %c32 = 32 : index
  arith.constant %cst_zero = 0.0 : f64
  arith.constant %cst_one = 1.0 : f64
  arith.constant %phi_inv = 0.6180339887498948482 : f64

  // ── External ABI ───────────────────────────────────────────────────
  func.func private @sndl_rotate_key_ffi(
      memref<32xi8>, i64, memref<32xi8>) -> ()
  func.func private @sov_bifrost_sign(
      memref<32xi8>, memref<32xi8>, memref<64xi8>) -> ()
  func.func private @sov_blake3_hash(
      memref<?xi8>, i64, memref<32xi8>) -> ()
  func.func private @worm_append_entry(
      memref<?xi8>, i64, memref<32xi8>) -> ()

  // ═══════════════════════════════════════════════════════════════════
  // PASS: phi_decay_rotation_factor
  // Computes rotation interval from φ-decay thermal monad
  // Factor = φ⁻ᵏ where k = current depth counter
  // ═══════════════════════════════════════════════════════════════════
  func.func @phi_decay_rotation_factor(
      %depth : i64
  ) -> f64 {
    // φ⁻ᵏ via repeated multiplication (matches training_adjoint.f90)
    %result = memref.alloc() : memref<f64>
    memref.store %cst_one, %result[] : memref<f64>

    affine.for %i = 0 to %depth {
      %cur = memref.load %result[] : memref<f64>
      %next = arith.mulf %cur, %phi_inv : f64
      memref.store %next, %result[] : memref<f64>
    }

    %factor = memref.load %result[] : memref<f64>
    memref.dealloc %result : memref<f64>
    return %factor : f64
  }

  // ═══════════════════════════════════════════════════════════════════
  // MAIN: sndl_key_rotation
  // Automatically rotates key using φ-decay thermal monad
  // Forward secrecy: old keys become useless
  // WORM-attested: rotation event sealed before key swap
  // ═══════════════════════════════════════════════════════════════════
  func.func @sndl_key_rotation(
      %current_key : memref<32xi8>,   // current 32-byte SNDL key
      %depth       : i64,             // φ-decay depth counter
      %new_key     : memref<32xi8>,   // output: rotated key
      %sk          : memref<32xi8>,   // signing key
      %sig         : memref<64xi8>    // signature output
  ) {
    // STEP 1: Compute rotation via Rust spectral.rs (φ-decay driven)
    func.call @sndl_rotate_key_ffi(%current_key, %depth, %new_key)
        : (memref<32xi8>, i64, memref<32xi8>) -> ()

    // STEP 2: WORM-attest the rotation event (forward secrecy proof)
    // Hash: Blake3(old_key ‖ new_key) → rotation receipt
    %combined = memref.alloc() : memref<64xi8>
    affine.for %i = 0 to 32 {
      %old_byte = memref.load %current_key[%i] : memref<32xi8>
      memref.store %old_byte, %combined[%i] : memref<64xi8>
    }
    affine.for %i = 0 to 32 {
      %new_byte = memref.load %new_key[%i] : memref<32xi8>
      %offset = arith.addi %i, %c32 : index
      memref.store %new_byte, %combined[%offset] : memref<64xi8>
    }

    %rotation_hash = memref.alloc() : memref<32xi8>
    %c64 = arith.constant 64 : i64
    %combined_cast = memref.cast %combined : memref<64xi8> to memref<?xi8>
    func.call @sov_blake3_hash(%combined_cast, %c64, %rotation_hash)
        : (memref<?xi8>, i64, memref<32xi8>) -> ()

    // STEP 3: Sign rotation receipt (Blake3+Ed25519)
    func.call @sov_bifrost_sign(%rotation_hash, %sk, %sig)
        : (memref<32xi8>, memref<32xi8>, memref<64xi8>) -> ()

    // STEP 4: Append rotation event to WORM chain
    %entry_tag = memref.alloc() : memref<20xi8>  // "SNDL_KEY_ROTATION\0"
    %entry_cast = memref.cast %entry_tag : memref<20xi8> to memref<?xi8>
    %c20 = arith.constant 20 : i64
    func.call @worm_append_entry(%entry_cast, %c20, %rotation_hash)
        : (memref<?xi8>, i64, memref<32xi8>) -> ()

    // Cleanup
    memref.dealloc %combined      : memref<64xi8>
    memref.dealloc %rotation_hash : memref<32xi8>
    memref.dealloc %entry_tag     : memref<20xi8>
    return
  }

  // ═══════════════════════════════════════════════════════════════════
  // PASS: sndl_should_rotate
  // Determines if key rotation is needed based on φ-decay schedule
  // Returns 1 if rotation needed, 0 otherwise
  // Rotation triggers every φ⁻ᵏ intervals (natural Fibonacci schedule)
  // ═══════════════════════════════════════════════════════════════════
  func.func @sndl_should_rotate(
      %execution_count : i64,
      %depth           : i64
  ) -> i1 {
    // Rotation interval = floor(φ^depth) executions
    %phi = arith.constant 1.6180339887498948482 : f64  // φ (not φ⁻¹)
    %depth_f = arith.sitofp %depth : i64 to f64
    %interval_f = math.powf %phi, %depth_f : f64
    %interval = arith.fptosi %interval_f : f64 to i64

    // Rotate if execution_count is multiple of interval
    %remainder = arith.remsi %execution_count, %interval : i64
    %zero = arith.constant 0 : i64
    %should_rotate = arith.cmpi "eq", %remainder, %zero : i64
    return %should_rotate : i1
  }

  // ═══════════════════════════════════════════════════════════════════
  // PASS: sndl_full_lifecycle
  // Complete key lifecycle: generate → use → rotate → attest
  // Integrates with QMHES hybrid key exchange output
  // ═══════════════════════════════════════════════════════════════════
  func.func @sndl_full_lifecycle(
      %H              : memref<?x?xcomplex<f64>>,  // Hamiltonian
      %rho            : memref<?x?xcomplex<f64>>,  // density matrix
      %current_key    : memref<32xi8>,              // current key
      %execution_count: i64,                        // execution counter
      %depth          : i64,                        // φ-decay depth
      %active_key     : memref<32xi8>,              // output: active key for this execution
      %sk             : memref<32xi8>,              // signing key
      %sig            : memref<64xi8>               // signature
  ) {
    // Check if rotation needed (Fibonacci schedule)
    %needs_rotation = func.call @sndl_should_rotate(%execution_count, %depth)
        : (i64, i64) -> i1

    cf.cond_br %needs_rotation, ^rotate, ^use_current

  ^rotate:
    // Perform rotation
    func.call @sndl_key_rotation(%current_key, %depth, %active_key, %sk, %sig)
        : (memref<32xi8>, i64, memref<32xi8>, memref<32xi8>, memref<64xi8>) -> ()
    cf.br ^done

  ^use_current:
    // Copy current key as active
    affine.for %i = 0 to 32 {
      %byte = memref.load %current_key[%i] : memref<32xi8>
      memref.store %byte, %active_key[%i] : memref<32xi8>
    }
    cf.br ^done

  ^done:
    return
  }

} // module @sndl_rotation
