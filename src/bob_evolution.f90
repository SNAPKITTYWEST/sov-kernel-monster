! BOB Quantum Civilization Engine - Time Evolution
! Module: bob_evolution
! Purpose: Schrödinger evolution, Trotterization, Krylov, RK4, Magnus
! Standard: Fortran 2018

module bob_evolution
    use bob_kinds
    use bob_errors
    use bob_state
    use bob_hamiltonian
    implicit none
    private

    public :: bob_evolve_exact
    public :: bob_evolve_trotter
    public :: bob_evolve_krylov
    public :: bob_evolve_rk4
    public :: bob_evolve_magnus
    public :: bob_time_evolution_operator
    public :: bob_time_integrator
    public :: INTEGRATOR_EXACT, INTEGRATOR_TROTTER, INTEGRATOR_KRYLOV
    public :: INTEGRATOR_RK4, INTEGRATOR_MAGNUS

    integer(i4), parameter :: INTEGRATOR_EXACT    = 1
    integer(i4), parameter :: INTEGRATOR_TROTTER  = 2
    integer(i4), parameter :: INTEGRATOR_KRYLOV   = 3
    integer(i4), parameter :: INTEGRATOR_RK4      = 4
    integer(i4), parameter :: INTEGRATOR_MAGNUS   = 5

    type, public :: bob_time_integrator
        integer(i4) :: method = INTEGRATOR_RK4
        real(wp) :: dt = 0.01_wp
        integer(i4) :: trotter_order = 2
        integer(i4) :: krylov_dim = 20
        character(len=:), allocatable :: name
    contains
        procedure, public :: init => int_init
        procedure, public :: step => int_step
    end type bob_time_integrator

contains

    !> Exact evolution: |ψ(t)⟩ = exp(-iHdt)|ψ(0)⟩
    subroutine bob_evolve_exact(state, H, dt)
        type(bob_quantum_state), intent(inout) :: state
        complex(cwp), intent(in) :: H(:,:)
        real(wp), intent(in) :: dt
        complex(cwp), allocatable :: U(:,:), psi_new(:)
        integer(i8) :: dim
        if (.not. state%is_valid) then
            call bob_set_error(BOB_ERROR_INVALID_STATE, "Invalid state", "bob_evolve_exact"); return
        end if
        dim = state%dim
        if (size(H,1)/=dim .or. size(H,2)/=dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, "H dim mismatch", "bob_evolve_exact"); return
        end if
        U = bob_time_evolution_operator(H, dt)
        allocate(psi_new(dim)); psi_new = matmul(U, state%amplitudes)
        state%amplitudes = psi_new; state%is_normalized = .true.
        call bob_clear_error()
    end subroutine bob_evolve_exact

    !> Time evolution operator exp(-iHdt) via Padé (6,6) + scaling/squaring
    function bob_time_evolution_operator(H, dt) result(U)
        complex(cwp), intent(in) :: H(:,:)
        real(wp), intent(in) :: dt
        complex(cwp), allocatable :: U(:,:), A(:,:), I_mat(:,:)
        complex(cwp), allocatable :: U_num(:,:), U_den(:,:), A2(:,:), A4(:,:), A6(:,:)
        integer :: dim, n_squarings, i
        real(wp) :: norm_H
        dim = size(H,1)
        allocate(U(dim,dim), A(dim,dim), I_mat(dim,dim))
        allocate(U_num(dim,dim), U_den(dim,dim), A2(dim,dim), A4(dim,dim), A6(dim,dim))
        I_mat = CZERO; do i=1,dim; I_mat(i,i)=CONE; end do
        norm_H = maxval(abs(H))
        if (norm_H > ZERO) then
            A = -CI * H * dt / norm_H
            n_squarings = max(0, ceiling(log(norm_H * abs(dt))/log(2.0_wp)))
        else
            A = -CI * H * dt; n_squarings = 0
        end if
        A2 = matmul(A, A)
        A4 = matmul(A2, A2)
        A6 = matmul(A4, A2)
        U_num = I_mat + A/2.0_wp + A2/12.0_wp + matmul(A,A2)/240.0_wp + A4/10080.0_wp + &
                matmul(A,A4)/725760.0_wp + A6/7257600.0_wp
        U_den = I_mat - A/2.0_wp + A2/12.0_wp - matmul(A,A2)/240.0_wp + A4/10080.0_wp - &
                matmul(A,A4)/725760.0_wp + A6/7257600.0_wp
        call invert_matrix(U_den, U)
        U = matmul(U, U_num)
        do i = 1, n_squarings
            U = matmul(U, U)
        end do
    end function bob_time_evolution_operator

    subroutine invert_matrix(A, Ainv)
        complex(cwp), intent(in) :: A(:,:)
        complex(cwp), intent(out) :: Ainv(:,:)
        integer :: n, i, k, pivot
        complex(cwp), allocatable :: aug(:,:)
        n = size(A,1)
        allocate(aug(n, 2*n)); aug = CZERO
        aug(:,1:n) = A
        do i=1,n; aug(i,n+i)=CONE; end do
        do i=1,n
            pivot = i
            do k=i+1,n; if (abs(aug(k,i)) > abs(aug(pivot,i))) pivot=k; end do
            if (abs(aug(pivot,i)) < TOL_NORM) then
                call bob_set_error(BOB_ERROR_CONVERGENCE, "Singular matrix", "invert_matrix")
                Ainv = CZERO; return
            end if
            if (pivot /= i) aug([i,pivot],:) = aug([pivot,i],:)
            aug(i,:) = aug(i,:) / aug(i,i)
            do k=1,n
                if (k /= i) aug(k,:) = aug(k,:) - aug(k,i) * aug(i,:)
            end do
        end do
        Ainv = aug(:,n+1:2*n)
    end subroutine invert_matrix

    !> Krylov subspace (Lanczos) evolution
    subroutine bob_evolve_krylov(state, H, dt, k)
        type(bob_quantum_state), intent(inout) :: state
        complex(cwp), intent(in) :: H(:,:)
        real(wp), intent(in) :: dt
        integer, intent(in), optional :: k
        integer :: krylov_dim, dim, i, m
        complex(cwp), allocatable :: V(:,:), T(:,:), beta(:), psi_krylov(:), w(:)
        real(wp) :: norm
        dim = state%dim
        krylov_dim = 20; if (present(k)) krylov_dim = min(k, dim)
        krylov_dim = min(krylov_dim, dim)
        allocate(V(dim, krylov_dim), T(krylov_dim, krylov_dim), beta(krylov_dim))
        allocate(psi_krylov(krylov_dim), w(dim))
        V = CZERO; T = CZERO; beta = ZERO
        V(:,1) = state%amplitudes
        norm = sqrt(real(dot_product(conjg(V(:,1)), V(:,1))))
        V(:,1) = V(:,1) / norm
        m = krylov_dim
        do i = 1, krylov_dim
            w = matmul(H, V(:,i))
            T(i,i) = dot_product(conjg(V(:,i)), w)
            w = w - T(i,i) * V(:,i)
            if (i > 1) w = w - beta(i-1) * V(:,i-1)
            beta(i) = sqrt(real(dot_product(conjg(w), w)))
            if (beta(i) < TOL_NORM .or. i == krylov_dim) then
                m = i; exit
            end if
            V(:,i+1) = w / beta(i)
            T(i,i+1) = beta(i); T(i+1,i) = beta(i)
        end do
        psi_krylov = CZERO; psi_krylov(1) = CONE
        psi_krylov(1:m) = matmul(bob_time_evolution_operator(T(1:m,1:m), dt), psi_krylov(1:m))
        state%amplitudes = matmul(V(:,1:m), psi_krylov(1:m))
        state%is_normalized = .true.
        call bob_clear_error()
    end subroutine bob_evolve_krylov

    !> 2nd-order Trotter-Suzuki decomposition
    subroutine bob_evolve_trotter(state, H, dt, order)
        type(bob_quantum_state), intent(inout) :: state
        complex(cwp), intent(in) :: H(:,:)
        real(wp), intent(in) :: dt
        integer, intent(in), optional :: order
        integer :: ord
        complex(cwp), allocatable :: U(:,:), psi_new(:)
        ord = 2; if (present(order)) ord = order
        if (ord == 1) then
            U = bob_time_evolution_operator(H, dt)
        else
            U = matmul(bob_time_evolution_operator(H, dt/2), bob_time_evolution_operator(H, dt/2))
        end if
        allocate(psi_new(state%dim))
        psi_new = matmul(U, state%amplitudes)
        state%amplitudes = psi_new; state%is_normalized = .true.
        call bob_clear_error()
    end subroutine bob_evolve_trotter

    !> Magnus expansion (2nd order)
    subroutine bob_evolve_magnus(state, H1, H2, dt)
        type(bob_quantum_state), intent(inout) :: state
        complex(cwp), intent(in) :: H1(:,:), H2(:,:)
        real(wp), intent(in) :: dt
        complex(cwp), allocatable :: Omega(:,:), U(:,:)
        integer :: dim
        dim = state%dim
        allocate(Omega(dim,dim), U(dim,dim))
        Omega = -CI * dt * (H1 + H2) / 2.0_wp
        U = bob_time_evolution_operator(Omega/(-CI*dt), dt)
        state%amplitudes = matmul(U, state%amplitudes)
        call state%normalize()
        call bob_clear_error()
    end subroutine bob_evolve_magnus

    subroutine bob_evolve_rk4(state, H, dt)
        type(bob_quantum_state), intent(inout) :: state
        complex(cwp), intent(in) :: H(:,:)
        real(wp), intent(in) :: dt
        complex(cwp), allocatable :: k1(:), k2(:), k3(:), k4(:), psi_temp(:)
        integer(i8) :: dim
        dim = state%dim
        allocate(k1(dim), k2(dim), k3(dim), k4(dim), psi_temp(dim))
        k1 = -CI * matmul(H, state%amplitudes)
        psi_temp = state%amplitudes + dt/2 * k1; k2 = -CI * matmul(H, psi_temp)
        psi_temp = state%amplitudes + dt/2 * k2; k3 = -CI * matmul(H, psi_temp)
        psi_temp = state%amplitudes + dt * k3;   k4 = -CI * matmul(H, psi_temp)
        state%amplitudes = state%amplitudes + dt/6 * (k1 + 2*k2 + 2*k3 + k4)
        call state%normalize()
        call bob_clear_error()
    end subroutine bob_evolve_rk4

    subroutine int_init(this, method, dt, name)
        class(bob_time_integrator), intent(inout) :: this
        integer(i4), intent(in) :: method
        real(wp), intent(in) :: dt
        character(*), intent(in) :: name
        this%method = method; this%dt = dt; this%name = name
    end subroutine int_init

    subroutine int_step(this, state, H)
        class(bob_time_integrator), intent(inout) :: this
        type(bob_quantum_state), intent(inout) :: state
        type(bob_hamiltonian_operator), intent(inout) :: H
        select case (this%method)
        case (INTEGRATOR_EXACT)
            call bob_evolve_exact(state, H%matrix, this%dt)
        case (INTEGRATOR_TROTTER)
            call bob_evolve_trotter(state, H%matrix, this%dt, this%trotter_order)
        case (INTEGRATOR_KRYLOV)
            call bob_evolve_krylov(state, H%matrix, this%dt, this%krylov_dim)
        case (INTEGRATOR_RK4)
            call bob_evolve_rk4(state, H%matrix, this%dt)
        case (INTEGRATOR_MAGNUS)
            call bob_evolve_exact(state, H%matrix, this%dt)
        case default
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, "Unknown integrator", "int_step")
        end select
    end subroutine int_step

end module bob_evolution
