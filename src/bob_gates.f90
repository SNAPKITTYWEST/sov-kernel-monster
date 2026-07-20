! BOB Quantum Civilization Engine - Quantum Gates
! Module: bob_gates
! Purpose: Complete quantum gate operations (Pauli, Hadamard, T, controlled gates)
! Standard: Fortran 2018

module bob_gates
    use bob_kinds
    use bob_errors
    use bob_state
    implicit none
    private
    
    ! Gate types
    integer(i4), parameter, public :: GATE_I = 0      ! Identity
    integer(i4), parameter, public :: GATE_X = 1      ! Pauli X (NOT)
    integer(i4), parameter, public :: GATE_Y = 2      ! Pauli Y
    integer(i4), parameter, public :: GATE_Z = 3      ! Pauli Z
    integer(i4), parameter, public :: GATE_H = 4      ! Hadamard
    integer(i4), parameter, public :: GATE_S = 5      ! S gate (phase)
    integer(i4), parameter, public :: GATE_T = 6      ! T gate (π/8)
    integer(i4), parameter, public :: GATE_CNOT = 7   ! Controlled-NOT
    integer(i4), parameter, public :: GATE_CZ = 8     ! Controlled-Z
    integer(i4), parameter, public :: GATE_SWAP = 9   ! SWAP
    integer(i4), parameter, public :: GATE_RX = 10    ! Rotation X
    integer(i4), parameter, public :: GATE_RY = 11    ! Rotation Y
    integer(i4), parameter, public :: GATE_RZ = 12    ! Rotation Z
    
    ! Pauli matrices
    complex(cwp), parameter :: PAULI_I(2,2) = reshape([ &
        CONE, CZERO, &
        CZERO, CONE], [2,2])
    
    complex(cwp), parameter :: PAULI_X(2,2) = reshape([ &
        CZERO, CONE, &
        CONE, CZERO], [2,2])
    
    complex(cwp), parameter :: PAULI_Y(2,2) = reshape([ &
        CZERO, -CI, &
        CI, CZERO], [2,2])
    
    complex(cwp), parameter :: PAULI_Z(2,2) = reshape([ &
        CONE, CZERO, &
        CZERO, -CONE], [2,2])
    
    public :: apply_single_qubit_gate
    public :: apply_two_qubit_gate
    public :: apply_rotation_gate
    public :: apply_controlled_gate
    public :: apply_arbitrary_unitary
    public :: verify_unitary
    
contains

    !> Apply single-qubit gate to state
    subroutine apply_single_qubit_gate(state, gate_type, qubit_index)
        type(bob_quantum_state), intent(inout) :: state
        integer(i4), intent(in) :: gate_type
        integer(i8), intent(in) :: qubit_index
        
        complex(cwp) :: gate_matrix(2,2)
        complex(cwp) :: new_amplitudes(state%dim)
        integer(i8) :: i, j, k, bit_mask, qubit_bit
        integer(i8) :: num_qubits, state_0, state_1
        complex(cwp) :: amp_0, amp_1
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot apply gate to invalid state", "apply_single_qubit_gate")
            return
        end if
        
        ! Get gate matrix
        select case (gate_type)
        case (GATE_I)
            gate_matrix = PAULI_I
        case (GATE_X)
            gate_matrix = PAULI_X
        case (GATE_Y)
            gate_matrix = PAULI_Y
        case (GATE_Z)
            gate_matrix = PAULI_Z
        case (GATE_H)
            ! Hadamard: (1/√2) * [[1, 1], [1, -1]]
            gate_matrix(1,1) = CONE / sqrt(TWO)
            gate_matrix(1,2) = CONE / sqrt(TWO)
            gate_matrix(2,1) = CONE / sqrt(TWO)
            gate_matrix(2,2) = -CONE / sqrt(TWO)
        case (GATE_S)
            ! S gate: [[1, 0], [0, i]]
            gate_matrix(1,1) = CONE
            gate_matrix(1,2) = CZERO
            gate_matrix(2,1) = CZERO
            gate_matrix(2,2) = CI
        case (GATE_T)
            ! T gate: [[1, 0], [0, exp(iπ/4)]]
            gate_matrix(1,1) = CONE
            gate_matrix(1,2) = CZERO
            gate_matrix(2,1) = CZERO
            gate_matrix(2,2) = exp(CI * PI / 4.0_wp)
        case default
            call bob_set_error(BOB_ERROR_INVALID_GATE, &
                "Unknown gate type", "apply_single_qubit_gate")
            return
        end select
        
        ! Calculate number of qubits
        num_qubits = int(log(real(state%dim, wp)) / log(TWO), i8)
        
        if (qubit_index < 0 .or. qubit_index >= num_qubits) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Qubit index out of range", "apply_single_qubit_gate")
            return
        end if
        
        ! Apply gate to each basis state
        bit_mask = ishft(1_i8, int(qubit_index))
        
        do i = 0, state%dim - 1
            qubit_bit = iand(i, bit_mask)
            
            if (qubit_bit == 0) then
                ! This basis state has qubit in |0⟩
                state_0 = i
                state_1 = ior(i, bit_mask)
                
                amp_0 = state%amplitudes(state_0 + 1)
                amp_1 = state%amplitudes(state_1 + 1)
                
                ! Apply gate matrix
                new_amplitudes(state_0 + 1) = gate_matrix(1,1) * amp_0 + gate_matrix(1,2) * amp_1
                new_amplitudes(state_1 + 1) = gate_matrix(2,1) * amp_0 + gate_matrix(2,2) * amp_1
            end if
        end do
        
        state%amplitudes = new_amplitudes
        state%is_normalized = .false.
        
        call bob_clear_error()
    end subroutine apply_single_qubit_gate
    
    !> Apply two-qubit gate
    subroutine apply_two_qubit_gate(state, gate_type, control_qubit, target_qubit)
        type(bob_quantum_state), intent(inout) :: state
        integer(i4), intent(in) :: gate_type
        integer(i8), intent(in) :: control_qubit, target_qubit
        
        complex(cwp) :: new_amplitudes(state%dim)
        integer(i8) :: i, control_mask, target_mask
        integer(i8) :: num_qubits, control_bit, target_bit
        integer(i8) :: state_00, state_01, state_10, state_11
        complex(cwp) :: amp_00, amp_01, amp_10, amp_11
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot apply gate to invalid state", "apply_two_qubit_gate")
            return
        end if
        
        num_qubits = int(log(real(state%dim, wp)) / log(TWO), i8)
        
        if (control_qubit < 0 .or. control_qubit >= num_qubits .or. &
            target_qubit < 0 .or. target_qubit >= num_qubits .or. &
            control_qubit == target_qubit) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Invalid qubit indices", "apply_two_qubit_gate")
            return
        end if
        
        control_mask = ishft(1_i8, int(control_qubit))
        target_mask = ishft(1_i8, int(target_qubit))
        
        new_amplitudes = state%amplitudes
        
        select case (gate_type)
        case (GATE_CNOT)
            ! CNOT: flip target if control is |1⟩
            do i = 0, state%dim - 1
                control_bit = iand(i, control_mask)
                
                if (control_bit /= 0) then
                    ! Control is |1⟩, flip target
                    target_bit = iand(i, target_mask)
                    
                    if (target_bit == 0) then
                        state_01 = i
                        state_11 = ior(i, target_mask)
                    else
                        state_11 = i
                        state_01 = iand(i, not(target_mask))
                    end if
                    
                    ! Swap amplitudes
                    amp_01 = state%amplitudes(state_01 + 1)
                    amp_11 = state%amplitudes(state_11 + 1)
                    new_amplitudes(state_01 + 1) = amp_11
                    new_amplitudes(state_11 + 1) = amp_01
                end if
            end do
            
        case (GATE_CZ)
            ! CZ: apply Z to target if control is |1⟩
            do i = 0, state%dim - 1
                control_bit = iand(i, control_mask)
                target_bit = iand(i, target_mask)
                
                if (control_bit /= 0 .and. target_bit /= 0) then
                    ! Both qubits are |1⟩, apply phase flip
                    new_amplitudes(i + 1) = -state%amplitudes(i + 1)
                end if
            end do
            
        case (GATE_SWAP)
            ! SWAP: exchange control and target qubits
            do i = 0, state%dim - 1
                control_bit = iand(i, control_mask)
                target_bit = iand(i, target_mask)
                
                ! Only process each pair once
                if (control_bit == 0 .and. target_bit /= 0) then
                    state_01 = i
                    state_10 = ior(iand(i, not(target_mask)), control_mask)
                    
                    amp_01 = state%amplitudes(state_01 + 1)
                    amp_10 = state%amplitudes(state_10 + 1)
                    new_amplitudes(state_01 + 1) = amp_10
                    new_amplitudes(state_10 + 1) = amp_01
                end if
            end do
            
        case default
            call bob_set_error(BOB_ERROR_INVALID_GATE, &
                "Unknown two-qubit gate type", "apply_two_qubit_gate")
            return
        end select
        
        state%amplitudes = new_amplitudes
        state%is_normalized = .false.
        
        call bob_clear_error()
    end subroutine apply_two_qubit_gate
    
    !> Apply rotation gate
    subroutine apply_rotation_gate(state, gate_type, qubit_index, angle)
        type(bob_quantum_state), intent(inout) :: state
        integer(i4), intent(in) :: gate_type
        integer(i8), intent(in) :: qubit_index
        real(wp), intent(in) :: angle
        
        complex(cwp) :: gate_matrix(2,2)
        real(wp) :: half_angle, cos_half, sin_half
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot apply gate to invalid state", "apply_rotation_gate")
            return
        end if
        
        half_angle = angle / TWO
        cos_half = cos(half_angle)
        sin_half = sin(half_angle)
        
        select case (gate_type)
        case (GATE_RX)
            ! RX(θ) = exp(-iθX/2) = [[cos(θ/2), -i*sin(θ/2)], [-i*sin(θ/2), cos(θ/2)]]
            gate_matrix(1,1) = cmplx(cos_half, ZERO, cwp)
            gate_matrix(1,2) = cmplx(ZERO, -sin_half, cwp)
            gate_matrix(2,1) = cmplx(ZERO, -sin_half, cwp)
            gate_matrix(2,2) = cmplx(cos_half, ZERO, cwp)
            
        case (GATE_RY)
            ! RY(θ) = exp(-iθY/2) = [[cos(θ/2), -sin(θ/2)], [sin(θ/2), cos(θ/2)]]
            gate_matrix(1,1) = cmplx(cos_half, ZERO, cwp)
            gate_matrix(1,2) = cmplx(-sin_half, ZERO, cwp)
            gate_matrix(2,1) = cmplx(sin_half, ZERO, cwp)
            gate_matrix(2,2) = cmplx(cos_half, ZERO, cwp)
            
        case (GATE_RZ)
            ! RZ(θ) = exp(-iθZ/2) = [[exp(-iθ/2), 0], [0, exp(iθ/2)]]
            gate_matrix(1,1) = exp(-CI * half_angle)
            gate_matrix(1,2) = CZERO
            gate_matrix(2,1) = CZERO
            gate_matrix(2,2) = exp(CI * half_angle)
            
        case default
            call bob_set_error(BOB_ERROR_INVALID_GATE, &
                "Unknown rotation gate type", "apply_rotation_gate")
            return
        end select
        
        ! Apply as single-qubit gate with custom matrix
        call apply_arbitrary_unitary(state, gate_matrix, qubit_index)
        
        call bob_clear_error()
    end subroutine apply_rotation_gate
    
    !> Apply controlled gate
    subroutine apply_controlled_gate(state, gate_matrix, control_qubit, target_qubit)
        type(bob_quantum_state), intent(inout) :: state
        complex(cwp), intent(in) :: gate_matrix(2,2)
        integer(i8), intent(in) :: control_qubit, target_qubit
        
        complex(cwp) :: new_amplitudes(state%dim)
        integer(i8) :: i, control_mask, target_mask
        integer(i8) :: num_qubits, control_bit, target_bit
        integer(i8) :: state_0, state_1
        complex(cwp) :: amp_0, amp_1
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot apply gate to invalid state", "apply_controlled_gate")
            return
        end if
        
        ! Verify gate is unitary
        if (.not. verify_unitary(gate_matrix, 2_i8)) then
            call bob_set_error(BOB_ERROR_NOT_UNITARY, &
                "Gate matrix is not unitary", "apply_controlled_gate")
            return
        end if
        
        num_qubits = int(log(real(state%dim, wp)) / log(TWO), i8)
        
        if (control_qubit < 0 .or. control_qubit >= num_qubits .or. &
            target_qubit < 0 .or. target_qubit >= num_qubits .or. &
            control_qubit == target_qubit) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Invalid qubit indices", "apply_controlled_gate")
            return
        end if
        
        control_mask = ishft(1_i8, int(control_qubit))
        target_mask = ishft(1_i8, int(target_qubit))
        
        new_amplitudes = state%amplitudes
        
        ! Apply gate only when control qubit is |1⟩
        do i = 0, state%dim - 1
            control_bit = iand(i, control_mask)
            
            if (control_bit /= 0) then
                ! Control is |1⟩, apply gate to target
                target_bit = iand(i, target_mask)
                
                if (target_bit == 0) then
                    state_0 = i
                    state_1 = ior(i, target_mask)
                    
                    amp_0 = state%amplitudes(state_0 + 1)
                    amp_1 = state%amplitudes(state_1 + 1)
                    
                    new_amplitudes(state_0 + 1) = gate_matrix(1,1) * amp_0 + gate_matrix(1,2) * amp_1
                    new_amplitudes(state_1 + 1) = gate_matrix(2,1) * amp_0 + gate_matrix(2,2) * amp_1
                end if
            end if
        end do
        
        state%amplitudes = new_amplitudes
        state%is_normalized = .false.
        
        call bob_clear_error()
    end subroutine apply_controlled_gate
    
    !> Apply arbitrary unitary matrix to single qubit
    subroutine apply_arbitrary_unitary(state, gate_matrix, qubit_index)
        type(bob_quantum_state), intent(inout) :: state
        complex(cwp), intent(in) :: gate_matrix(2,2)
        integer(i8), intent(in) :: qubit_index
        
        complex(cwp) :: new_amplitudes(state%dim)
        integer(i8) :: i, bit_mask, qubit_bit
        integer(i8) :: num_qubits, state_0, state_1
        complex(cwp) :: amp_0, amp_1
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot apply gate to invalid state", "apply_arbitrary_unitary")
            return
        end if
        
        ! Verify gate is unitary
        if (.not. verify_unitary(gate_matrix, 2_i8)) then
            call bob_set_error(BOB_ERROR_NOT_UNITARY, &
                "Gate matrix is not unitary", "apply_arbitrary_unitary")
            return
        end if
        
        num_qubits = int(log(real(state%dim, wp)) / log(TWO), i8)
        
        if (qubit_index < 0 .or. qubit_index >= num_qubits) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Qubit index out of range", "apply_arbitrary_unitary")
            return
        end if
        
        bit_mask = ishft(1_i8, int(qubit_index))
        
        do i = 0, state%dim - 1
            qubit_bit = iand(i, bit_mask)
            
            if (qubit_bit == 0) then
                state_0 = i
                state_1 = ior(i, bit_mask)
                
                amp_0 = state%amplitudes(state_0 + 1)
                amp_1 = state%amplitudes(state_1 + 1)
                
                new_amplitudes(state_0 + 1) = gate_matrix(1,1) * amp_0 + gate_matrix(1,2) * amp_1
                new_amplitudes(state_1 + 1) = gate_matrix(2,1) * amp_0 + gate_matrix(2,2) * amp_1
            end if
        end do
        
        state%amplitudes = new_amplitudes
        state%is_normalized = .false.
        
        call bob_clear_error()
    end subroutine apply_arbitrary_unitary
    
    !> Verify matrix is unitary: U†U = I
    function verify_unitary(matrix, dim) result(is_unitary)
        integer(i8), intent(in) :: dim
        complex(cwp), intent(in) :: matrix(dim, dim)
        logical(lk) :: is_unitary
        
        complex(cwp) :: product(dim, dim)
        complex(cwp) :: identity(dim, dim)
        integer(i8) :: i, j, k
        real(wp) :: max_error
        
        is_unitary = .false.
        
        ! Compute U†U
        product = CZERO
        do i = 1, dim
            do j = 1, dim
                do k = 1, dim
                    product(i,j) = product(i,j) + conjg(matrix(k,i)) * matrix(k,j)
                end do
            end do
        end do
        
        ! Create identity matrix
        identity = CZERO
        do i = 1, dim
            identity(i,i) = CONE
        end do
        
        ! Check if product equals identity
        max_error = ZERO
        do i = 1, dim
            do j = 1, dim
                max_error = max(max_error, abs(product(i,j) - identity(i,j)))
            end do
        end do
        
        is_unitary = (max_error < TOL_UNITARY)
    end function verify_unitary
    
    !> C ABI: Apply gate to state
    function bob_gate_apply(state_ptr, gate_type, qubit_index) result(status) &
        bind(C, name="bob_gate_apply")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: state_ptr
        integer(c_int), value :: gate_type
        integer(c_int64_t), value :: qubit_index
        integer(c_int) :: status
        
        type(bob_quantum_state), pointer :: state
        
        if (.not. c_associated(state_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(state_ptr, state)
        call apply_single_qubit_gate(state, gate_type, qubit_index)
        status = bob_get_last_error()
    end function bob_gate_apply

end module bob_gates

! Made with Bob
