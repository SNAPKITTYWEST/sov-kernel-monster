! BOB Quantum Civilization Engine - Random Number Generation
! Module: bob_rng
! Purpose: Deterministic seeded pseudo-random number generation
! Standard: Fortran 2018

module bob_rng
    use bob_kinds
    use bob_errors
    implicit none
    private
    
    !> Random number generator state
    type, public :: bob_rng_state
        integer(i8) :: seed = 0_i8
        integer(i8) :: state(4) = 0_i8  ! xoshiro256** state
        integer(i8) :: call_count = 0_i8
        logical(lk) :: is_initialized = .false.
    contains
        procedure :: init => rng_init
        procedure :: uniform => rng_uniform
        procedure :: normal => rng_normal
        procedure :: integer_range => rng_integer_range
        procedure :: choice => rng_choice
    end type bob_rng_state
    
    public :: bob_rng_create
    public :: bob_rng_destroy
    public :: bob_rng_seed
    
contains

    !> Initialize RNG with seed
    subroutine rng_init(this, seed)
        class(bob_rng_state), intent(inout) :: this
        integer(i8), intent(in) :: seed
        integer :: i
        
        this%seed = seed
        this%call_count = 0_i8
        
        ! Initialize xoshiro256** state using splitmix64
        this%state(1) = splitmix64(seed)
        this%state(2) = splitmix64(this%state(1))
        this%state(3) = splitmix64(this%state(2))
        this%state(4) = splitmix64(this%state(3))
        
        this%is_initialized = .true.
    end subroutine rng_init
    
    !> Generate uniform random number in [0, 1)
    function rng_uniform(this) result(r)
        class(bob_rng_state), intent(inout) :: this
        real(wp) :: r
        integer(i8) :: bits
        
        if (.not. this%is_initialized) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "RNG not initialized", "rng_uniform")
            r = ZERO
            return
        end if
        
        bits = xoshiro256ss(this%state)
        this%call_count = this%call_count + 1
        
        ! Convert to [0, 1) using upper 53 bits
        r = real(ishft(bits, -11), wp) * (ONE / real(ishft(1_i8, 53), wp))
        
        call bob_clear_error()
    end function rng_uniform
    
    !> Generate normal random number (Box-Muller transform)
    function rng_normal(this, mean, stddev) result(r)
        class(bob_rng_state), intent(inout) :: this
        real(wp), intent(in), optional :: mean, stddev
        real(wp) :: r
        real(wp) :: u1, u2, z0
        real(wp) :: mu, sigma
        
        mu = ZERO
        sigma = ONE
        if (present(mean)) mu = mean
        if (present(stddev)) sigma = stddev
        
        ! Box-Muller transform
        u1 = this%uniform()
        u2 = this%uniform()
        
        z0 = sqrt(-TWO * log(u1)) * cos(TWO * PI * u2)
        r = mu + sigma * z0
    end function rng_normal
    
    !> Generate random integer in [min_val, max_val]
    function rng_integer_range(this, min_val, max_val) result(r)
        class(bob_rng_state), intent(inout) :: this
        integer(i8), intent(in) :: min_val, max_val
        integer(i8) :: r
        real(wp) :: u
        
        if (min_val > max_val) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "min_val > max_val", "rng_integer_range")
            r = min_val
            return
        end if
        
        u = this%uniform()
        r = min_val + int(u * real(max_val - min_val + 1, wp), i8)
        
        ! Clamp to range
        if (r > max_val) r = max_val
        
        call bob_clear_error()
    end function rng_integer_range
    
    !> Choose random element from array
    function rng_choice(this, array, n) result(idx)
        class(bob_rng_state), intent(inout) :: this
        integer(i8), intent(in) :: n
        integer(i8), intent(in) :: array(n)
        integer(i8) :: idx
        
        if (n <= 0) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Array size must be positive", "rng_choice")
            idx = 0
            return
        end if
        
        idx = this%integer_range(1_i8, n)
        call bob_clear_error()
    end function rng_choice
    
    !> xoshiro256** algorithm
    function xoshiro256ss(state) result(r)
        integer(i8), intent(inout) :: state(4)
        integer(i8) :: r, t
        
        ! result = rotl(state[1] * 5, 7) * 9
        r = rotl64(state(2) * 5_i8, 7) * 9_i8
        
        t = ishft(state(2), 17)
        
        state(3) = ieor(state(3), state(1))
        state(4) = ieor(state(4), state(2))
        state(2) = ieor(state(2), state(3))
        state(1) = ieor(state(1), state(4))
        
        state(3) = ieor(state(3), t)
        state(4) = rotl64(state(4), 45)
    end function xoshiro256ss
    
    !> Rotate left 64-bit integer
    function rotl64(x, k) result(r)
        integer(i8), intent(in) :: x
        integer, intent(in) :: k
        integer(i8) :: r
        
        r = ior(ishft(x, k), ishft(x, k - 64))
    end function rotl64
    
    !> splitmix64 for seeding
    function splitmix64(x) result(r)
        integer(i8), intent(in) :: x
        integer(i8) :: r, z
        
        z = x + int(z'9e3779b97f4a7c15', i8)
        z = ieor(z, ishft(z, -30)) * int(z'bf58476d1ce4e5b9', i8)
        z = ieor(z, ishft(z, -27)) * int(z'94d049bb133111eb', i8)
        r = ieor(z, ishft(z, -31))
    end function splitmix64
    
    !> C ABI: Create RNG
    function bob_rng_create(seed) result(rng_ptr) bind(C, name="bob_rng_create")
        use, intrinsic :: iso_c_binding
        integer(c_int64_t), value :: seed
        type(c_ptr) :: rng_ptr
        
        type(bob_rng_state), pointer :: rng
        
        allocate(rng)
        call rng%init(seed)
        rng_ptr = c_loc(rng)
    end function bob_rng_create
    
    !> C ABI: Destroy RNG
    subroutine bob_rng_destroy(rng_ptr) bind(C, name="bob_rng_destroy")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: rng_ptr
        type(bob_rng_state), pointer :: rng
        
        if (.not. c_associated(rng_ptr)) return
        
        call c_f_pointer(rng_ptr, rng)
        deallocate(rng)
    end subroutine bob_rng_destroy
    
    !> C ABI: Seed RNG
    function bob_rng_seed(rng_ptr, seed) result(status) bind(C, name="bob_rng_seed")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: rng_ptr
        integer(c_int64_t), value :: seed
        integer(c_int) :: status
        
        type(bob_rng_state), pointer :: rng
        
        if (.not. c_associated(rng_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(rng_ptr, rng)
        call rng%init(seed)
        status = BOB_SUCCESS
    end function bob_rng_seed

end module bob_rng

! Made with Bob
