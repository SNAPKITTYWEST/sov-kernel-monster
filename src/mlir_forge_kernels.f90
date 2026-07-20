!======================================================================
! MLIR_FORGE_KERNELS.F90 — Fortran FFI stubs for Agent 5
! Polyhedral MLIR optimization kernel + quantum adapter injection
!
! These stubs wrap calls to mlir-opt command-line passes and provide
! a clean Fortran interface to the MLIR C API (via C wrapper).
!
! Agent 5 (Forge Master) uses this module to:
!   1. Apply affine-loop-fusion, linalg-tile, vectorize passes
!   2. Inject IBM Qiskit quantum adapter hints
!   3. Sign optimized IR via Bifrost (Ed25519)
!
! Interface: tensor<?xi8> <-> raw byte buffer (IR serialization)
!======================================================================

module mlir_forge_kernels
  use iso_c_binding
  use bob_kinds
  implicit none

  public :: mlir_forge_pipeline
  public :: inject_quantum_adapters
  public :: mlir_opt_pass_pipeline

  !====================================================================
  ! C FFI DECLARATIONS — MLIR C API (Phase 2: link to mlir-c-lib)
  !====================================================================

  ! mlir_forge_backend_t: opaque struct for MLIR context + module
  type, bind(C) :: mlir_forge_backend_t
    type(c_ptr) :: ctx
    type(c_ptr) :: mod
  end type mlir_forge_backend_t

  ! C function: init MLIR context
  interface
    subroutine mlir_context_create(ctx) bind(C, name="mlir_context_create")
      use iso_c_binding
      type(c_ptr), intent(out) :: ctx
    end subroutine
  end interface

  ! C function: load MLIR module from bytes
  interface
    function mlir_module_load_from_bytes(ctx, bytes, nbytes) result(mod) &
        bind(C, name="mlir_module_load_from_bytes")
      use iso_c_binding
      type(c_ptr), value :: ctx
      type(c_ptr), value :: bytes
      integer(c_int), value :: nbytes
      type(c_ptr) :: mod
    end function
  end interface

  ! C function: apply optimization pass pipeline
  interface
    function mlir_opt_apply_passes(mod, pass_pipeline) result(success) &
        bind(C, name="mlir_opt_apply_passes")
      use iso_c_binding
      type(c_ptr), value :: mod
      character(kind=c_char), intent(in) :: pass_pipeline(*)
      integer(c_int) :: success
    end function
  end interface

  ! C function: dump MLIR module to bytes
  interface
    function mlir_module_dump_to_bytes(mod, out_bytes, out_nbytes) result(success) &
        bind(C, name="mlir_module_dump_to_bytes")
      use iso_c_binding
      type(c_ptr), value :: mod
      type(c_ptr), intent(out) :: out_bytes
      integer(c_int), intent(out) :: out_nbytes
      integer(c_int) :: success
    end function
  end interface

  ! C function: free MLIR context
  interface
    subroutine mlir_context_destroy(ctx) bind(C, name="mlir_context_destroy")
      use iso_c_binding
      type(c_ptr), value :: ctx
    end subroutine
  end interface

contains

  !====================================================================
  ! MLIR_FORGE_PIPELINE — Core Agent 5 optimization kernel
  !
  ! Input:
  !   pipeline_ir_bytes  — Serialized MLIR IR (byte array)
  !   target_triple      — Target architecture string (e.g., "aarch64-unknown-linux-gnu")
  !   constraints        — [latency_ms, memory_mb, power_w, quantum_budget]
  !   quantum_available  — Flag: IBM Qiskit backend available?
  !
  ! Output:
  !   optimized_ir_bytes — Fused + tiled + vectorized MLIR IR
  !
  ! Process:
  !   1. Initialize MLIR context (C API)
  !   2. Load input IR into module
  !   3. Build pass pipeline string based on target_triple + constraints
  !   4. Apply passes: affine-loop-fusion → linalg-tile → vectorize → gpu-kernel-outlining
  !   5. Dump module back to bytes
  !   6. Return optimized IR (caller will Blake3 + sign)
  !====================================================================
  subroutine mlir_forge_pipeline(pipeline_ir_bytes, ir_nbytes, target_triple, constraints, &
                                  quantum_available, optimized_ir_bytes, opt_nbytes)
    implicit none

    ! Input parameters
    integer, intent(in) :: ir_nbytes, quantum_available
    integer(c_int8_t), dimension(ir_nbytes), intent(in), target :: pipeline_ir_bytes
    integer, intent(out) :: opt_nbytes

    ! String inputs (C-interop)
    character(len=*), intent(in) :: target_triple
    real(kind=rp), dimension(4), intent(in) :: constraints

    ! Output (allocatable for Fortran caller)
    integer(c_int8_t), dimension(:), allocatable, intent(out) :: optimized_ir_bytes

    ! Local variables
    type(c_ptr) :: ctx, mod, out_ptr
    integer(c_int) :: success, c_nbytes
    character(len=512) :: pass_pipeline
    character(len=:), allocatable :: c_triple

    ! ────────────────────────────────────────────────────────────────
    ! Step 1: Init MLIR context
    ! ────────────────────────────────────────────────────────────────
    call mlir_context_create(ctx)
    if (.not. c_associated(ctx)) then
      print '(A)', "[FORGE] ERROR: Failed to create MLIR context"
      opt_nbytes = 0
      return
    end if

    ! ────────────────────────────────────────────────────────────────
    ! Step 2: Load input IR
    ! ────────────────────────────────────────────────────────────────
    mod = mlir_module_load_from_bytes(ctx, c_loc(pipeline_ir_bytes(1)), ir_nbytes)
    if (.not. c_associated(mod)) then
      print '(A)', "[FORGE] ERROR: Failed to load MLIR module"
      call mlir_context_destroy(ctx)
      opt_nbytes = 0
      return
    end if

    ! ────────────────────────────────────────────────────────────────
    ! Step 3: Build pass pipeline based on target + constraints
    ! ────────────────────────────────────────────────────────────────
    call build_pass_pipeline(target_triple, constraints, quantum_available, pass_pipeline)
    print '(A,A)', "[FORGE] Pass pipeline: ", trim(pass_pipeline)

    ! ────────────────────────────────────────────────────────────────
    ! Step 4: Apply optimization passes
    ! ────────────────────────────────────────────────────────────────
    success = mlir_opt_apply_passes(mod, trim(pass_pipeline) // c_null_char)
    if (success /= 0) then
      print '(A)', "[FORGE] ERROR: MLIR optimization failed"
      call mlir_context_destroy(ctx)
      opt_nbytes = 0
      return
    end if
    print '(A)', "[FORGE] Optimization complete"

    ! ────────────────────────────────────────────────────────────────
    ! Step 5: Dump optimized module to bytes
    ! ────────────────────────────────────────────────────────────────
    success = mlir_module_dump_to_bytes(mod, out_ptr, c_nbytes)
    if (success /= 0 .or. .not. c_associated(out_ptr)) then
      print '(A)', "[FORGE] ERROR: Failed to dump MLIR module"
      call mlir_context_destroy(ctx)
      opt_nbytes = 0
      return
    end if

    ! ────────────────────────────────────────────────────────────────
    ! Step 6: Copy to Fortran output buffer
    ! ────────────────────────────────────────────────────────────────
    allocate(optimized_ir_bytes(c_nbytes))
    block
      integer(c_int8_t), pointer :: c_ptr_arr(:)
      call c_f_pointer(out_ptr, c_ptr_arr, [c_nbytes])
      optimized_ir_bytes(:) = c_ptr_arr(:)
    end block

    opt_nbytes = c_nbytes
    print '(A,I0)', "[FORGE] Output IR size: ", opt_nbytes

    ! Cleanup
    call mlir_context_destroy(ctx)

  end subroutine mlir_forge_pipeline

  !====================================================================
  ! INJECT_QUANTUM_ADAPTERS — Add IBM Qiskit quantum kernel hints
  !
  ! When IBM quantum backend is available (via Bedrock or local simulator),
  ! inject metadata into MLIR module to hint quantum circuit extraction.
  !
  ! This adds @quantum.gate operations to linalg matmul loops,
  ! enabling hybrid classical-quantum execution on Qiskit + IBM Quantum.
  !====================================================================
  subroutine inject_quantum_adapters(ir_bytes, ir_nbytes, quantum_available, &
                                      adapted_ir_bytes, adapted_nbytes)
    implicit none

    integer, intent(in) :: ir_nbytes, quantum_available
    integer(c_int8_t), dimension(ir_nbytes), intent(in), target :: ir_bytes
    integer, intent(out) :: adapted_nbytes
    integer(c_int8_t), dimension(:), allocatable, intent(out) :: adapted_ir_bytes

    if (quantum_available == 0) then
      ! No quantum; just return input IR unchanged
      allocate(adapted_ir_bytes(ir_nbytes))
      adapted_ir_bytes(:) = ir_bytes(:)
      adapted_nbytes = ir_nbytes
      return
    end if

    ! Phase 2: Wire to mlir-opt with quantum-specific passes:
    !   --convert-linalg-to-quantum --inject-qiskit-stubs
    ! For now: identity (return input unchanged, marked for Phase 2)
    allocate(adapted_ir_bytes(ir_nbytes))
    adapted_ir_bytes(:) = ir_bytes(:)
    adapted_nbytes = ir_nbytes

    print '(A)', "[FORGE] Quantum adapter injection (Phase 2)"

  end subroutine inject_quantum_adapters

  !====================================================================
  ! BUILD_PASS_PIPELINE — Construct mlir-opt pass string
  !
  ! Selects optimization passes based on target architecture and constraints:
  !
  ! Common passes (all targets):
  !   - affine-loop-fusion      (merge adjacent loops)
  !   - linalg-tile             (polyhedral tiling for cache locality)
  !   - vectorize               (convert to vector operations)
  !   - convert-linalg-to-loops (lower linalg to scf)
  !   - convert-vector-to-scf   (lower vector to scalar)
  !
  ! Target-specific:
  !   - ARM64 SVE2:   add canonicalize-for-sve2 (custom)
  !   - x86_64 AVX512: add canonicalize-for-avx512 (custom)
  !   - NVIDIA PTX:   add gpu-kernel-outlining
  !
  ! Constraint-driven:
  !   - latency < 1ms: --linalg-tile="tile-sizes=4,4" (fine grained)
  !   - memory < 512MB: --linalg-tile="tile-sizes=32,32" (conservative)
  !   - power < 10W: --vectorize-limit=2048 (reduce SIMD width)
  !====================================================================
  subroutine build_pass_pipeline(target_triple, constraints, quantum_available, pipeline_str)
    implicit none

    character(len=*), intent(in) :: target_triple
    real(kind=rp), dimension(4), intent(in) :: constraints
    integer, intent(in) :: quantum_available
    character(len=512), intent(out) :: pipeline_str

    real(kind=rp) :: latency_ms, memory_mb, power_w, quantum_budget
    character(len=128) :: tile_sizes

    latency_ms = constraints(1)
    memory_mb  = constraints(2)
    power_w    = constraints(3)
    quantum_budget = constraints(4)

    ! Base pipeline: applies to all targets
    pipeline_str = "builtin.module(func.func("

    ! Affine fusion
    pipeline_str = trim(pipeline_str) // "affine-loop-fusion,"

    ! Linalg tiling (adaptive based on constraints)
    if (latency_ms < 1.0_rp) then
      ! Low latency: fine-grained tiling (4x4 blocks)
      tile_sizes = "4,4"
    else if (memory_mb < 512.0_rp) then
      ! Low memory: conservative tiling (32x32 blocks)
      tile_sizes = "32,32"
    else
      ! Default: medium tiling (16x16 blocks)
      tile_sizes = "16,16"
    end if
    pipeline_str = trim(pipeline_str) // "linalg-tile{tile-sizes=" // trim(tile_sizes) // "},"

    ! Vectorization (power-aware)
    if (power_w < 10.0_rp) then
      ! Low power: restrict SIMD width
      pipeline_str = trim(pipeline_str) // "vectorize{vectorize-vector-width=128},"
    else
      ! Default: full SIMD (up to 512-bit on AVX-512/SVE2)
      pipeline_str = trim(pipeline_str) // "vectorize,"
    end if

    ! Target-specific optimizations
    if (index(target_triple, "aarch64") > 0) then
      ! ARM64 SVE2
      pipeline_str = trim(pipeline_str) // "canonicalize-for-sve2,"
    else if (index(target_triple, "x86_64") > 0) then
      ! x86_64 AVX-512
      pipeline_str = trim(pipeline_str) // "canonicalize-for-avx512,"
    else if (index(target_triple, "nvptx") > 0) then
      ! NVIDIA PTX (GPU)
      pipeline_str = trim(pipeline_str) // "gpu-kernel-outlining,"
      pipeline_str = trim(pipeline_str) // "gpu-module-to-binary,"
    end if

    ! Quantum injection (Phase 2)
    if (quantum_available /= 0 .and. quantum_budget > 0.0_rp) then
      ! Placeholder: Phase 2 will add convert-linalg-to-quantum
      pipeline_str = trim(pipeline_str) // "convert-linalg-to-quantum,"
    end if

    ! Final lowering stack (all targets)
    pipeline_str = trim(pipeline_str) // &
      "convert-linalg-to-loops,convert-vector-to-scf,convert-scf-to-llvm,convert-func-to-llvm))"

  end subroutine build_pass_pipeline

end module mlir_forge_kernels
