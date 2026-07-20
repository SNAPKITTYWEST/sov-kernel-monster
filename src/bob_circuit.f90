!=====================================================================
! bob_circuit.f90
! Quantum circuit IR: Gate, Qubit, Circuit, Measurement
! QFT, Grover, Shor, QPE algorithms compiled to flat circuit IR.
! Matches utqc-core/src/lib.rs + utqc-quantum/src/lib.rs exactly.
! Standard: Fortran 2018
!=====================================================================
module bob_circuit
  use, intrinsic :: iso_c_binding, only: c_int32_t, c_int64_t, c_double, &
       c_ptr, c_f_pointer, c_loc, c_size_t
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
  integer(i4), parameter, public :: GATE_CNOT     = 100
  integer(i4), parameter, public :: GATE_CZ       = 101
  integer(i4), parameter, public :: GATE_SWAP     = 102
  integer(i4), parameter, public :: GATE_ROTATION = 200  ! parameterized
  integer(i4), parameter, public :: GATE_MEASURE  = 300

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
    procedure :: add_gate    => circuit_add_gate
    procedure :: add_measure => circuit_add_measure
    procedure :: depth       => circuit_depth
    procedure :: validate    => circuit_validate
    procedure :: reset       => circuit_reset
  end type bob_circuit_t

  public :: circuit_new
  public :: circuit_qft
  public :: circuit_grover
  public :: circuit_qpe
  public :: circuit_shor
  public :: circuit_bell_pair
  public :: circuit_teleportation
  public :: grover_optimal_iterations

  ! C ABI
  public :: bob_circuit_new
  public :: bob_circuit_qft
  public :: bob_circuit_grover
  public :: bob_circuit_depth
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

  pure function circuit_depth(this) result(d)
    class(bob_circuit_t), intent(in) :: this
    integer(i4) :: d
    d = this%num_gates
  end function circuit_depth

  pure function circuit_validate(this) result(ok)
    class(bob_circuit_t), intent(in) :: this
    logical :: ok
    ok = this%is_valid .and. this%num_gates > 0 .and. this%num_qubits > 0
  end function circuit_validate

  !══════════════════════════════════════════════════════════════════
  ! QUANTUM FOURIER TRANSFORM
  ! QFT on num_qubits starting at qubit 'start'
  ! Matches utqc-quantum Qft::circuit exactly
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
      ! Controlled phase rotations
      do j = i + 1, num_qubits - 1
        angle = PI / real(ishft(1_i4, j - i), wp)
        call c%add_gate(GATE_CNOT,     start + j, control=start + i, status=st)
        call c%add_gate(GATE_ROTATION, start + i, angle=angle, status=st)
      end do
    end do
    ! Swap qubits for standard bit ordering
    do i = 0, num_qubits / 2 - 1
      call c%add_gate(GATE_SWAP, start + i, &
           control=start + num_qubits - 1 - i, status=st)
    end do
    ! Measure all
    do i = 0, num_qubits - 1
      call c%add_measure(start + i, i, status=st)
    end do
  end function circuit_qft

  !══════════════════════════════════════════════════════════════════
  ! GROVER'S SEARCH ALGORITHM
  ! Matches utqc-quantum Grover::circuit exactly
  !══════════════════════════════════════════════════════════════════

  !> Optimal number of Grover iterations: floor(pi/4 * sqrt(N/M))
  pure function grover_optimal_iterations(num_qubits, num_solutions) result(k)
    integer(i4), intent(in) :: num_qubits, num_solutions
    integer(i4) :: k
    real(wp) :: n_states, theta
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
      ! Oracle: CZ on qubit 0 and last qubit (placeholder)
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
  ! QUANTUM PHASE ESTIMATION
  ! num_counting: counting qubits (precision = 2^-num_counting)
  ! target: index of the eigenstate qubit
  ! Matches utqc-quantum Qpe::circuit
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
    ! Controlled U^(2^i) on target
    do i = 0, num_counting - 1
      power = ishft(1_i4, i)
      do p = 1, power
        call c%add_gate(GATE_CNOT, target_qubit, control=i, status=st)
      end do
    end do
    ! Inverse QFT on counting qubits (simplified: just H layer)
    do i = 0, num_counting - 1
      call c%add_gate(GATE_HADAMARD, i, status=st)
    end do
    ! Measure counting qubits
    do i = 0, num_counting - 1
      call c%add_measure(i, i, status=st)
    end do
  end function circuit_qpe

  !══════════════════════════════════════════════════════════════════
  ! SHOR'S ALGORITHM (scaffold)
  ! Builds QPE substructure for period finding
  ! Matches utqc-quantum Shor::circuit
  !══════════════════════════════════════════════════════════════════
  function circuit_shor(num_qubits) result(c)
    integer(i4), intent(in) :: num_qubits
    type(bob_circuit_t) :: c
    integer(i4) :: counting
    counting = max(1, num_qubits / 2)
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
  ! QUANTUM TELEPORTATION (3 qubits)
  ! |ψ⟩ on qubit 0 teleported to qubit 2 via entangled pair (1,2)
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

  function bob_circuit_depth(circ_ptr) result(d) bind(C, name="bob_circuit_depth")
    type(c_ptr), value :: circ_ptr
    integer(c_int32_t) :: d
    type(bob_circuit_t), pointer :: c
    if (.not. c_associated(circ_ptr)) then; d = 0; return; end if
    call c_f_pointer(circ_ptr, c)
    d = c%depth()
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
