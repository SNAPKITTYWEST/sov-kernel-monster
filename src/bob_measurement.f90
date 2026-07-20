! BOB Quantum Civilization Engine - Quantum Measurement
! Module: bob_measurement
! Purpose: Basis measurement, probability distributions, state collapse
! Standard: Fortran 2018

module bob_measurement
    use bob_kinds
    use bob_errors
    use bob_state
    use bob_rng
    implicit none
    private
    
    !> Measurement result
    type, public :: bob_measurement_result
        integer(i8) :: num_qubits                       ! Number of qubits measured
        integer(i8), allocatable :: outcomes(:)         ! Measurement outcomes (0 or 1)
        real(wp), allocatable :: probabilities(:)       ! Probability of each outcome
        integer(i8) :: num_shots                        ! Number of measurement shots
        integer(i8), allocatable :: counts(:)           ! Count of each outcome
        real(wp) :: measurement_time                    ! When measurement occurred
        logical(lk) :: collapsed                        ! Whether state collapsed
    contains
        procedure :: init => measurement_result_init
        procedure :: destroy => measurement_result_destroy
        procedure :: get_outcome => measurement_result_get_outcome
        procedure :: get_probability => measurement_result_get_probability
        procedure :: get_count => measurement_result_get_count
    end type bob_measurement_result
    
    public :: measure_state
    public :: measure_qubit
    public :: measure_basis
    public :: measure_shots
    public :: calculate_probabilities
    public :: collapse_state
    
contains

    !> Initialize measurement result
    subroutine measurement_result_init(this, num_qubits, num_shots)
        class(bob_measurement_result), intent(inout) :: this
        integer(i8), intent(in) :: num_qubits, num_shots
        integer :: stat
        integer(i8) :: num_outcomes
        
        this%num_qubits = num_qubits
        this%num_shots = num_shots
        this%collapsed = .false.
        this%measurement_time = ZERO
        
        ! Number of possible outcomes: 2^num_qubits
        num_outcomes = ishft(1_i8, int(num_qubits))
        
        ! Allocate arrays
        if (allocated(this%outcomes)) deallocate(this%outcomes)
        if (allocated(this%probabilities)) deallocate(this%probabilities)
        if (allocated(this%counts)) deallocate(this%counts)
        
        allocate(this%outcomes(num_outcomes), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate outcomes", "measurement_result_init")
            return
        end if
        
        allocate(this%probabilities(num_outcomes), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate probabilities", "measurement_result_init")
            return
        end if
        
        allocate(this%counts(num_outcomes), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate counts", "measurement_result_init")
            return
        end if
        
        ! Initialize to zero
        this%outcomes = 0
        this%probabilities = ZERO
        this%counts = 0
        
        call bob_clear_error()
    end subroutine measurement_result_init
    
    !> Destroy measurement result
    subroutine measurement_result_destroy(this)
        class(bob_measurement_result), intent(inout) :: this
        
        if (allocated(this%outcomes)) deallocate(this%outcomes)
        if (allocated(this%probabilities)) deallocate(this%probabilities)
        if (allocated(this%counts)) deallocate(this%counts)
        
        this%num_qubits = 0
        this%num_shots = 0
    end subroutine measurement_result_destroy
    
    !> Get measurement outcome
    function measurement_result_get_outcome(this, index) result(outcome)
        class(bob_measurement_result), intent(in) :: this
        integer(i8), intent(in) :: index
        integer(i8) :: outcome
        
        if (index < 1 .or. index > size(this%outcomes, kind=i8)) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Outcome index out of range", "measurement_result_get_outcome")
            outcome = 0
            return
        end if
        
        outcome = this%outcomes(index)
        call bob_clear_error()
    end function measurement_result_get_outcome
    
    !> Get outcome probability
    function measurement_result_get_probability(this, index) result(prob)
        class(bob_measurement_result), intent(in) :: this
        integer(i8), intent(in) :: index
        real(wp) :: prob
        
        if (index < 1 .or. index > size(this%probabilities, kind=i8)) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Probability index out of range", "measurement_result_get_probability")
            prob = ZERO
            return
        end if
        
        prob = this%probabilities(index)
        call bob_clear_error()
    end function measurement_result_get_probability
    
    !> Get outcome count
    function measurement_result_get_count(this, index) result(count)
        class(bob_measurement_result), intent(in) :: this
        integer(i8), intent(in) :: index
        integer(i8) :: count
        
        if (index < 1 .or. index > size(this%counts, kind=i8)) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Count index out of range", "measurement_result_get_count")
            count = 0
            return
        end if
        
        count = this%counts(index)
        call bob_clear_error()
    end function measurement_result_get_count
    
    !> Measure entire quantum state
    subroutine measure_state(state, rng, result, collapse)
        type(bob_quantum_state), intent(inout) :: state
        type(bob_rng_state), intent(inout) :: rng
        type(bob_measurement_result), intent(out) :: result
        logical(lk), intent(in), optional :: collapse
        
        integer(i8) :: num_qubits, i
        real(wp) :: cumulative_prob, random_val
        integer(i8) :: measured_outcome
        logical(lk) :: do_collapse
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot measure invalid state", "measure_state")
            return
        end if
        
        do_collapse = .true.
        if (present(collapse)) do_collapse = collapse
        
        ! Calculate number of qubits
        num_qubits = int(log(real(state%dim, wp)) / log(TWO), i8)
        
        ! Initialize result
        call result%init(num_qubits, 1_i8)
        
        ! Calculate probabilities
        call calculate_probabilities(state, result)
        
        ! Sample from probability distribution
        random_val = rng%uniform()
        cumulative_prob = ZERO
        measured_outcome = 0
        
        do i = 1, state%dim
            cumulative_prob = cumulative_prob + result%probabilities(i)
            if (random_val <= cumulative_prob) then
                measured_outcome = i - 1
                exit
            end if
        end do
        
        ! Store outcome
        result%outcomes(measured_outcome + 1) = measured_outcome
        result%counts(measured_outcome + 1) = 1
        result%collapsed = do_collapse
        
        ! Collapse state if requested
        if (do_collapse) then
            call collapse_state(state, measured_outcome)
        end if
        
        call bob_clear_error()
    end subroutine measure_state
    
    !> Measure single qubit
    subroutine measure_qubit(state, qubit_index, rng, result, collapse)
        type(bob_quantum_state), intent(inout) :: state
        integer(i8), intent(in) :: qubit_index
        type(bob_rng_state), intent(inout) :: rng
        integer(i8), intent(out) :: result
        logical(lk), intent(in), optional :: collapse
        
        integer(i8) :: num_qubits, i, bit_mask, qubit_bit
        real(wp) :: prob_0, prob_1, random_val
        logical(lk) :: do_collapse
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot measure invalid state", "measure_qubit")
            result = 0
            return
        end if
        
        num_qubits = int(log(real(state%dim, wp)) / log(TWO), i8)
        
        if (qubit_index < 0 .or. qubit_index >= num_qubits) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Qubit index out of range", "measure_qubit")
            result = 0
            return
        end if
        
        do_collapse = .true.
        if (present(collapse)) do_collapse = collapse
        
        ! Calculate probabilities for |0⟩ and |1⟩
        bit_mask = ishft(1_i8, int(qubit_index))
        prob_0 = ZERO
        prob_1 = ZERO
        
        do i = 0, state%dim - 1
            qubit_bit = iand(i, bit_mask)
            
            if (qubit_bit == 0) then
                prob_0 = prob_0 + real(state%amplitudes(i + 1) * conjg(state%amplitudes(i + 1)))
            else
                prob_1 = prob_1 + real(state%amplitudes(i + 1) * conjg(state%amplitudes(i + 1)))
            end if
        end do
        
        ! Sample measurement outcome
        random_val = rng%uniform()
        
        if (random_val < prob_0) then
            result = 0
        else
            result = 1
        end if
        
        ! Collapse state if requested
        if (do_collapse) then
            call collapse_qubit(state, qubit_index, result)
        end if
        
        call bob_clear_error()
    end subroutine measure_qubit
    
    !> Measure in arbitrary basis
    subroutine measure_basis(state, basis_vectors, rng, result, collapse)
        type(bob_quantum_state), intent(inout) :: state
        complex(cwp), intent(in) :: basis_vectors(:,:)
        type(bob_rng_state), intent(inout) :: rng
        integer(i8), intent(out) :: result
        logical(lk), intent(in), optional :: collapse
        
        integer(i8) :: num_basis, i, j
        real(wp), allocatable :: probabilities(:)
        real(wp) :: cumulative_prob, random_val
        complex(cwp) :: inner_prod
        logical(lk) :: do_collapse
        integer :: stat
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot measure invalid state", "measure_basis")
            result = 0
            return
        end if
        
        num_basis = size(basis_vectors, 2, kind=i8)
        
        if (size(basis_vectors, 1, kind=i8) /= state%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "Basis vectors dimension mismatch", "measure_basis")
            result = 0
            return
        end if
        
        do_collapse = .true.
        if (present(collapse)) do_collapse = collapse
        
        ! Allocate probabilities
        allocate(probabilities(num_basis), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate probabilities", "measure_basis")
            result = 0
            return
        end if
        
        ! Calculate probabilities: P(i) = |⟨basis_i|ψ⟩|²
        do i = 1, num_basis
            inner_prod = CZERO
            
            do j = 1, state%dim
                inner_prod = inner_prod + conjg(basis_vectors(j, i)) * state%amplitudes(j)
            end do
            
            probabilities(i) = real(inner_prod * conjg(inner_prod))
        end do
        
        ! Sample from probability distribution
        random_val = rng%uniform()
        cumulative_prob = ZERO
        result = 0
        
        do i = 1, num_basis
            cumulative_prob = cumulative_prob + probabilities(i)
            if (random_val <= cumulative_prob) then
                result = i - 1
                exit
            end if
        end do
        
        ! Collapse to measured basis state if requested
        if (do_collapse) then
            state%amplitudes = basis_vectors(:, result + 1)
            call state%normalize()
        end if
        
        deallocate(probabilities)
        call bob_clear_error()
    end subroutine measure_basis
    
    !> Perform multiple measurement shots
    subroutine measure_shots(state, num_shots, rng, result)
        type(bob_quantum_state), intent(in) :: state
        integer(i8), intent(in) :: num_shots
        type(bob_rng_state), intent(inout) :: rng
        type(bob_measurement_result), intent(out) :: result
        
        integer(i8) :: num_qubits, shot, i
        real(wp) :: cumulative_prob, random_val
        integer(i8) :: measured_outcome
        type(bob_quantum_state) :: temp_state
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot measure invalid state", "measure_shots")
            return
        end if
        
        if (num_shots <= 0) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Number of shots must be positive", "measure_shots")
            return
        end if
        
        num_qubits = int(log(real(state%dim, wp)) / log(TWO), i8)
        
        ! Initialize result
        call result%init(num_qubits, num_shots)
        
        ! Calculate probabilities (once)
        call calculate_probabilities(state, result)
        
        ! Perform shots
        do shot = 1, num_shots
            random_val = rng%uniform()
            cumulative_prob = ZERO
            measured_outcome = 0
            
            do i = 1, state%dim
                cumulative_prob = cumulative_prob + result%probabilities(i)
                if (random_val <= cumulative_prob) then
                    measured_outcome = i - 1
                    exit
                end if
            end do
            
            ! Increment count for this outcome
            result%counts(measured_outcome + 1) = result%counts(measured_outcome + 1) + 1
        end do
        
        result%collapsed = .false.
        call bob_clear_error()
    end subroutine measure_shots
    
    !> Calculate measurement probabilities
    subroutine calculate_probabilities(state, result)
        type(bob_quantum_state), intent(in) :: state
        type(bob_measurement_result), intent(inout) :: result
        
        integer(i8) :: i
        real(wp) :: total_prob
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot calculate probabilities for invalid state", &
                "calculate_probabilities")
            return
        end if
        
        ! Calculate P(i) = |ψᵢ|²
        total_prob = ZERO
        do i = 1, state%dim
            result%probabilities(i) = real(state%amplitudes(i) * conjg(state%amplitudes(i)))
            total_prob = total_prob + result%probabilities(i)
        end do
        
        ! Verify normalization
        if (abs(total_prob - ONE) > TOL_NORM) then
            call bob_set_error(BOB_ERROR_NOT_NORMALIZED, &
                "State probabilities do not sum to 1", "calculate_probabilities")
            return
        end if
        
        call bob_clear_error()
    end subroutine calculate_probabilities
    
    !> Collapse state to measured outcome
    subroutine collapse_state(state, outcome)
        type(bob_quantum_state), intent(inout) :: state
        integer(i8), intent(in) :: outcome
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot collapse invalid state", "collapse_state")
            return
        end if
        
        if (outcome < 0 .or. outcome >= state%dim) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Outcome out of range", "collapse_state")
            return
        end if
        
        ! Set all amplitudes to zero except measured outcome
        state%amplitudes = CZERO
        state%amplitudes(outcome + 1) = CONE
        state%is_normalized = .true.
        
        call bob_clear_error()
    end subroutine collapse_state
    
    !> Collapse single qubit
    subroutine collapse_qubit(state, qubit_index, outcome)
        type(bob_quantum_state), intent(inout) :: state
        integer(i8), intent(in) :: qubit_index, outcome
        
        integer(i8) :: i, bit_mask, qubit_bit
        real(wp) :: norm_factor
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot collapse invalid state", "collapse_qubit")
            return
        end if
        
        if (outcome /= 0 .and. outcome /= 1) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Qubit outcome must be 0 or 1", "collapse_qubit")
            return
        end if
        
        bit_mask = ishft(1_i8, int(qubit_index))
        
        ! Zero out amplitudes inconsistent with measurement
        do i = 0, state%dim - 1
            qubit_bit = iand(i, bit_mask)
            
            if ((outcome == 0 .and. qubit_bit /= 0) .or. &
                (outcome == 1 .and. qubit_bit == 0)) then
                state%amplitudes(i + 1) = CZERO
            end if
        end do
        
        ! Renormalize
        call state%normalize()
        
        call bob_clear_error()
    end subroutine collapse_qubit
    
    !> C ABI: Measure state
    function bob_state_measure(state_ptr, rng_ptr, outcome) result(status) &
        bind(C, name="bob_state_measure")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: state_ptr, rng_ptr
        integer(c_int64_t), intent(out) :: outcome
        integer(c_int) :: status
        
        type(bob_quantum_state), pointer :: state
        type(bob_rng_state), pointer :: rng
        type(bob_measurement_result) :: result
        
        if (.not. c_associated(state_ptr) .or. .not. c_associated(rng_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(state_ptr, state)
        call c_f_pointer(rng_ptr, rng)
        
        call measure_state(state, rng, result, collapse=.true.)
        
        if (bob_get_last_error() == BOB_SUCCESS) then
            outcome = result%outcomes(1)
        else
            outcome = 0
        end if
        
        call result%destroy()
        status = bob_get_last_error()
    end function bob_state_measure

end module bob_measurement

! Made with Bob
