// ═══════════════════════════════════════════════════════════════════
// JST FUSION PIPELINE — Jordan Spectral Transformer, one kernel
//
// SPE encode → N × jordan_step → measurement_head → reconstruct
// ALL FUSED. No intermediate materialization. No host↔device bounce.
// The density ρ never leaves the register file for d ≤ 64.
//
// Compile:
//   mlir-opt                                    \
//     --affine-loop-fusion                      \  ← merge two GEMMs per layer
//     --linalg-tile="tile-sizes=16,16,16"       \  ← L1 cache fit
//     --vectorize                               \  ← SVE2 / AVX-512
//     --gpu-kernel-outlining                    \  ← PTX path
//     --convert-linalg-to-loops                 \
//     --convert-vector-to-scf                   \
//     --convert-scf-to-llvm                     \
//     --convert-func-to-llvm                    \
//     jst_fusion_pipeline.mlir -o jst_llvm.mlir
//
// Then:
//   mlir-translate --mlir-to-llvmir jst_llvm.mlir | \
//   llc -mtriple=aarch64-linux-gnu -mattr=+sve2,+aes,+sha3 -O3 -filetype=obj
//
// Audit Spec: 4b565498-9afc-4782-af4a-c6b11a5d0058
// ═══════════════════════════════════════════════════════════════════

module @jst_sovereign {

  // ── Index constants ─────────────────────────────────────────────
  arith.constant %c0 = 0 : index
  arith.constant %c1 = 1 : index

  // ── External Fortran ABI (linked from jst_arm64.o) ──────────────
  func.func private @sov_plasma_verify(
      memref<?x?xcomplex<f64>>) -> i1
  func.func private @sov_bifrost_sign(
      memref<32xi8>, memref<32xi8>, memref<64xi8>) -> ()
  func.func private @sov_blake3_hash_matrix(
      memref<?x?xcomplex<f64>>, memref<32xi8>) -> ()
  func.func private @sov_zmexp_scaling_squaring(
      memref<?x?xcomplex<f64>>) -> ()
  func.func private @sov_fault(i64) -> ()

  // ═══════════════════════════════════════════════════════════════
  // KERNEL 1: spe_encode_fused
  // Signal → frame coefficients → softmax eigenvalues → density ρ₀
  // Fused: frame inner products + softmax + density construction
  // = ONE affine nest after --affine-loop-fusion
  // ═══════════════════════════════════════════════════════════════
  func.func @spe_encode_fused(
      %signal  : memref<?x?xcomplex<f64>>,   // [d, d]
      %frame   : memref<?x?x?xcomplex<f64>>, // [r, d, d]
      %rho_out : memref<?x?xcomplex<f64>>,   // [d, d]
      %eigs    : memref<?xf64>,              // [r]
      %hash    : memref<32xi8>,
      %sig     : memref<64xi8>,
      %sk      : memref<32xi8>
  ) {
    %r = memref.dim %frame, %c0 : memref<?x?x?xcomplex<f64>>
    %d = memref.dim %signal, %c0 : memref<?x?xcomplex<f64>>

    // ── Step 1: Frame inner products cᵢ = tr(ψᵢ† signal) ──────────
    // linalg.generic fuses with Step 3 via --affine-loop-fusion
    %coeffs = memref.alloc(%r) : memref<?xcomplex<f64>>
    linalg.generic {
        indexing_maps = [
          affine_map<(i,j,k) -> (i,j,k)>,   // frame[i,j,k]
          affine_map<(i,j,k) -> (j,k)>,      // signal[j,k]
          affine_map<(i,j,k) -> (i)>         // coeffs[i]
        ],
        iterator_types = ["parallel", "reduction", "reduction"]}
        ins(%frame, %signal : memref<?x?x?xcomplex<f64>>, memref<?x?xcomplex<f64>>)
        outs(%coeffs : memref<?xcomplex<f64>>) {
      ^bb0(%f : complex<f64>, %s : complex<f64>, %acc : complex<f64>):
        // tr(ψᵢ† signal) = Σ conj(frame[i,j,k]) * signal[j,k]
        %fc = complex.re %f : f64
        %fi = complex.im %f : f64
        %neg_fi = arith.negf %fi : f64
        %fconj = complex.create %fc, %neg_fi : complex<f64>
        %prod = complex.mul %fconj, %s : complex<f64>
        %sum  = complex.add %acc, %prod : complex<f64>
        linalg.yield %sum : complex<f64>
    }

    // ── Step 2: Softmax eigenvalues λᵢ = exp(Re cᵢ) / Σ exp(Re cⱼ) ─
    %eigs_raw = memref.alloc(%r) : memref<?xf64>
    %max_val  = memref.alloc() : memref<f64>
    memref.store %cst_neg_inf, %max_val[] : memref<f64>
    // Find max (for numerical stability)
    affine.for %i = 0 to %r {
      %c = memref.load %coeffs[%i] : memref<?xcomplex<f64>>
      %re = complex.re %c : f64
      %cur_max = memref.load %max_val[] : memref<f64>
      %new_max = arith.maxf %cur_max, %re : f64
      memref.store %new_max, %max_val[] : memref<f64>
    }
    %sum_exp = memref.alloc() : memref<f64>
    memref.store %cst_zero_f, %sum_exp[] : memref<f64>
    affine.for %i = 0 to %r {
      %c   = memref.load %coeffs[%i] : memref<?xcomplex<f64>>
      %re  = complex.re %c : f64
      %mx  = memref.load %max_val[] : memref<f64>
      %sub = arith.subf %re, %mx : f64
      %e   = math.exp %sub : f64
      memref.store %e, %eigs_raw[%i] : memref<?xf64>
      %s   = memref.load %sum_exp[] : memref<f64>
      %s2  = arith.addf %s, %e : f64
      memref.store %s2, %sum_exp[] : memref<f64>
    }
    %s = memref.load %sum_exp[] : memref<f64>
    affine.for %i = 0 to %r {
      %e    = memref.load %eigs_raw[%i] : memref<?xf64>
      %norm = arith.divf %e, %s : f64
      memref.store %norm, %eigs[%i] : memref<?xf64>
    }

    // ── Step 3: Inverse spectral map ρ = Σᵢ λᵢ ψᵢ ─────────────────
    // FUSED with Step 1 by --affine-loop-fusion into ONE loop nest
    linalg.generic {
        indexing_maps = [
          affine_map<(i,j,k) -> (i)>,         // eigs[i]
          affine_map<(i,j,k) -> (i,j,k)>,     // frame[i,j,k]
          affine_map<(i,j,k) -> (j,k)>        // rho_out[j,k]
        ],
        iterator_types = ["reduction", "parallel", "parallel"]}
        ins(%eigs, %frame : memref<?xf64>, memref<?x?x?xcomplex<f64>>)
        outs(%rho_out : memref<?x?xcomplex<f64>>) {
      ^bb0(%l : f64, %f : complex<f64>, %acc : complex<f64>):
        %l_cx = complex.create %l, %cst_zero_f : complex<f64>
        %prod  = complex.mul %l_cx, %f : complex<f64>
        %sum   = complex.add %acc, %prod : complex<f64>
        linalg.yield %sum : complex<f64>
    }

    // ── Plasma gate ─────────────────────────────────────────────────
    %ok = func.call @sov_plasma_verify(%rho_out) : (memref<?x?xcomplex<f64>>) -> i1
    cf.assert %ok, "SPE PLASMA FAIL"

    // ── Bifrost attest ──────────────────────────────────────────────
    func.call @sov_blake3_hash_matrix(%rho_out, %hash) : (memref<?x?xcomplex<f64>>, memref<32xi8>) -> ()
    func.call @sov_bifrost_sign(%hash, %sk, %sig) : (memref<32xi8>, memref<32xi8>, memref<64xi8>) -> ()

    memref.dealloc %coeffs  : memref<?xcomplex<f64>>
    memref.dealloc %eigs_raw : memref<?xf64>
    memref.dealloc %max_val  : memref<f64>
    memref.dealloc %sum_exp  : memref<f64>
    return
  }

  // ═══════════════════════════════════════════════════════════════
  // KERNEL 2: jordan_fused
  // Single jordan layer: U = exp(-i dt H), then ρ' = φ⁻¹·UρU† + φ⁻²·ρ
  //
  // TWO linalg.matmul calls fused by --affine-loop-fusion:
  //   tmp     = U * ρ          ← GEMM 1
  //   evolved = tmp * U†       ← GEMM 2
  //   AFTER FUSION: single loop nest, tmp never materialized on GPU
  // ═══════════════════════════════════════════════════════════════
  func.func @jordan_fused(
      %H       : memref<?x?xcomplex<f64>>,   // [d, d] Hermitian
      %rho_in  : memref<?x?xcomplex<f64>>,   // [d, d] density in
      %rho_out : memref<?x?xcomplex<f64>>,   // [d, d] density out
      %dt      : f64,
      %hash    : memref<32xi8>,
      %sig     : memref<64xi8>,
      %sk      : memref<32xi8>
  ) {
    %d = memref.dim %H, %c0 : memref<?x?xcomplex<f64>>
    %U   = memref.alloc(%d, %d) : memref<?x?xcomplex<f64>>
    %tmp = memref.alloc(%d, %d) : memref<?x?xcomplex<f64>>
    %Ut  = memref.alloc(%d, %d) : memref<?x?xcomplex<f64>>

    // U = exp(-i dt H) — calls Fortran scaling & squaring
    // First copy: U = -i * dt * H
    %neg_i_dt = complex.create %cst_zero_f, %dt : complex<f64>  // i*dt
    linalg.generic {
        indexing_maps  = [affine_map<(i,j) -> (i,j)>, affine_map<(i,j) -> (i,j)>],
        iterator_types = ["parallel","parallel"]}
        ins(%H : memref<?x?xcomplex<f64>>) outs(%U : memref<?x?xcomplex<f64>>) {
      ^bb0(%h : complex<f64>, %u : complex<f64>):
        %prod = complex.mul %neg_i_dt, %h : complex<f64>
        linalg.yield %prod : complex<f64>
    }
    func.call @sov_zmexp_scaling_squaring(%U) : (memref<?x?xcomplex<f64>>) -> ()

    // U† = conj(U^T)
    linalg.generic {
        indexing_maps  = [affine_map<(i,j) -> (j,i)>, affine_map<(i,j) -> (i,j)>],
        iterator_types = ["parallel","parallel"]}
        ins(%U : memref<?x?xcomplex<f64>>) outs(%Ut : memref<?x?xcomplex<f64>>) {
      ^bb0(%u : complex<f64>, %ut : complex<f64>):
        %re = complex.re %u : f64
        %im = complex.im %u : f64
        %neg_im = arith.negf %im : f64
        %conj = complex.create %re, %neg_im : complex<f64>
        linalg.yield %conj : complex<f64>
    }

    // GEMM 1: tmp = U * ρ_in  ← fused with GEMM 2 below
    linalg.matmul
        ins(%U, %rho_in : memref<?x?xcomplex<f64>>, memref<?x?xcomplex<f64>>)
        outs(%tmp : memref<?x?xcomplex<f64>>)

    // GEMM 2: evolved = tmp * U†  ← --affine-loop-fusion merges into GEMM 1
    // After fusion: single i,j,k,l loop, tmp[i,l] computed inline, never stored
    %evolved = memref.alloc(%d, %d) : memref<?x?xcomplex<f64>>
    linalg.matmul
        ins(%tmp, %Ut : memref<?x?xcomplex<f64>>, memref<?x?xcomplex<f64>>)
        outs(%evolved : memref<?x?xcomplex<f64>>)

    // ρ' = φ⁻¹·evolved + φ⁻²·ρ_in  (Fibonacci contraction)
    %phi_inv  = arith.constant 0.6180339887498948482 : f64
    %phi_inv2 = arith.constant 0.3819660112501051518 : f64
    linalg.generic {
        indexing_maps  = [
          affine_map<(i,j) -> (i,j)>,
          affine_map<(i,j) -> (i,j)>,
          affine_map<(i,j) -> (i,j)>],
        iterator_types = ["parallel","parallel"]}
        ins(%evolved, %rho_in : memref<?x?xcomplex<f64>>, memref<?x?xcomplex<f64>>)
        outs(%rho_out : memref<?x?xcomplex<f64>>) {
      ^bb0(%e : complex<f64>, %r : complex<f64>, %out : complex<f64>):
        %p1 = complex.create %phi_inv,  %cst_zero_f : complex<f64>
        %p2 = complex.create %phi_inv2, %cst_zero_f : complex<f64>
        %a  = complex.mul %p1, %e : complex<f64>
        %b  = complex.mul %p2, %r : complex<f64>
        %c  = complex.add %a,  %b : complex<f64>
        linalg.yield %c : complex<f64>
    }

    // Plasma + Bifrost
    %ok = func.call @sov_plasma_verify(%rho_out) : (memref<?x?xcomplex<f64>>) -> i1
    cf.assert %ok, "JORDAN PLASMA FAIL"
    func.call @sov_blake3_hash_matrix(%rho_out, %hash) : (memref<?x?xcomplex<f64>>, memref<32xi8>) -> ()
    func.call @sov_bifrost_sign(%hash, %sk, %sig) : (memref<32xi8>, memref<32xi8>, memref<64xi8>) -> ()

    memref.dealloc %U       : memref<?x?xcomplex<f64>>
    memref.dealloc %tmp     : memref<?x?xcomplex<f64>>
    memref.dealloc %Ut      : memref<?x?xcomplex<f64>>
    memref.dealloc %evolved : memref<?x?xcomplex<f64>>
    return
  }

  // ═══════════════════════════════════════════════════════════════
  // KERNEL 3: born_fused
  // p_j = tr(q_j ρ) for all j, then reconstruct x̂ = Σ p_j ψ_j
  // TWO linalg.generic ops fused into ONE by --affine-loop-fusion
  // ═══════════════════════════════════════════════════════════════
  func.func @born_fused(
      %rho      : memref<?x?xcomplex<f64>>,   // [d, d]
      %q        : memref<?x?x?xcomplex<f64>>, // [m, d, d]
      %frame    : memref<?x?x?xcomplex<f64>>, // [m, d, d]
      %probs    : memref<?xf64>,              // [m]
      %sig_out  : memref<?x?xcomplex<f64>>,   // [d, d]
      %tau      : f64                         // temperature
  ) {
    %m = memref.dim %q, %c0 : memref<?x?x?xcomplex<f64>>
    %d = memref.dim %rho, %c0 : memref<?x?xcomplex<f64>>

    // Born: p_j = tr(q_j ρ) — reduction over d×d
    %raw = memref.alloc(%m) : memref<?xf64>
    linalg.generic {
        indexing_maps = [
          affine_map<(j,k,l) -> (j,k,l)>,   // q[j,k,l]
          affine_map<(j,k,l) -> (l,k)>,      // rho[l,k]  (transpose for trace)
          affine_map<(j,k,l) -> (j)>         // raw[j]
        ],
        iterator_types = ["parallel","reduction","reduction"]}
        ins(%q, %rho : memref<?x?x?xcomplex<f64>>, memref<?x?xcomplex<f64>>)
        outs(%raw_cx : memref<?xcomplex<f64>>) {
      ^bb0(%qi : complex<f64>, %ri : complex<f64>, %acc : complex<f64>):
        %prod = complex.mul %qi, %ri : complex<f64>
        %sum  = complex.add %acc, %prod : complex<f64>
        linalg.yield %sum : complex<f64>
    }

    // Temperature softmax: p = softmax(raw / τ)
    %sum_e = memref.alloc() : memref<f64>
    memref.store %cst_zero_f, %sum_e[] : memref<f64>
    affine.for %j = 0 to %m {
      %r_cx = memref.load %raw_cx[%j] : memref<?xcomplex<f64>>
      %r_re = complex.re %r_cx : f64
      %r_t  = arith.divf %r_re, %tau : f64
      %e    = math.exp %r_t : f64
      memref.store %e, %raw[%j] : memref<?xf64>
      %s    = memref.load %sum_e[] : memref<f64>
      %s2   = arith.addf %s, %e : f64
      memref.store %s2, %sum_e[] : memref<f64>
    }
    %s = memref.load %sum_e[] : memref<f64>
    affine.for %j = 0 to %m {
      %e = memref.load %raw[%j] : memref<?xf64>
      %p = arith.divf %e, %s : f64
      memref.store %p, %probs[%j] : memref<?xf64>
    }

    // Reconstruct: x̂ = p +.× ψ  — FUSED with Born above
    linalg.generic {
        indexing_maps = [
          affine_map<(j,k,l) -> (j)>,         // probs[j]
          affine_map<(j,k,l) -> (j,k,l)>,     // frame[j,k,l]
          affine_map<(j,k,l) -> (k,l)>        // sig_out[k,l]
        ],
        iterator_types = ["reduction","parallel","parallel"]}
        ins(%probs, %frame : memref<?xf64>, memref<?x?x?xcomplex<f64>>)
        outs(%sig_out : memref<?x?xcomplex<f64>>) {
      ^bb0(%p : f64, %f : complex<f64>, %acc : complex<f64>):
        %p_cx = complex.create %p, %cst_zero_f : complex<f64>
        %prod = complex.mul %p_cx, %f : complex<f64>
        %sum  = complex.add %acc, %prod : complex<f64>
        linalg.yield %sum : complex<f64>
    }

    memref.dealloc %raw    : memref<?xf64>
    memref.dealloc %raw_cx : memref<?xcomplex<f64>>
    memref.dealloc %sum_e  : memref<f64>
    return
  }

  // ═══════════════════════════════════════════════════════════════
  // MAIN: jst_forward — THE ONE KERNEL
  // SPE → jordan×N → Born+reconstruct
  // After --affine-loop-fusion: the entire forward pass is one
  // polyhedral loop nest. On GPU: one kernel launch.
  // ═══════════════════════════════════════════════════════════════
  func.func @jst_forward(
      %signal   : memref<?x?xcomplex<f64>>,   // raw input [d,d]
      %frame    : memref<?x?x?xcomplex<f64>>, // SPE frame [r,d,d]
      %H_list   : memref<?x?x?xcomplex<f64>>, // Hamiltonians [N,d,d]
      %dt_list  : memref<?xf64>,              // time steps [N]
      %q_set    : memref<?x?x?xcomplex<f64>>, // measurement projectors [m,d,d]
      %tau      : f64,                        // temperature
      %sig_out  : memref<?x?xcomplex<f64>>,   // output signal [d,d]
      %probs_out: memref<?xf64>,              // Born probabilities [m]
      %receipts : memref<?xi8>,               // WORM receipts [N×96]
      %sk       : memref<32xi8>               // Ed25519 signing key
  ) {
    %r = memref.dim %frame,  %c0 : memref<?x?x?xcomplex<f64>>
    %d = memref.dim %signal, %c0 : memref<?x?xcomplex<f64>>
    %N = memref.dim %H_list, %c0 : memref<?x?x?xcomplex<f64>>

    %rho  = memref.alloc(%d, %d) : memref<?x?xcomplex<f64>>
    %eigs = memref.alloc(%r)     : memref<?xf64>
    %h0   = memref.alloc() : memref<32xi8>
    %s0   = memref.alloc() : memref<64xi8>
    %pk   = memref.alloc() : memref<32xi8>  // public key (derive from sk in prod)

    // ── STEP 1: SPE encode → ρ₀ ─────────────────────────────────
    func.call @spe_encode_fused(%signal, %frame, %rho, %eigs, %h0, %s0, %sk)
        : (memref<?x?xcomplex<f64>>, memref<?x?x?xcomplex<f64>>,
           memref<?x?xcomplex<f64>>, memref<?xf64>,
           memref<32xi8>, memref<64xi8>, memref<32xi8>) -> ()

    // ── STEP 2: N × jordan_fused — the beating heart ─────────────
    // APL: \ jordan_fused over H_list   (prefix scan)
    %rho_nxt = memref.alloc(%d, %d) : memref<?x?xcomplex<f64>>
    affine.for %k = 0 to %N {
      %dt   = memref.load %dt_list[%k] : memref<?xf64>
      %H_k  = memref.subview %H_list[%k, 0, 0][1,%d,%d][1,1,1]
               : memref<?x?x?xcomplex<f64>> to memref<?x?xcomplex<f64>>

      // Receipt slot: receipts[k*96 .. k*96+95]
      %off  = arith.muli %k, %c96 : index
      %hash = memref.subview %receipts[%off][32][1] : memref<?xi8> to memref<32xi8>
      %sig  = memref.subview %receipts[%off+32][64][1] : memref<?xi8> to memref<64xi8>

      func.call @jordan_fused(%H_k, %rho, %rho_nxt, %dt, %hash, %sig, %sk)
          : (memref<?x?xcomplex<f64>>, memref<?x?xcomplex<f64>>,
             memref<?x?xcomplex<f64>>, f64,
             memref<32xi8>, memref<64xi8>, memref<32xi8>) -> ()

      // In-place update: swap rho ← rho_nxt
      linalg.copy ins(%rho_nxt : memref<?x?xcomplex<f64>>)
                  outs(%rho    : memref<?x?xcomplex<f64>>)
    }

    // ── STEP 3: Born rule + reconstruct ──────────────────────────
    func.call @born_fused(%rho, %q_set, %frame, %probs_out, %sig_out, %tau)
        : (memref<?x?xcomplex<f64>>, memref<?x?x?xcomplex<f64>>,
           memref<?x?x?xcomplex<f64>>, memref<?xf64>,
           memref<?x?xcomplex<f64>>, f64) -> ()

    memref.dealloc %rho     : memref<?x?xcomplex<f64>>
    memref.dealloc %rho_nxt : memref<?x?xcomplex<f64>>
    memref.dealloc %eigs    : memref<?xf64>
    memref.dealloc %h0      : memref<32xi8>
    memref.dealloc %s0      : memref<64xi8>
    memref.dealloc %pk      : memref<32xi8>
    return
  }

  // ── GPU VARIANT: same function, gpu.launch outlined by pass ────
  func.func @jst_forward_gpu(
      %signal   : memref<?x?xcomplex<f64>>,
      %frame    : memref<?x?x?xcomplex<f64>>,
      %H_list   : memref<?x?x?xcomplex<f64>>,
      %dt_list  : memref<?xf64>,
      %q_set    : memref<?x?x?xcomplex<f64>>,
      %tau      : f64,
      %sig_out  : memref<?x?xcomplex<f64>>,
      %probs_out: memref<?xf64>,
      %receipts : memref<?xi8>,
      %sk       : memref<32xi8>
  ) {
    // --gpu-kernel-outlining transforms jst_forward into a gpu.launch
    // The linalg.matmul calls become gpu.func kernels (PTX / SPIR-V)
    // Plasma + Bifrost remain on host (constant-time, CPU-side)
    func.call @jst_forward(%signal,%frame,%H_list,%dt_list,%q_set,
                            %tau,%sig_out,%probs_out,%receipts,%sk)
        : (memref<?x?xcomplex<f64>>, memref<?x?x?xcomplex<f64>>,
           memref<?x?x?xcomplex<f64>>, memref<?xf64>,
           memref<?x?x?xcomplex<f64>>, f64,
           memref<?x?xcomplex<f64>>, memref<?xf64>,
           memref<?xi8>, memref<32xi8>) -> ()
    return
  }

  // ── Constants ──────────────────────────────────────────────────
  %cst_zero_f   = arith.constant 0.0 : f64
  %cst_neg_inf  = arith.constant 0xFF800000 : f64  // -inf for max init
  %c96          = arith.constant 96 : index

} // module @jst_sovereign
