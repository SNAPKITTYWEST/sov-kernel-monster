! BOB Quantum Civilization Engine - Quantum Metrics
! Module: bob_metrics
! Purpose: Energy, entropy, purity, fidelity, coherence calculations
! Standard: Fortran 2018

module bob_metrics
    use bob_kinds
    use bob_errors
    use bob_state
    use bob_lattice
    implicit none
    private
    
    !> Quantum metrics container
    type, public :: bob_quantum_metrics
        real(wp) :: norm                    ! State norm
        real(wp) :: energy                  ! Energy expectation value
        real(wp) :: purity                  ! State purity Tr(ρ²)
        real(wp) :: von_neumann_entropy     ! Von Neumann entropy -Tr(ρ log ρ)
        real(wp) :: linear_entropy          ! Linear entropy 1 - Tr(ρ²)
        real(wp) :: fidelity                ! Fidelity with reference state
        real(wp) :: coherence               ! Coherence measure
        real(wp) :: entanglement_measure    ! Entanglement measure
        real(wp) :: participation_ratio     ! Inverse participation ratio
        real(wp) :: computation_time        ! Time to compute metrics
    contains
        procedure :: init => metrics_init
        procedure :: compute_all => metrics_compute_all
        procedure :: print => metrics_print
    end type bob_quantum_metrics
    
    public :: compute_norm
    public :: compute_energy
    public :: compute_purity
    public :: compute_von_neumann_entropy
    public :: compute_linear_entropy
    public :: compute_fidelity
    public :: compute_coherence
    public :: compute_entanglement
    public :: compute_participation_ratio
    
contains

    !> Initialize metrics
    subroutine metrics_init(this)
        class(bob_quantum_metrics), intent(inout) :: this
        
        this%norm = ZERO
        this%energy = ZERO
        this%purity = ZERO
        this%von_neumann_entropy = ZERO
        this%linear_entropy = ZERO
        this%fidelity = ZERO
        this%coherence = ZERO
        this%entanglement_measure = ZERO
        this%participation_ratio = ZERO
        this%computation_time = ZERO
    end subroutine metrics_init
    
    !> Compute all metrics
    subroutine metrics_compute_all(this, state, hamiltonian, reference_state)
        class(bob_quantum_metrics), intent(inout) :: this
        type(bob_quantum_state), intent(in) :: state
        complex(cwp), intent(in), optional :: hamiltonian(:,:)
        type(bob_quantum_state), intent(in), optional :: reference_state
        
        real(wp) :: start_time, end_time
        
        call cpu_time(start_time)
        
        ! Compute basic metrics
        this%norm = compute_norm(state)
        this%purity = compute_purity(state)
        this%linear_entropy = compute_linear_entropy(state)
        this%von_neumann_entropy = compute_von_neumann_entropy(state)
        this%coherence = compute_coherence(state)
        this%participation_ratio = compute_participation_ratio(state)
        
        ! Compute energy if Hamiltonian provided
        if (present(hamiltonian)) then
            this%energy = compute_energy(state, hamiltonian)
        end if
        
        ! Compute fidelity if reference state provided
        if (present(reference_state)) then
            this%fidelity = compute_fidelity(state, reference_state)
        end if
        
        call cpu_time(end_time)
        this%computation_time = end_time - start_time
    end subroutine metrics_compute_all
    
    !> Print metrics
    subroutine metrics_print(this)
        class(bob_quantum_metrics), intent(in) :: this
        
        print '(A)', "Quantum Metrics:"
        print '(A,F12.8)', "  Norm:                  ", this%norm
        print '(A,F12.8)', "  Energy:                ", this%energy
        print '(A,F12.8)', "  Purity:                ", this%purity
        print '(A,F12.8)', "  Von Neumann Entropy:   ", this%von_neumann_entropy
        print '(A,F12.8)', "  Linear Entropy:        ", this%linear_entropy
        print '(A,F12.8)', "  Fidelity:              ", this%fidelity
        print '(A,F12.8)', "  Coherence:             ", this%coherence
        print '(A,F12.8)', "  Entanglement:          ", this%entanglement_measure
        print '(A,F12.8)', "  Participation Ratio:   ", this%participation_ratio
        print '(A,F12.8)', "  Computation Time (s):  ", this%computation_time
    end subroutine metrics_print
    
    !> Compute state norm: ||ψ|| = sqrt(⟨ψ|ψ⟩)
    function compute_norm(state) result(norm_val)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: norm_val
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute norm of invalid state", "compute_norm")
            norm_val = ZERO
            return
        end if
        
        norm_val = state%norm()
        call bob_clear_error()
    end function compute_norm
    
    !> Compute energy expectation: E = ⟨ψ|H|ψ⟩
    function compute_energy(state, hamiltonian) result(energy)
        type(bob_quantum_state), intent(in) :: state
        complex(cwp), intent(in) :: hamiltonian(:,:)
        real(wp) :: energy
        
        complex(cwp), allocatable :: h_psi(:)
        integer(i8) :: i, j
        complex(cwp) :: expectation
        integer :: stat
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute energy of invalid state", "compute_energy")
            energy = ZERO
            return
        end if
        
        if (size(hamiltonian, 1, kind=i8) /= state%dim .or. &
            size(hamiltonian, 2, kind=i8) /= state%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "Hamiltonian dimension mismatch", "compute_energy")
            energy = ZERO
            return
        end if
        
        ! Allocate temporary array
        allocate(h_psi(state%dim), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate temporary array", "compute_energy")
            energy = ZERO
            return
        end if
        
        ! Compute H|ψ⟩
        h_psi = CZERO
        do i = 1, state%dim
            do j = 1, state%dim
                h_psi(i) = h_psi(i) + hamiltonian(i,j) * state%amplitudes(j)
            end do
        end do
        
        ! Compute ⟨ψ|H|ψ⟩
        expectation = CZERO
        do i = 1, state%dim
            expectation = expectation + conjg(state%amplitudes(i)) * h_psi(i)
        end do
        
        energy = real(expectation)
        
        deallocate(h_psi)
        call bob_clear_error()
    end function compute_energy
    
    !> Compute purity: Tr(ρ²) where ρ = |ψ⟩⟨ψ|
    function compute_purity(state) result(purity)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: purity
        
        integer(i8) :: i
        real(wp) :: sum_prob_squared
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute purity of invalid state", "compute_purity")
            purity = ZERO
            return
        end if
        
        ! For pure states: Tr(ρ²) = Σᵢ|ψᵢ|⁴
        sum_prob_squared = ZERO
        do i = 1, state%dim
            sum_prob_squared = sum_prob_squared + &
                real(state%amplitudes(i) * conjg(state%amplitudes(i))) ** 2
        end do
        
        purity = sum_prob_squared
        call bob_clear_error()
    end function compute_purity
    
    !> Compute von Neumann entropy: S = -Tr(ρ log ρ)
    function compute_von_neumann_entropy(state) result(entropy)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: entropy
        
        integer(i8) :: i
        real(wp) :: prob, log_prob
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute entropy of invalid state", "compute_von_neumann_entropy")
            entropy = ZERO
            return
        end if
        
        ! For pure states: S = -Σᵢ pᵢ log(pᵢ) where pᵢ = |ψᵢ|²
        entropy = ZERO
        do i = 1, state%dim
            prob = real(state%amplitudes(i) * conjg(state%amplitudes(i)))
            
            if (prob > TOL_NORM) then
                log_prob = log(prob)
                entropy = entropy - prob * log_prob
            end if
        end do
        
        call bob_clear_error()
    end function compute_von_neumann_entropy
    
    !> Compute linear entropy: S_L = 1 - Tr(ρ²)
    function compute_linear_entropy(state) result(entropy)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: entropy
        
        real(wp) :: purity
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute linear entropy of invalid state", "compute_linear_entropy")
            entropy = ZERO
            return
        end if
        
        purity = compute_purity(state)
        entropy = ONE - purity
        
        call bob_clear_error()
    end function compute_linear_entropy
    
    !> Compute fidelity: F = |⟨ψ|φ⟩|²
    function compute_fidelity(state1, state2) result(fidelity)
        type(bob_quantum_state), intent(in) :: state1, state2
        real(wp) :: fidelity
        
        complex(cwp) :: inner_prod
        
        if (.not. state1%is_valid .or. .not. state2%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute fidelity of invalid states", "compute_fidelity")
            fidelity = ZERO
            return
        end if
        
        if (state1%dim /= state2%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "States have different dimensions", "compute_fidelity")
            fidelity = ZERO
            return
        end if
        
        inner_prod = state1%inner_product(state2)
        fidelity = real(inner_prod * conjg(inner_prod))
        
        call bob_clear_error()
    end function compute_fidelity
    
    !> Compute coherence: C = Σᵢ≠ⱼ |ρᵢⱼ|
    function compute_coherence(state) result(coherence)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: coherence
        
        integer(i8) :: i, j
        complex(cwp) :: rho_ij
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute coherence of invalid state", "compute_coherence")
            coherence = ZERO
            return
        end if
        
        ! Coherence = sum of off-diagonal density matrix elements
        coherence = ZERO
        do i = 1, state%dim
            do j = i + 1, state%dim
                rho_ij = state%amplitudes(i) * conjg(state%amplitudes(j))
                coherence = coherence + abs(rho_ij)
            end do
        end do
        
        ! Multiply by 2 for symmetry
        coherence = TWO * coherence
        
        call bob_clear_error()
    end function compute_coherence
    
    !> Compute entanglement measure (for bipartite systems)
    function compute_entanglement(state, subsystem_dim) result(entanglement)
        type(bob_quantum_state), intent(in) :: state
        integer(i8), intent(in) :: subsystem_dim
        real(wp) :: entanglement
        
        complex(cwp), allocatable :: reduced_density(:,:)
        real(wp), allocatable :: eigenvalues(:)
        integer(i8) :: i, j, k, l
        integer(i8) :: dim_a, dim_b
        integer :: stat
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute entanglement of invalid state", "compute_entanglement")
            entanglement = ZERO
            return
        end if
        
        dim_a = subsystem_dim
        dim_b = state%dim / subsystem_dim
        
        if (dim_a * dim_b /= state%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, &
                "Subsystem dimension incompatible", "compute_entanglement")
            entanglement = ZERO
            return
        end if
        
        ! Allocate reduced density matrix
        allocate(reduced_density(dim_a, dim_a), stat=stat)
        if (stat /= 0) then
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate reduced density matrix", "compute_entanglement")
            entanglement = ZERO
            return
        end if
        
        ! Compute reduced density matrix: ρ_A = Tr_B(|ψ⟩⟨ψ|)
        reduced_density = CZERO
        do i = 1, dim_a
            do j = 1, dim_a
                do k = 1, dim_b
                    reduced_density(i,j) = reduced_density(i,j) + &
                        state%amplitudes((i-1)*dim_b + k) * &
                        conjg(state%amplitudes((j-1)*dim_b + k))
                end do
            end do
        end do
        
        ! Compute von Neumann entropy of reduced density matrix
        ! This requires eigenvalue decomposition (simplified here)
        allocate(eigenvalues(dim_a), stat=stat)
        if (stat /= 0) then
            deallocate(reduced_density)
            call bob_set_error(BOB_ERROR_ALLOCATION, &
                "Failed to allocate eigenvalues", "compute_entanglement")
            entanglement = ZERO
            return
        end if
        
        ! Simplified: use trace of ρ² as entanglement measure
        entanglement = ZERO
        do i = 1, dim_a
            do j = 1, dim_a
                entanglement = entanglement + &
                    real(reduced_density(i,j) * conjg(reduced_density(j,i)))
            end do
        end do
        
        ! Convert to entropy-like measure
        entanglement = ONE - entanglement
        
        deallocate(reduced_density, eigenvalues)
        call bob_clear_error()
    end function compute_entanglement
    
    !> Compute inverse participation ratio: IPR = Σᵢ|ψᵢ|⁴
    function compute_participation_ratio(state) result(ipr)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: ipr
        
        integer(i8) :: i
        real(wp) :: prob
        
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute IPR of invalid state", "compute_participation_ratio")
            ipr = ZERO
            return
        end if
        
        ipr = ZERO
        do i = 1, state%dim
            prob = real(state%amplitudes(i) * conjg(state%amplitudes(i)))
            ipr = ipr + prob ** 2
        end do
        
        call bob_clear_error()
    end function compute_participation_ratio
    
    !> Compute lattice metrics
    subroutine compute_lattice_metrics(lattice, metrics)
        type(bob_vortex_lattice), intent(in) :: lattice
        type(bob_quantum_metrics), intent(out) :: metrics
        
        call metrics%init()
        
        if (.not. lattice%is_initialized) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, &
                "Cannot compute metrics of uninitialized lattice", &
                "compute_lattice_metrics")
            return
        end if
        
        metrics%energy = lattice%total_energy()
        metrics%entanglement_measure = lattice%entanglement_entropy()
        metrics%norm = ONE  ! Lattice is always normalized
        
        call bob_clear_error()
    end subroutine compute_lattice_metrics
    
    !> C ABI: Compute metrics
    function bob_metrics_compute(state_ptr, metrics_ptr) result(status) &
        bind(C, name="bob_metrics_compute")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: state_ptr, metrics_ptr
        integer(c_int) :: status
        
        type(bob_quantum_state), pointer :: state
        type(bob_quantum_metrics), pointer :: metrics
        
        if (.not. c_associated(state_ptr) .or. .not. c_associated(metrics_ptr)) then
            status = BOB_ERROR_INVALID_ARGUMENT
            return
        end if
        
        call c_f_pointer(state_ptr, state)
        call c_f_pointer(metrics_ptr, metrics)
        
        call metrics%compute_all(state)
        status = bob_get_last_error()
    end function bob_metrics_compute
    
    !> C ABI: Get energy
    function bob_metrics_get_energy(metrics_ptr) result(energy) &
        bind(C, name="bob_metrics_get_energy")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: metrics_ptr
        real(c_double) :: energy
        
        type(bob_quantum_metrics), pointer :: metrics
        
        if (.not. c_associated(metrics_ptr)) then
            energy = ZERO
            return
        end if
        
        call c_f_pointer(metrics_ptr, metrics)
        energy = metrics%energy
    end function bob_metrics_get_energy
    
    !> C ABI: Get entropy
    function bob_metrics_get_entropy(metrics_ptr) result(entropy) &
        bind(C, name="bob_metrics_get_entropy")
        use, intrinsic :: iso_c_binding
        type(c_ptr), value :: metrics_ptr
        real(c_double) :: entropy
        
        type(bob_quantum_metrics), pointer :: metrics
        
        if (.not. c_associated(metrics_ptr)) then
            entropy = ZERO
            return
        end if
        
        call c_f_pointer(metrics_ptr, metrics)
        entropy = metrics%von_neumann_entropy
    end function bob_metrics_get_entropy

end module bob_metrics

! Made with Bob
