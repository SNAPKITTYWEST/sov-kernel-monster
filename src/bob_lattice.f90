! BOB Quantum Civilization Engine - Quantum Vortex Lattice
! Module: bob_lattice
! Purpose: 3D lattice of quantum vortices with topological properties
! Standard: Fortran 2018

module bob_lattice
    use bob_kinds
    use bob_errors
    use bob_state
    use bob_rng
    implicit none
    private
    
    !> Vortex in lattice
    type :: bob_vortex
        integer(i8) :: position(3)              ! (x, y, z) position
        integer(i4) :: winding_number           ! Topological charge
        complex(cwp) :: phase                   ! Quantum phase
        real(wp) :: energy                      ! Local energy
        integer(i8) :: entangled_neighbors(6)   ! Indices of entangled neighbors
        integer(i4) :: num_entangled            ! Number of entangled neighbors
        integer(i8) :: measurement_count        ! Number of measurements
        real(wp) :: creation_time               ! When vortex was created
    end type bob_vortex
    
    !> 3D quantum vortex lattice
    type, public :: bob_vortex_lattice
        integer(i8) :: size(3)                  ! Lattice dimensions (nx, ny, nz)
        integer(i8) :: num_vortices             ! Total number of vortices
        type(bob_vortex), allocatable :: vortices(:,:,:)  ! 3D array of vortices
        real(wp) :: coupling_strength           ! Nearest-neighbor coupling
        real(wp) :: time                        ! Simulation time
        real(wp) :: dt                          ! Time step
        logical(lk) :: periodic_boundary        ! Periodic boundary conditions
        logical(lk) :: is_initialized           ! Initialization flag
        type(bob_rng_state) :: rng              ! Random number generator
    contains
        procedure :: init => lattice_init
        procedure :: destroy => lattice_destroy
        procedure :: evolve => lattice_evolve
        procedure :: get_vortex => lattice_get_vortex
        procedure :: set_vortex => lattice_set_vortex
        procedure :: get_neighbors => lattice_get_neighbors
        procedure :: create_entanglement => lattice_create_entanglement
        procedure :: calculate_hamiltonian => lattice_calculate_hamiltonian
        procedure :: total_energy => lattice_total_energy
        procedure :: entanglement_entropy => lattice_entanglement_entropy
        procedure :: apply_error_correction => lattice_apply_error_correction
    end type bob_vortex_lattice
    
    public :: bob_lattice_create
    public :: bob_lattice_destroy
    public :: bob_lattice_evolve
    public :: bob_lattice_get_energy
    
contains

    !> Initialize lattice
    subroutine lattice_init(this, nx, ny, nz, coupling, seed, periodic)
        class(bob_vortex_lattice), intent(inout) :: this
        integer(i8), intent(in) :: nx, ny, nz
        real(wp), intent(in) :: coupling
        integer(i8), intent(in) :: seed
        logical(lk), intent(in), optional :: periodic
        
        integer(i8) :: i, j, k
        integer :: stat
        real(wp) :: phase_real, phase_imag
        
        if (nx <= 0 .or. ny <= 0 .or. nz <= 0) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Lattice dimensions must be positive", "lattice_init")
            return
        end if
        
        this%size = [nx, ny, nz]
        this%num_vortices = nx * ny * nz
        this%coupling_strength = coupling
        this%time = ZERO
        this%dt = 0.01_wp
        this%periodic_boundary = .true.
        if (present(periodic)) this%periodic_boundary = periodic
        
        ! Initialize RNG
        call this%rng%init(seed)
        
        ! Allocate vortex array
        if (allocated(this%vortices)) deallocate(this%vortices)
        allocate(this%vortices(nx, ny, nz), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate vortex lattice", "lattice_init")
            return
        end if
        
        ! Initialize each vortex
        do k = 1, nz
            do j = 1, ny
                do i = 1, nx
                    this%vortices(i,j,k)%position = [i, j, k]
                    
                    ! Random winding number: -1, 0, or 1
                    this%vortices(i,j,k)%winding_number = &
                        int(this%rng%integer_range(-1_i8, 1_i8), i4)
                    
                    ! Random initial phase
                    phase_real = this%rng%normal(ZERO, ONE)
                    phase_imag = this%rng%normal(ZERO, ONE)
                    this%vortices(i,j,k)%phase = cmplx(phase_real, phase_imag, cwp)
                    
                    ! Normalize phase
                    this%vortices(i,j,k)%phase = this%vortices(i,j,k)%phase / &
                        abs(this%vortices(i,j,k)%phase)
                    
                    ! Initial energy
                    this%vortices(i,j,k)%energy = this%rng%uniform() * TWO - ONE
                    
                    ! No entanglement yet
                    this%vortices(i,j,k)%entangled_neighbors = 0
                    this%vortices(i,j,k)%num_entangled = 0
                    this%vortices(i,j,k)%measurement_count = 0
                    this%vortices(i,j,k)%creation_time = ZERO
                end do
            end do
        end do
        
        ! Create nearest-neighbor entanglement
        call this%create_entanglement()
        
        this%is_initialized = .true.
        call bob_clear_error()
    end subroutine lattice_init
    
    !> Destroy lattice
    subroutine lattice_destroy(this)
        class(bob_vortex_lattice), intent(inout) :: this
        
        if (allocated(this%vortices)) deallocate(this%vortices)
        this%num_vortices = 0
        this%is_initialized = .false.
    end subroutine lattice_destroy
    
    !> Evolve lattice in time
    subroutine lattice_evolve(this, dt)
        class(bob_vortex_lattice), intent(inout) :: this
        real(wp), intent(in), optional :: dt
        
        integer(i8) :: i, j, k
        real(wp) :: timestep, hamiltonian
        complex(cwp) :: evolution_factor
        
        if (.not. this%is_initialized) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Lattice not initialized", "lattice_evolve")
            return
        end if
        
        timestep = this%dt
        if (present(dt)) timestep = dt
        
        ! Evolve each vortex under local Hamiltonian
        do k = 1, this%size(3)
            do j = 1, this%size(2)
                do i = 1, this%size(1)
                    ! Calculate local Hamiltonian
                    hamiltonian = this%calculate_hamiltonian(i, j, k)
                    
                    ! Time evolution: |ψ(t+dt)⟩ = exp(-iHdt/ℏ)|ψ(t)⟩
                    ! Using ℏ = 1 for simplicity
                    evolution_factor = exp(-CI * hamiltonian * timestep)
                    
                    ! Apply evolution
                    this%vortices(i,j,k)%phase = this%vortices(i,j,k)%phase * evolution_factor
                    this%vortices(i,j,k)%energy = hamiltonian
                end do
            end do
        end do
        
        this%time = this%time + timestep
        call bob_clear_error()
    end subroutine lattice_evolve
    
    !> Get vortex at position
    function lattice_get_vortex(this, i, j, k) result(vortex)
        class(bob_vortex_lattice), intent(in) :: this
        integer(i8), intent(in) :: i, j, k
        type(bob_vortex) :: vortex
        
        if (i < 1 .or. i > this%size(1) .or. &
            j < 1 .or. j > this%size(2) .or. &
            k < 1 .or. k > this%size(3)) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Vortex position out of bounds", "lattice_get_vortex")
            return
        end if
        
        vortex = this%vortices(i, j, k)
        call bob_clear_error()
    end function lattice_get_vortex
    
    !> Set vortex at position
    subroutine lattice_set_vortex(this, i, j, k, vortex)
        class(bob_vortex_lattice), intent(inout) :: this
        integer(i8), intent(in) :: i, j, k
        type(bob_vortex), intent(in) :: vortex
        
        if (i < 1 .or. i > this%size(1) .or. &
            j < 1 .or. j > this%size(2) .or. &
            k < 1 .or. k > this%size(3)) then
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
                "Vortex position out of bounds", "lattice_set_vortex")
            return
        end if
        
        this%vortices(i, j, k) = vortex
        call bob_clear_error()
    end subroutine lattice_set_vortex
    
    !> Get neighbor positions
    subroutine lattice_get_neighbors(this, i, j, k, neighbors, num_neighbors)
        class(bob_vortex_lattice), intent(in) :: this
        integer(i8), intent(in) :: i, j, k
        integer(i8), intent(out) :: neighbors(6, 3)
        integer(i4), intent(out) :: num_neighbors
        
        integer(i8) :: ni, nj, nk
        integer(i4) :: count
        
        count = 0
        neighbors = 0
        
        ! Six nearest neighbors: ±x, ±y, ±z
        ! +x neighbor
        ni = i + 1
        if (this%periodic_boundary) ni = mod(ni - 1, this%size(1)) + 1
        if (ni >= 1 .and. ni <= this%size(1)) then
            count = count + 1
            neighbors(count, :) = [ni, j, k]
        end if
        
        ! -x neighbor
        ni = i - 1
        if (this%periodic_boundary .and. ni < 1) ni = this%size(1)
        if (ni >= 1 .and. ni <= this%size(1)) then
            count = count + 1
            neighbors(count, :) = [ni, j, k]
        end if
        
        ! +y neighbor
        nj = j + 1
        if (this%periodic_boundary) nj = mod(nj - 1, this%size(2)) + 1
        if (nj >= 1 .and. nj <= this%size(2)) then
            count = count + 1
            neighbors(count, :) = [i, nj, k]
        end if
        
        ! -y neighbor
        nj = j - 1
        if (this%periodic_boundary .and. nj < 1) nj = this%size(2)
        if (nj >= 1 .and. nj <= this%size(2)) then
            count = count + 1
            neighbors(count, :) = [i, nj, k]
        end if
        
        ! +z neighbor
        nk = k + 1
        if (this%periodic_boundary) nk = mod(nk - 1, this%size(3)) + 1
        if (nk >= 1 .and. nk <= this%size(3)) then
            count = count + 1
            neighbors(count, :) = [i, j, nk]
        end if
        
        ! -z neighbor
        nk = k - 1
        if (this%periodic_boundary .and. nk < 1) nk = this%size(3)
        if (nk >= 1 .and. nk <= this%size(3)) then
            count = count + 1
            neighbors(count, :) = [i, j, nk]
        end if
        
        num_neighbors = count
    end subroutine lattice_get_neighbors
    
    !> Create entanglement network
    subroutine lattice_create_entanglement(this)
        class(bob_vortex_lattice), intent(inout) :: this
        
        integer(i8) :: i, j, k, n
        integer(i8) :: neighbors(6, 3)
        integer(i4) :: num_neighbors
        complex(cwp) :: entangled_phase
        
        do k = 1, this%size(3)
            do j = 1, this%size(2)
                do i = 1, this%size(1)
                    call this%get_neighbors(i, j, k, neighbors, num_neighbors)
                    
                    this%vortices(i,j,k)%num_entangled = num_neighbors
                    
                    ! Entangle with neighbors
                    do n = 1, num_neighbors
                        ! Store neighbor index (flattened)
                        this%vortices(i,j,k)%entangled_neighbors(n) = &
                            (neighbors(n,1) - 1) * this%size(2) * this%size(3) + &
                            (neighbors(n,2) - 1) * this%size(3) + &
                            neighbors(n,3)
                        
                        ! Create entangled state: (|ψ₁⟩ + |ψ₂⟩)/√2
                        entangled_phase = (this%vortices(i,j,k)%phase + &
                            this%vortices(neighbors(n,1), neighbors(n,2), neighbors(n,3))%phase) / &
                            sqrt(TWO)
                        
                        this%vortices(i,j,k)%phase = entangled_phase
                        this%vortices(neighbors(n,1), neighbors(n,2), neighbors(n,3))%phase = &
                            entangled_phase
                    end do
                end do
            end do
        end do
    end subroutine lattice_create_entanglement
    
    !> Calculate local Hamiltonian for vortex
    function lattice_calculate_hamiltonian(this, i, j, k) result(hamiltonian)
        class(bob_vortex_lattice), intent(in) :: this
        integer(i8), intent(in) :: i, j, k
        real(wp) :: hamiltonian
        
        integer(i8) :: neighbors(6, 3)
        integer(i4) :: num_neighbors, n
        real(wp) :: kinetic, interaction
        complex(cwp) :: neighbor_phase
        
        ! Kinetic energy: proportional to winding number squared
        kinetic = real(this%vortices(i,j,k)%winding_number ** 2, wp)
        
        ! Interaction energy with neighbors
        interaction = ZERO
        call this%get_neighbors(i, j, k, neighbors, num_neighbors)
        
        do n = 1, num_neighbors
            neighbor_phase = this%vortices(neighbors(n,1), neighbors(n,2), neighbors(n,3))%phase
            
            ! Quantum coupling: ⟨ψᵢ|ψⱼ⟩
            interaction = interaction + real(this%vortices(i,j,k)%phase * conjg(neighbor_phase))
        end do
        
        interaction = -this%coupling_strength * interaction
        
        hamiltonian = kinetic + interaction
    end function lattice_calculate_hamiltonian
    
    !> Calculate total lattice energy
    function lattice_total_energy(this) result(energy)
        class(bob_vortex_lattice), intent(in) :: this
        real(wp) :: energy
        
        integer(i8) :: i, j, k
        
        energy = ZERO
        
        if (.not. this%is_initialized) return
        
        do k = 1, this%size(3)
            do j = 1, this%size(2)
                do i = 1, this%size(1)
                    energy = energy + this%vortices(i,j,k)%energy
                end do
            end do
        end do
    end function lattice_total_energy
    
    !> Calculate entanglement entropy
    function lattice_entanglement_entropy(this) result(entropy)
        class(bob_vortex_lattice), intent(in) :: this
        real(wp) :: entropy
        
        integer(i8) :: i, j, k
        integer(i8) :: total_entanglement, max_entanglement
        
        if (.not. this%is_initialized) then
            entropy = ZERO
            return
        end if
        
        total_entanglement = 0
        
        do k = 1, this%size(3)
            do j = 1, this%size(2)
                do i = 1, this%size(1)
                    total_entanglement = total_entanglement + &
                        int(this%vortices(i,j,k)%num_entangled, i8)
                end do
            end do
        end do
        
        ! Maximum possible entanglement (6 neighbors per vortex)
        max_entanglement = this%num_vortices * 6
        
        if (max_entanglement > 0) then
            entropy = real(total_entanglement, wp) / real(max_entanglement, wp)
        else
            entropy = ZERO
        end if
    end function lattice_entanglement_entropy
    
    !> Apply topological error correction
    function lattice_apply_error_correction(this) result(errors_corrected)
        class(bob_vortex_lattice), intent(inout) :: this
        integer(i8) :: errors_corrected
        
        integer(i8) :: i, j, k
        real(wp) :: phase_magnitude
        
        errors_corrected = 0
        
        if (.not. this%is_initialized) return
        
        ! Check for phase errors (magnitude too small)
        do k = 1, this%size(3)
            do j = 1, this%size(2)
                do i = 1, this%size(1)
                    phase_magnitude = abs(this%vortices(i,j,k)%phase)
                    
                    if (phase_magnitude < 0.1_wp) then
                        ! Apply X gate (phase flip)
                        this%vortices(i,j,k)%phase = -this%vortices(i,j,k)%phase
                        errors_corrected = errors_corrected + 1
                    end if
                    
                    ! Renormalize phase
                    if (phase_magnitude > TOL_NORM) then
                        this%vortices(i,j,k)%phase = this%vortices(i,j,k)%phase / phase_magnitude
                    end if
                end do
            end do
        end do
    end function lattice_apply_error_correction
    
    !> C ABI: Create lattice
    function bob_lattice_create(nx, ny, nz, coupling, seed) result(lattice_ptr) &
        bind(C, name="bob_lattice_create")
        use, intrinsic :: iso_c_binding
        integer(c_int64_t), value :: nx, ny, nz
        real(c_double), value :: coupling
        integer(c_int64_t), value :: seed
        type(c_ptr) :: lattice_ptr
        
        type(bob_vortex_lattice), pointer :: lattice
        
        allocate(lattice)
        call lattice%init(nx, ny, nz, coupling, seed)
        lattice_ptr = c_loc(lattice)
    end function bob_lattice_create
    
    !> C ABI: Destroy lattice
    subroutine bob_lattice_destroy(lattice_ptr) bind(C, name="bob_lattice_destroy")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: lattice_ptr
        type(bob_vortex_lattice), pointer :: lattice
        
        if (.not. c_associated(lattice_ptr)) return
        
        call c_f_pointer(lattice_ptr, lattice)
        call lattice%destroy()
        deallocate(lattice)
    end subroutine bob_lattice_destroy
    
    !> C ABI: Evolve lattice
    function bob_lattice_evolve(lattice_ptr, dt) result(status) &
        bind(C, name="bob_lattice_evolve")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: lattice_ptr
        real(c_double), value :: dt
        integer(c_int) :: status
        
        type(bob_vortex_lattice), pointer :: lattice
        
        if (.not. c_associated(lattice_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(lattice_ptr, lattice)
        call lattice%evolve(dt)
        status = bob_get_last_error()
    end function bob_lattice_evolve
    
    !> C ABI: Get total energy
    function bob_lattice_get_energy(lattice_ptr) result(energy) &
        bind(C, name="bob_lattice_get_energy")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: lattice_ptr
        real(c_double) :: energy
        
        type(bob_vortex_lattice), pointer :: lattice
        
        if (.not. c_associated(lattice_ptr)) then
            energy = ZERO
            return
        end if
        
        call c_f_pointer(lattice_ptr, lattice)
        energy = lattice%total_energy()
    end function bob_lattice_get_energy

end module bob_lattice

! Made with Bob
