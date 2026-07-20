! BOB Quantum Civilization Engine - Hamiltonian Construction
! Module: bob_hamiltonian
! Purpose: Build and manipulate quantum Hamiltonians
! Standard: Fortran 2018

module bob_hamiltonian
    use bob_kinds
    use bob_errors
    use bob_state
    implicit none
    private
    
    !> Hamiltonian operator
    type, public :: bob_hamiltonian_operator
        integer(i8) :: dim                              ! Hilbert space dimension
        complex(cwp), allocatable :: matrix(:,:)        ! Hamiltonian matrix
        logical(lk) :: is_hermitian                     ! Hermiticity flag
        logical(lk) :: is_sparse                        ! Sparsity flag
        real(wp) :: kinetic_coefficient                 ! Kinetic energy coefficient
        real(wp) :: interaction_coefficient             ! Interaction coefficient
        real(wp) :: external_field                      ! External field strength
        character(len=64) :: label                      ! Hamiltonian label
    contains
        procedure :: init => hamiltonian_init
        procedure :: destroy => hamiltonian_destroy
        procedure :: add_kinetic => hamiltonian_add_kinetic
        procedure :: add_interaction => hamiltonian_add_interaction
        procedure :: add_external_field => hamiltonian_add_external_field
        procedure :: add_term => hamiltonian_add_term
        procedure :: verify_hermitian => hamiltonian_verify_hermitian
        procedure :: get_eigenvalues => hamiltonian_get_eigenvalues
        procedure :: apply_to_state => hamiltonian_apply_to_state
        procedure :: expectation_value => hamiltonian_expectation_value
    end type bob_hamiltonian_operator
    
    public :: bob_hamiltonian_create
    public :: bob_hamiltonian_destroy
    public :: bob_hamiltonian_apply
    
contains

    !> Initialize Hamiltonian
    subroutine hamiltonian_init(this, dim, label)
        class(bob_hamiltonian_operator), intent(inout) :: this
        integer(i8), intent(in) :: dim
        character(len=*), intent(in), optional :: label
        integer :: stat
        
        if (dim <= 0) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Hamiltonian dimension must be positive", "hamiltonian_init")
            return
        end if
        
        this%dim = dim
        this%is_hermitian = .false.
        this%is_sparse = .false.
        this%kinetic_coefficient = ONE
        this%interaction_coefficient = ONE
        this%external_field = ZERO
        
        if (present(label)) then
            this%label = trim(label)
        else
            this%label = "unnamed_hamiltonian"
        end if
        
        ! Allocate matrix
        if (allocated(this%matrix)) deallocate(this%matrix)
        allocate(this%matrix(dim, dim), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate Hamiltonian matrix", "hamiltonian_init")
            return
        end if
        
        ! Initialize to zero
        this%matrix = CZERO
        
        call bob_clear_error()
    end subroutine hamiltonian_init
    
    !> Destroy Hamiltonian
    subroutine hamiltonian_destroy(this)
        class(bob_hamiltonian_operator), intent(inout) :: this
        
        if (allocated(this%matrix)) deallocate(this%matrix)
        this%dim = 0
        this%is_hermitian = .false.
        this%label = ""
    end subroutine hamiltonian_destroy
    
    !> Add kinetic energy term
    subroutine hamiltonian_add_kinetic(this, coefficient)
        class(bob_hamiltonian_operator), intent(inout) :: this
        real(wp), intent(in), optional :: coefficient
        
        integer(i8) :: i
        real(wp) :: coeff
        
        if (.not. allocated(this%matrix)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Hamiltonian not initialized", "hamiltonian_add_kinetic")
            return
        end if
        
        coeff = ONE
        if (present(coefficient)) coeff = coefficient
        this%kinetic_coefficient = coeff
        
        ! Add kinetic term to diagonal: T = -∇²/2m (simplified as identity)
        do i = 1, this%dim
            this%matrix(i,i) = this%matrix(i,i) + cmplx(coeff, ZERO, cwp)
        end do
        
        call bob_clear_error()
    end subroutine hamiltonian_add_kinetic
    
    !> Add interaction term
    subroutine hamiltonian_add_interaction(this, interaction_matrix, coefficient)
        class(bob_hamiltonian_operator), intent(inout) :: this
        complex(cwp), intent(in) :: interaction_matrix(:,:)
        real(wp), intent(in), optional :: coefficient
        
        integer(i8) :: i, j
        real(wp) :: coeff
        
        if (.not. allocated(this%matrix)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Hamiltonian not initialized", "hamiltonian_add_interaction")
            return
        end if
        
        if (size(interaction_matrix, 1, kind=i8) /= this%dim .or. &
            size(interaction_matrix, 2, kind=i8) /= this%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "Interaction matrix dimension mismatch", "hamiltonian_add_interaction")
            return
        end if
        
        coeff = ONE
        if (present(coefficient)) coeff = coefficient
        this%interaction_coefficient = coeff
        
        ! Add interaction term
        do i = 1, this%dim
            do j = 1, this%dim
                this%matrix(i,j) = this%matrix(i,j) + &
                    cmplx(coeff, ZERO, cwp) * interaction_matrix(i,j)
            end do
        end do
        
        call bob_clear_error()
    end subroutine hamiltonian_add_interaction
    
    !> Add external field term
    subroutine hamiltonian_add_external_field(this, field_operator, field_strength)
        class(bob_hamiltonian_operator), intent(inout) :: this
        complex(cwp), intent(in) :: field_operator(:,:)
        real(wp), intent(in) :: field_strength
        
        integer(i8) :: i, j
        
        if (.not. allocated(this%matrix)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Hamiltonian not initialized", "hamiltonian_add_external_field")
            return
        end if
        
        if (size(field_operator, 1, kind=i8) /= this%dim .or. &
            size(field_operator, 2, kind=i8) /= this%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "Field operator dimension mismatch", "hamiltonian_add_external_field")
            return
        end if
        
        this%external_field = field_strength
        
        ! Add field term: H_field = -μ·B
        do i = 1, this%dim
            do j = 1, this%dim
                this%matrix(i,j) = this%matrix(i,j) - &
                    cmplx(field_strength, ZERO, cwp) * field_operator(i,j)
            end do
        end do
        
        call bob_clear_error()
    end subroutine hamiltonian_add_external_field
    
    !> Add arbitrary term to Hamiltonian
    subroutine hamiltonian_add_term(this, term_matrix, coefficient)
        class(bob_hamiltonian_operator), intent(inout) :: this
        complex(cwp), intent(in) :: term_matrix(:,:)
        complex(cwp), intent(in), optional :: coefficient
        
        integer(i8) :: i, j
        complex(cwp) :: coeff
        
        if (.not. allocated(this%matrix)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Hamiltonian not initialized", "hamiltonian_add_term")
            return
        end if
        
        if (size(term_matrix, 1, kind=i8) /= this%dim .or. &
            size(term_matrix, 2, kind=i8) /= this%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "Term matrix dimension mismatch", "hamiltonian_add_term")
            return
        end if
        
        coeff = CONE
        if (present(coefficient)) coeff = coefficient
        
        ! Add term
        do i = 1, this%dim
            do j = 1, this%dim
                this%matrix(i,j) = this%matrix(i,j) + coeff * term_matrix(i,j)
            end do
        end do
        
        call bob_clear_error()
    end subroutine hamiltonian_add_term
    
    !> Verify Hamiltonian is Hermitian: H = H†
    function hamiltonian_verify_hermitian(this) result(is_hermitian)
        class(bob_hamiltonian_operator), intent(inout) :: this
        logical(lk) :: is_hermitian
        
        integer(i8) :: i, j
        real(wp) :: max_error
        complex(cwp) :: diff
        
        is_hermitian = .false.
        
        if (.not. allocated(this%matrix)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Hamiltonian not initialized", "hamiltonian_verify_hermitian")
            return
        end if
        
        ! Check H(i,j) = H*(j,i)
        max_error = ZERO
        do i = 1, this%dim
            do j = i, this%dim
                diff = this%matrix(i,j) - conjg(this%matrix(j,i))
                max_error = max(max_error, abs(diff))
            end do
        end do
        
        is_hermitian = (max_error < TOL_HERMITIAN)
        this%is_hermitian = is_hermitian
        
        if (.not. is_hermitian) then
            call bob_set_error(BOB_ERROR_NOT_HERMITIAN, &
                "Hamiltonian is not Hermitian", "hamiltonian_verify_hermitian")
        else
            call bob_clear_error()
        end if
    end function hamiltonian_verify_hermitian
    
    !> Get eigenvalues (simplified - returns diagonal elements)
    subroutine hamiltonian_get_eigenvalues(this, eigenvalues)
        class(bob_hamiltonian_operator), intent(in) :: this
        real(wp), intent(out) :: eigenvalues(:)
        
        integer(i8) :: i
        
        if (.not. allocated(this%matrix)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Hamiltonian not initialized", "hamiltonian_get_eigenvalues")
            return
        end if
        
        if (size(eigenvalues, kind=i8) /= this%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "Eigenvalues array dimension mismatch", "hamiltonian_get_eigenvalues")
            return
        end if
        
        ! Simplified: return diagonal elements
        ! Full implementation would ! use LAPACK  ! removed: zero-dep build eigenvalue solver
        do i = 1, this%dim
            eigenvalues(i) = real(this%matrix(i,i))
        end do
        
        call bob_clear_error()
    end subroutine hamiltonian_get_eigenvalues
    
    !> Apply Hamiltonian to state: |ψ'⟩ = H|ψ⟩
    subroutine hamiltonian_apply_to_state(this, state, result_state)
        class(bob_hamiltonian_operator), intent(in) :: this
        type(bob_quantum_state), intent(in) :: state
        type(bob_quantum_state), intent(out) :: result_state
        
        integer(i8) :: i, j
        
        if (.not. allocated(this%matrix)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Hamiltonian not initialized", "hamiltonian_apply_to_state")
            return
        end if
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot apply Hamiltonian to invalid state", &
                "hamiltonian_apply_to_state")
            return
        end if
        
        if (state%dim /= this%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "State dimension mismatch", "hamiltonian_apply_to_state")
            return
        end if
        
        ! Initialize result state
        call result_state%allocate(this%dim, "H|psi>")
        
        ! Compute H|ψ⟩
        result_state%amplitudes = CZERO
        do i = 1, this%dim
            do j = 1, this%dim
                result_state%amplitudes(i) = result_state%amplitudes(i) + &
                    this%matrix(i,j) * state%amplitudes(j)
            end do
        end do
        
        result_state%is_valid = .true.
        result_state%is_normalized = .false.
        
        call bob_clear_error()
    end subroutine hamiltonian_apply_to_state
    
    !> Calculate expectation value: E = ⟨ψ|H|ψ⟩
    function hamiltonian_expectation_value(this, state) result(expectation)
        class(bob_hamiltonian_operator), intent(in) :: this
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: expectation
        
        type(bob_quantum_state) :: h_psi
        complex(cwp) :: inner_prod
        
        if (.not. allocated(this%matrix)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Hamiltonian not initialized", "hamiltonian_expectation_value")
            expectation = ZERO
            return
        end if
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute expectation for invalid state", &
                "hamiltonian_expectation_value")
            expectation = ZERO
            return
        end if
        
        ! Compute H|ψ⟩
        call this%apply_to_state(state, h_psi)
        
        if (bob_get_last_error() /= BOB_SUCCESS) then
            expectation = ZERO
            return
        end if
        
        ! Compute ⟨ψ|H|ψ⟩
        inner_prod = state%inner_product(h_psi)
        expectation = real(inner_prod)
        
        call h_psi%deallocate()
        call bob_clear_error()
    end function hamiltonian_expectation_value
    
    !> Build Ising Hamiltonian: H = -J Σ σᵢᶻσⱼᶻ - h Σ σᵢˣ
    subroutine build_ising_hamiltonian(hamiltonian, num_sites, coupling, field)
        type(bob_hamiltonian_operator), intent(out) :: hamiltonian
        integer(i8), intent(in) :: num_sites
        real(wp), intent(in) :: coupling, field
        
        integer(i8) :: dim, i, j, site
        integer(i8) :: state_i, state_j, bit_i, bit_j
        real(wp) :: interaction_energy
        
        ! Hilbert space dimension: 2^num_sites
        dim = ishft(1_i8, int(num_sites))
        
        call hamiltonian%init(dim, "Ising")
        
        ! Build Hamiltonian matrix
        do state_i = 0, dim - 1
            do state_j = 0, dim - 1
                
                if (state_i == state_j) then
                    ! Diagonal: interaction term -J Σ σᵢᶻσⱼᶻ
                    interaction_energy = ZERO
                    
                    do site = 0, num_sites - 2
                        bit_i = iand(ishft(state_i, -int(site)), 1_i8)
                        bit_j = iand(ishft(state_i, -int(site+1)), 1_i8)
                        
                        ! Convert 0,1 to -1,+1
                        interaction_energy = interaction_energy - coupling * &
                            (TWO * real(bit_i, wp) - ONE) * (TWO * real(bit_j, wp) - ONE)
                    end do
                    
                    hamiltonian%matrix(state_i + 1, state_j + 1) = &
                        cmplx(interaction_energy, ZERO, cwp)
                    
                else
                    ! Off-diagonal: transverse field term -h Σ σᵢˣ
                    ! σˣ flips one bit
                    if (popcnt(ieor(state_i, state_j)) == 1) then
                        hamiltonian%matrix(state_i + 1, state_j + 1) = &
                            cmplx(-field, ZERO, cwp)
                    end if
                end if
                
            end do
        end do
        
        hamiltonian%is_hermitian = .true.
    end subroutine build_ising_hamiltonian
    
    !> Build Heisenberg Hamiltonian: H = J Σ (σᵢˣσⱼˣ + σᵢʸσⱼʸ + σᵢᶻσⱼᶻ)
    subroutine build_heisenberg_hamiltonian(hamiltonian, num_sites, coupling)
        type(bob_hamiltonian_operator), intent(out) :: hamiltonian
        integer(i8), intent(in) :: num_sites
        real(wp), intent(in) :: coupling
        
        integer(i8) :: dim, i, j
        integer(i8) :: state_i, state_j, site
        integer(i8) :: bit_i, bit_j, flipped_state
        real(wp) :: zz_term
        
        dim = ishft(1_i8, int(num_sites))
        call hamiltonian%init(dim, "Heisenberg")
        
        do state_i = 0, dim - 1
            do state_j = 0, dim - 1
                
                if (state_i == state_j) then
                    ! Diagonal: σᶻσᶻ term
                    zz_term = ZERO
                    
                    do site = 0, num_sites - 2
                        bit_i = iand(ishft(state_i, -int(site)), 1_i8)
                        bit_j = iand(ishft(state_i, -int(site+1)), 1_i8)
                        
                        zz_term = zz_term + coupling * &
                            (TWO * real(bit_i, wp) - ONE) * (TWO * real(bit_j, wp) - ONE)
                    end do
                    
                    hamiltonian%matrix(state_i + 1, state_j + 1) = &
                        cmplx(zz_term, ZERO, cwp)
                    
                else
                    ! Off-diagonal: σˣσˣ + σʸσʸ terms
                    ! These flip two adjacent bits
                    if (popcnt(ieor(state_i, state_j)) == 2) then
                        hamiltonian%matrix(state_i + 1, state_j + 1) = &
                            cmplx(coupling / TWO, ZERO, cwp)
                    end if
                end if
                
            end do
        end do
        
        hamiltonian%is_hermitian = .true.
    end subroutine build_heisenberg_hamiltonian
    
    !> Build Hubbard Hamiltonian (simplified)
    subroutine build_hubbard_hamiltonian(hamiltonian, num_sites, hopping, interaction)
        type(bob_hamiltonian_operator), intent(out) :: hamiltonian
        integer(i8), intent(in) :: num_sites
        real(wp), intent(in) :: hopping, interaction
        
        integer(i8) :: dim
        
        dim = ishft(1_i8, int(num_sites))
        call hamiltonian%init(dim, "Hubbard")
        
        ! Simplified Hubbard model
        ! Full implementation would handle fermionic operators
        
        ! Add hopping term
        call hamiltonian%add_kinetic(-hopping)
        
        ! Add interaction term (simplified)
        hamiltonian%matrix = hamiltonian%matrix + &
            cmplx(interaction, ZERO, cwp)
        
        hamiltonian%is_hermitian = .true.
    end subroutine build_hubbard_hamiltonian
    
    !> C ABI: Create Hamiltonian
    function bob_hamiltonian_create(dim) result(ham_ptr) &
        bind(C, name="bob_hamiltonian_create")
        use, intrinsic :: iso_c_binding
        integer(c_int64_t), value :: dim
        type(c_ptr) :: ham_ptr
        
        type(bob_hamiltonian_operator), pointer :: hamiltonian
        
        allocate(hamiltonian)
        call hamiltonian%init(dim)
        ham_ptr = c_loc(hamiltonian)
    end function bob_hamiltonian_create
    
    !> C ABI: Destroy Hamiltonian
    subroutine bob_hamiltonian_destroy(ham_ptr) bind(C, name="bob_hamiltonian_destroy")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: ham_ptr
        type(bob_hamiltonian_operator), pointer :: hamiltonian
        
        if (.not. c_associated(ham_ptr)) return
        
        call c_f_pointer(ham_ptr, hamiltonian)
        call hamiltonian%destroy()
        deallocate(hamiltonian)
    end subroutine bob_hamiltonian_destroy
    
    !> C ABI: Apply Hamiltonian to state
    function bob_hamiltonian_apply(ham_ptr, state_ptr, result_ptr) result(status) &
        bind(C, name="bob_hamiltonian_apply")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: ham_ptr, state_ptr, result_ptr
        integer(c_int) :: status
        
        type(bob_hamiltonian_operator), pointer :: hamiltonian
        type(bob_quantum_state), pointer :: state, result
        
        if (.not. c_associated(ham_ptr) .or. &
            .not. c_associated(state_ptr) .or. &
            .not. c_associated(result_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(ham_ptr, hamiltonian)
        call c_f_pointer(state_ptr, state)
        call c_f_pointer(result_ptr, result)
        
        call hamiltonian%apply_to_state(state, result)
        status = bob_get_last_error()
    end function bob_hamiltonian_apply

end module bob_hamiltonian

! Made with Bob
