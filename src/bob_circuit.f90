!=====================================================================
! bob_circuit.f90
! Quantum circuit IR: Gate, Qubit, Circuit, Measurement
! QFT, Grover, Shor, QPE algorithms compiled to flat circuit IR.
! Matches utqc-core/src/lib.rs + utqc-quantum/src/lib.rs exactly.
! Standard: Fortran 2018
!
! PHASE 1 HARDENING (Correctness First)
! ─────────────────────────────────────
! This module implements critical bug fixes and scaffolding documentation:
!
! 1. Circuit Depth Fixes (Tasks 1.2, 2.1):
!    - Renamed: circuit_depth() → gate_count() [counts gates, not depth]
!    - Added: logical_depth() [computes proper critical-path depth]
!    - Deprecated: circuit_depth() → now calls logical_depth() for backwards compat
!
! 2. New Gate Types (Task 2.3):
!    - GATE_RX, GATE_RY, GATE_RZ: explicit rotation axes (not ambiguous)
!    - Documentation: semantics and decomposition formulas
!
! 3. Exact Inverse QFT (Task 2.2):
!    - New function: circuit_exact_inverse_qft() [full controlled-phase gates]
!    - Status: IN_PROGRESS_SCAFFOLD [proper QFT† with 2π/2^k phases]
!    - Reference: Nielsen & Chuang §5.1
!
! 4. Scaffold Documentation:
!    - circuit_qft(): Simplified (not full QFT, angle factor off by 2π)
!    - circuit_grover(): Hardcoded oracle (not programmable)
!    - circuit_qpe(): Uses H layer, not inverse QFT
!    - circuit_shor(): Period-finding only (no modular exponentiation)
!    - Details: see SCAFFOLDS_IN_PROGRESS.md
!
! 5. Phase 1B TODO (Classical Control IR):
!    - GATE_MEASURE_STORE, GATE_COND_GATE type codes defined
!    - Semantic issue: measurement results cannot be distinguished from quantum controls
!    - Workaround: see circuit_teleportation comments
!    - Fix: Phase 1B will add separate classical control IR
!
! See: SCAFFOLDS_IN_PROGRESS.md for full documentation of known gaps
!=====================================================================
module bob_circuit
  use, intrinsic :: iso_c_binding, only: c_int32_t, c_int64_t, c_double, &
       c_ptr, c_f_pointer, c_loc, c_size_t, c_associated
  use, intrinsic :: iso_fortran_env, only: int64, real64, int32
  use bob_kinds
  use bob_errors
  implicit none
  private

  !──────────────────────────────────────────────────────────────────
  ! Gate type codes (matches utqc-core SingleGate + DoubleGate enums)
  !──────────────────────────────────────────────────────────────────
  integer(i4), parameter, public :: GATE_PAULI_X  = 0
  integer(i4), parameter, public :: GATE_PAULI_Y  = 1
  integer(i4), parameter, public :: GATE_PAULI_Z  = 2
  integer(i4), parameter, public :: GATE_HADAMARD = 3
  integer(i4), parameter, public :: GATE_T        = 4
  integer(i4), parameter, public :: GATE_S        = 5
  ! Explicit rotation gates (single-qubit, angle in radians)
  integer(i4), parameter, public :: GATE_RX       = 10  ! Rotation around X axis: Rx(θ) = [[cos(θ/2), -i·sin(θ/2)], [...]]
  integer(i4), parameter, public :: GATE_RY       = 11  ! Rotation around Y axis: Ry(θ) = [[cos(θ/2), -sin(θ/2)], [...]]
  integer(i4), parameter, public :: GATE_RZ       = 12  ! Rotation around Z axis: Rz(θ) = [[exp(-i·θ/2), 0], [0, exp(i·θ/2)]]
  ! Parameterized gate (deprecated - use explicit RX/RY/RZ instead)
  integer(i4), parameter, public :: GATE_ROTATION = 200  ! Generic rotation (DEPRECATED - prefer RX/RY/RZ)
  ! Two-qubit gates
  integer(i4), parameter, public :: GATE_CNOT     = 100
  integer(i4), parameter, public :: GATE_CZ       = 101
  integer(i4), parameter, public :: GATE_SWAP     = 102
  ! Measurement gates
  integer(i4), parameter, public :: GATE_MEASURE  = 300
  ! Classical control gates (Phase 1B TODO)
  integer(i4), parameter, public :: GATE_MEASURE_STORE = 301  ! Measure qubit to classical bit (Phase 1B)
  integer(i4), parameter, public :: GATE_COND_GATE     = 302  ! Conditional quantum gate (Phase 1B)

  !> Maximum gates in one circuit
  integer(i4), parameter, public :: MAX_CIRCUIT_GATES = 65536
  !> Maximum qubits
  integer(i4), parameter, public :: MAX_QUBITS = 64

  !> A single gate operation
  type, public :: bob_gate_t
    integer(i4) :: gate_type   = 0     ! GATE_* constant
    integer(i4) :: target      = -1    ! target qubit (0-indexed)
    integer(i4) :: control     = -1    ! control qubit (-1 = none)
    real(wp)    :: angle       = ZERO  ! rotation angle (radians)
    integer(i4) :: classical   = -1    ! classical bit for measurement
  end type bob_gate_t

  !> Flat quantum circuit IR (non-recursive — matches utqc-core Circuit)
  type, public :: bob_circuit_t
    integer(i4) :: num_qubits      = 0
    integer(i4) :: num_classical   = 0
    integer(i4) :: num_gates       = 0
    integer(i4) :: num_measurements= 0
    type(bob_gate_t) :: gates(MAX_CIRCUIT_GATES)
    logical(lk) :: is_valid        = .false.
  contains
    procedure :: add_gate        => circuit_add_gate
    procedure :: add_measure     => circuit_add_measure
    procedure :: gate_count      => circuit_gate_count
    procedure :: logical_depth   => circuit_logical_depth
    procedure :: depth           => circuit_depth  ! Deprecated: use logical_depth()
    procedure :: validate        => circuit_validate
    procedure :: reset           => circuit_reset
  end type bob_circuit_t

  public :: circuit_new
  public :: circuit_qft
  public :: circuit_grover
  public :: circuit_qpe
  public :: circuit_shor
  public :: circuit_bell_pair
  public :: circuit_teleportation
  public :: circuit_exact_inverse_qft  ! New: Task 2.2
  public :: grover_optimal_iterations

  ! C ABI
  public :: bob_circuit_new
  public :: bob_circuit_qft
  public :: bob_circuit_grover
  public :: bob_circuit_gate_count     ! New: Task 1.2
  public :: bob_circuit_logical_depth  ! New: Task 2.1
  public :: bob_circuit_depth          ! Deprecated wrapper for backwards compat
  public :: bob_circuit_free

contains

  !──────────────────────────────────────────────────────────────────
  ! Constructor
  !──────────────────────────────────────────────────────────────────
  pure function circuit_new(num_qubits, num_classical) result(c)
    integer(i4), intent(in) :: num_qubits, num_classical
    type(bob_circuit_t) :: c
    c%num_qubits    = num_qubits
    c%num_classical = num_classical
    c%num_gates     = 0
    c%is_valid      = .true.
  end function circuit_new

  subroutine circuit_reset(this)
    class(bob_circuit_t), intent(inout) :: this
    this%num_gates       = 0
    this%num_measurements= 0
    this%is_valid        = .true.
  end subroutine circuit_reset

  !──────────────────────────────────────────────────────────────────
  ! Add a gate
  !──────────────────────────────────────────────────────────────────
  subroutine circuit_add_gate(this, gate_type, target, control, angle, status)
    class(bob_circuit_t), intent(inout) :: this
    integer(i4), intent(in) :: gate_type, target
    integer(i4), intent(in), optional :: control
    real(wp),    intent(in), optional :: angle
    integer(i4), intent(out), optional :: status
    integer(i4) :: st
    st = BOB_SUCCESS
    if (.not. this%is_valid) then; st = BOB_ERROR_INVALID_STATE; goto 99; end if
    if (this%num_gates >= MAX_CIRCUIT_GATES) then
      call bob_set_error(BOB_ERROR_ALLOCATION, "circuit full", "circuit_add_gate")
      st = BOB_ERROR_ALLOCATION; goto 99
    end if
    if (target < 0 .or. target >= this%num_qubits) then
      st = BOB_ERROR_INVALID_ARGUMENT; goto 99
    end if
    this%num_gates = this%num_gates + 1
    this%gates(this%num_gates)%gate_type = gate_type
    this%gates(this%num_gates)%target    = target
    this%gates(this%num_gates)%control   = -1
    this%gates(this%num_gates)%angle     = ZERO
    this%gates(this%num_gates)%classical = -1
    if (present(control)) this%gates(this%num_gates)%control = control
    if (present(angle))   this%gates(this%num_gates)%angle   = angle
    99 if (present(status)) status = st
  end subroutine circuit_add_gate

  subroutine circuit_add_measure(this, qubit, classical_bit, status)
    class(bob_circuit_t), intent(inout) :: this
    integer(i4), intent(in) :: qubit, classical_bit
    integer(i4), intent(out), optional :: status
    integer(i4) :: st
    st = BOB_SUCCESS
    if (qubit < 0 .or. qubit >= this%num_qubits) then
      st = BOB_ERROR_INVALID_ARGUMENT; goto 99
    end if
    this%num_gates = this%num_gates + 1
    this%gates(this%num_gates)%gate_type = GATE_MEASURE
    this%gates(this%num_gates)%target    = qubit
    this%gates(this%num_gates)%classical = classical_bit
    this%num_measurements = this%num_measurements + 1
    99 if (present(status)) status = st
  end subroutine circuit_add_measure

  !> Gate count (total number of gates, not depth)
  pure function circuit_gate_count(this) result(d)
    class(bob_circuit_t), intent(in) :: this
    integer(i4) :: d
    d = this%num_gates
  end function circuit_gate_count

  !> Logical circuit depth: longest critical path accounting for parallelism
  !> Algorithm: Track activation layer for each qubit, layer(gate) = 1 + max(layers of involved qubits)
  pure function circuit_logical_depth(this) result(d)
    class(bob_circuit_t), intent(in) :: this
    integer(i4) :: d
    integer(i4) :: i, q, layer, max_layer
    integer(i4) :: qubit_layer(MAX_QUBITS)

    if (this%num_gates == 0) then
      d = 0
      return
    end if

    ! Initialize all qubit layers to 0
    qubit_layer(1:MAX_QUBITS) = 0
    max_layer = 0

    ! Process each gate in order
    do i = 1, this%num_gates
      layer = 1  ! Each gate starts at layer 1 (after dependencies)

      ! Find max layer of target qubit
      if (this%gates(i)%target >= 0 .and. this%gates(i)%target < this%num_qubits) then
        layer = max(layer, qubit_layer(this%gates(i)%target + 1) + 1)
      end if

      ! Find max layer of control qubit (if present and quantum control, not classical)
      ! Note: classical control (measurement) does not create dependency
      if (this%gates(i)%control >= 0 .and. this%gates(i)%control < this%num_qubits) then
        ! Only create dependency if control is a qubit (control >= 0 and < num_qubits)
        ! Measurement gates have classical destination, not qubit dependency
        if (this%gates(i)%gate_type /= GATE_MEASURE) then
          layer = max(layer, qubit_layer(this%gates(i)%control + 1) + 1)
        end if
      end if

      ! Update qubit layers
      if (this%gates(i)%target >= 0 .and. this%gates(i)%target < this%num_qubits) then
        qubit_layer(this%gates(i)%target + 1) = layer
      end if
      if (this%gates(i)%control >= 0 .and. this%gates(i)%control < this%num_qubits .and. &
          this%gates(i)%gate_type /= GATE_MEASURE) then
        qubit_layer(this%gates(i)%control + 1) = layer
      end if

      max_layer = max(max_layer, layer)
    end do

    d = max_layer
  end function circuit_logical_depth

  !> Deprecated: Use logical_depth() or gate_count()
  pure function circuit_depth(this) result(d)
    class(bob_circuit_t), intent(in) :: this
    integer(i4) :: d
    ! For backwards compatibility with C ABI, call logical_depth
    d = this%logical_depth()
  end function circuit_depth

  pure function circuit_validate(this) result(ok)
    class(bob_circuit_t), intent(in) :: this
    logical :: ok
    ok = this%is_valid .and. this%num_gates > 0 .and. this%num_qubits > 0
  end function circuit_validate

  !══════════════════════════════════════════════════════════════════
  ! EXACT INVERSE QUANTUM FOURIER TRANSFORM (Phase 1B)
  ! Implements QFT† = QFT^(-1) with proper controlled-phase gates
  ! Uses full 2π/2^k phase accumulation (not simplified)
  ! Reference: Nielsen & Chuang §5.1
  !
  ! Circuit structure:
  !   For each qubit j from 0 to n-1:
  !     For each qubit k from j+1 to n-1:
  !       Apply controlled-phase with angle 2π/2^(k-j) (controlled by j, target k)
  !     Apply Hadamard to qubit j
  !   (Optional: Apply SWAPs to reverse bit order for standard convention)
  !
  ! Status: IN_PROGRESS_SCAFFOLD
  ! Known limitation: This is the inverse QFT; compositions with QPE require
  !                   proper modular exponentiation in the forward QFT.
  !══════════════════════════════════════════════════════════════════
  function circuit_exact_inverse_qft(num_qubits, start) result(c)
    integer(i4), intent(in) :: num_qubits, start
    type(bob_circuit_t) :: c
    integer(i4) :: i, j, st, k_exp
    real(wp) :: angle

    c = circuit_new(num_qubits, num_qubits)

    ! Inverse QFT: Process qubits from 0 to n-1
    ! (Inverse because controlled-phases are in reverse order vs. forward QFT)
    do i = 0, num_qubits - 1
      ! Controlled-phase rotations from higher-index qubits to this qubit
      do j = i + 1, num_qubits - 1
        ! Phase angle: 2π / 2^(j-i) = 2π * 2^(-(j-i))
        k_exp = j - i
        ! angle = 2π / 2^k_exp (computed via bit shift for accuracy)
        angle = TWO * PI / real(ishft(1_i4, k_exp), wp)

        ! Apply controlled-phase: CPhase(angle) controlled by qubit (start+i), target (start+j)
        ! Implementation: Use RZ gate with proper control
        ! Note: CPhase(θ) controlled by |1⟩ on control qubit
        ! For now, use GATE_RZ with control field (Phase 1 limitation)
        ! TODO: Implement proper controlled-phase gate in Phase 1B
        call c%add_gate(GATE_RZ, start + j, control=start + i, angle=angle, status=st)
      end do

      ! Hadamard on this qubit
      call c%add_gate(GATE_HADAMARD, start + i, status=st)
    end do

    ! Optional: SWAP qubits to reverse bit order (standard QFT convention)
    ! This makes the QFT match textbook form where qubit 0 is most significant
    do i = 0, (num_qubits - 1) / 2
      if (i /= num_qubits - 1 - i) then
        call c%add_gate(GATE_SWAP, start + i, &
             control=start + num_qubits - 1 - i, status=st)
      end if
    end do

  end function circuit_exact_inverse_qft

  !══════════════════════════════════════════════════════════════════
  ! QUANTUM FOURIER TRANSFORM (Phase 1 Scaffold)
  ! QFT on num_qubits starting at qubit 'start'
  ! Matches utqc-quantum Qft::circuit exactly
  !
  ! Status: IN_PROGRESS_SCAFFOLD (see SCAFFOLDS_IN_PROGRESS.md)
  ! Known limitations:
  !   1. Uses simplified Hadamard layer + phase rotations (not standard QFT†)
  !   2. Angle = π/2^(j-i), NOT 2π/2^(j-i) (missing factor of 2)
  !   3. Uses CNOT+ROTATION instead of proper CPhase gate
  !   4. Includes measurements (makes circuit non-composable)
  !   5. Not suitable for use within QPE (see circuit_exact_inverse_qft instead)
  !
  ! This circuit is adequate for demonstrating compiler pipeline.
  ! Phase 2 will implement full QFT with proper controlled-phase gates.
  !══════════════════════════════════════════════════════════════════
  function circuit_qft(num_qubits, start) result(c)
    integer(i4), intent(in) :: num_qubits, start
    type(bob_circuit_t) :: c
    integer(i4) :: i, j, st
    real(wp)    :: angle
    c = circuit_new(num_qubits, num_qubits)
    do i = 0, num_qubits - 1
      ! Hadamard on qubit i
      call c%add_gate(GATE_HADAMARD, start + i, status=st)
      ! Controlled phase rotations (SCAFFOLD: simplified, uses CNOT+ROTATION)
      do j = i + 1, num_qubits - 1
        angle = PI / real(ishft(1_i4, j - i), wp)  ! SCAFFOLD: Should be 2π/2^(j-i)
        call c%add_gate(GATE_CNOT,     start + j, control=start + i, status=st)
        call c%add_gate(GATE_ROTATION, start + i, angle=angle, status=st)
      end do
    end do
    ! Swap qubits for standard bit ordering
    do i = 0, num_qubits / 2 - 1
      call c%add_gate(GATE_SWAP, start + i, &
           control=start + num_qubits - 1 - i, status=st)
    end do
    ! Measure all (SCAFFOLD: makes circuit non-composable)
    do i = 0, num_qubits - 1
      call c%add_measure(start + i, i, status=st)
    end do
  end function circuit_qft

  !══════════════════════════════════════════════════════════════════
  ! GROVER'S SEARCH ALGORITHM (Phase 1 Scaffold)
  ! Matches utqc-quantum Grover::circuit exactly
  !
  ! Status: IN_PROGRESS_SCAFFOLD (see SCAFFOLDS_IN_PROGRESS.md)
  ! Known limitations:
  !   1. Oracle is HARDCODED: CZ(q_last, control=q_0) only
  !   2. Cannot search for arbitrary marked states
  !   3. Only demonstrates amplitude amplification structure
  !   4. Iteration count formula is correct (grover_optimal_iterations)
  !   5. Future: Accept programmable oracle parameter
  !
  ! This circuit demonstrates the iteration structure and counts optimal
  ! iterations. Phase 2 will allow programmable oracles.
  !══════════════════════════════════════════════════════════════════

  !> Optimal number of Grover iterations: floor(pi/4 * sqrt(N/M))
  pure function grover_optimal_iterations(num_qubits, num_solutions) result(k)
    integer(i4), intent(in) :: num_qubits, num_solutions
    integer(i4) :: k
    real(wp) :: n_states, theta
    real(wp), parameter :: QUART = 0.25_wp  ! π/4 = π * 0.25
    n_states = real(ishft(1_i4, num_qubits), wp)
    theta = asin(sqrt(real(num_solutions, wp) / n_states))
    k = max(1, int(PI * QUART / theta, i4))
  end function grover_optimal_iterations

  function circuit_grover(num_qubits, num_solutions) result(c)
    integer(i4), intent(in) :: num_qubits, num_solutions
    type(bob_circuit_t) :: c
    integer(i4) :: i, iter, iters, st
    c = circuit_new(num_qubits, num_qubits)
    ! Initialize: H on all
    do i = 0, num_qubits - 1
      call c%add_gate(GATE_HADAMARD, i, status=st)
    end do
    iters = grover_optimal_iterations(num_qubits, num_solutions)
    do iter = 1, iters
      ! Oracle: CZ on qubit 0 and last qubit (SCAFFOLD: hardcoded, not programmable)
      if (num_qubits >= 2) then
        call c%add_gate(GATE_CZ, num_qubits - 1, control=0, status=st)
      end if
      ! Diffusion operator: H X CZ X H on all
      do i = 0, num_qubits - 1
        call c%add_gate(GATE_HADAMARD, i, status=st)
        call c%add_gate(GATE_PAULI_X, i, status=st)
      end do
      if (num_qubits >= 2) then
        call c%add_gate(GATE_CZ, num_qubits - 1, control=0, status=st)
      end if
      do i = 0, num_qubits - 1
        call c%add_gate(GATE_PAULI_X, i, status=st)
        call c%add_gate(GATE_HADAMARD, i, status=st)
      end do
    end do
    ! Measure
    do i = 0, num_qubits - 1
      call c%add_measure(i, i, status=st)
    end do
  end function circuit_grover

  !══════════════════════════════════════════════════════════════════
  ! QUANTUM PHASE ESTIMATION (Phase 1 Scaffold)
  ! num_counting: counting qubits (precision = 2^-num_counting)
  ! target: index of the eigenstate qubit
  ! Matches utqc-quantum Qpe::circuit
  !
  ! Status: IN_PROGRESS_SCAFFOLD (see SCAFFOLDS_IN_PROGRESS.md)
  ! Known limitations:
  !   1. Inverse QFT replaced with just Hadamard layer (simplified)
  !   2. Correct inverse QFT uses controlled-phase gates (2π/2^k)
  !   3. Phase information is not properly extracted into counting register
  !   4. Eigenvalue estimation will be inaccurate
  !   5. Controlled unitary is simulated with repeated CNOT (not general U)
  !
  ! This circuit demonstrates the phase estimation structure: superposition
  ! initialization, controlled powers, and measurement. Phase 2 will use
  ! the exact inverse QFT (circuit_exact_inverse_qft) for correctness.
  !══════════════════════════════════════════════════════════════════
  function circuit_qpe(num_counting, target_qubit) result(c)
    integer(i4), intent(in) :: num_counting, target_qubit
    type(bob_circuit_t) :: c
    integer(i4) :: total, i, power, p, st
    type(bob_circuit_t) :: qft_c
    total = num_counting + 1
    c = circuit_new(total, num_counting)
    ! H on counting qubits
    do i = 0, num_counting - 1
      call c%add_gate(GATE_HADAMARD, i, status=st)
    end do
    ! Controlled U^(2^i) on target (SCAFFOLD: simulated as repeated CNOT)
    do i = 0, num_counting - 1
      power = ishft(1_i4, i)
      do p = 1, power
        call c%add_gate(GATE_CNOT, target_qubit, control=i, status=st)
      end do
    end do
    ! Inverse QFT on counting qubits (SCAFFOLD: simplified - just H layer, not full QFT†)
    ! Phase 2: Replace with circuit_exact_inverse_qft() call
    do i = 0, num_counting - 1
      call c%add_gate(GATE_HADAMARD, i, status=st)
    end do
    ! Measure counting qubits
    do i = 0, num_counting - 1
      call c%add_measure(i, i, status=st)
    end do
  end function circuit_qpe

  !══════════════════════════════════════════════════════════════════
  ! SHOR'S ALGORITHM (Phase 1 Scaffold — Period Finding Only)
  ! Builds QPE substructure for period finding
  ! Matches utqc-quantum Shor::circuit
  !
  ! Status: IN_PROGRESS_SCAFFOLD (see SCAFFOLDS_IN_PROGRESS.md)
  ! What's implemented:
  !   - Period-finding subroutine via QPE
  !   - Qubit allocation (counting qubits = num_qubits/2)
  !
  ! What's stubbed (nearly everything):
  !   1. Modular exponentiation circuit (reversible a^x mod N)
  !   2. Quantum order-finding (currently just delegates to QPE)
  !   3. Classical reduction via Euclidean algorithm
  !   4. Integer factorization (extracting factors from period)
  !
  ! This circuit is only the quantum period-finding part. The full
  ! Shor algorithm requires classical post-processing to convert
  ! the period r into factors of N via gcd(a^(r/2) ± 1, N).
  !
  ! Phase 2 will implement:
  !   - Reversible modular exponentiation
  !   - Full factorization loop
  !   - Classical reduction phase
  !══════════════════════════════════════════════════════════════════
  function circuit_shor(num_qubits) result(c)
    integer(i4), intent(in) :: num_qubits
    type(bob_circuit_t) :: c
    integer(i4) :: counting
    counting = max(1, num_qubits / 2)
    ! Shor's algorithm = Period finding via QPE
    ! (Full algorithm requires classical post-processing and modular exponentiation)
    c = circuit_qpe(counting, counting)
  end function circuit_shor

  !══════════════════════════════════════════════════════════════════
  ! BELL PAIR (2-qubit entangled state)
  ! |Φ+⟩ = (|00⟩ + |11⟩)/√2
  !══════════════════════════════════════════════════════════════════
  function circuit_bell_pair() result(c)
    type(bob_circuit_t) :: c
    integer(i4) :: st
    c = circuit_new(2, 2)
    call c%add_gate(GATE_HADAMARD, 0, status=st)
    call c%add_gate(GATE_CNOT, 1, control=0, status=st)
    call c%add_measure(0, 0, status=st)
    call c%add_measure(1, 1, status=st)
  end function circuit_bell_pair

  !══════════════════════════════════════════════════════════════════
  ! QUANTUM TELEPORTATION (3 qubits) — Known Semantic Issue
  ! |ψ⟩ on qubit 0 teleported to qubit 2 via entangled pair (1,2)
  !
  ! SEMANTIC BUG (Phase 1B TODO):
  !   Lines with control=0 and control=1 after measurements are INCORRECT.
  !   The IR conflates:
  !     - Quantum control: gate applied if control qubit is |1⟩
  !     - Classical control: gate applied if measurement result == 1
  !
  !   Current code:
  !     call c%add_measure(0, 0, status=st)  ! Measure q0 → c0 (classical bit)
  !     call c%add_gate(GATE_PAULI_Z, 2, control=0, status=st)  ! control=0 is qubit 0, not bit!
  !
  !   This is interpreted as: "if qubit 0 is in |1⟩, apply Z to qubit 2"
  !   But measurement already collapsed qubit 0. The intent is:
  !     "if measurement result of bit c0 is 1, apply Z to qubit 2"
  !
  ! WORKAROUND (Phase 1):
  !   For now, interpret control field on post-measurement gates as classical
  !   (requires runtime to enforce measurement-before-use).
  !   The circuit logic is correct; only the IR semantics are ambiguous.
  !
  ! FIX (Phase 1B):
  !   Use GATE_COND_GATE with separate classical condition specification:
  !     call c%add_gate(GATE_MEASURE_STORE, 0, classical=0, status=st)
  !     call c%add_gate(GATE_COND_GATE, 2, gate_type=GATE_PAULI_Z, &
  !                     classical_condition=0, status=st)
  !
  ! See: SCAFFOLDS_IN_PROGRESS.md § "Teleportation Semantic Bug"
  !══════════════════════════════════════════════════════════════════
  function circuit_teleportation() result(c)
    type(bob_circuit_t) :: c
    integer(i4) :: st
    c = circuit_new(3, 3)
    ! Prepare Bell pair on qubits 1,2
    call c%add_gate(GATE_HADAMARD, 1, status=st)
    call c%add_gate(GATE_CNOT, 2, control=1, status=st)
    ! Alice's operations on qubits 0,1
    call c%add_gate(GATE_CNOT, 1, control=0, status=st)
    call c%add_gate(GATE_HADAMARD, 0, status=st)
    ! Measure Alice's qubits
    call c%add_measure(0, 0, status=st)
    call c%add_measure(1, 1, status=st)
    ! Bob's corrections (conditional X and Z)
    ! NOTE: These control fields should be interpreted as classical conditions
    ! (see semantic bug above). Phase 1B will clarify with separate IR types.
    call c%add_gate(GATE_PAULI_X, 2, control=1, status=st)
    call c%add_gate(GATE_PAULI_Z, 2, control=0, status=st)
    call c%add_measure(2, 2, status=st)
  end function circuit_teleportation

  !══════════════════════════════════════════════════════════════════
  ! C ABI
  !══════════════════════════════════════════════════════════════════

  function bob_circuit_new(num_qubits, num_classical) result(ptr) &
       bind(C, name="bob_circuit_new")
    integer(c_int32_t), value :: num_qubits, num_classical
    type(c_ptr) :: ptr
    type(bob_circuit_t), pointer :: c
    allocate(c)
    c = circuit_new(int(num_qubits,i4), int(num_classical,i4))
    ptr = c_loc(c)
  end function bob_circuit_new

  function bob_circuit_qft(num_qubits, start) result(ptr) &
       bind(C, name="bob_circuit_qft")
    integer(c_int32_t), value :: num_qubits, start
    type(c_ptr) :: ptr
    type(bob_circuit_t), pointer :: c
    allocate(c)
    c = circuit_qft(int(num_qubits,i4), int(start,i4))
    ptr = c_loc(c)
  end function bob_circuit_qft

  function bob_circuit_grover(num_qubits, num_solutions) result(ptr) &
       bind(C, name="bob_circuit_grover")
    integer(c_int32_t), value :: num_qubits, num_solutions
    type(c_ptr) :: ptr
    type(bob_circuit_t), pointer :: c
    allocate(c)
    c = circuit_grover(int(num_qubits,i4), int(num_solutions,i4))
    ptr = c_loc(c)
  end function bob_circuit_grover

  function bob_circuit_gate_count(circ_ptr) result(d) bind(C, name="bob_circuit_gate_count")
    type(c_ptr), value :: circ_ptr
    integer(c_int32_t) :: d
    type(bob_circuit_t), pointer :: c
    if (.not. c_associated(circ_ptr)) then; d = 0; return; end if
    call c_f_pointer(circ_ptr, c)
    d = c%gate_count()
  end function bob_circuit_gate_count

  function bob_circuit_logical_depth(circ_ptr) result(d) bind(C, name="bob_circuit_logical_depth")
    type(c_ptr), value :: circ_ptr
    integer(c_int32_t) :: d
    type(bob_circuit_t), pointer :: c
    if (.not. c_associated(circ_ptr)) then; d = 0; return; end if
    call c_f_pointer(circ_ptr, c)
    d = c%logical_depth()
  end function bob_circuit_logical_depth

  function bob_circuit_depth(circ_ptr) result(d) bind(C, name="bob_circuit_depth")
    type(c_ptr), value :: circ_ptr
    integer(c_int32_t) :: d
    type(bob_circuit_t), pointer :: c
    if (.not. c_associated(circ_ptr)) then; d = 0; return; end if
    call c_f_pointer(circ_ptr, c)
    ! Deprecated: Now calls logical_depth() for correctness
    d = c%logical_depth()
  end function bob_circuit_depth

  subroutine bob_circuit_free(circ_ptr) bind(C, name="bob_circuit_free")
    type(c_ptr), value :: circ_ptr
    type(bob_circuit_t), pointer :: c
    if (.not. c_associated(circ_ptr)) return
    call c_f_pointer(circ_ptr, c)
    deallocate(c)
  end subroutine bob_circuit_free

end module bob_circuit

! Made with Bob
