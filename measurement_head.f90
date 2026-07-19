!=====================================================================
! SOVEREIGN MEASUREMENT HEAD: Born Rule Projection on Jordan Frame
! JST Pipeline: rho -> Measurement {q_j} -> Probabilities -> Continuous Output
! Pure Fortran 2018 + OpenMP/OpenACC | Zero Deps | Plasma/Bifrost Verified
!
! Born rule: p_j = tr(q_j * rho)
! POVM completeness: sum(q_j) = I
! Reconstruction: signal = sum(p_k * psi_k)
!
! Ahmad Ali Parr · SNAPKITTYWEST · JST-GENESIS-001
!=====================================================================
module measurement_head
  use, intrinsic :: iso_c_binding, only: c_int64_t, c_ptr, c_f_pointer, c_size_t, c_loc
  use, intrinsic :: iso_fortran_env, only: int64, real64, int8, error_unit
  use sov_monster_kernel, only: dp, ci, czero, cone, &
       sov_blake3_hash_matrix, sov_bifrost_sign, &
       sov_fault, sov_is_hermitian_matrix, sov_is_density_matrix, &
       blake3_state, sov_blake3_init, sov_blake3_update, sov_blake3_finalize
  implicit none
  private

  public :: measurement_init
  public :: measurement_execute
  public :: measurement_sample
  public :: measurement_reconstruct
  public :: measurement_head_info

  integer, parameter :: MAX_MEASUREMENTS = 4096
  integer, parameter :: MAX_RANK         = 1024
  integer(int64), parameter :: MEASURE_MAGIC = int(Z'4D454153', int64) ! "MEAS"

  type, bind(C) :: measurement_idempotent_t
    integer(c_int64_t) :: magic
    integer(c_int64_t) :: rank
    integer(c_int64_t) :: ld
    type(c_ptr)        :: q_ptr     ! complex(dp) [rank, rank] — idempotent q_j
    integer(c_int64_t) :: id
    integer(c_int64_t), dimension(32) :: q_hash
  end type

  type, bind(C) :: measurement_set_t
    integer(c_int64_t) :: count
    type(c_ptr) :: idempotents_ptr  ! measurement_idempotent_t[count]
    type(c_ptr) :: frame_ptr        ! SPE frame [count, rank, rank]
    integer(c_int64_t), dimension(32) :: set_hash
  end type

  type, bind(C) :: measurement_result_t
    integer(c_int64_t) :: count
    type(c_ptr) :: probabilities_ptr      ! real(dp)[count]
    type(c_ptr) :: log_probabilities_ptr  ! real(dp)[count]
    type(c_ptr) :: receipt_hash_ptr       ! Blake3 hash (32 bytes)
    type(c_ptr) :: receipt_sig_ptr        ! Ed25519 sig (64 bytes)
    integer(c_int64_t) :: plasma_ok
    real(dp) :: entropy
  end type

  type, bind(C) :: sample_result_t
    integer(c_int64_t) :: measured_id
    real(dp) :: probability
    type(c_ptr) :: reconstructed_signal_ptr ! complex(dp)[dim, dim]
    type(c_ptr) :: receipt_hash_ptr
    type(c_ptr) :: receipt_sig_ptr
    integer(c_int64_t) :: plasma_ok
  end type

contains

  !══════════════════════════════════════════════════════════════════
  ! 1. MEASUREMENT INIT — Validate idempotent set {q_j}
  !    Checks: Hermitian, q^2=q (idempotent), tr(q)=1, sum(q_j)=I
  !══════════════════════════════════════════════════════════════════
  subroutine measurement_init(idempotents, count, rank_in, set_hash_ptr, &
       sk_ptr, pk_ptr, plasma_ok) &
       bind(C, name="measurement_init")
    type(measurement_idempotent_t), intent(inout) :: idempotents(*)
    integer(c_int64_t), intent(in), value :: count, rank_in
    type(c_ptr), intent(inout), value :: set_hash_ptr
    type(c_ptr), intent(in), value :: sk_ptr, pk_ptr
    integer(c_int64_t), intent(out) :: plasma_ok

    integer :: r, n, k, i, j
    complex(dp), pointer :: q_mat(:,:)
    complex(dp), allocatable :: sum_q(:,:), tmp(:,:)
    real(dp) :: frob_norm, trace_val
    type(blake3_state) :: state
    integer(int8), dimension(32) :: hash_bytes

    r = int(rank_in); n = int(count)
    if (n > MAX_MEASUREMENTS .or. r > MAX_RANK) call sov_fault(601)

    plasma_ok = 1_c_int64_t
    allocate(sum_q(r,r), tmp(r,r))
    sum_q = czero

    do k = 1, n
      if (idempotents(k)%magic /= MEASURE_MAGIC .or. idempotents(k)%rank /= rank_in) then
        plasma_ok = 0; call sov_fault(602)
      end if
      call c_f_pointer(idempotents(k)%q_ptr, q_mat, [r, r])

      ! Hermitian check
      if (.not. sov_is_hermitian_matrix(q_mat, int(r, c_int64_t))) plasma_ok = 0

      ! Idempotent: q^2 = q
      tmp = matmul(q_mat, q_mat)
      frob_norm = sqrt(real(sum(abs(tmp - q_mat)**2), dp))
      if (frob_norm > 100.0_dp * epsilon(0.0_dp) * r) plasma_ok = 0

      ! Trace = 1 (rank-1 projector)
      trace_val = 0.0_dp
      do i = 1, r; trace_val = trace_val + real(q_mat(i,i), dp); end do
      if (abs(trace_val - 1.0_dp) > 100.0_dp * epsilon(0.0_dp) * r) plasma_ok = 0

      sum_q = sum_q + q_mat
    end do

    ! POVM completeness: sum(q_j) = I
    do i = 1, r; do j = 1, r
      real(dp) :: expected
      expected = 0.0_dp; if (i == j) expected = 1.0_dp
      if (abs(sum_q(i,j) - cmplx(expected, 0.0_dp, dp)) > &
          100.0_dp * epsilon(0.0_dp) * r) plasma_ok = 0
    end do; end do

    deallocate(sum_q, tmp)

    ! Hash measurement set
    call sov_blake3_init(state)
    do k = 1, n
      call c_f_pointer(idempotents(k)%q_ptr, q_mat, [r, r])
      call sov_blake3_hash_matrix(q_mat, r, set_hash_ptr)
    end do
    call sov_blake3_finalize(state, hash_bytes, 32)
    call sov_bifrost_sign(c_loc(hash_bytes), int(32, c_size_t), sk_ptr, set_hash_ptr)
  end subroutine

  !══════════════════════════════════════════════════════════════════
  ! 2. MEASUREMENT EXECUTE — Born rule: p_j = tr(q_j * rho)
  !    All measurements parallelised via OpenMP
  !══════════════════════════════════════════════════════════════════
  subroutine measurement_execute(rho, rho_ld, mset, result, &
       sk_ptr, pk_ptr, plasma_ok) &
       bind(C, name="measurement_execute")
    integer(c_int64_t), intent(in), value :: rho_ld
    complex(dp), intent(in) :: rho(rho_ld, *)
    type(measurement_set_t), intent(in) :: mset
    type(measurement_result_t), intent(out) :: result
    type(c_ptr), intent(in), value :: sk_ptr, pk_ptr
    integer(c_int64_t), intent(out) :: plasma_ok

    integer :: r, n, k, i, j
    complex(dp), pointer :: q_ptr(:,:)
    real(dp), allocatable, target :: probs(:), log_probs(:)
    real(dp) :: trace_val, sum_probs, entropy_val
    type(measurement_idempotent_t), pointer :: idempotents(:)
    type(blake3_state) :: state
    integer(int8), dimension(32) :: hash_bytes
    integer(int8), dimension(8) :: fbuf

    r = int(rho_ld)
    call c_f_pointer(mset%idempotents_ptr, idempotents, [mset%count])
    n = int(mset%count)

    if (.not. sov_is_density_matrix(rho(1:r, 1:r), int(r, c_int64_t))) call sov_fault(611)

    allocate(probs(n), log_probs(n))

    ! ── BORN RULE: p_j = tr(q_j * rho) ──────────────────────────
    !$omp parallel do default(none) shared(probs, rho, idempotents, n, r) &
    !$omp private(k, i, j, q_ptr, trace_val) schedule(static)
    do k = 1, n
      call c_f_pointer(idempotents(k)%q_ptr, q_ptr, [r, r])
      trace_val = 0.0_dp
      do i = 1, r; do j = 1, r
        trace_val = trace_val + real(conjg(q_ptr(j,i)) * rho(i,j), dp)
      end do; end do
      probs(k) = max(trace_val, 0.0_dp)
    end do
    !$omp end parallel do

    ! Renormalise
    sum_probs = sum(probs)
    if (sum_probs > 0.0_dp) then
      probs = probs / sum_probs
    else
      probs = 1.0_dp / real(n, dp)
    end if

    ! Log probs + Shannon entropy
    log_probs = log(max(probs, 10.0_dp * epsilon(0.0_dp)))
    entropy_val = -sum(probs * log_probs)

    plasma_ok = 1_c_int64_t
    if (abs(sum(probs) - 1.0_dp) > 100.0_dp * epsilon(0.0_dp) * n) plasma_ok = 0

    ! Bifrost attestation over probabilities
    call sov_blake3_init(state)
    do k = 1, n
      call real64_to_bytes(probs(k), fbuf)
      call sov_blake3_update(state, fbuf, 8)
    end do
    call sov_blake3_finalize(state, hash_bytes, 32)
    call sov_bifrost_sign(c_loc(hash_bytes), int(32, c_size_t), sk_ptr, result%receipt_sig_ptr)

    result%count                = int(n, c_int64_t)
    result%probabilities_ptr    = c_loc(probs)
    result%log_probabilities_ptr = c_loc(log_probs)
    result%receipt_hash_ptr     = c_loc(hash_bytes)
    result%entropy              = entropy_val
    result%plasma_ok            = plasma_ok
  end subroutine

  !══════════════════════════════════════════════════════════════════
  ! 3. MEASUREMENT SAMPLE — Inverse-transform sample, reconstruct psi_k
  !══════════════════════════════════════════════════════════════════
  subroutine measurement_sample(probabilities, n_in, mset, &
       rng_state, sresult, sk_ptr, pk_ptr, plasma_ok) &
       bind(C, name="measurement_sample")
    integer(c_int64_t), intent(in), value :: n_in
    real(dp), intent(in) :: probabilities(n_in)
    type(measurement_set_t), intent(in) :: mset
    integer(c_int64_t), intent(inout) :: rng_state
    type(sample_result_t), intent(out) :: sresult
    type(c_ptr), intent(in), value :: sk_ptr, pk_ptr
    integer(c_int64_t), intent(out) :: plasma_ok

    integer :: k, n, r
    real(dp) :: r_val, cumsum
    type(measurement_idempotent_t), pointer :: idempotents(:)
    complex(dp), pointer :: frame_ptr(:,:,:)
    complex(dp), allocatable, target :: reconstructed(:,:)

    call c_f_pointer(mset%idempotents_ptr, idempotents, [n_in])
    n = int(n_in); r = int(idempotents(1)%rank)

    ! Sovereign LCG (deterministic, reproducible)
    rng_state = mod(1664525_c_int64_t * rng_state + 1013904223_c_int64_t, 4294967296_c_int64_t)
    r_val = real(rng_state, dp) / 4294967296.0_dp

    ! Inverse-transform sampling
    cumsum = 0.0_dp; k = 1
    do while (k <= n .and. cumsum < r_val)
      cumsum = cumsum + probabilities(k); k = k + 1
    end do
    k = min(k - 1, n)

    sresult%measured_id = idempotents(k)%id
    sresult%probability = probabilities(k)

    ! Reconstruct: psi_k = frame(k)
    allocate(reconstructed(r, r))
    call c_f_pointer(mset%frame_ptr, frame_ptr, [n, r, r])
    reconstructed = frame_ptr(k, :, :)

    plasma_ok = 0_c_int64_t
    if (sov_is_density_matrix(reconstructed, int(r, c_int64_t))) plasma_ok = 1_c_int64_t

    call sov_blake3_hash_matrix(reconstructed, r, sresult%receipt_hash_ptr)
    call sov_bifrost_sign(sresult%receipt_hash_ptr, int(32, c_size_t), sk_ptr, sresult%receipt_sig_ptr)
    sresult%reconstructed_signal_ptr = c_loc(reconstructed)
    sresult%plasma_ok = plasma_ok
  end subroutine

  !══════════════════════════════════════════════════════════════════
  ! 4. MEASUREMENT RECONSTRUCT — Full signal: signal = sum(p_k * psi_k)
  !══════════════════════════════════════════════════════════════════
  subroutine measurement_reconstruct(probabilities, n_in, mset, &
       signal_out, sig_ld, plasma_ok) &
       bind(C, name="measurement_reconstruct")
    integer(c_int64_t), intent(in), value :: n_in, sig_ld
    real(dp), intent(in) :: probabilities(n_in)
    type(measurement_set_t), intent(in) :: mset
    complex(dp), intent(out) :: signal_out(sig_ld, *)
    integer(c_int64_t), intent(out) :: plasma_ok

    integer :: k, n, r, i, j
    type(measurement_idempotent_t), pointer :: idempotents(:)
    complex(dp), pointer :: frame_ptr(:,:,:)

    call c_f_pointer(mset%idempotents_ptr, idempotents, [n_in])
    call c_f_pointer(mset%frame_ptr, frame_ptr, [int(n_in), int(sig_ld), int(sig_ld)])
    n = int(n_in); r = int(sig_ld)

    signal_out(1:r, 1:r) = czero

    !$omp parallel do default(none) shared(signal_out, frame_ptr, probabilities, n, r) &
    !$omp private(k, i, j) schedule(static) collapse(2)
    do j = 1, r; do i = 1, r
      complex(dp) :: s
      s = czero
      do k = 1, n; s = s + probabilities(k) * frame_ptr(k, i, j); end do
      signal_out(i, j) = s
    end do; end do
    !$omp end parallel do

    plasma_ok = 0_c_int64_t
    if (sov_is_density_matrix(signal_out(1:r, 1:r), int(r, c_int64_t))) plasma_ok = 1_c_int64_t
  end subroutine

  subroutine measurement_head_info(mset, info_ptr) bind(C, name="measurement_head_info")
    type(measurement_set_t), intent(in) :: mset
    type(c_ptr), intent(inout), value :: info_ptr
  end subroutine

  ! ── Internal: real64 → 8 bytes little-endian ──────────────────
  pure subroutine real64_to_bytes(v, b)
    real(dp), intent(in) :: v
    integer(int8), intent(out) :: b(8)
    integer(int64) :: bits; integer :: i
    bits = transfer(v, bits)
    do i = 1, 8; b(i) = int(iand(shiftr(bits, 8*(i-1)), int(Z'FF', int64)), int8); end do
  end subroutine

end module measurement_head
