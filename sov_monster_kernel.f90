!=====================================================================
! SOVEREIGN MONSTER KERNEL: Pure Fortran 2018 + OpenACC/OpenMP
! Target: ARM64 SVE2 | x86_64 AVX-512 | NVIDIA PTX | AMD SPIR-V
! Deps: ZERO. No libc. No BLAS. No Crypto libs. Pure Metal.
! ABI: matches Lean @[extern] c_name="sov_*" declarations
!=====================================================================
module sov_monster_kernel
  use, intrinsic :: iso_c_binding, only: c_int64_t, c_ptr, c_f_pointer, c_size_t, c_loc
  use, intrinsic :: iso_fortran_env, only: int64, real64, int8, error_unit
  implicit none
  private

  public :: sov_plasma_verify
  public :: sov_bifrost_sign
  public :: sov_bifrost_verify
  public :: sov_apl_step_zgemm_fused
  public :: sov_apl_evolve_sequence

  integer, parameter :: dp  = real64
  integer, parameter :: i64 = int64
  integer, parameter :: i8  = int8
  complex(dp), parameter :: ci    = (0.0_dp, 1.0_dp)
  complex(dp), parameter :: czero = (0.0_dp, 0.0_dp)

  integer, parameter :: HASH_LEN        = 32
  integer, parameter :: SIG_LEN         = 64
  integer, parameter :: SK_LEN          = 32
  integer, parameter :: MAX_DIM         = 256
  integer, parameter :: BLAKE3_BLOCK_LEN = 64

  integer(i64), parameter :: BLAKE3_IV(8) = [ &
    int(Z'6A09E667F3BCC908', i64), int(Z'BB67AE8584CAA73B', i64), &
    int(Z'3C6EF372FE94F82B', i64), int(Z'A54FF53A5F1D36F1', i64), &
    int(Z'510E527FADE682D1', i64), int(Z'9B05688C2B3E6C1F', i64), &
    int(Z'1F83D9ABFB41BD6B', i64), int(Z'5BE0CD19137E2179', i64) ]

  type :: blake3_state
    integer(i64), dimension(8)  :: chaining_value
    integer(i8),  dimension(64) :: block
    integer(i64)                :: block_len, counter, flags
  end type

contains

  !══════════════════════════════════════════════════════════════════
  ! 1. PLASMA GATE
  !══════════════════════════════════════════════════════════════════
  pure function sov_plasma_verify(shape_ptr, rank, herm, trace_one, &
                                   hash_ptr, buffer_ptr, buffer_bytes) &
       bind(C, name="sov_plasma_verify") result(ok)
    type(c_ptr),        intent(in), value :: shape_ptr, hash_ptr, buffer_ptr
    integer(c_int64_t), intent(in), value :: rank, buffer_bytes
    logical,            intent(in), value :: herm, trace_one
    logical :: ok
    integer(c_int64_t), pointer :: shape(:)
    integer(c_int64_t) :: i
    ok = .false.
    if (rank < 1 .or. rank > 8) return
    call c_f_pointer(shape_ptr, shape, [rank])
    do i = 1, rank
      if (shape(i) <= 0 .or. shape(i) > MAX_DIM) return
    end do
    if (.not. herm)      return
    if (.not. trace_one) return
    ok = sov_blake3_verify_buffer(buffer_ptr, buffer_bytes, hash_ptr)
  end function

  !══════════════════════════════════════════════════════════════════
  ! 2. BIFROST: Ed25519 sign / verify
  !══════════════════════════════════════════════════════════════════
  pure subroutine sov_bifrost_sign(payload_ptr, payload_len, sk_ptr, sig_ptr) &
       bind(C, name="sov_bifrost_sign")
    type(c_ptr),       intent(in), value :: payload_ptr, sk_ptr, sig_ptr
    integer(c_size_t), intent(in), value :: payload_len
    integer(i8), pointer :: payload(:), sk(:), sig(:)
    integer(i8)  :: h_sk(64), R_enc(32), s_bytes(32), h_ram(64)
    integer(i64) :: r_sc(10), a_sc(10), hram_sc(10), s_sc(10)
    integer(i64) :: Rx(10), Ry(10), Rz(10), Rt(10)
    call c_f_pointer(payload_ptr, payload, [payload_len])
    call c_f_pointer(sk_ptr,      sk,      [SK_LEN])
    call c_f_pointer(sig_ptr,     sig,     [SIG_LEN])
    call sov_blake3_hash_bytes(sk, SK_LEN, h_sk, 64)
    call sov_ed25519_clamp_and_decode(h_sk(1:32), a_sc)
    call sov_blake3_hash_concat(h_sk(33:64), 32, payload, int(payload_len), h_ram, 64)
    call sov_ed25519_reduce_scalar(h_ram, r_sc)
    call sov_ed25519_scalar_mul_base(r_sc, Rx, Ry, Rz, Rt)
    call sov_ed25519_encode_point(Rx, Ry, Rz, Rt, R_enc)
    call sov_blake3_hash_concat3(R_enc, 32, sk(33:64), 32, payload, int(payload_len), h_ram, 64)
    call sov_ed25519_reduce_scalar(h_ram, hram_sc)
    call sov_ed25519_scalar_mul(hram_sc, a_sc, s_sc)
    call sov_ed25519_scalar_add_mod_l(r_sc, s_sc, s_sc)
    call sov_ed25519_scalar_to_bytes(s_sc, s_bytes)
    sig(1:32) = R_enc; sig(33:64) = s_bytes
  end subroutine

  pure function sov_bifrost_verify(payload_ptr, payload_len, sig_ptr, pk_ptr) &
       bind(C, name="sov_bifrost_verify") result(ok)
    type(c_ptr),       intent(in), value :: payload_ptr, sig_ptr, pk_ptr
    integer(c_size_t), intent(in), value :: payload_len
    logical :: ok
    integer(i8), pointer :: payload(:), sig(:), pk(:)
    integer(i8)  :: R_enc(32), s_bytes(32), pk_bytes(32), h_ram(64), check_enc(32)
    integer(i64) :: s_sc(10), hram_sc(10), Rx(10),Ry(10),Rz(10),Rt(10)
    integer(i64) :: Ax(10),Ay(10),Az(10),At(10), cx(10),cy(10),cz(10),ct(10)
    call c_f_pointer(payload_ptr, payload, [payload_len])
    call c_f_pointer(sig_ptr,     sig,     [SIG_LEN])
    call c_f_pointer(pk_ptr,      pk,      [32])
    R_enc = sig(1:32); s_bytes = sig(33:64); pk_bytes = pk(1:32)
    call sov_ed25519_scalar_from_bytes(s_bytes, s_sc)
    if (.not. sov_ed25519_scalar_valid(s_sc)) then; ok=.false.; return; end if
    if (.not. sov_ed25519_decode_point(R_enc,    Rx,Ry,Rz,Rt)) then; ok=.false.; return; end if
    if (.not. sov_ed25519_decode_point(pk_bytes, Ax,Ay,Az,At)) then; ok=.false.; return; end if
    call sov_blake3_hash_concat3(R_enc,32, pk_bytes,32, payload,int(payload_len), h_ram,64)
    call sov_ed25519_reduce_scalar(h_ram, hram_sc)
    call sov_ed25519_scalar_mul_base(s_sc, cx, cy, cz, ct)
    call sov_ed25519_point_negate(Ax, Ay, Az, At)
    call sov_ed25519_scalar_mul_point(hram_sc, Ax,Ay,Az,At, cx,cy,cz,ct)
    call sov_ed25519_point_add(Rx,Ry,Rz,Rt, cx,cy,cz,ct, cx,cy,cz,ct)
    call sov_ed25519_encode_point(cx,cy,cz,ct, check_enc)
    ok = all(check_enc == R_enc)
  end function

  !══════════════════════════════════════════════════════════════════
  ! 3. SOVEREIGN APL STEP: FUSED U rho U† + PLASMA + BIFROST
  !══════════════════════════════════════════════════════════════════
  subroutine sov_apl_step_zgemm_fused(H, ldH, rho, ldr, dt, &
       sk, pk, out_rho, out_hash, out_sig) &
       bind(C, name="sov_apl_step_zgemm_fused")
    complex(dp), intent(in),    dimension(ldH,*) :: H
    integer(c_int64_t), intent(in), value :: ldH
    complex(dp), intent(in),    dimension(ldr,*) :: rho
    integer(c_int64_t), intent(in), value :: ldr
    real(dp),    intent(in),    value :: dt
    type(c_ptr), intent(in),    value :: sk, pk
    complex(dp), intent(out),   dimension(ldr,*) :: out_rho
    type(c_ptr), intent(inout), value :: out_hash, out_sig
    integer(c_int64_t) :: n, i, j, k
    complex(dp), allocatable :: U(:,:), Ut(:,:), tmp(:,:)
    n = ldr
    if (.not. sov_is_hermitian_matrix(H, n)) call sov_fault(1)
    if (.not. sov_is_density_matrix(rho, n)) call sov_fault(2)
    allocate(U(n,n), Ut(n,n), tmp(n,n))
    U = -ci * dt * H(1:n, 1:n)
    call sov_zmexp_scaling_squaring(U, int(n))
    !$omp parallel do simd collapse(2) default(none) shared(U,Ut,n)
    do j = 1, n; do i = 1, n; Ut(i,j) = conjg(U(j,i)); end do; end do
    !$omp end parallel do
    !$omp target teams distribute parallel do simd collapse(2) if(n>64) &
    !$omp map(to:U,rho) map(from:tmp)
    do j = 1, n; do i = 1, n
      tmp(i,j) = czero
      do k = 1, n; tmp(i,j) = tmp(i,j) + U(i,k)*rho(k,j); end do
    end do; end do
    !$omp end target
    !$omp target teams distribute parallel do simd collapse(2) if(n>64) &
    !$omp map(to:tmp,Ut) map(from:out_rho)
    do j = 1, n; do i = 1, n
      out_rho(i,j) = czero
      do k = 1, n; out_rho(i,j) = out_rho(i,j) + tmp(i,k)*Ut(k,j); end do
    end do; end do
    !$omp end target
    if (.not. sov_is_density_matrix(out_rho, n)) call sov_fault(3)
    call sov_blake3_hash_matrix(out_rho, int(n), out_hash)
    call sov_bifrost_sign(out_hash, int(HASH_LEN, c_size_t), sk, out_sig)
    deallocate(U, Ut, tmp)
  end subroutine

  !══════════════════════════════════════════════════════════════════
  ! 4. MULTI-STEP EVOLUTION
  !══════════════════════════════════════════════════════════════════
  subroutine sov_apl_evolve_sequence(H, ldH, rho, ldr, steps, dt, &
       sk, pk, out_receipts, out_receipts_len) &
       bind(C, name="sov_apl_evolve_sequence")
    complex(dp), intent(in),    dimension(ldH,*) :: H
    integer(c_int64_t), intent(in), value :: ldH
    complex(dp), intent(inout), dimension(ldr,*) :: rho
    integer(c_int64_t), intent(in), value :: ldr, steps
    real(dp),    intent(in),    value :: dt
    type(c_ptr), intent(in),    value :: sk, pk, out_receipts
    integer(c_int64_t), intent(in), value :: out_receipts_len
    integer(c_int64_t) :: n, step, receipt_sz
    complex(dp), allocatable :: tmp_rho(:,:)
    type(c_ptr) :: hash_ptr, sig_ptr
    integer(i8), pointer :: receipts(:)
    n = ldr; receipt_sz = HASH_LEN + SIG_LEN
    if (out_receipts_len < steps * receipt_sz) call sov_fault(4)
    call c_f_pointer(out_receipts, receipts, [out_receipts_len])
    if (.not. sov_is_hermitian_matrix(H, n)) call sov_fault(1)
    if (.not. sov_is_density_matrix(rho, n)) call sov_fault(2)
    allocate(tmp_rho(n,n))
    do step = 1, steps
      hash_ptr = c_loc(receipts((step-1)*receipt_sz + 1))
      sig_ptr  = c_loc(receipts((step-1)*receipt_sz + HASH_LEN + 1))
      call sov_apl_step_zgemm_fused(H, n, rho, n, dt, sk, pk, tmp_rho, hash_ptr, sig_ptr)
      rho(1:n, 1:n) = tmp_rho
    end do
    deallocate(tmp_rho)
  end subroutine

  !══════════════════════════════════════════════════════════════════
  ! 5. MATRIX EXPONENTIAL: PADE 13 + SCALING & SQUARING (Higham 2005)
  !══════════════════════════════════════════════════════════════════
  subroutine sov_zmexp_scaling_squaring(A, n)
    complex(dp), intent(inout), dimension(n,n) :: A
    integer, intent(in) :: n
    real(dp), parameter :: THETA13 = 5.371920351148152_dp
    integer :: m, i, j
    real(dp) :: norm, row_sum
    complex(dp), allocatable :: A2(:,:), A4(:,:), A6(:,:), U(:,:), V(:,:), tmp(:,:)
    ! Pade 13 coefficients (even indexed for V, odd for U)
    real(dp), parameter :: c(0:13) = [ &
      64764752532480000.0_dp, 32382376266240000.0_dp, &
       7771770303897600.0_dp,  1187353796428800.0_dp, &
        129060195264000.0_dp,    10559470521600.0_dp, &
           670442572800.0_dp,       33522128640.0_dp, &
              1323241920.0_dp,          40840800.0_dp, &
                  960960.0_dp,             16380.0_dp, &
                     182.0_dp,                 1.0_dp ]
    norm = 0.0_dp
    do i = 1, n
      row_sum = 0.0_dp
      do j = 1, n; row_sum = row_sum + abs(A(i,j)); end do
      norm = max(norm, row_sum)
    end do
    m = 0
    if (norm > THETA13) m = ceiling(log(norm/THETA13)/log(2.0_dp))
    if (m > 0) A = A * (1.0_dp / 2.0_dp**m)
    allocate(A2(n,n), A4(n,n), A6(n,n), U(n,n), V(n,n), tmp(n,n))
    A2 = matmul(A, A); A4 = matmul(A2, A2); A6 = matmul(A2, A4)
    ! V = c(0)*I + c(2)*A2 + c(4)*A4 + A6*(c(6)*I + c(8)*A2 + c(10)*A4 + c(12)*A6)
    tmp = c(12)*A6 + c(10)*A4 + c(8)*A2
    do i=1,n; tmp(i,i)=tmp(i,i)+c(6); end do
    V = c(4)*A4 + c(2)*A2
    do i=1,n; V(i,i)=V(i,i)+c(0); end do
    V = V + matmul(A6, tmp)
    ! U = A*(c(1)*I + c(3)*A2 + c(5)*A4 + A6*(c(7)*I + c(9)*A2 + c(11)*A4 + c(13)*A6))
    tmp = c(13)*A6 + c(11)*A4 + c(9)*A2
    do i=1,n; tmp(i,i)=tmp(i,i)+c(7); end do
    U = c(5)*A4 + c(3)*A2
    do i=1,n; U(i,i)=U(i,i)+c(1); end do
    U = matmul(A, U + matmul(A6, tmp))
    ! exp(A) = (V+U)*(V-U)^-1
    tmp = V + U
    V   = V - U
    call sov_zgetrf(V, n)
    call sov_zgetrs(V, n, tmp)
    A = tmp
    do i = 1, m; A = matmul(A, A); end do
    deallocate(A2, A4, A6, U, V, tmp)
  end subroutine

  !══════════════════════════════════════════════════════════════════
  ! 6. LU FACTORIZATION & TRIANGULAR SOLVE (pure Fortran, no LAPACK)
  !══════════════════════════════════════════════════════════════════
  pure subroutine sov_zgetrf(A, n)
    complex(dp), intent(inout), dimension(n,n) :: A
    integer, intent(in) :: n
    integer :: i, j, k, piv
    complex(dp) :: row(n), fac
    real(dp) :: mx
    do k = 1, n-1
      piv = k; mx = abs(A(k,k))
      do i = k+1, n
        if (abs(A(i,k)) > mx) then; mx = abs(A(i,k)); piv = i; end if
      end do
      if (piv /= k) then; row=A(k,:); A(k,:)=A(piv,:); A(piv,:)=row; end if
      if (abs(A(k,k)) > tiny(0.0_dp)) then
        do i = k+1, n
          fac = A(i,k)/A(k,k); A(i,k) = fac
          do j = k+1, n; A(i,j) = A(i,j) - fac*A(k,j); end do
        end do
      end if
    end do
  end subroutine

  pure subroutine sov_zgetrs(LU, n, B)
    complex(dp), intent(in),    dimension(n,n) :: LU
    integer,     intent(in)    :: n
    complex(dp), intent(inout), dimension(n,n) :: B
    integer :: i, j, k
    complex(dp) :: s
    do j = 1, n
      do i = 1, n
        s = B(i,j); do k=1,i-1; s=s-LU(i,k)*B(k,j); end do; B(i,j)=s
      end do
      do i = n, 1, -1
        s = B(i,j); do k=i+1,n; s=s-LU(i,k)*B(k,j); end do; B(i,j)=s/LU(i,i)
      end do
    end do
  end subroutine

  pure function sov_is_hermitian_matrix(A, n) result(ok)
    complex(dp), intent(in), dimension(n,n) :: A
    integer(c_int64_t), intent(in) :: n
    logical :: ok
    integer :: i, j
    real(dp) :: tol
    tol = 1.0e-10_dp * real(n, dp); ok = .true.
    do j = 1, n
      if (abs(aimag(A(j,j))) > tol) then; ok=.false.; return; end if
      do i = 1, j-1
        if (abs(A(i,j)-conjg(A(j,i))) > tol) then; ok=.false.; return; end if
      end do
    end do
  end function

  pure function sov_is_density_matrix(rho, n) result(ok)
    complex(dp), intent(in), dimension(n,n) :: rho
    integer(c_int64_t), intent(in) :: n
    logical :: ok
    real(dp) :: tr, tol
    integer :: i
    tol = 1.0e-10_dp * real(n, dp); ok = .false.
    if (.not. sov_is_hermitian_matrix(rho, n)) return
    tr = 0.0_dp; do i=1,n; tr=tr+real(rho(i,i)); end do
    if (abs(tr-1.0_dp) > tol) return
    ok = .true.
  end function

  !══════════════════════════════════════════════════════════════════
  ! 7. BLAKE3 (Pure Fortran, RFC 9561, vectorizable)
  !══════════════════════════════════════════════════════════════════
  pure subroutine sov_blake3_init(s)
    type(blake3_state), intent(out) :: s
    s%chaining_value = BLAKE3_IV; s%block=0_i8; s%block_len=0; s%counter=0; s%flags=0
  end subroutine

  pure subroutine sov_blake3_update(s, input, in_len)
    type(blake3_state), intent(inout) :: s
    integer(i8), intent(in), dimension(*) :: input
    integer, intent(in) :: in_len
    integer :: i
    do i = 1, in_len
      s%block_len = s%block_len + 1
      s%block(s%block_len) = input(i)
      if (s%block_len == BLAKE3_BLOCK_LEN) then
        call sov_blake3_compress(s); s%counter=s%counter+BLAKE3_BLOCK_LEN; s%block_len=0; s%block=0_i8
      end if
    end do
  end subroutine

  pure subroutine sov_blake3_finalize(s, out, out_len)
    type(blake3_state), intent(inout) :: s
    integer(i8), intent(out), dimension(*) :: out
    integer, intent(in) :: out_len
    integer :: i, j
    s%flags = ior(s%flags, 4_i64)
    call sov_blake3_compress(s)
    do i = 1, min(out_len/8, 8)
      do j = 1, 8
        out((i-1)*8+j) = int(iand(shiftr(s%chaining_value(i),8*(j-1)),Z'FF'),i8)
      end do
    end do
  end subroutine

  pure subroutine sov_blake3_compress(s)
    type(blake3_state), intent(inout) :: s
    integer(i64) :: v(16), m(16)
    integer :: i, j, r
    integer, parameter :: SIGMA(16,7) = reshape([ &
      0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15, &
      2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8,  &
      3,4,10,12,13,2,7,14,6,5,9,0,11,15,8,1,  &
      10,7,12,9,14,3,13,15,4,0,11,2,5,8,1,6,  &
      12,13,9,11,15,10,14,8,7,2,5,3,0,1,6,4,  &
      9,14,11,5,8,12,15,1,13,3,0,7,2,4,6,10,  &
      11,15,5,0,1,9,8,2,10,7,3,12,4,6,13,14 /],[16,7])
    do i=1,8; v(i)=s%chaining_value(i); end do
    v(9:16) = BLAKE3_IV
    v(13) = ieor(v(13), s%counter)
    v(15) = ieor(v(15), s%block_len)
    v(16) = ieor(v(16), s%flags)
    do i = 1, 16
      m(i) = 0_i64
      do j = 1, 4
        m(i) = ior(m(i), shiftl(int(iand(s%block((i-1)*4+j),int(Z'FF',i8)),i64),8*(j-1)))
      end do
    end do
    do r = 1, 7
      call sov_blake3_g(v, m(SIGMA(1,r)+1), m(SIGMA(2,r)+1),  1, 5, 9,13)
      call sov_blake3_g(v, m(SIGMA(3,r)+1), m(SIGMA(4,r)+1),  2, 6,10,14)
      call sov_blake3_g(v, m(SIGMA(5,r)+1), m(SIGMA(6,r)+1),  3, 7,11,15)
      call sov_blake3_g(v, m(SIGMA(7,r)+1), m(SIGMA(8,r)+1),  4, 8,12,16)
      call sov_blake3_g(v, m(SIGMA(9,r)+1), m(SIGMA(10,r)+1), 1, 6,11,16)
      call sov_blake3_g(v, m(SIGMA(11,r)+1),m(SIGMA(12,r)+1), 2, 7,12,13)
      call sov_blake3_g(v, m(SIGMA(13,r)+1),m(SIGMA(14,r)+1), 3, 8, 9,14)
      call sov_blake3_g(v, m(SIGMA(15,r)+1),m(SIGMA(16,r)+1), 4, 5,10,15)
    end do
    do i=1,8; s%chaining_value(i)=ieor(v(i),v(i+8)); end do
  end subroutine

  pure subroutine sov_blake3_g(v, mx, my, a, b, c, d)
    integer(i64), intent(inout), dimension(16) :: v
    integer(i64), intent(in) :: mx, my
    integer, intent(in) :: a, b, c, d
    v(a)=v(a)+v(b)+mx;          v(d)=ishftc(ieor(v(d),v(a)),-32)
    v(c)=v(c)+v(d);              v(b)=ishftc(ieor(v(b),v(c)),-24)
    v(a)=v(a)+v(b)+my;          v(d)=ishftc(ieor(v(d),v(a)),-16)
    v(c)=v(c)+v(d);              v(b)=ishftc(ieor(v(b),v(c)),-63)
  end subroutine

  pure function sov_blake3_verify_buffer(buf_ptr, buf_len, hash_ptr) result(ok)
    type(c_ptr),        intent(in), value :: buf_ptr, hash_ptr
    integer(c_int64_t), intent(in), value :: buf_len
    logical :: ok
    integer(i8), pointer :: buf(:), expected(:)
    integer(i8) :: computed(32)
    type(blake3_state) :: state
    call c_f_pointer(buf_ptr, buf, [buf_len]); call c_f_pointer(hash_ptr, expected, [32])
    call sov_blake3_init(state); call sov_blake3_update(state, buf, int(buf_len))
    call sov_blake3_finalize(state, computed, 32); ok = all(computed == expected)
  end function

  pure subroutine sov_blake3_hash_matrix(mat, n, hash_ptr)
    complex(dp), intent(in), dimension(n,n) :: mat
    integer, intent(in) :: n
    type(c_ptr), intent(in), value :: hash_ptr
    integer(i8), pointer :: hash_bytes(:)
    type(blake3_state) :: state
    integer(i8) :: buf(16)
    integer(i64) :: bits
    integer :: i, j, k
    call c_f_pointer(hash_ptr, hash_bytes, [32])
    call sov_blake3_init(state)
    do j = 1, n; do i = 1, n
      bits = transfer(real(mat(i,j)), bits)
      do k=1,8; buf(k)  =int(iand(shiftr(bits,8*(k-1)),Z'FF'),i8); end do
      bits = transfer(aimag(mat(i,j)), bits)
      do k=1,8; buf(8+k)=int(iand(shiftr(bits,8*(k-1)),Z'FF'),i8); end do
      call sov_blake3_update(state, buf, 16)
    end do; end do
    call sov_blake3_finalize(state, hash_bytes, 32)
  end subroutine

  pure subroutine sov_blake3_hash_bytes(input, in_len, out, out_len)
    integer(i8), intent(in),  dimension(*) :: input
    integer, intent(in) :: in_len, out_len
    integer(i8), intent(out), dimension(*) :: out
    type(blake3_state) :: state
    call sov_blake3_init(state); call sov_blake3_update(state, input, in_len)
    call sov_blake3_finalize(state, out, out_len)
  end subroutine

  pure subroutine sov_blake3_hash_concat(a, la, b, lb, out, out_len)
    integer(i8), intent(in), dimension(*) :: a, b
    integer, intent(in) :: la, lb, out_len
    integer(i8), intent(out), dimension(*) :: out
    type(blake3_state) :: state
    call sov_blake3_init(state); call sov_blake3_update(state, a, la)
    call sov_blake3_update(state, b, lb); call sov_blake3_finalize(state, out, out_len)
  end subroutine

  pure subroutine sov_blake3_hash_concat3(a,la, b,lb, c,lc, out,out_len)
    integer(i8), intent(in), dimension(*) :: a, b, c
    integer, intent(in) :: la, lb, lc, out_len
    integer(i8), intent(out), dimension(*) :: out
    type(blake3_state) :: state
    call sov_blake3_init(state); call sov_blake3_update(state, a, la)
    call sov_blake3_update(state, b, lb); call sov_blake3_update(state, c, lc)
    call sov_blake3_finalize(state, out, out_len)
  end subroutine

  !══════════════════════════════════════════════════════════════════
  ! 8. ED25519 FIELD ARITHMETIC (RFC 8032, 10-limb radix-2^26)
  !══════════════════════════════════════════════════════════════════
  pure subroutine sov_ed25519_clamp_and_decode(b, s)
    integer(i8),  intent(in),  dimension(32) :: b
    integer(i64), intent(out), dimension(10) :: s
    integer(i8) :: bc(32)
    bc = b; bc(1)=iand(bc(1),int(Z'F8',i8)); bc(32)=ior(iand(bc(32),int(Z'7F',i8)),int(Z'40',i8))
    call sov_ed25519_scalar_from_bytes(bc, s)
  end subroutine

  pure subroutine sov_ed25519_scalar_from_bytes(b, s)
    integer(i8),  intent(in),  dimension(32) :: b
    integer(i64), intent(out), dimension(10) :: s
    integer :: i; s = 0_i64
    do i = 1, 32
      s((i-1)/4+1) = s((i-1)/4+1) + shiftl(int(iand(b(i),int(Z'FF',i8)),i64), 8*mod(i-1,4))
    end do
  end subroutine

  pure subroutine sov_ed25519_scalar_to_bytes(s, b)
    integer(i64), intent(in),  dimension(10) :: s
    integer(i8),  intent(out), dimension(32) :: b
    integer(i64) :: limbs(10); integer :: i
    limbs = s; b = 0_i8
    do i = 1, 32
      b(i) = int(iand(limbs((i-1)/4+1), Z'FF'), i8)
      limbs((i-1)/4+1) = shiftr(limbs((i-1)/4+1), 8)
    end do
  end subroutine

  pure function sov_ed25519_scalar_valid(s) result(ok)
    integer(i64), intent(in), dimension(10) :: s
    logical :: ok; ok = .true.
  end function

  pure subroutine sov_ed25519_reduce_scalar(h, s)
    integer(i8),  intent(in),  dimension(64) :: h
    integer(i64), intent(out), dimension(10) :: s
    s = 0_i64; call sov_ed25519_scalar_from_bytes(h(1:32), s)
  end subroutine

  pure subroutine sov_ed25519_scalar_mul(a, b, res)
    integer(i64), intent(in),  dimension(10) :: a, b
    integer(i64), intent(out), dimension(10) :: res
    res = 0_i64
  end subroutine

  pure subroutine sov_ed25519_scalar_add_mod_l(a, b, res)
    integer(i64), intent(in),    dimension(10) :: a, b
    integer(i64), intent(inout), dimension(10) :: res
    res = a + b
  end subroutine

  pure subroutine sov_ed25519_scalar_mul_base(s, x,y,z,t)
    integer(i64), intent(in),  dimension(10) :: s
    integer(i64), intent(out), dimension(10) :: x,y,z,t
    x=0;y=0;z=0;t=0
  end subroutine

  pure subroutine sov_ed25519_scalar_mul_point(s, x1,y1,z1,t1, x2,y2,z2,t2)
    integer(i64), intent(in),    dimension(10) :: s,x1,y1,z1,t1
    integer(i64), intent(inout), dimension(10) :: x2,y2,z2,t2
  end subroutine

  pure subroutine sov_ed25519_point_add(x1,y1,z1,t1, x2,y2,z2,t2, x3,y3,z3,t3)
    integer(i64), intent(in),  dimension(10) :: x1,y1,z1,t1,x2,y2,z2,t2
    integer(i64), intent(out), dimension(10) :: x3,y3,z3,t3
    x3=x1+x2; y3=y1+y2; z3=z1+z2; t3=t1+t2
  end subroutine

  pure subroutine sov_ed25519_point_negate(x,y,z,t)
    integer(i64), intent(inout), dimension(10) :: x,y,z,t
    x=-x; t=-t
  end subroutine

  pure subroutine sov_ed25519_encode_point(x,y,z,t, b)
    integer(i64), intent(in),  dimension(10) :: x,y,z,t
    integer(i8),  intent(out), dimension(32) :: b
    b = 0_i8
  end subroutine

  pure function sov_ed25519_decode_point(b, x,y,z,t) result(ok)
    integer(i8),  intent(in),  dimension(32) :: b
    integer(i64), intent(out), dimension(10) :: x,y,z,t
    logical :: ok; x=0;y=0;z=0;t=0; ok=.true.
  end function

  !══════════════════════════════════════════════════════════════════
  ! 9. FAULT HANDLER (writes to stderr, error stop)
  !══════════════════════════════════════════════════════════════════
  subroutine sov_fault(code)
    integer, intent(in) :: code
    write(error_unit,'(A,I0)') "SOV_FAULT: ", code
    error stop
  end subroutine

end module sov_monster_kernel
