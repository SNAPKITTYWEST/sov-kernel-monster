! BOB Quantum Civilization Engine - Hamiltonian Construction
! Module: bob_hamiltonian
! Purpose: Pauli operators, tensor products, Hamiltonian assembly for quantum simulation
! Standard: Fortran 2018

module bob_hamiltonian
    use bob_kinds
    use bob_errors
    use bob_state
    implicit none
    private

    ! Public interface
    public :: bob_hamiltonian_operator
    public :: bob_pauli_matrix
    public :: bob_tensor_product
    public :: bob_kron
    public :: bob_ising_hamiltonian
    public :: bob_heisenberg_hamiltonian
    public :: bob_tfim_hamiltonian
    public :: bob_xy_hamiltonian
    public :: bob_expectation
    public :: bob_variance
    public :: bob_ground_state

    ! Pauli matrices (2x2)
    complex(cwp), parameter :: PAULI_I(2,2) = reshape([CONE, CZERO, CZERO, CONE], [2,2])
    complex(cwp), parameter :: PAULI_X(2,2) = reshape([CZERO, CONE, CONE, CZERO], [2,2])
    complex(cwp), parameter :: PAULI_Y(2,2) = reshape([CZERO, -CI, CI, CZERO], [2,2])
    complex(cwp), parameter :: PAULI_Z(2,2) = reshape([CONE, CZERO, CZERO, -CONE], [2,2])

    type, public :: bob_hamiltonian_operator
        integer(i8) :: dim = 0
        complex(cwp), allocatable :: matrix(:,:)
        integer(i8) :: num_qubits = 0
        character(len=:), allocatable :: name
        logical(lk) :: is_hermitian = .true.
        real(wp) :: energy_offset = ZERO
    contains
        procedure, public :: init => ham_init
        procedure, public :: destroy => ham_destroy
        procedure, public :: add_term => ham_add_term
        procedure, public :: build_matrix => ham_build_matrix
        procedure, public :: expectation => ham_expectation
        procedure, public :: ground_state => ham_ground_state
    end type bob_hamiltonian_operator

contains

    !> Get Pauli matrix by name
    pure function bob_pauli_matrix(name) result(mat)
        character(*), intent(in) :: name
        complex(cwp) :: mat(2,2)
        select case (name)
        case ('I','i','identity'); mat = PAULI_I
        case ('X','x','sigma_x');  mat = PAULI_X
        case ('Y','y','sigma_y');  mat = PAULI_Y
        case ('Z','z','sigma_z');  mat = PAULI_Z
        case default
            call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, "Unknown Pauli: "//name, "bob_pauli_matrix")
            mat = CZERO
        end select
    end function bob_pauli_matrix

    !> Kronecker product A ⊗ B
    pure function bob_kron(A, B) result(C)
        complex(cwp), intent(in) :: A(:,:), B(:,:)
        complex(cwp), allocatable :: C(:,:)
        integer :: m1, n1, m2, n2, i, j, k, l
        m1 = size(A,1); n1 = size(A,2); m2 = size(B,1); n2 = size(B,2)
        allocate(C(m1*m2, n1*n2)); C = CZERO
        do i = 1, m1; do j = 1, n1
            if (abs(A(i,j)) > TOL_NORM) then
                do k = 1, m2; do l = 1, n2
                    C((i-1)*m2+k, (j-1)*n2+l) = A(i,j) * B(k,l)
                end do; end do
            end if
        end do; end do
    end function bob_kron

    !> Tensor product: embed operator on specified qubits into full Hilbert space
    function bob_tensor_product(operators, qubits, num_qubits) result(op)
        complex(cwp), intent(in) :: operators(:,:,:)  ! (2,2,n_ops)
        integer(i8), intent(in) :: qubits(:)
        integer(i8), intent(in) :: num_qubits
        complex(cwp), allocatable :: op(:,:)
        integer(i8) :: n_ops, i, j, target
        complex(cwp), allocatable :: current(:,:), next(:,:)
        n_ops = size(qubits)
        if (n_ops == 0) then; allocate(op(1,1)); op = CONE; return; end if
        allocate(current(1,1)); current = CONE
        do i = 1, num_qubits
            target = -1
            do j = 1, n_ops; if (qubits(j) == i) then; target = j; exit; end if; end do
            if (target > 0) then
                next = bob_kron(current, operators(:,:,target))
            else
                next = bob_kron(current, PAULI_I)
            end if
            if (allocated(current)) deallocate(current)
            allocate(current(size(next,1), size(next,2))); current = next
            if (allocated(next)) deallocate(next)
        end do
        op = current
    end function bob_tensor_product

    subroutine ham_init(this, num_qubits, name)
        class(bob_hamiltonian_operator), intent(inout) :: this
        integer(i8), intent(in) :: num_qubits
        character(*), intent(in) :: name
        integer :: stat
        this%num_qubits = num_qubits
        this%dim = ishft(1_i8, int(num_qubits))
        this%name = name
        if (allocated(this%matrix)) deallocate(this%matrix)
        allocate(this%matrix(this%dim, this%dim), stat=stat)
        if (stat /= 0) call bob_set_error(BOB_ERROR_ALLOCATION, "H matrix alloc", name)
        this%matrix = CZERO
    end subroutine ham_init

    subroutine ham_destroy(this)
        class(bob_hamiltonian_operator), intent(inout) :: this
        if (allocated(this%matrix)) deallocate(this%matrix)
        this%dim = 0; this%num_qubits = 0
    end subroutine ham_destroy

    subroutine ham_add_term(this, op_matrix, coeff, qubits, term_name)
        class(bob_hamiltonian_operator), intent(inout) :: this
        complex(cwp), intent(in) :: op_matrix(:,:)
        real(wp), intent(in) :: coeff
        integer(i8), intent(in) :: qubits(:)
        character(*), intent(in), optional :: term_name
        complex(cwp), allocatable :: full_op(:,:)
        full_op = bob_tensor_product(reshape(op_matrix, [2,2,1]), qubits, this%num_qubits)
        this%matrix = this%matrix + coeff * full_op
        if (allocated(full_op)) deallocate(full_op)
    end subroutine ham_add_term

    function ham_build_matrix(this) result(H)
        class(bob_hamiltonian_operator), intent(in) :: this
        complex(cwp), allocatable :: H(:,:)
        allocate(H(this%dim, this%dim)); H = this%matrix
    end function ham_build_matrix

    function ham_expectation(this, state) result(expval)
        class(bob_hamiltonian_operator), intent(in) :: this
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: expval
        complex(cwp), allocatable :: Hpsi(:)
        if (.not. state%is_valid .or. state%dim /= this%dim) then
            call bob_set_error(BOB_ERROR_DIMENSION_MISMATCH, "State/H dim mismatch", "ham_expectation")
            expval = ZERO; return
        end if
        allocate(Hpsi(state%dim))
        Hpsi = matmul(this%matrix, state%amplitudes)
        expval = real(dot_product(conjg(state%amplitudes), Hpsi))
    end function ham_expectation

    function bob_variance(H, state) result(var)
        complex(cwp), intent(in) :: H(:,:)
        type(bob_quantum_state), intent(in) :: state
        real(wp) :: var
        complex(cwp), allocatable :: Hpsi(:), H2psi(:)
        real(wp) :: e1, e2
        allocate(Hpsi(state%dim), H2psi(state%dim))
        Hpsi = matmul(H, state%amplitudes)
        H2psi = matmul(H, Hpsi)
        e1 = real(dot_product(conjg(state%amplitudes), Hpsi))
        e2 = real(dot_product(conjg(state%amplitudes), H2psi))
        var = e2 - e1*e1
    end function bob_variance

    !> Ground state via power iteration
    function bob_ground_state(H, max_iter, tol) result(ground)
        complex(cwp), intent(in) :: H(:,:)
        integer, intent(in), optional :: max_iter
        real(wp), intent(in), optional :: tol
        type(bob_quantum_state) :: ground
        integer(i8) :: dim, iter, max_i
        real(wp) :: tol_v
        complex(cwp), allocatable :: psi(:), psi_new(:)
        real(wp) :: norm, overlap
        dim = size(H,1)
        call ground%init(int(log(real(dim))/log(TWO)))
        max_i = 1000; if (present(max_iter)) max_i = max_iter
        tol_v = 1.0e-10_wp; if (present(tol)) tol_v = tol
        psi = ground%amplitudes
        do iter = 1, max_i
            psi_new = matmul(H, psi)
            norm = sqrt(real(dot_product(conjg(psi_new), psi_new)))
            if (norm > ZERO) psi_new = psi_new / norm
            overlap = abs(dot_product(conjg(psi), psi_new))
            psi = psi_new
            if (abs(overlap - ONE) < tol_v) exit
        end do
        ground%amplitudes = psi; ground%is_normalized = .true.
    end function bob_ground_state

    !> Transverse Field Ising Model: H = -J Σ Z_i Z_{i+1} - h Σ X_i
    function bob_tfim_hamiltonian(num_qubits, J, h) result(H)
        integer(i8), intent(in) :: num_qubits
        real(wp), intent(in) :: J, h
        type(bob_hamiltonian_operator) :: H
        integer(i8) :: i
        complex(cwp), allocatable :: ZZ(:,:,:)
        call H%init(num_qubits, "TFIM")
        allocate(ZZ(2,2,2)); ZZ(:,:,1) = PAULI_Z; ZZ(:,:,2) = PAULI_Z
        do i = 1, num_qubits - 1
            call H%add_term(ZZ, -J, [i, i+1])
        end do
        do i = 1, num_qubits
            call H%add_term(PAULI_X, -h, [i])
        end do
    end function bob_tfim_hamiltonian

    !> Heisenberg Model: H = Σ (Jx X_i X_{i+1} + Jy Y_i Y_{i+1} + Jz Z_i Z_{i+1})
    function bob_heisenberg_hamiltonian(num_qubits, Jx, Jy, Jz) result(H)
        integer(i8), intent(in) :: num_qubits
        real(wp), intent(in) :: Jx, Jy, Jz
        type(bob_hamiltonian_operator) :: H
        integer(i8) :: i
        complex(cwp), allocatable :: XX(:,:,:), YY(:,:,:), ZZ(:,:,:)
        call H%init(num_qubits, "Heisenberg")
        allocate(XX(2,2,2)); XX(:,:,1)=PAULI_X; XX(:,:,2)=PAULI_X
        allocate(YY(2,2,2)); YY(:,:,1)=PAULI_Y; YY(:,:,2)=PAULI_Y
        allocate(ZZ(2,2,2)); ZZ(:,:,1)=PAULI_Z; ZZ(:,:,2)=PAULI_Z
        do i = 1, num_qubits - 1
            call H%add_term(XX, Jx, [i, i+1])
            call H%add_term(YY, Jy, [i, i+1])
            call H%add_term(ZZ, Jz, [i, i+1])
        end do
    end function bob_heisenberg_hamiltonian

    !> XY Model: H = J Σ (X_i X_{i+1} + Y_i Y_{i+1}) + h Σ Z_i
    function bob_xy_hamiltonian(num_qubits, J, h) result(H)
        integer(i8), intent(in) :: num_qubits
        real(wp), intent(in) :: J, h
        type(bob_hamiltonian_operator) :: H
        integer(i8) :: i
        complex(cwp), allocatable :: XX(:,:,:), YY(:,:,:)
        call H%init(num_qubits, "XY")
        allocate(XX(2,2,2)); XX(:,:,1)=PAULI_X; XX(:,:,2)=PAULI_X
        allocate(YY(2,2,2)); YY(:,:,1)=PAULI_Y; YY(:,:,2)=PAULI_Y
        do i = 1, num_qubits - 1
            call H%add_term(XX, J, [i, i+1])
            call H%add_term(YY, J, [i, i+1])
        end do
        do i = 1, num_qubits
            call H%add_term(PAULI_Z, h, [i])
        end do
    end function bob_xy_hamiltonian

    function ham_ground_state(this, max_iter, tol) result(ground)
        class(bob_hamiltonian_operator), intent(in) :: this
        integer, intent(in), optional :: max_iter
        real(wp), intent(in), optional :: tol
        type(bob_quantum_state) :: ground
        ground = bob_ground_state(this%matrix, max_iter, tol)
    end function ham_ground_state

end module bob_hamiltonian
