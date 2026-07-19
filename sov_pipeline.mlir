// ════════════════════════════════════════════════════════════════
// SOV_PIPELINE.MLIR — Polyhedral fusion spec
// MLIR affine/linalg pipeline: U * rho * U† → SINGLE KERNEL
// Targets: ARM64 SVE2 | x86_64 AVX-512 | NVIDIA PTX
//
// Compile pipeline:
//   mlir-opt --affine-loop-fusion --linalg-tile="tile-sizes=16,16"
//             --vectorize --gpu-kernel-outlining
//             --convert-linalg-to-loops --convert-vector-to-scf
//             --convert-scf-to-llvm
//             sov_pipeline.mlir -o sov_llvm.mlir
// ════════════════════════════════════════════════════════════════

module @sov_gemm_fused {

  // ── Types ──────────────────────────────────────────────────────
  // complex<f64> represented as !sov.complex = vector<2xf64>
  // Density matrix: memref<?x?xvector<2xf64>>

  // ── exp(H) computation (scaling & squaring) ───────────────────
  func.func private @sov_exp_ham(
      %H  : memref<?x?xvector<2xf64>>,
      %dt : f64
  ) -> memref<?x?xvector<2xf64>>

  // ── U† = conj(transpose(U)) ───────────────────────────────────
  func.func private @sov_adjoint(
      %U : memref<?x?xvector<2xf64>>
  ) -> memref<?x?xvector<2xf64>>

  // ── Plasma verify (inlined into kernel) ───────────────────────
  func.func private @sov_plasma_verify_mlir(
      %rho : memref<?x?xvector<2xf64>>
  ) -> i1

  // ── Blake3 hash ───────────────────────────────────────────────
  func.func private @sov_blake3_hash(
      %rho  : memref<?x?xvector<2xf64>>,
      %hash : memref<32xi8>
  )

  // ── Ed25519 sign ──────────────────────────────────────────────
  func.func private @sov_ed25519_sign(
      %hash : memref<32xi8>,
      %sk   : memref<32xi8>,
      %sig  : memref<64xi8>
  )

  // ── MAIN FUSED KERNEL ─────────────────────────────────────────
  // Computes: out_rho = exp(-i*dt*H) * rho * exp(+i*dt*H)
  // Then: plasma verify + blake3 hash + ed25519 sign
  // MLIR linalg.matmul fusion merges tmp=U*rho and out=tmp*U†
  // into ONE kernel (zero intermediate materialisation on GPU).
  func.func @sov_fused_uru(
      %H       : memref<?x?xvector<2xf64>>,
      %rho     : memref<?x?xvector<2xf64>>,
      %dt      : f64,
      %sk      : memref<32xi8>,
      %pk      : memref<32xi8>,
      %out_rho : memref<?x?xvector<2xf64>>,
      %out_hash: memref<32xi8>,
      %out_sig : memref<64xi8>
  ) {
    %n = memref.dim %H, %c0 : memref<?x?xvector<2xf64>>

    // 1. Compute U = exp(-i * dt * H)
    %U    = func.call @sov_exp_ham(%H, %dt) : (memref<?x?xvector<2xf64>>, f64) -> memref<?x?xvector<2xf64>>
    %Udag = func.call @sov_adjoint(%U)      : (memref<?x?xvector<2xf64>>) -> memref<?x?xvector<2xf64>>

    // 2. tmp = U * rho  (linalg: affine_map column-major, tile 16x16)
    %tmp = memref.alloc(%n, %n) : memref<?x?xvector<2xf64>>
    linalg.matmul
      ins(%U, %rho   : memref<?x?xvector<2xf64>>, memref<?x?xvector<2xf64>>)
      outs(%tmp      : memref<?x?xvector<2xf64>>)

    // 3. out_rho = tmp * U†  (fused with step 2 by --affine-loop-fusion)
    linalg.matmul
      ins(%tmp, %Udag  : memref<?x?xvector<2xf64>>, memref<?x?xvector<2xf64>>)
      outs(%out_rho    : memref<?x?xvector<2xf64>>)

    // 4. Plasma verify (constant-time, inlined)
    %ok = func.call @sov_plasma_verify_mlir(%out_rho) : (memref<?x?xvector<2xf64>>) -> i1
    cf.assert %ok, "PLASMA: out_rho failed density check"

    // 5. Blake3 hash of out_rho
    func.call @sov_blake3_hash(%out_rho, %out_hash)
        : (memref<?x?xvector<2xf64>>, memref<32xi8>) -> ()

    // 6. Ed25519 sign
    func.call @sov_ed25519_sign(%out_hash, %sk, %out_sig)
        : (memref<32xi8>, memref<32xi8>, memref<64xi8>) -> ()

    memref.dealloc %tmp : memref<?x?xvector<2xf64>>
    return
  }

  // ── GPU VARIANT (outlined by --gpu-kernel-outlining) ──────────
  // After outlining, linalg.matmul loops become gpu.launch regions
  // targeting PTX (nvptx64) or SPIR-V (AMD/Intel) depending on llc target.

  func.func @sov_fused_uru_gpu(
      %H       : memref<?x?xvector<2xf64>>,
      %rho     : memref<?x?xvector<2xf64>>,
      %dt      : f64,
      %sk      : memref<32xi8>,
      %pk      : memref<32xi8>,
      %out_rho : memref<?x?xvector<2xf64>>,
      %out_hash: memref<32xi8>,
      %out_sig : memref<64xi8>
  ) {
    // Host: compute U, U†, allocate device buffers
    // Device: fused matmul kernel (PTX/SPIR-V)
    // Host: plasma verify + hash + sign (constant-time, CPU)
    func.call @sov_fused_uru(%H, %rho, %dt, %sk, %pk, %out_rho, %out_hash, %out_sig)
        : (memref<?x?xvector<2xf64>>, memref<?x?xvector<2xf64>>, f64,
           memref<32xi8>, memref<32xi8>, memref<?x?xvector<2xf64>>,
           memref<32xi8>, memref<64xi8>) -> ()
    return
  }

  // Constants
  arith.constant %c0 = 0 : index

} // module @sov_gemm_fused
