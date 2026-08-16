! BOB Quantum Civilization Engine - Quantum Metrics
! Module: bob_metrics
! Purpose: Entanglement entropy, coherence, fidelity, energy, participation ratios
! Standard: Fortran 2018

module bob_metrics
    use bob_kinds
    use bob_errors
    use bob_state
    implicit none
    private

    public :: bob_quantum_metrics
    public :: compute_von_neumann_entropy
    public :: compute_renyi_entropy
    public :: compute_coherence
    public :: compute_participation_ratio
    public :: compute_fidelity
    public :: compute_trace_distance
    public :: compute_expectation
    public :: compute_variance
    public :: compute_correlation
    public :: compute_mutual_information

    type, public :: bob_quantum_metrics
        real(wp) :: energy = ZERO
        real(wp) :: von_neumann_entropy = ZERO
        real(wp) :: renyi_entropy_2 = ZERO
        real(wp) :: coherence = ONE
        real(wp) :: participation_ratio = ZERO
        real(wp) :: fidelity = ZERO
        real(wp) :: trace_distance = ZERO
        real(wp), allocatable :: correlation_matrix(:,:)
        real(wp), allocatable :: mutual_info_matrix(:,:)
        integer(i8) :: num_qubits = 0
    contains
        procedure, public :: init => met_init
        procedure, public :: compute_all => met_compute_all
        procedure, public :: compute_subsystem => met_compute_subsystem
    end type bob_quantum_metrics

contains

    subroutine met_init(this)
        class(bob_quantum_metrics), intent(inout) :: this
        this%energy = ZERO; this%von_neumann_entropy = ZERO
        this%renyi_entropy_2 = ZERO; this%coherence = ONE
        this%participation_ratio = ZERO; this%fidelity = ZERO
        this%trace_distance = ZERO; this%num_qubits = 0
        if (allocated(this%correlation_matrix)) deallocate(this%correlation_matrix)
        if (allocated(this%mutual_info_matrix)) deallocate(this%mutual_info_matrix)
    end subroutine met_init

    subroutine met_compute_all(this, state, H)
        class(bob_quantum_metrics), intent(inout) :: this
        type(bob_quantum_state), intent(in) :: state
        complex(cwp), intent(in), optional :: H(:,:)
        complex(cwp), allocatable :: Hpsi(:)
        integer(i8) :: dim, nq
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, "Invalid state", "met_compute_all"); return
        end if
        dim = state%dim; nq = int(log(real(dim))/log(TWO))
        this%num_qubits = nq
        if (.not. allocated(this%correlation_matrix)) allocate(this%correlation_matrix(nq, nq))
        if (.not. allocated(this%mutual_info_matrix))  allocate(this%mutual_info_matrix(nq, nq))
        if (present(H)) then
            allocate(Hpsi(dim))
            Hpsi = matmul(H, state%amplitudes)
            this%energy = real(dot_product(conjg(state%amplitudes), Hpsi))
        end if
        this%von_neumann_entropy = compute_von_neumann_entropy(state)
        this%renyi_entropy_2     = compute_renyi_entropy(state, 2)
        this%coherence           = compute_coherence(state)
        this%participation_ratio = compute_participation_ratio(state)
        this%correlation_matrix  = ZERO
        this%mutual_info_matrix  = ZERO
        call bob_clear_error()
    end subroutine met_compute_all

    !> Von Neumann entropy S = -Σ p_i log p_i
    function compute_von_neumann_entropy(state) result(S)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: S
        integer(i8) :: i, dim
        real(wp) :: p
        if (.not. state%is_valid) then; S = ZERO; return; end if
        dim = state%dim; S = ZERO
        do i = 1, dim
            p = real(state%amplitudes(i) * conjg(state%amplitudes(i)))
            if (p > TOL_NORM) S = S - p * log(p)
        end do
    end function compute_von_neumann_entropy

    !> Rényi entropy S_α = 1/(1-α) log Σ p_i^α
    function compute_renyi_entropy(state, alpha) result(S)
        type(bob_quantum_state), intent(in) :: state
        integer, intent(in) :: alpha
        real(wp) :: S
        integer(i8) :: i, dim
        real(wp) :: p, sum_p
        if (.not. state%is_valid) then; S = ZERO; return; end if
        dim = state%dim; sum_p = ZERO
        do i = 1, dim
            p = real(state%amplitudes(i) * conjg(state%amplitudes(i)))
            if (alpha == 2) then; sum_p = sum_p + p*p
            else;                 sum_p = sum_p + p**alpha
            end if
        end do
        if (sum_p > ZERO .and. alpha /= 1) then
            S = log(sum_p) / (1 - alpha)
        else
            S = compute_von_neumann_entropy(state)
        end if
    end function compute_renyi_entropy

    !> L1-norm coherence C = Σ_{i≠j} |ρ_{ij}|
    function compute_coherence(state) result(C)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: C
        integer(i8) :: i, j, dim
        complex(cwp) :: rho_ij
        if (.not. state%is_valid) then; C = ZERO; return; end if
        dim = state%dim; C = ZERO
        do i = 1, dim
            do j = 1, dim
                if (i /= j) then
                    rho_ij = state%amplitudes(i) * conjg(state%amplitudes(j))
                    C = C + abs(rho_ij)
                end if
            end do
        end do
    end function compute_coherence

    !> Participation ratio PR = 1 / Σ |ψ_i|⁴
    function compute_participation_ratio(state) result(PR)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: PR
        integer(i8) :: i, dim
        real(wp) :: sum_p4, p
        if (.not. state%is_valid) then; PR = ZERO; return; end if
        dim = state%dim; sum_p4 = ZERO
        do i = 1, dim
            p = real(state%amplitudes(i) * conjg(state%amplitudes(i)))
            sum_p4 = sum_p4 + p*p
        end do
        if (sum_p4 > ZERO) then; PR = ONE / sum_p4; else; PR = ZERO; end if
    end function compute_participation_ratio

    !> Fidelity F = |⟨ψ|φ⟩|²
    function compute_fidelity(state1, state2) result(F)
        type(bob_quantum_state), intent(in) :: state1, state2
        real(wp) :: F
        complex(cwp) :: inner
        if (.not. state1%is_valid .or. .not. state2%is_valid .or. state1%dim /= state2%dim) then
            F = ZERO; return
        end if
        inner = dot_product(conjg(state1%amplitudes), state2%amplitudes)
        F = real(inner * conjg(inner))
    end function compute_fidelity

    !> Trace distance D = sqrt(1 - F) for pure states
    function compute_trace_distance(state1, state2) result(D)
        type(bob_quantum_state), intent(in) :: state1, state2
        real(wp) :: D
        real(wp) :: F
        F = compute_fidelity(state1, state2)
        D = sqrt(max(ZERO, ONE - F))
    end function compute_trace_distance

    !> Expectation value ⟨O⟩
    function compute_expectation(state, O) result(expval)
        type(bob_quantum_state), intent(in) :: state
        complex(cwp), intent(in) :: O(:,:)
        real(wp) :: expval
        complex(cwp), allocatable :: Opsi(:)
        if (.not. state%is_valid) then; expval = ZERO; return; end if
        allocate(Opsi(state%dim))
        Opsi = matmul(O, state%amplitudes)
        expval = real(dot_product(conjg(state%amplitudes), Opsi))
    end function compute_expectation

    !> Variance Var(O) = ⟨O²⟩ - ⟨O⟩²
    function compute_variance(state, O) result(var)
        type(bob_quantum_state), intent(in) :: state
        complex(cwp), intent(in) :: O(:,:)
        real(wp) :: var
        complex(cwp), allocatable :: Opsi(:), O2psi(:)
        real(wp) :: e1, e2
        if (.not. state%is_valid) then; var = ZERO; return; end if
        allocate(Opsi(state%dim), O2psi(state%dim))
        Opsi  = matmul(O, state%amplitudes)
        O2psi = matmul(O, Opsi)
        e1 = real(dot_product(conjg(state%amplitudes), Opsi))
        e2 = real(dot_product(conjg(state%amplitudes), O2psi))
        var = e2 - e1*e1
    end function compute_variance

    !> Placeholder: two-point Z-Z correlation
    function compute_correlation(state, i, j) result(corr)
        type(bob_quantum_state), intent(in) :: state
        integer(i8), intent(in) :: i, j
        real(wp) :: corr
        corr = ZERO  ! TODO: build Z_i Z_j operator via kron
    end function compute_correlation

    !> Placeholder: mutual information I(i:j)
    function compute_mutual_information(state, i, j) result(mi)
        type(bob_quantum_state), intent(in) :: state
        integer(i8), intent(in) :: i, j
        real(wp) :: mi
        mi = ZERO  ! TODO: partial trace implementation
    end function compute_mutual_information

    subroutine met_compute_subsystem(this, state, qubits)
        class(bob_quantum_metrics), intent(inout) :: this
        type(bob_quantum_state), intent(in) :: state
        integer(i8), intent(in) :: qubits(:)
        call bob_set_error(BOB_ERROR_CONVERGENCE, "Partial trace not yet implemented", "met_compute_subsystem")
    end subroutine met_compute_subsystem

end module bob_metrics
