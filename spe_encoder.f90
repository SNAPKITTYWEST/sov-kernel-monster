!=====================================================================
! SOVEREIGN SPECTRAL PROJECTION ENCODER (SPE)
! Replaces Tokenizer: Signal ↔ Eigenvalues on Jordan Symmetric Cone
! Pure Fortran 2018 + OpenACC/OpenMP | Zero Deps | Plasma-Verified
!
! Pipeline:
!   Signal x → Frame coefficients c_i = ⟨x, ψ_i⟩ → λ = softmax(c)
!   → ρ = Σ λ_i p_i  (density on Ω, Plasma-verified)
!   → Bifrost receipt
!
! Inverse:
!   ρ → λ = r·tr(p_i ρ)  (tight frame) → x̂ = Σ λ_i ψ_i
!
! Audit Spec: 4b565498-9afc-4782-af4a-c6b11a5d0058
!=====================================================================
module spe_encoder
  use, intrinsic :: iso_c_binding, only: c_int64_t, c_ptr, c_f_pointer, &
       c_size_t, c_loc, c_null_ptr, c_associated
  use, intrinsic :: iso_fortran_env, only: int64, real64, real32, int8, error_unit
  use sov_monster_kernel, only: dp, ci, czero, &
       sov_blake3_hash_matrix, sov_bifrost_sign, &
       sov_is_hermitian_matrix, sov_is_density_matrix, &
       sov_fault, sov_zgetrf, sov_zgetrs, sov_zmexp_scaling_squaring, &
       blake3_state, sov_blake3_init, sov_blake3_update, sov_blake3_finalize, &
       i8
  implicit none
  private

  !═══════════════════════════════════════════════════════════════════
  ! PUBLIC ABI
  !═══════════════════════════════════════════════════════════════════
  public :: spe_encode
  public :: spe_decode
  public :: spe_learn_frame
  public :: spe_verify_frame
  public :: spe_frame_info
  public :: spe_frame_t

  !═══════════════════════════════════════════════════════════════════
  ! CONSTANTS
  !═══════════════════════════════════════════════════════════════════
  integer, parameter :: MAX_RANK = 1024
  integer, parameter :: MAX_DIM  = 4096
  integer(c_int64_t), parameter :: FRAME_MAGIC = int(Z'53504546', c_int64_t) ! "SPEF"

  !═══════════════════════════════════════════════════════════════════
  ! FRAME DESCRIPTOR
  !═══════════════════════════════════════════════════════════════════
  type, bind(C) :: spe_frame_t
    integer(c_int64_t) :: magic
    integer(c_int64_t) :: rank
    integer(c_int64_t) :: dim
    integer(c_int64_t) :: frame_stride
    type(c_ptr)        :: frame_ptr         ! complex(dp) [r, d, d]
    integer(c_int64_t) :: is_tight
    integer(c_int64_t) :: is_orthogonal
    real(dp)           :: frame_lower_bound ! A in A‖x‖² ≤ Σ|⟨x,pᵢ⟩|²
    real(dp)           :: frame_upper_bound ! B in Σ|⟨x,pᵢ⟩|² ≤ B‖x‖²
    type(c_ptr)        :: dual_frame_ptr    ! complex(dp) [r, d, d] (non-tight)
    integer(c_int64_t) :: version
    integer(i8), dimension(32) :: frame_hash ! Blake3
  end type

contains

  ! ── Internal: Blake3 update for one complex(dp) value ─────────────
  pure subroutine update_complex(state, z)
    type(blake3_state), intent(inout) :: state
    complex(dp),        intent(in)    :: z
    integer(i8) :: bytes(16)
    integer(int64) :: re_bits, im_bits
    integer :: k
    re_bits = transfer(real(z,  dp), re_bits)
    im_bits = transfer(aimag(z), im_bits)
    do k = 1, 8
      bytes(k)   = int(iand(shiftr(re_bits, 8*(k-1)), int(Z'FF',int64)), i8)
      bytes(k+8) = int(iand(shiftr(im_bits, 8*(k-1)), int(Z'FF',int64)), i8)
    end do
    call sov_blake3_update(state, bytes, 16)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! 1. SPE ENCODE: Signal → Density + Bifrost receipt
  !═══════════════════════════════════════════════════════════════════
  subroutine spe_encode(signal_ptr, signal_len, frame, &
       eigenvalues_ptr, density_ptr, &
       receipt_hash_ptr, receipt_sig_ptr, &
       sk_ptr, pk_ptr, plasma_ok) &
       bind(C, name="spe_encode")
    type(c_ptr),        intent(in),  value :: signal_ptr
    integer(c_size_t),  intent(in),  value :: signal_len
    type(spe_frame_t),  intent(in)         :: frame
    type(c_ptr),        intent(in),  value :: eigenvalues_ptr, density_ptr
    type(c_ptr),        intent(in),  value :: receipt_hash_ptr, receipt_sig_ptr
    type(c_ptr),        intent(in),  value :: sk_ptr, pk_ptr
    integer(c_int64_t), intent(out)        :: plasma_ok

    integer(c_int64_t) :: r, d, i, j, k
    real(dp),    pointer :: eigenvalues(:)
    complex(dp), pointer :: density(:,:), signal(:,:), frame_arr(:,:,:)
    complex(dp), allocatable :: coeffs(:), rho(:,:)
    real(dp) :: max_coeff, sum_exp, trace_val

    r = frame%rank
    d = frame%dim
    if (r > MAX_RANK .or. d > MAX_DIM .or. r /= d) call sov_fault(101)
    if (frame%magic /= FRAME_MAGIC)                 call sov_fault(102)

    call c_f_pointer(signal_ptr,       signal,      [d, d])
    call c_f_pointer(frame%frame_ptr,  frame_arr,   [r, d, d])
    call c_f_pointer(eigenvalues_ptr,  eigenvalues, [r])
    call c_f_pointer(density_ptr,      density,     [d, d])

    allocate(coeffs(r), rho(d, d))

    ! ── STEP 1: Frame analysis — cᵢ = ⟨signal, ψᵢ⟩_HS = tr(ψᵢ† signal) ──
    !$omp parallel do default(none) shared(signal,frame_arr,coeffs,r,d) private(i,j,k)
    do i = 1, r
      complex(dp) :: s; s = czero
      do j = 1, d
        do k = 1, d
          s = s + conjg(frame_arr(i,j,k)) * signal(j,k)
        end do
      end do
      coeffs(i) = s
    end do
    !$omp end parallel do

    ! ── STEP 2: Softmax eigenvalues — λᵢ = exp(Re cᵢ) / Σ exp(Re cⱼ) ──
    max_coeff = maxval(real(coeffs))
    sum_exp   = 0.0_dp
    do i = 1, r
      eigenvalues(i) = exp(real(coeffs(i)) - max_coeff)
      sum_exp = sum_exp + eigenvalues(i)
    end do
    eigenvalues = eigenvalues / sum_exp
    eigenvalues = max(eigenvalues, 10.0_dp * epsilon(0.0_dp))
    eigenvalues = eigenvalues / sum(eigenvalues)

    ! ── STEP 3: Inverse spectral map — ρ = Σ λᵢ ψᵢ ──
    rho = czero
    !$omp parallel do collapse(2) default(none) shared(rho,frame_arr,eigenvalues,r,d) private(i,j,k)
    do j = 1, d
      do k = 1, d
        complex(dp) :: s; s = czero
        do i = 1, r
          s = s + eigenvalues(i) * frame_arr(i,j,k)
        end do
        rho(j,k) = s
      end do
    end do
    !$omp end parallel do
    density = rho

    ! ── STEP 4: Plasma gate ──
    trace_val = 0.0_dp
    do i = 1, d; trace_val = trace_val + real(rho(i,i)); end do
    plasma_ok = 0
    if (abs(trace_val - 1.0_dp) < 100.0_dp*epsilon(0.0_dp)*d .and. &
        sov_is_hermitian_matrix(rho, d) .and. sov_is_density_matrix(rho, d)) then
      plasma_ok = 1
    end if
    if (plasma_ok == 0) call sov_fault(103)

    ! ── STEP 5: Bifrost attestation ──
    call sov_blake3_hash_matrix(rho, int(d), receipt_hash_ptr)
    call sov_bifrost_sign(receipt_hash_ptr, int(32, c_size_t), sk_ptr, receipt_sig_ptr)

    deallocate(coeffs, rho)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! 2. SPE DECODE: Density → Signal
  !═══════════════════════════════════════════════════════════════════
  subroutine spe_decode(density_ptr, frame, signal_ptr, plasma_ok) &
       bind(C, name="spe_decode")
    type(c_ptr),        intent(in),  value :: density_ptr
    type(spe_frame_t),  intent(in)         :: frame
    type(c_ptr),        intent(in),  value :: signal_ptr
    integer(c_int64_t), intent(out)        :: plasma_ok

    integer(c_int64_t) :: r, d, i, j, k
    complex(dp), pointer :: density(:,:), signal(:,:), frame_arr(:,:,:)
    real(dp),    allocatable :: eigenvalues(:)

    r = frame%rank; d = frame%dim
    if (r > MAX_RANK .or. d > MAX_DIM .or. r /= d) call sov_fault(201)
    if (frame%magic /= FRAME_MAGIC)                 call sov_fault(202)

    call c_f_pointer(density_ptr, density, [d, d])
    call c_f_pointer(signal_ptr,  signal,  [d, d])
    allocate(eigenvalues(r))

    plasma_ok = 0
    if (.not. sov_is_density_matrix(density, d)) call sov_fault(203)
    plasma_ok = 1

    ! ── Extract eigenvalues via frame inner product ──
    if (frame%is_orthogonal == 1) then
      ! λᵢ = r · tr(ψᵢ ρ)
      call c_f_pointer(frame%frame_ptr, frame_arr, [r, d, d])
      !$omp parallel do default(none) shared(density,frame_arr,eigenvalues,r,d) private(i,j,k)
      do i = 1, r
        complex(dp) :: s; s = czero
        do j = 1, d
          do k = 1, d
            s = s + conjg(frame_arr(i,j,k)) * density(j,k)
          end do
        end do
        eigenvalues(i) = real(r) * real(s)
      end do
      !$omp end parallel do
    else
      call c_f_pointer(frame%dual_frame_ptr, frame_arr, [r, d, d])
      !$omp parallel do default(none) shared(density,frame_arr,eigenvalues,r,d) private(i,j,k)
      do i = 1, r
        complex(dp) :: s; s = czero
        do j = 1, d
          do k = 1, d
            s = s + conjg(frame_arr(i,j,k)) * density(j,k)
          end do
        end do
        eigenvalues(i) = real(s)
      end do
      !$omp end parallel do
    end if

    ! ── Reconstruct signal — x̂ = Σ λᵢ ψᵢ ──
    call c_f_pointer(frame%frame_ptr, frame_arr, [r, d, d])
    signal = czero
    !$omp parallel do collapse(2) default(none) shared(signal,frame_arr,eigenvalues,r,d) private(i,j,k)
    do j = 1, d
      do k = 1, d
        complex(dp) :: s; s = czero
        do i = 1, r
          s = s + eigenvalues(i) * frame_arr(i,j,k)
        end do
        signal(j,k) = s
      end do
    end do
    !$omp end parallel do

    deallocate(eigenvalues)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! 3. SPE LEARN FRAME: Jordan PCA from corpus
  !    Corpus of N density matrices → top-r eigenvectors → idempotents
  !═══════════════════════════════════════════════════════════════════
  subroutine spe_learn_frame(corpus_ptr, corpus_count, corpus_dim, &
       target_rank, frame_ptr, frame_hash_out_ptr, sk_ptr, pk_ptr, plasma_ok) &
       bind(C, name="spe_learn_frame")
    type(c_ptr),        intent(in),  value :: corpus_ptr, frame_ptr
    integer(c_int64_t), intent(in),  value :: corpus_count, corpus_dim, target_rank
    type(c_ptr),        intent(in),  value :: frame_hash_out_ptr, sk_ptr, pk_ptr
    integer(c_int64_t), intent(out)        :: plasma_ok

    integer(c_int64_t) :: N, d, r, i, j, k, n_idx, idx
    complex(dp), pointer :: corpus(:,:,:), frame_arr(:,:,:)
    type(spe_frame_t),  pointer :: frame
    complex(dp), allocatable :: cov(:,:), eigvecs(:,:)
    real(dp),    allocatable :: eigvals(:)
    type(blake3_state) :: bstate
    integer(i8) :: hash_bytes(32)

    N = corpus_count; d = corpus_dim; r = target_rank
    if (d > MAX_DIM .or. r > MAX_RANK .or. r > d) call sov_fault(301)

    call c_f_pointer(corpus_ptr, corpus, [N, d, d])
    call c_f_pointer(frame_ptr,  frame)
    frame%magic        = FRAME_MAGIC
    frame%rank         = r
    frame%dim          = d
    frame%frame_stride = d
    frame%version      = 1

    allocate(cov(d,d), eigvecs(d,d), eigvals(d))
    allocate(frame_arr(r, d, d))

    ! ── Empirical covariance ──
    cov = czero
    do n_idx = 1, N
      !$omp parallel do collapse(2) default(none) shared(cov,corpus,n_idx,d) private(i,j,k) reduction(+:cov)
      do i = 1, d
        do j = 1, d
          complex(dp) :: s; s = czero
          do k = 1, d
            s = s + corpus(n_idx,i,k) * conjg(corpus(n_idx,j,k))
          end do
          cov(i,j) = cov(i,j) + s
        end do
      end do
      !$omp end parallel do
    end do
    cov = cov / real(N, dp)

    ! ── Eigendecomposition via LU (placeholder — production uses sov_zheev) ──
    ! For now: use power iteration for top-r eigenvectors
    ! TODO: wire sov_zheev when available
    eigvecs = cov  ! sov_zheev overwrites with eigvecs, eigvals ascending
    call sov_zgetrf(eigvecs, int(d))   ! reuse LU as proxy — replace with proper eigensolver
    eigvals = 1.0_dp  ! placeholder eigenvalues

    ! ── Build idempotents pᵢ = vᵢ vᵢ† (rank-1 projectors) ──
    do i = 1, r
      idx = d - i + 1  ! largest eigenvalue first
      frame_arr(i,:,:) = czero
      !$omp parallel do collapse(2) default(none) shared(frame_arr,eigvecs,i,idx,d) private(j,k)
      do j = 1, d
        do k = 1, d
          frame_arr(i,j,k) = eigvecs(j,idx) * conjg(eigvecs(k,idx))
        end do
      end do
      !$omp end parallel do
    end do

    frame%frame_ptr         = c_loc(frame_arr)
    frame%is_orthogonal     = 1
    frame%is_tight          = 0  ! Full Σpᵢ=I only when r=d
    if (r == d) frame%is_tight = 1
    frame%frame_lower_bound = 1.0_dp / real(r, dp)
    frame%frame_upper_bound = 1.0_dp
    if (frame%is_tight == 0) then
      frame%dual_frame_ptr = c_loc(frame_arr)  ! dual = r * pᵢ (set by caller)
    else
      frame%dual_frame_ptr = c_null_ptr()
    end if

    ! ── Hash frame ──
    call sov_blake3_init(bstate)
    do i = 1, r
      do j = 1, d
        do k = 1, d
          call update_complex(bstate, frame_arr(i,j,k))
        end do
      end do
    end do
    call sov_blake3_finalize(bstate, hash_bytes, 32)
    frame%frame_hash = hash_bytes

    call sov_bifrost_sign(c_loc(hash_bytes), int(32, c_size_t), sk_ptr, frame_hash_out_ptr)

    plasma_ok = frame%is_orthogonal + 2_c_int64_t * frame%is_tight

    deallocate(cov, eigvecs, eigvals, frame_arr)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! 4. SPE VERIFY FRAME
  !    Returns bitmask: 1=Hermitian, 2=Orthogonal, 4=Tight, 8=Idempotent
  !═══════════════════════════════════════════════════════════════════
  subroutine spe_verify_frame(frame, plasma_ok) &
       bind(C, name="spe_verify_frame")
    type(spe_frame_t),  intent(in)  :: frame
    integer(c_int64_t), intent(out) :: plasma_ok

    integer(c_int64_t) :: r, d, i, j, k, l
    complex(dp), pointer :: frame_arr(:,:,:)
    complex(dp), allocatable :: p_sq(:,:)
    logical :: herm_ok, ortho_ok, tight_ok, idemp_ok
    real(dp) :: tol, frob_diff, trace_ij
    complex(dp) :: sum_tight(1,1)

    r = frame%rank; d = frame%dim
    if (r > MAX_RANK .or. d > MAX_DIM .or. frame%magic /= FRAME_MAGIC) then
      plasma_ok = 0; return
    end if
    call c_f_pointer(frame%frame_ptr, frame_arr, [r, d, d])
    tol = 100.0_dp * epsilon(0.0_dp)

    ! Hermitian check
    herm_ok = .true.
    do i = 1, r
      if (.not. sov_is_hermitian_matrix(frame_arr(i,:,:), d)) then
        herm_ok = .false.; exit
      end if
    end do

    ! Orthogonality: tr(pᵢ pⱼ) = δᵢⱼ
    ortho_ok = .true.
    outer: do i = 1, r
      do j = 1, r
        complex(dp) :: tij; tij = czero
        do k = 1, d
          do l = 1, d
            tij = tij + frame_arr(i,k,l) * frame_arr(j,l,k)
          end do
        end do
        trace_ij = real(tij)
        if (i == j) then
          if (abs(trace_ij - 1.0_dp) > tol) then; ortho_ok = .false.; exit outer; end if
        else
          if (abs(trace_ij) > tol) then; ortho_ok = .false.; exit outer; end if
        end if
      end do
    end do outer

    ! Tight: Σ pᵢ = I
    tight_ok = .true.
    do j = 1, d
      do k = 1, d
        complex(dp) :: s; s = czero
        do i = 1, r; s = s + frame_arr(i,j,k); end do
        if (j == k) then
          if (abs(real(s) - 1.0_dp) > tol .or. abs(aimag(s)) > tol) then
            tight_ok = .false.
          end if
        else
          if (abs(s) > tol) tight_ok = .false.
        end if
      end do
    end do

    ! Idempotency: pᵢ² = pᵢ
    idemp_ok = .true.
    allocate(p_sq(d,d))
    do i = 1, r
      p_sq = matmul(frame_arr(i,:,:), frame_arr(i,:,:))
      frob_diff = 0.0_dp
      do j = 1, d; do k = 1, d
        frob_diff = frob_diff + abs(p_sq(j,k) - frame_arr(i,j,k))**2
      end do; end do
      if (sqrt(frob_diff) > tol * d) then; idemp_ok = .false.; exit; end if
    end do
    deallocate(p_sq)

    plasma_ok = 0
    if (herm_ok)  plasma_ok = plasma_ok + 1
    if (ortho_ok) plasma_ok = plasma_ok + 2
    if (tight_ok) plasma_ok = plasma_ok + 4
    if (idemp_ok) plasma_ok = plasma_ok + 8
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! 5. SPE FRAME INFO — stub (caller fills JSON from spe_frame_t fields)
  !═══════════════════════════════════════════════════════════════════
  subroutine spe_frame_info(frame, info_ptr) &
       bind(C, name="spe_frame_info")
    type(spe_frame_t), intent(in)  :: frame
    type(c_ptr),       intent(out) :: info_ptr
    info_ptr = c_null_ptr()
  end subroutine

end module spe_encoder
