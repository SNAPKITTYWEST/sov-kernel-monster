! BOB Quantum Civilization Engine - C ABI Wrapper
! Module: bob_abi
! Purpose: Complete C-compatible interface for all BOB functionality
! Standard: Fortran 2018

module bob_abi
    use, intrinsic :: iso_c_binding
    use bob_kinds
    use bob_errors
    use bob_state
    use bob_gates
    use bob_rng
    use bob_lattice
    use bob_measurement
    use bob_metrics
    use bob_hamiltonian
    use bob_integrator
    implicit none
    private
    
    ! Export all C functions
    public :: bob_engine_version
    public :: bob_engine_info
    public :: bob_last_error_message
    
contains

    !> Get engine version string
    subroutine bob_engine_version(version_str, max_len) bind(C, name="bob_engine_version")
        character(kind=c_char), dimension(*), intent(out) :: version_str
        integer(c_int), value :: max_len
        
        character(len=64) :: version
        integer :: i, len_version
        
        version = "BOB Quantum Engine v1.0.0"
        len_version = min(len_trim(version), max_len - 1)
        
        do i = 1, len_version
            version_str(i) = version(i:i)
        end do
        version_str(len_version + 1) = c_null_char
    end subroutine bob_engine_version
    
    !> Get engine information
    subroutine bob_engine_info(info_str, max_len) bind(C, name="bob_engine_info")
        character(kind=c_char), dimension(*), intent(out) :: info_str
        integer(c_int), value :: max_len
        
        character(len=512) :: info
        integer :: i, len_info
        
        info = "BOB Quantum Civilization Engine" // c_new_line // &
               "Fortran 2018 Implementation" // c_new_line // &
               "Features: State vectors, Gates, Lattices, Measurement, " // &
               "Hamiltonians, Time evolution" // c_new_line // &
               "License: MIT (Sovereign Source)"
        
        len_info = min(len_trim(info), max_len - 1)
        
        do i = 1, len_info
            info_str(i) = info(i:i)
        end do
        info_str(len_info + 1) = c_null_char
    end subroutine bob_engine_info
    
    !> Get last error message
    subroutine bob_last_error_message(msg_str, max_len) bind(C, name="bob_last_error_message")
        character(kind=c_char), dimension(*), intent(out) :: msg_str
        integer(c_int), value :: max_len
        
        character(len=256) :: message
        integer :: i, len_msg
        integer(i4) :: error_code
        
        error_code = bob_get_last_error()
        message = bob_error_message(error_code)
        
        if (len_trim(g_error_state%message) > 0) then
            message = trim(message) // ": " // trim(g_error_state%message)
        end if
        
        if (len_trim(g_error_state%location) > 0) then
            message = trim(message) // " [" // trim(g_error_state%location) // "]"
        end if
        
        len_msg = min(len_trim(message), max_len - 1)
        
        do i = 1, len_msg
            msg_str(i) = message(i:i)
        end do
        msg_str(len_msg + 1) = c_null_char
    end subroutine bob_last_error_message
    
    !> Create complete quantum simulation
    function bob_simulation_create(num_qubits, seed) result(sim_ptr) &
        bind(C, name="bob_simulation_create")
        integer(c_int64_t), value :: num_qubits
        integer(c_int64_t), value :: seed
        type(c_ptr) :: sim_ptr
        
        type :: bob_simulation
            type(bob_quantum_state) :: state
            type(bob_hamiltonian_operator) :: hamiltonian
            type(bob_time_integrator) :: integrator
            type(bob_rng_state) :: rng
            type(bob_quantum_metrics) :: metrics
        end type bob_simulation
        
        type(bob_simulation), pointer :: sim
        integer(i8) :: dim
        
        allocate(sim)
        
        ! Initialize RNG
        call sim%rng%init(seed)
        
        ! Create state
        dim = ishft(1_i8, int(num_qubits))
        call sim%state%allocate(dim, "simulation_state")
        
        ! Initialize to |0...0⟩
        sim%state%amplitudes = CZERO
        sim%state%amplitudes(1) = CONE
        sim%state%is_normalized = .true.
        
        ! Create Hamiltonian
        call sim%hamiltonian%init(dim, "simulation_hamiltonian")
        
        ! Create integrator (RK4 by default)
        call sim%integrator%init(INTEGRATOR_RK4, 0.01_wp, "simulation_integrator")
        
        ! Initialize metrics
        call sim%metrics%init()
        
        sim_ptr = c_loc(sim)
    end function bob_simulation_create
    
    !> Destroy simulation
    subroutine bob_simulation_destroy(sim_ptr) bind(C, name="bob_simulation_destroy")
        type(c_ptr), value :: sim_ptr
        
        type :: bob_simulation
            type(bob_quantum_state) :: state
            type(bob_hamiltonian_operator) :: hamiltonian
            type(bob_time_integrator) :: integrator
            type(bob_rng_state) :: rng
            type(bob_quantum_metrics) :: metrics
        end type bob_simulation
        
        type(bob_simulation), pointer :: sim
        
        if (.not. c_associated(sim_ptr)) return
        
        call c_f_pointer(sim_ptr, sim)
        
        call sim%state%deallocate()
        call sim%hamiltonian%destroy()
        
        deallocate(sim)
    end subroutine bob_simulation_destroy
    
    !> Run simulation step
    function bob_simulation_step(sim_ptr) result(status) &
        bind(C, name="bob_simulation_step")
        type(c_ptr), value :: sim_ptr
        integer(c_int) :: status
        
        type :: bob_simulation
            type(bob_quantum_state) :: state
            type(bob_hamiltonian_operator) :: hamiltonian
            type(bob_time_integrator) :: integrator
            type(bob_rng_state) :: rng
            type(bob_quantum_metrics) :: metrics
        end type bob_simulation
        
        type(bob_simulation), pointer :: sim
        
        if (.not. c_associated(sim_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(sim_ptr, sim)
        
        ! Take integration step
        call sim%integrator%step(sim%state, sim%hamiltonian)
        
        status = bob_get_last_error()
    end function bob_simulation_step
    
    !> Get simulation metrics
    function bob_simulation_get_metrics(sim_ptr, energy, entropy, coherence) result(status) &
        bind(C, name="bob_simulation_get_metrics")
        type(c_ptr), value :: sim_ptr
        real(c_double), intent(out) :: energy, entropy, coherence
        integer(c_int) :: status
        
        type :: bob_simulation
            type(bob_quantum_state) :: state
            type(bob_hamiltonian_operator) :: hamiltonian
            type(bob_time_integrator) :: integrator
            type(bob_rng_state) :: rng
            type(bob_quantum_metrics) :: metrics
        end type bob_simulation
        
        type(bob_simulation), pointer :: sim
        
        if (.not. c_associated(sim_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            energy = ZERO
            entropy = ZERO
            coherence = ZERO
            return
        end if
        
        call c_f_pointer(sim_ptr, sim)
        
        ! Compute metrics
        call sim%metrics%compute_all(sim%state, sim%hamiltonian%matrix)
        
        energy = sim%metrics%energy
        entropy = sim%metrics%von_neumann_entropy
        coherence = sim%metrics%coherence
        
        status = bob_get_last_error()
    end function bob_simulation_get_metrics
    
    !> Batch operations: Create multiple states
    function bob_batch_create_states(num_states, dim) result(batch_ptr) &
        bind(C, name="bob_batch_create_states")
        integer(c_int64_t), value :: num_states, dim
        type(c_ptr) :: batch_ptr
        
        type :: bob_state_batch
            integer(i8) :: num_states
            type(bob_quantum_state), allocatable :: states(:)
        end type bob_state_batch
        
        type(bob_state_batch), pointer :: batch
        integer(i8) :: i
        integer :: stat
        
        allocate(batch, stat=stat)
        if (stat /= 0) then
            batch_ptr = c_null_ptr
            return
        end if
        
        batch%num_states = num_states
        allocate(batch%states(num_states), stat=stat)
        if (stat /= 0) then
            deallocate(batch)
            batch_ptr = c_null_ptr
            return
        end if
        
        do i = 1, num_states
            call batch%states(i)%allocate(dim, "batch_state")
        end do
        
        batch_ptr = c_loc(batch)
    end function bob_batch_create_states
    
    !> Destroy batch of states
    subroutine bob_batch_destroy_states(batch_ptr) bind(C, name="bob_batch_destroy_states")
        type(c_ptr), value :: batch_ptr
        
        type :: bob_state_batch
            integer(i8) :: num_states
            type(bob_quantum_state), allocatable :: states(:)
        end type bob_state_batch
        
        type(bob_state_batch), pointer :: batch
        integer(i8) :: i
        
        if (.not. c_associated(batch_ptr)) return
        
        call c_f_pointer(batch_ptr, batch)
        
        do i = 1, batch%num_states
            call batch%states(i)%deallocate()
        end do
        
        deallocate(batch%states)
        deallocate(batch)
    end subroutine bob_batch_destroy_states
    
    !> Parallel gate application
    function bob_batch_apply_gate(batch_ptr, gate_type, qubit_index) result(status) &
        bind(C, name="bob_batch_apply_gate")
        type(c_ptr), value :: batch_ptr
        integer(c_int), value :: gate_type
        integer(c_int64_t), value :: qubit_index
        integer(c_int) :: status
        
        type :: bob_state_batch
            integer(i8) :: num_states
            type(bob_quantum_state), allocatable :: states(:)
        end type bob_state_batch
        
        type(bob_state_batch), pointer :: batch
        integer(i8) :: i
        
        if (.not. c_associated(batch_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(batch_ptr, batch)
        
        ! Apply gate to all states
        !$omp parallel do if(batch%num_states > 10)
        do i = 1, batch%num_states
            call apply_single_qubit_gate(batch%states(i), gate_type, qubit_index)
        end do
        !$omp end parallel do
        
        status = BOB_SUCCESS
    end function bob_batch_apply_gate
    
    !> Snapshot operations: Save state to file
    function bob_snapshot_save(state_ptr, filename, filename_len) result(status) &
        bind(C, name="bob_snapshot_save")
        type(c_ptr), value :: state_ptr
        character(kind=c_char), dimension(*) :: filename
        integer(c_int), value :: filename_len
        integer(c_int) :: status
        
        type(bob_quantum_state), pointer :: state
        character(len=:), allocatable :: fname
        integer :: unit, i, iostat
        
        if (.not. c_associated(state_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(state_ptr, state)
        
        ! Convert C string to Fortran string
        allocate(character(len=filename_len) :: fname)
        do i = 1, filename_len
            fname(i:i) = filename(i)
        end do
        
        ! Open file
        open(newunit=unit, file=fname, form='unformatted', &
             access='stream', status='replace', iostat=iostat)
        
        if (iostat /= 0) then
            status = BOB_ERROR_IO
            return
        end if
        
        ! Write state
        write(unit, iostat=iostat) state%dim
        write(unit, iostat=iostat) state%amplitudes
        write(unit, iostat=iostat) state%is_normalized
        
        close(unit)
        
        if (iostat /= 0) then
            status = BOB_ERROR_IO
        else
            status = BOB_SUCCESS
        end if
    end function bob_snapshot_save
    
    !> Load state from file
    function bob_snapshot_load(filename, filename_len) result(state_ptr) &
        bind(C, name="bob_snapshot_load")
        character(kind=c_char), dimension(*) :: filename
        integer(c_int), value :: filename_len
        type(c_ptr) :: state_ptr
        
        type(bob_quantum_state), pointer :: state
        character(len=:), allocatable :: fname
        integer :: unit, i, iostat
        integer(i8) :: dim
        logical(lk) :: is_normalized
        
        ! Convert C string
        allocate(character(len=filename_len) :: fname)
        do i = 1, filename_len
            fname(i:i) = filename(i)
        end do
        
        ! Open file
        open(newunit=unit, file=fname, form='unformatted', &
             access='stream', status='old', iostat=iostat)
        
        if (iostat /= 0) then
            state_ptr = c_null_ptr
            return
        end if
        
        ! Read dimension
        read(unit, iostat=iostat) dim
        if (iostat /= 0) then
            close(unit)
            state_ptr = c_null_ptr
            return
        end if
        
        ! Allocate state
        allocate(state)
        call state%allocate(dim, "loaded_state")
        
        ! Read amplitudes
        read(unit, iostat=iostat) state%amplitudes
        read(unit, iostat=iostat) is_normalized
        
        close(unit)
        
        if (iostat /= 0) then
            call state%deallocate()
            deallocate(state)
            state_ptr = c_null_ptr
            return
        end if
        
        state%is_normalized = is_normalized
        state_ptr = c_loc(state)
    end function bob_snapshot_load
    
    !> Utility: Get state amplitude
    function bob_state_get_amplitude(state_ptr, index, real_part, imag_part) result(status) &
        bind(C, name="bob_state_get_amplitude")
        type(c_ptr), value :: state_ptr
        integer(c_int64_t), value :: index
        real(c_double), intent(out) :: real_part, imag_part
        integer(c_int) :: status
        
        type(bob_quantum_state), pointer :: state
        
        if (.not. c_associated(state_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            real_part = ZERO
            imag_part = ZERO
            return
        end if
        
        call c_f_pointer(state_ptr, state)
        
        if (index < 0 .or. index >= state%dim) then
            status = BOB_ERROR_INVALID_ARGUMENT
            real_part = ZERO
            imag_part = ZERO
            return
        end if
        
        real_part = real(state%amplitudes(index + 1))
        imag_part = aimag(state%amplitudes(index + 1))
        status = BOB_SUCCESS
    end function bob_state_get_amplitude
    
    !> Utility: Set state amplitude
    function bob_state_set_amplitude(state_ptr, index, real_part, imag_part) result(status) &
        bind(C, name="bob_state_set_amplitude")
        type(c_ptr), value :: state_ptr
        integer(c_int64_t), value :: index
        real(c_double), value :: real_part, imag_part
        integer(c_int) :: status
        
        type(bob_quantum_state), pointer :: state
        
        if (.not. c_associated(state_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(state_ptr, state)
        
        if (index < 0 .or. index >= state%dim) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        state%amplitudes(index + 1) = cmplx(real_part, imag_part, cwp)
        state%is_normalized = .false.
        status = BOB_SUCCESS
    end function bob_state_set_amplitude

end module bob_abi

! Made with Bob
