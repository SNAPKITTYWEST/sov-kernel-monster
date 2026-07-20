! BOB Quantum Civilization Engine - Quantum State Management
! Module: bob_state
! Purpose: State vector representation, normalization, validation
! Standard: Fortran 2018

module bob_state
    use bob_kinds
    use bob_errors
    implicit none
    private
    
    !> Quantum state vector
    type, public :: bob_quantum_state
        integer(i8) :: dim = 0                          ! Hilbert space dimension
        complex(cwp), allocatable :: amplitudes(:)      ! State vector |ψ⟩
        logical(lk) :: is_normalized = .false.
        logical(lk) :: is_valid = .false.
        character(len=64) :: label = ""
        real(wp) :: creation_time = 0.0_wp
    contains
        procedure :: allocate => state_allocate
        procedure :: deallocate => state_deallocate
        procedure :: normalize => state_normalize
        procedure :: validate => state_validate
        procedure :: copy => state_copy
        procedure :: norm => state_norm
        procedure :: inner_product => state_inner_product
    end type bob_quantum_state
    
    public :: bob_state_create
    public :: bob_state_destroy
    public :: bob_state_normalize
    public :: bob_state_validate
    public :: bob_state_copy
    
contains

    !> Allocate state vector memory
    subroutine state_allocate(this, dim, label)
        class(bob_quantum_state), intent(inout) :: this
        integer(i8), intent(in) :: dim
        character(len=*), intent(in), optional :: label
        integer :: stat
        
        if (dim <= 0) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "State dimension must be positive", "state_allocate")
            return
        end if
        
        ! Deallocate if already allocated
        if (allocated(this%amplitudes)) then
            deallocate(this%amplitudes)
        end if
        
        ! Allocate new state vector
        allocate(this%amplitudes(dim), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate state vector", "state_allocate")
            return
        end if
        
        this%dim = dim
        this%amplitudes = CZERO
        this%is_normalized = .false.
        this%is_valid = .true.
        
        if (present(label)) then
            this%label = trim(label)
        else
            this%label = "unnamed_state"
        end if
        
        call bob_clear_error()
    end subroutine state_allocate
    
    !> Deallocate state vector memory
    subroutine state_deallocate(this)
        class(bob_quantum_state), intent(inout) :: this
        
        if (allocated(this%amplitudes)) then
            deallocate(this%amplitudes)
        end if
        
        this%dim = 0
        this%is_normalized = .false.
        this%is_valid = .false.
        this%label = ""
    end subroutine state_deallocate
    
    !> Normalize state vector to unit norm
    subroutine state_normalize(this)
        class(bob_quantum_state), intent(inout) :: this
        real(wp) :: norm_val
        
        if (.not. this%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot normalize invalid state", "state_normalize")
            return
        end if
        
        norm_val = this%norm()
        
        if (abs(norm_val) < TOL_NORM) then
            call bob_set_error(BOB_ERROR_NOT_NORMALIZED, &
                "State has zero norm", "state_normalize")
            return
        end if
        
        ! Normalize: |ψ⟩ → |ψ⟩/||ψ||
        this%amplitudes = this%amplitudes / norm_val
        this%is_normalized = .true.
        
        call bob_clear_error()
    end subroutine state_normalize
    
    !> Validate state vector
    function state_validate(this) result(is_valid)
        class(bob_quantum_state), intent(in) :: this
        logical(lk) :: is_valid
        real(wp) :: norm_val
        integer(i8) :: i
        
        is_valid = .false.
        
        ! Check allocation
        if (.not. allocated(this%amplitudes)) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "State vector not allocated", "state_validate")
            return
        end if
        
        ! Check dimension
        if (this%dim <= 0) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Invalid state dimension", "state_validate")
            return
        end if
        
        ! Check for NaN or Inf
        do i = 1, this%dim
            if (isnan(real(this%amplitudes(i))) .or. &
                isnan(aimag(this%amplitudes(i))) .or. &
                abs(this%amplitudes(i)) > huge(1.0_wp)) then
                call bob_set_error(BOB_ERROR_INVALID_STATE, &
                    "State contains NaN or Inf", "state_validate")
                return
            end if
        end do
        
        ! Check normalization
        norm_val = this%norm()
        if (abs(norm_val - ONE) > TOL_NORM) then
            call bob_set_error(BOB_ERROR_NOT_NORMALIZED, &
                "State not normalized", "state_validate")
            return
        end if
        
        is_valid = .true.
        call bob_clear_error()
    end function state_validate
    
    !> Copy state vector
    subroutine state_copy(this, other)
        class(bob_quantum_state), intent(inout) :: this
        type(bob_quantum_state), intent(in) :: other
        
        if (.not. other%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot copy invalid state", "state_copy")
            return
        end if
        
        call this%allocate(other%dim, other%label)
        this%amplitudes = other%amplitudes
        this%is_normalized = other%is_normalized
        this%is_valid = other%is_valid
        
        call bob_clear_error()
    end subroutine state_copy
    
    !> Calculate state norm: ||ψ|| = sqrt(⟨ψ|ψ⟩)
    function state_norm(this) result(norm_val)
        class(bob_quantum_state), intent(in) :: this
        real(wp) :: norm_val
        integer(i8) :: i
        
        norm_val = ZERO
        
        if (.not. allocated(this%amplitudes)) then
            return
        end if
        
        ! Calculate ⟨ψ|ψ⟩ = Σ|ψᵢ|²
        do i = 1, this%dim
            norm_val = norm_val + real(this%amplitudes(i) * conjg(this%amplitudes(i)))
        end do
        
        norm_val = sqrt(norm_val)
    end function state_norm
    
    !> Calculate inner product: ⟨φ|ψ⟩
    function state_inner_product(this, other) result(inner_prod)
        class(bob_quantum_state), intent(in) :: this
        type(bob_quantum_state), intent(in) :: other
        complex(cwp) :: inner_prod
        integer(i8) :: i
        
        inner_prod = CZERO
        
        if (this%dim /= other%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "States have different dimensions", "state_inner_product")
            return
        end if
        
        ! Calculate ⟨φ|ψ⟩ = Σ φᵢ* ψᵢ
        do i = 1, this%dim
            inner_prod = inner_prod + conjg(this%amplitudes(i)) * other%amplitudes(i)
        end do
        
        call bob_clear_error()
    end function state_inner_product
    
    !> C ABI: Create quantum state
    function bob_state_create(dim, label, label_len) result(state_ptr) bind(C, name="bob_state_create")
        use, intrinsic :: iso_c_binding
        integer(c_int64_t), value :: dim
        character(kind=c_char), dimension(*) :: label
        integer(c_int), value :: label_len
        type(c_ptr) :: state_ptr
        
        type(bob_quantum_state), pointer :: state
        character(len=:), allocatable :: label_str
        integer :: i
        
        ! Allocate state object
        allocate(state)
        
        ! Convert C string to Fortran string
        allocate(character(len=label_len) :: label_str)
        do i = 1, label_len
            label_str(i:i) = label(i)
        end do
        
        ! Initialize state
        call state%allocate(int(dim, i8), label_str)
        
        ! Return C pointer
        state_ptr = c_loc(state)
    end function bob_state_create
    
    !> C ABI: Destroy quantum state
    subroutine bob_state_destroy(state_ptr) bind(C, name="bob_state_destroy")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: state_ptr
        type(bob_quantum_state), pointer :: state
        
        if (.not. c_associated(state_ptr)) return
        
        call c_f_pointer(state_ptr, state)
        call state%deallocate()
        deallocate(state)
    end subroutine bob_state_destroy
    
    !> C ABI: Normalize quantum state
    function bob_state_normalize(state_ptr) result(status) bind(C, name="bob_state_normalize")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: state_ptr
        integer(c_int) :: status
        type(bob_quantum_state), pointer :: state
        
        if (.not. c_associated(state_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(state_ptr, state)
        call state%normalize()
        status = bob_get_last_error()
    end function bob_state_normalize
    
    !> C ABI: Validate quantum state
    function bob_state_validate(state_ptr) result(status) bind(C, name="bob_state_validate")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: state_ptr
        integer(c_int) :: status
        type(bob_quantum_state), pointer :: state
        logical(lk) :: is_valid
        
        if (.not. c_associated(state_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(state_ptr, state)
        is_valid = state%validate()
        
        if (is_valid) then
            status = BOB_SUCCESS
        else
            status = bob_get_last_error()
        end if
    end function bob_state_validate
    
    !> C ABI: Copy quantum state
    function bob_state_copy(src_ptr, dst_ptr) result(status) bind(C, name="bob_state_copy")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: src_ptr, dst_ptr
        integer(c_int) :: status
        type(bob_quantum_state), pointer :: src, dst
        
        if (.not. c_associated(src_ptr) .or. .not. c_associated(dst_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(src_ptr, src)
        call c_f_pointer(dst_ptr, dst)
        call dst%copy(src)
        status = bob_get_last_error()
    end function bob_state_copy

end module bob_state

! Made with Bob
