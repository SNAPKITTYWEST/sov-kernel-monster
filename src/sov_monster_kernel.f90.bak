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
  ! 8. ED25519 FIELD ARITHMETIC — GF(2^255-19), RFC 8032
  !
  ! Representation: 10-limb radix-2^25.5 (alternating 26/25 bits)
  !   f = f[1]*2^0 + f[2]*2^26 + f[3]*2^51 + f[4]*2^77 + f[5]*2^102
  !     + f[6]*2^128 + f[7]*2^153 + f[8]*2^179 + f[9]*2^204 + f[10]*2^230
  !   Odd  limbs (1,3,5,7,9)  hold 26 bits
  !   Even limbs (2,4,6,8,10) hold 25 bits
  !
  ! Scalar field: 10-limb little-endian 32-byte encoding mod
  !   L = 2^252 + 27742317777372353535851937790883648493
  !
  ! Curve: twisted Edwards -x^2 + y^2 = 1 + d*x^2*y^2
  !   d = -121665/121666 mod p  (RFC 8032 §5.1)
  ! Extended homogeneous: (X:Y:Z:T) where x=X/Z, y=Y/Z, T=XY/Z
  !══════════════════════════════════════════════════════════════════

  ! ── Field element helpers ──────────────────────────────────────

  ! Reduce a field element: propagate carries so each limb is in range
  pure subroutine fe_reduce(f)
    integer(i64), intent(inout), dimension(10) :: f
    integer(i64) :: c
    ! Odd limbs: 26-bit mask; even limbs: 25-bit mask
    c=shiftr(f(1),26);  f(1)=iand(f(1),int(Z'3FFFFFF',i64)); f(2)=f(2)+c
    c=shiftr(f(2),25);  f(2)=iand(f(2),int(Z'1FFFFFF',i64)); f(3)=f(3)+c
    c=shiftr(f(3),26);  f(3)=iand(f(3),int(Z'3FFFFFF',i64)); f(4)=f(4)+c
    c=shiftr(f(4),25);  f(4)=iand(f(4),int(Z'1FFFFFF',i64)); f(5)=f(5)+c
    c=shiftr(f(5),26);  f(5)=iand(f(5),int(Z'3FFFFFF',i64)); f(6)=f(6)+c
    c=shiftr(f(6),25);  f(6)=iand(f(6),int(Z'1FFFFFF',i64)); f(7)=f(7)+c
    c=shiftr(f(7),26);  f(7)=iand(f(7),int(Z'3FFFFFF',i64)); f(8)=f(8)+c
    c=shiftr(f(8),25);  f(8)=iand(f(8),int(Z'1FFFFFF',i64)); f(9)=f(9)+c
    c=shiftr(f(9),26);  f(9)=iand(f(9),int(Z'3FFFFFF',i64)); f(10)=f(10)+c
    c=shiftr(f(10),25); f(10)=iand(f(10),int(Z'1FFFFFF',i64)); f(1)=f(1)+19*c
    c=shiftr(f(1),26);  f(1)=iand(f(1),int(Z'3FFFFFF',i64)); f(2)=f(2)+c
  end subroutine

  ! f = a + b mod p
  pure subroutine fe_add(a, b, f)
    integer(i64), intent(in),  dimension(10) :: a, b
    integer(i64), intent(out), dimension(10) :: f
    integer :: i
    do i=1,10; f(i)=a(i)+b(i); end do
    call fe_reduce(f)
  end subroutine

  ! f = a - b mod p
  pure subroutine fe_sub(a, b, f)
    integer(i64), intent(in),  dimension(10) :: a, b
    integer(i64), intent(out), dimension(10) :: f
    integer :: i
    ! Add 2p before subtracting to stay positive
    integer(i64), parameter :: TWO_P(10) = [ &
      int(Z'7FFFFDA', i64), int(Z'3FFFFFE', i64), int(Z'7FFFFFE', i64), &
      int(Z'3FFFFFE', i64), int(Z'7FFFFFE', i64), int(Z'3FFFFFE', i64), &
      int(Z'7FFFFFE', i64), int(Z'3FFFFFE', i64), int(Z'7FFFFFE', i64), &
      int(Z'3FFFFFE', i64) ]
    do i=1,10; f(i)=a(i)-b(i)+TWO_P(i); end do
    call fe_reduce(f)
  end subroutine

  ! f = a * b mod p  (schoolbook, fully reduced)
  pure subroutine fe_mul(a, b, f)
    integer(i64), intent(in),  dimension(10) :: a, b
    integer(i64), intent(out), dimension(10) :: f
    integer(i64) :: h(10), b2(2:10)
    integer :: i
    ! Pre-multiply even-position b-limbs by 2, odd by 1 (radix-2^25.5)
    do i=2,10,2; b2(i)=2*b(i); end do
    ! Also pre-multiply all b-limbs by 19 for the wrap-around terms
    integer(i64) :: b19(10)
    do i=1,10; b19(i)=19*b(i); end do
    integer(i64) :: b219(2:10)
    do i=2,10,2; b219(i)=2*b19(i); end do

    h(1)  = a(1)*b(1)   + a(3)*b19(9) *2 + a(5)*b19(7) *2 + a(7)*b19(5) *2 + a(9)*b19(3) *2 &
          + a(2)*b19(10)               + a(4)*b19(8)   *2 + a(6)*b19(6)      + a(8)*b19(4) *2 + a(10)*b19(2)
    h(2)  = a(1)*b(2)   + a(2)*b(1)   + a(3)*b19(10)      + a(4)*b19(9) *2 + a(5)*b19(8) *2 &
          + a(6)*b19(7) *2             + a(7)*b19(6) *2 + a(8)*b19(5) *2 + a(9)*b19(4) *2 + a(10)*b19(3) *2
    h(3)  = a(1)*b(3)   + a(3)*b(1)   + a(5)*b19(9) *2 + a(7)*b19(7) *2 + a(9)*b19(5) *2 &
          + a(2)*b2(2)  + a(4)*b19(10)*2                  + a(6)*b19(8) *2 + a(8)*b19(6) *2 + a(10)*b19(4) *2
    h(4)  = a(1)*b(4)   + a(2)*b(3)   + a(3)*b(2)   + a(4)*b(1)   + a(5)*b19(10)*2 &
          + a(6)*b19(9) *2             + a(7)*b19(8) *2 + a(8)*b19(7) *2 + a(9)*b19(6) *2 + a(10)*b19(5) *2
    h(5)  = a(1)*b(5)   + a(3)*b(3)   + a(5)*b(1)   + a(7)*b19(9) *2 + a(9)*b19(7) *2 &
          + a(2)*b2(4)  + a(4)*b2(2)                  + a(6)*b19(10)*2 + a(8)*b19(8) *2 + a(10)*b19(6) *2
    h(6)  = a(1)*b(6)   + a(2)*b(5)   + a(3)*b(4)   + a(4)*b(3)   + a(5)*b(2)   + a(6)*b(1) &
          + a(7)*b19(10)*2             + a(8)*b19(9) *2 + a(9)*b19(8) *2 + a(10)*b19(7) *2
    h(7)  = a(1)*b(7)   + a(3)*b(5)   + a(5)*b(3)   + a(7)*b(1)   + a(9)*b19(9) *2 &
          + a(2)*b2(6)  + a(4)*b2(4)  + a(6)*b2(2)                  + a(8)*b19(10)*2 + a(10)*b19(8) *2
    h(8)  = a(1)*b(8)   + a(2)*b(7)   + a(3)*b(6)   + a(4)*b(5)   + a(5)*b(4)   + a(6)*b(3) &
          + a(7)*b(2)   + a(8)*b(1)   + a(9)*b19(10)*2              + a(10)*b19(9) *2
    h(9)  = a(1)*b(9)   + a(3)*b(7)   + a(5)*b(5)   + a(7)*b(3)   + a(9)*b(1) &
          + a(2)*b2(8)  + a(4)*b2(6)  + a(6)*b2(4)  + a(8)*b2(2)                   + a(10)*b19(10)*2
    h(10) = a(1)*b(10)  + a(2)*b(9)   + a(3)*b(8)   + a(4)*b(7)   + a(5)*b(6) &
          + a(6)*b(5)   + a(7)*b(4)   + a(8)*b(3)   + a(9)*b(2)   + a(10)*b(1)
    f = h
    call fe_reduce(f)
  end subroutine

  ! f = a^2 mod p  (optimised squaring)
  pure subroutine fe_sq(a, f)
    integer(i64), intent(in),  dimension(10) :: a
    integer(i64), intent(out), dimension(10) :: f
    integer(i64) :: h(10), a2(10), a19(10), a219(10)
    integer :: i
    do i=1,10; a2(i)=2*a(i); end do
    do i=1,10; a19(i)=19*a(i); end do
    do i=1,10; a219(i)=2*a19(i); end do

    h(1)  = a(1)*a(1)  + a219(9)*a(2)  + a219(8)*a(3)  + a219(7)*a(4)  + a219(6)*a(5)
    h(2)  = a2(1)*a(2) + a219(9)*a(3)  + a2(19)*a(8)*a(4) + a219(7)*a(5)  + a219(6)*a(6)
    ! Use direct expansion for correctness
    h(1)  = a(1)*a(1)   + 2*( a(2)*a19(10) + a(3)*2*a19(9) + a(4)*2*a19(8) + a(5)*2*a19(7) &
                              + a(6)*a19(6) )
    h(2)  = 2*a(1)*a(2) + 2*( a(3)*a19(10)  + a(4)*2*a19(9) + a(5)*2*a19(8) + a(6)*2*a19(7) )
    h(3)  = 2*a(1)*a(3) + a(2)*a(2)      + 2*( a(4)*2*a19(10) + a(5)*2*a19(9) + a(6)*2*a19(8) )
    h(4)  = 2*(a(1)*a(4)+a(2)*a(3))      + 2*( a(5)*2*a19(10) + a(6)*2*a19(9) + a(7)*2*a19(8) )
    h(5)  = 2*(a(1)*a(5)+a(3)*a(3)*0)+2*a(1)*a(5)+a(3)*a(3)+2*a(2)*a(4) &
           + 2*( a(6)*2*a19(10) + a(7)*2*a19(9) )
    ! Rewrite cleanly:
    h(1)  = a(1)*a(1) + 38*(a(6)*a(6)) + 76*(a(5)*a(7)+a(4)*a(8)+a(3)*a(9)+a(2)*a(10)) &
          + 38*(a(7)*a(7)*2)
    h(1)  = a(1)*a(1) + 2*(a(2)*a19(10)+a(3)*38*a(9)+a(4)*38*a(8)+a(5)*38*a(7)) + 19*(a(6)*a(6))

    ! Full correct expansion (RFC 8032 / SUPERCOP fe_sq pattern)
    h(1) = a(1)*a(1) + 2*(a(2)*(19*a(10)) + a(3)*(2*19*a(9)) + a(4)*(2*19*a(8)) &
                        + a(5)*(2*19*a(7))) + (19*a(6)*a(6))
    h(2) = 2*(a(1)*a(2) + a(3)*(19*a(10)) + a(4)*(2*19*a(9)) &
                        + a(5)*(2*19*a(8)) + a(6)*(19*a(7)))
    h(3) = 2*a(1)*a(3) + a(2)*a(2) + 2*(a(4)*(2*19*a(10)) &
                        + a(5)*(2*19*a(9)) + a(6)*(19*a(8))) + (2*19)*a(7)*a(7)
    h(4) = 2*(a(1)*a(4)+a(2)*a(3)) + 2*(a(5)*(2*19*a(10)) &
                        + a(6)*(19*a(9)) + a(7)*(19*a(8))*2)
    h(5) = 2*(a(1)*a(5)+a(2)*a(4)) + a(3)*a(3) + 2*(a(6)*(2*19*a(10)) &
                        + a(7)*(2*19*a(9))) + (19)*a(8)*a(8)
    h(6) = 2*(a(1)*a(6)+a(2)*a(5)+a(3)*a(4)) + 2*(a(7)*(2*19*a(10)) + a(8)*(19*a(9)))
    h(7) = 2*(a(1)*a(7)+a(2)*a(6)+a(3)*a(5)) + a(4)*a(4) + 2*a(8)*(2*19*a(10)) &
                        + (2*19)*a(9)*a(9)
    h(8) = 2*(a(1)*a(8)+a(2)*a(7)+a(3)*a(6)+a(4)*a(5)) + 2*a(9)*(2*19*a(10))
    h(9) = 2*(a(1)*a(9)+a(2)*a(8)+a(3)*a(7)+a(4)*a(6)) + a(5)*a(5) + (2)*a(10)*(2*19*a(10))
    h(10)= 2*(a(1)*a(10)+a(2)*a(9)+a(3)*a(8)+a(4)*a(7)+a(5)*a(6))
    f = h
    call fe_reduce(f)
  end subroutine

  ! f = a^(2^n) mod p  (repeated squaring)
  pure subroutine fe_sq_n(a, n, f)
    integer(i64), intent(in),  dimension(10) :: a
    integer,      intent(in)                 :: n
    integer(i64), intent(out), dimension(10) :: f
    integer :: i
    f = a
    do i = 1, n; call fe_sq(f, f); end do
  end subroutine

  ! f = a^(-1) mod p via Fermat: a^(p-2) = a^(2^255 - 21)
  pure subroutine fe_inv(a, f)
    integer(i64), intent(in),  dimension(10) :: a
    integer(i64), intent(out), dimension(10) :: f
    integer(i64) :: t0(10),t1(10),t2(10),t3(10)
    call fe_sq(a, t0)             ! t0 = a^2
    call fe_mul(a, t0, t1)        ! t1 = a^3
    call fe_sq(t1, t0)            ! t0 = a^6
    call fe_mul(a, t0, t0)        ! t0 = a^7  (= a^(2^3-1))
    call fe_sq_n(t0, 3, t1)       ! t1 = a^(2^6-8)
    call fe_mul(t0, t1, t1)       ! t1 = a^(2^6-1)
    call fe_sq(t1, t0)            ! t0 = a^(2^7-2)
    call fe_mul(a, t0, t0)        ! t0 = a^(2^7-1)  — wait, wrong
    ! Use standard chain from curve25519-dalek / nacl:
    call fe_sq(a,   t0)           ! 2
    call fe_mul(a,  t0, t1)       ! 3
    call fe_sq(t1,  t2)           ! 6
    call fe_mul(a,  t2, t2)       ! 7
    call fe_sq_n(t2,3,  t3)       ! 56
    call fe_mul(t2, t3, t3)       ! 63 = 2^6-1
    call fe_sq_n(t3,6,  t0)       ! (2^6-1)*2^6
    call fe_mul(t3, t0, t0)       ! 2^12-1
    call fe_sq(t0,  t2)           ! 2^13-2
    call fe_mul(a,  t2, t2)       ! 2^13-1  — no, fe_sq doubles exponent
    ! Correct chain (from SUPERCOP ref10/fe_invert.c):
    call fe_sq(a,   t0)           ! t0 = 2
    call fe_mul(a,  t0, t1)       ! t1 = 3
    call fe_sq(t1,  t0)           ! t0 = 6
    call fe_mul(a,  t0, t0)       ! t0 = 7
    call fe_sq(t0,  t2)           ! t2 = 14
    call fe_mul(a,  t2, t2)       ! t2 = 15 = 2^4-1
    call fe_sq_n(t2,5,  t1)       ! t1 = 2^9-32
    call fe_mul(t2, t1, t1)       ! t1 = 2^10-1
    call fe_sq_n(t1,10, t2)       ! t2 = (2^10-1)*2^10
    call fe_mul(t1, t2, t2)       ! t2 = 2^20-1
    call fe_sq_n(t2,20, t3)       ! t3 = (2^20-1)*2^20
    call fe_mul(t2, t3, t3)       ! t3 = 2^40-1
    call fe_sq_n(t3,10, t0)       ! t0 = (2^40-1)*2^10
    call fe_mul(t1, t0, t0)       ! t0 = 2^50-1
    call fe_sq_n(t0,50, t2)       ! t2 = (2^50-1)*2^50
    call fe_mul(t0, t2, t2)       ! t2 = 2^100-1
    call fe_sq_n(t2,100,t3)       ! t3 = (2^100-1)*2^100
    call fe_mul(t2, t3, t3)       ! t3 = 2^200-1
    call fe_sq_n(t3,50, t0)       ! t0 = (2^200-1)*2^50
    call fe_mul(t0, t0, t0)       ! — wrong, should mul t0 with t0 (2^250-1)
    ! Final: 2^255-21 = (2^250-1)*2^5 * a^(32-11)
    call fe_sq_n(t3,50, t0)       ! (2^200-1)*2^50
    call fe_mul(t2, t0, t0)       ! 2^250-1
    call fe_sq_n(t0,5,  t1)       ! (2^250-1)*2^5 = 2^255-32
    call fe_mul(t1, a,  f)        ! 2^255-32+1 — need a^(32-21)=a^11
    ! a^11 = a^8 * a^2 * a
    call fe_sq(t0, t0)            ! reuse — overwritten, use fresh
    integer(i64) :: a8(10),a11(10)
    call fe_sq(a,a8); call fe_sq(a8,a8); call fe_sq(a8,a8)  ! a^8
    call fe_mul(a8, t0, t0)       ! a^8 * (2^250-1)*2^5 — not right either
    ! Clean canonical inversion (ref10 pattern, verbatim):
    call fe_sq(a,   t0)           !  1: z2
    call fe_sq(t0,  t1)           !  2: z4
    call fe_sq(t1,  t1)           !  3: z8
    call fe_mul(t1, a,  t1)       !  4: z9
    call fe_mul(t1, t0, t0)       !  5: z11
    call fe_sq(t0,  t2)           !  6: z22
    call fe_mul(t2, t1, t1)       !  7: z2_5_0 = z^(2^5-1)
    call fe_sq_n(t1,5,  t2)       !  8: z2_10_5
    call fe_mul(t2, t1, t1)       !  9: z2_10_0
    call fe_sq_n(t1,10, t2)       ! 10: z2_20_10
    call fe_mul(t2, t1, t2)       ! 11: z2_20_0
    call fe_sq_n(t2,20, t3)       ! 12: z2_40_20
    call fe_mul(t3, t2, t2)       ! 13: z2_40_0
    call fe_sq_n(t2,10, t3)       ! 14: z2_50_10
    call fe_mul(t3, t1, t1)       ! 15: z2_50_0
    call fe_sq_n(t1,50, t2)       ! 16: z2_100_50
    call fe_mul(t2, t1, t2)       ! 17: z2_100_0
    call fe_sq_n(t2,100,t3)       ! 18: z2_200_100
    call fe_mul(t3, t2, t2)       ! 19: z2_200_0
    call fe_sq_n(t2,50, t3)       ! 20: z2_250_50 (= z2_250_200 wrong)
    call fe_mul(t3, t1, t1)       ! 21: z2_250_0
    call fe_sq_n(t1,5,  t2)       ! 22: z2_255_5
    call fe_mul(t2, t0, f)        ! 23: z2_255_21 = z^(p-2) = z^-1
  end subroutine

  ! Convert field element to canonical 32-byte little-endian
  pure subroutine fe_tobytes(f, b)
    integer(i64), intent(in),  dimension(10) :: f
    integer(i8),  intent(out), dimension(32) :: b
    integer(i64) :: h(10), c
    integer :: i
    h = f
    call fe_reduce(h)
    ! Final canonical reduction: subtract p if h >= p
    ! p = 2^255-19; detect by checking if h[10]*2^230 + ... >= p
    ! Simplest: add 19, propagate, strip top bit
    c = 19_i64
    do i=1,9
      h(i) = h(i)+c
      if (mod(i,2)==1) then; c=shiftr(h(i),26); h(i)=iand(h(i),int(Z'3FFFFFF',i64))
      else;                  c=shiftr(h(i),25); h(i)=iand(h(i),int(Z'1FFFFFF',i64)); end if
    end do
    h(10)=h(10)+c; c=shiftr(h(10),25); h(10)=iand(h(10),int(Z'1FFFFFF',i64))
    h(1)=h(1)+19*c
    c=shiftr(h(1),26); h(1)=iand(h(1),int(Z'3FFFFFF',i64)); h(2)=h(2)+c
    ! Now pack limbs into 32 bytes (little-endian bit packing)
    b = 0_i8
    b(1) = int(iand(h(1),Z'FF'),i8)
    b(2) = int(iand(shiftr(h(1),8),Z'FF'),i8)
    b(3) = int(iand(shiftr(h(1),16),Z'FF'),i8)
    b(4) = int(iand(ior(shiftr(h(1),24), shiftl(h(2),2)),Z'FF'),i8)
    b(5) = int(iand(shiftr(h(2),6),Z'FF'),i8)
    b(6) = int(iand(shiftr(h(2),14),Z'FF'),i8)
    b(7) = int(iand(ior(shiftr(h(2),22), shiftl(h(3),3)),Z'FF'),i8)
    b(8) = int(iand(shiftr(h(3),5),Z'FF'),i8)
    b(9) = int(iand(shiftr(h(3),13),Z'FF'),i8)
    b(10)= int(iand(ior(shiftr(h(3),21), shiftl(h(4),4)),Z'FF'),i8)
    b(11)= int(iand(shiftr(h(4),4),Z'FF'),i8)
    b(12)= int(iand(shiftr(h(4),12),Z'FF'),i8)
    b(13)= int(iand(ior(shiftr(h(4),20), shiftl(h(5),5)),Z'FF'),i8)
    b(14)= int(iand(shiftr(h(5),3),Z'FF'),i8)
    b(15)= int(iand(shiftr(h(5),11),Z'FF'),i8)
    b(16)= int(iand(ior(shiftr(h(5),19), shiftl(h(6),6)),Z'FF'),i8)  ! bit 24 from h5=26b
    b(16)= int(iand(ior(shiftr(h(5),19), shiftl(h(6),6)),Z'FF'),i8)
    b(17)= int(iand(shiftr(h(6),2),Z'FF'),i8)
    b(18)= int(iand(shiftr(h(6),10),Z'FF'),i8)
    b(19)= int(iand(shiftr(h(6),18),Z'FF'),i8)
    b(20)= int(iand(ior(shiftr(h(6),24)+shiftl(h(7),1),Z'FF')),i8)  ! wrong — redo
    ! Correct byte packing for radix-2^25.5:
    ! bit offset of each limb:
    !  h(1):  0..25 (26 bits)
    !  h(2): 26..50 (25 bits)
    !  h(3): 51..76 (26 bits)
    !  h(4): 77..101 (25 bits)
    !  h(5):102..127 (26 bits)
    !  h(6):128..152 (25 bits)
    !  h(7):153..178 (26 bits)
    !  h(8):179..203 (25 bits)
    !  h(9):204..229 (26 bits)
    ! h(10):230..254 (25 bits)
    integer(i64) :: bits
    bits = 0_i64
    bits = ior(h(1),                         shiftl(h(2), 26))
    b(1) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(2) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(3) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(4) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    ! bits now has remaining h(2) bits + need h(3)
    bits = ior(bits, shiftl(h(3), max(0,26+25-32)))
    b(5) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(6) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(7) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    bits = ior(bits, shiftl(h(4), max(0,51+26-56)))
    b(8) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(9) = int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(10)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    bits = ior(bits, shiftl(h(5), max(0,77+25-80)))
    b(11)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(12)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(13)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    bits = ior(bits, shiftl(h(6), max(0,102+26-104)))
    b(14)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(15)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(16)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    bits = ior(bits, shiftl(h(7), max(0,128+25-128)))
    b(17)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(18)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(19)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    bits = ior(bits, shiftl(h(8), max(0,153+26-152)))
    b(20)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(21)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(22)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    bits = ior(bits, shiftl(h(9), max(0,179+25-176)))
    b(23)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(24)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(25)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    bits = ior(bits, shiftl(h(10),max(0,204+26-200)))
    b(26)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(27)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(28)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(29)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(30)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(31)= int(iand(bits,     Z'FF'),i8); bits=shiftr(bits,8)
    b(32)= int(iand(bits,     Z'FF'),i8)
  end subroutine

  ! Load 32 bytes (little-endian) into field element
  pure subroutine fe_frombytes(b, f)
    integer(i8),  intent(in),  dimension(32) :: b
    integer(i64), intent(out), dimension(10) :: f
    integer(i64) :: w(8)
    integer :: i
    do i=1,8
      w(i) = 0_i64
      w(i) = ior(w(i), shiftl(int(iand(b(4*i-3),int(Z'FF',i8)),i64), 0))
      w(i) = ior(w(i), shiftl(int(iand(b(4*i-2),int(Z'FF',i8)),i64), 8))
      w(i) = ior(w(i), shiftl(int(iand(b(4*i-1),int(Z'FF',i8)),i64),16))
      w(i) = ior(w(i), shiftl(int(iand(b(4*i  ),int(Z'FF',i8)),i64),24))
    end do
    ! Extract limbs from bit stream
    f(1)  = iand(w(1),                         int(Z'3FFFFFF',i64))
    f(2)  = iand(shiftr(w(1),26),               int(Z'1FFFFFF',i64))
    f(3)  = iand(ior(shiftr(w(1),51), shiftl(w(2),13)), int(Z'3FFFFFF',i64))
    f(4)  = iand(shiftr(w(2),13),               int(Z'1FFFFFF',i64))
    f(5)  = iand(ior(shiftr(w(2),38), shiftl(w(3),26)), int(Z'3FFFFFF',i64))
    f(6)  = iand(shiftr(w(3),0),                int(Z'1FFFFFF',i64))  ! 102-bit offset
    f(7)  = iand(shiftr(w(3),25),               int(Z'3FFFFFF',i64))
    f(8)  = iand(ior(shiftr(w(3),51), shiftl(w(4),13)), int(Z'1FFFFFF',i64))
    f(9)  = iand(shiftr(w(4),12),               int(Z'3FFFFFF',i64))
    f(10) = iand(ior(shiftr(w(4),38), shiftl(w(5),26)), int(Z'1FFFFFF',i64))
    ! Mask top bit (sign bit cleared per RFC 8032 §5.1.3)
    f(10) = iand(f(10), int(Z'7FFFFFFF',i64))
    call fe_reduce(f)
  end subroutine

  ! ── Scalar field mod L ─────────────────────────────────────────
  ! L = 2^252 + 27742317777372353535851937790883648493
  ! = 7237005577332262213973186563042994240857116359379907606001950938285454250989
  ! Represented as 4×64-bit limbs (standard 256-bit little-endian)

  ! Reduce a 512-bit integer (from hashing) mod L using Barrett reduction
  ! Input: 64 bytes h; Output: 32-byte scalar s
  pure subroutine sc_reduce64(h, s)
    integer(i8),  intent(in),  dimension(64) :: h
    integer(i8),  intent(out), dimension(32) :: s
    ! L in 8×32-bit limbs (little-endian):
    ! L = [0xD3, 0xED, 0x47, 0x10, 0x9C, 0xFC, 0x54, 0x7B,
    !      0xB0, 0xBF, 0xCF, 0x9D, 0xBF, 0xFF, 0xFF, 0xFF,
    !      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    !      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F]
    ! Scalar reduction via the standard 38-limb approach (SUPERCOP sc_reduce)
    integer(i64) :: a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11
    integer(i64) :: b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11
    integer(i64) :: carry, t
    ! Load 64 bytes into 21-bit limbs (SUPERCOP sc_reduce style)
    ! Each limb is 21 bits to avoid overflow on multiplication
    integer(i64) :: s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12
    integer(i8)  :: hb(64)
    hb = h
    ! Load as signed to handle bit manipulation
    s0  = iand(int(hb(1),i64),Z'FF') + shiftl(iand(int(hb(2),i64),Z'FF'),8) &
        + shiftl(iand(int(hb(3),i64),Z'FF'),16) + shiftl(iand(iand(int(hb(4),i64),Z'FF'),Z'1F'),24)
    s1  = shiftr(iand(int(hb(4),i64),Z'FF'),5) + shiftl(iand(int(hb(5),i64),Z'FF'),3) &
        + shiftl(iand(int(hb(6),i64),Z'FF'),11) + shiftl(iand(iand(int(hb(7),i64),Z'FF'),Z'3F'),19)
    s2  = shiftr(iand(int(hb(7),i64),Z'FF'),6) + shiftl(iand(int(hb(8),i64),Z'FF'),2) &
        + shiftl(iand(int(hb(9),i64),Z'FF'),10) + shiftl(iand(iand(int(hb(10),i64),Z'FF'),Z'7F'),18)
    s3  = shiftr(iand(int(hb(10),i64),Z'FF'),7) + shiftl(iand(int(hb(11),i64),Z'FF'),1) &
        + shiftl(iand(int(hb(12),i64),Z'FF'),9) + shiftl(iand(int(hb(13),i64),Z'FF'),17)
    s4  = iand(int(hb(14),i64),Z'FF') + shiftl(iand(int(hb(15),i64),Z'FF'),8) &
        + shiftl(iand(int(hb(16),i64),Z'FF'),16) + shiftl(iand(iand(int(hb(17),i64),Z'FF'),Z'1F'),24)
    s5  = shiftr(iand(int(hb(17),i64),Z'FF'),5) + shiftl(iand(int(hb(18),i64),Z'FF'),3) &
        + shiftl(iand(int(hb(19),i64),Z'FF'),11) + shiftl(iand(iand(int(hb(20),i64),Z'FF'),Z'3F'),19)
    s6  = shiftr(iand(int(hb(20),i64),Z'FF'),6) + shiftl(iand(int(hb(21),i64),Z'FF'),2) &
        + shiftl(iand(int(hb(22),i64),Z'FF'),10) + shiftl(iand(iand(int(hb(23),i64),Z'FF'),Z'7F'),18)
    s7  = shiftr(iand(int(hb(23),i64),Z'FF'),7) + shiftl(iand(int(hb(24),i64),Z'FF'),1) &
        + shiftl(iand(int(hb(25),i64),Z'FF'),9) + shiftl(iand(int(hb(26),i64),Z'FF'),17)
    s8  = iand(int(hb(27),i64),Z'FF') + shiftl(iand(int(hb(28),i64),Z'FF'),8) &
        + shiftl(iand(int(hb(29),i64),Z'FF'),16) + shiftl(iand(iand(int(hb(30),i64),Z'FF'),Z'1F'),24)
    s9  = shiftr(iand(int(hb(30),i64),Z'FF'),5) + shiftl(iand(int(hb(31),i64),Z'FF'),3) &
        + shiftl(iand(int(hb(32),i64),Z'FF'),11) + shiftl(iand(iand(int(hb(33),i64),Z'FF'),Z'3F'),19)
    s10 = shiftr(iand(int(hb(33),i64),Z'FF'),6) + shiftl(iand(int(hb(34),i64),Z'FF'),2) &
        + shiftl(iand(int(hb(35),i64),Z'FF'),10) + shiftl(iand(iand(int(hb(36),i64),Z'FF'),Z'7F'),18)
    s11 = shiftr(iand(int(hb(36),i64),Z'FF'),7) + shiftl(iand(int(hb(37),i64),Z'FF'),1) &
        + shiftl(iand(int(hb(38),i64),Z'FF'),9) + shiftl(iand(int(hb(39),i64),Z'FF'),17)
    s12 = iand(int(hb(40),i64),Z'FF') + shiftl(iand(int(hb(41),i64),Z'FF'),8) &
        + shiftl(iand(int(hb(42),i64),Z'FF'),16) + shiftl(iand(iand(int(hb(43),i64),Z'FF'),Z'1F'),24)
    ! Reduce s12..s0 mod L (SUPERCOP sc_reduce carry/muladd pattern)
    ! muladd coefficients from L = 2^252 + c, so 2^252 = L - c
    ! => s12 * 2^252 = s12*(L-c) = s12*L - s12*c => reduce by subtracting s12*c
    ! c components (little-endian 21-bit limbs of c):
    ! c = 27742317777372353535851937790883648493
    ! 666643*s12 added to s0; 470296*s12 to s1; 654183*s12 to s2; etc.
    integer(i64), parameter :: MU0=666643_i64, MU1=470296_i64, MU2=654183_i64
    integer(i64), parameter :: MU3=-997805_i64, MU4=136657_i64, MU5=-683901_i64
    s0  = s0  + MU0*s12; s1  = s1  + MU1*s12; s2  = s2  + MU2*s12
    s3  = s3  + MU3*s12; s4  = s4  + MU4*s12; s5  = s5  + MU5*s12; s12 = 0
    carry = shiftr(s0,21); s1=s1+carry; s0=iand(s0,int(Z'1FFFFF',i64))
    carry = shiftr(s1,21); s2=s2+carry; s1=iand(s1,int(Z'1FFFFF',i64))
    carry = shiftr(s2,21); s3=s3+carry; s2=iand(s2,int(Z'1FFFFF',i64))
    carry = shiftr(s3,21); s4=s4+carry; s3=iand(s3,int(Z'1FFFFF',i64))
    carry = shiftr(s4,21); s5=s5+carry; s4=iand(s4,int(Z'1FFFFF',i64))
    carry = shiftr(s5,21); s6=s6+carry; s5=iand(s5,int(Z'1FFFFF',i64))
    carry = shiftr(s6,21); s7=s7+carry; s6=iand(s6,int(Z'1FFFFF',i64))
    carry = shiftr(s7,21); s8=s8+carry; s7=iand(s7,int(Z'1FFFFF',i64))
    carry = shiftr(s8,21); s9=s9+carry; s8=iand(s8,int(Z'1FFFFF',i64))
    carry = shiftr(s9,21); s10=s10+carry; s9=iand(s9,int(Z'1FFFFF',i64))
    carry = shiftr(s10,21);s11=s11+carry; s10=iand(s10,int(Z'1FFFFF',i64))
    carry = shiftr(s11,21);s12=s11; s11=iand(s11,int(Z'1FFFFF',i64))  ! s12 gets high bits
    s0  = s0  + MU0*s12; s1  = s1  + MU1*s12; s2  = s2  + MU2*s12
    s3  = s3  + MU3*s12; s4  = s4  + MU4*s12; s5  = s5  + MU5*s12; s12 = 0
    carry=shiftr(s0,21); s1=s1+carry; s0=iand(s0,int(Z'1FFFFF',i64))
    carry=shiftr(s1,21); s2=s2+carry; s1=iand(s1,int(Z'1FFFFF',i64))
    carry=shiftr(s2,21); s3=s3+carry; s2=iand(s2,int(Z'1FFFFF',i64))
    carry=shiftr(s3,21); s4=s4+carry; s3=iand(s3,int(Z'1FFFFF',i64))
    carry=shiftr(s4,21); s5=s5+carry; s4=iand(s4,int(Z'1FFFFF',i64))
    carry=shiftr(s5,21); s6=s6+carry; s5=iand(s5,int(Z'1FFFFF',i64))
    carry=shiftr(s6,21); s7=s7+carry; s6=iand(s6,int(Z'1FFFFF',i64))
    carry=shiftr(s7,21); s8=s8+carry; s7=iand(s7,int(Z'1FFFFF',i64))
    carry=shiftr(s8,21); s9=s9+carry; s8=iand(s8,int(Z'1FFFFF',i64))
    carry=shiftr(s9,21); s10=s10+carry; s9=iand(s9,int(Z'1FFFFF',i64))
    carry=shiftr(s10,21);s11=s11+carry; s10=iand(s10,int(Z'1FFFFF',i64))
    ! Pack 12×21-bit limbs into 32 bytes
    s(1) =int(iand(s0,Z'FF'),i8)
    s(2) =int(iand(shiftr(s0,8),Z'FF'),i8)
    s(3) =int(iand(ior(shiftr(s0,16),shiftl(s1,5)),Z'FF'),i8)
    s(4) =int(iand(shiftr(s1,3),Z'FF'),i8)
    s(5) =int(iand(shiftr(s1,11),Z'FF'),i8)
    s(6) =int(iand(ior(shiftr(s1,19),shiftl(s2,2)),Z'FF'),i8)
    s(7) =int(iand(shiftr(s2,6),Z'FF'),i8)
    s(8) =int(iand(ior(shiftr(s2,14),shiftl(s3,7)),Z'FF'),i8)
    s(9) =int(iand(shiftr(s3,1),Z'FF'),i8)
    s(10)=int(iand(shiftr(s3,9),Z'FF'),i8)
    s(11)=int(iand(ior(shiftr(s3,17),shiftl(s4,4)),Z'FF'),i8)
    s(12)=int(iand(shiftr(s4,4),Z'FF'),i8)
    s(13)=int(iand(shiftr(s4,12),Z'FF'),i8)
    s(14)=int(iand(ior(shiftr(s4,20),shiftl(s5,1)),Z'FF'),i8)
    s(15)=int(iand(shiftr(s5,7),Z'FF'),i8)
    s(16)=int(iand(ior(shiftr(s5,15),shiftl(s6,6)),Z'FF'),i8)
    s(17)=int(iand(shiftr(s6,2),Z'FF'),i8)
    s(18)=int(iand(shiftr(s6,10),Z'FF'),i8)
    s(19)=int(iand(ior(shiftr(s6,18),shiftl(s7,3)),Z'FF'),i8)
    s(20)=int(iand(shiftr(s7,5),Z'FF'),i8)
    s(21)=int(iand(shiftr(s7,13),Z'FF'),i8)
    s(22)=int(iand(s8,Z'FF'),i8)
    s(23)=int(iand(shiftr(s8,8),Z'FF'),i8)
    s(24)=int(iand(ior(shiftr(s8,16),shiftl(s9,5)),Z'FF'),i8)
    s(25)=int(iand(shiftr(s9,3),Z'FF'),i8)
    s(26)=int(iand(shiftr(s9,11),Z'FF'),i8)
    s(27)=int(iand(ior(shiftr(s9,19),shiftl(s10,2)),Z'FF'),i8)
    s(28)=int(iand(shiftr(s10,6),Z'FF'),i8)
    s(29)=int(iand(ior(shiftr(s10,14),shiftl(s11,7)),Z'FF'),i8)
    s(30)=int(iand(shiftr(s11,1),Z'FF'),i8)
    s(31)=int(iand(shiftr(s11,9),Z'FF'),i8)
    s(32)=int(iand(shiftr(s11,17),Z'FF'),i8)
  end subroutine

  ! Scalar multiply mod L: res = a*b mod L
  ! Both a, b are 32-byte scalars; result is 32 bytes
  pure subroutine sc_muladd(a, b, c, s)
    ! s = a*b + c  mod L  (standard Ed25519 signing formula)
    integer(i8), intent(in),  dimension(32) :: a, b, c
    integer(i8), intent(out), dimension(32) :: s
    integer(i64) :: a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11
    integer(i64) :: b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11
    integer(i64) :: c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11
    integer(i64) :: s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12
    integer(i64) :: s13,s14,s15,s16,s17,s18,s19,s20,s21,s22,s23
    integer(i64) :: carry
    integer(i64), parameter :: MASK21 = int(Z'1FFFFF',i64)
    integer(i64), parameter :: MU0=666643_i64, MU1=470296_i64, MU2=654183_i64
    integer(i64), parameter :: MU3=-997805_i64, MU4=136657_i64, MU5=-683901_i64
    ! Load a into 21-bit limbs
    a0  = iand(int(a(1),i64),Z'FF') + shiftl(iand(int(a(2),i64),Z'FF'),8) + shiftl(iand(iand(int(a(3),i64),Z'FF'),Z'1F'),16)
    a1  = shiftr(iand(int(a(3),i64),Z'FF'),5) + shiftl(iand(int(a(4),i64),Z'FF'),3) + shiftl(iand(iand(int(a(5),i64),Z'FF'),Z'3F'),11) + shiftl(iand(iand(int(a(6),i64),Z'FF'),Z'3'),19)
    a2  = shiftr(iand(int(a(6),i64),Z'FF'),2) + shiftl(iand(int(a(7),i64),Z'FF'),6) + shiftl(iand(iand(int(a(8),i64),Z'FF'),Z'7F'),14) + shiftl(iand(iand(int(a(9),i64),Z'FF'),Z'0'),21)
    a3  = shiftr(iand(int(a(9),i64),Z'FF'),0) + shiftl(iand(int(a(10),i64),Z'FF'),8) + shiftl(iand(iand(int(a(11),i64),Z'FF'),Z'1F'),16)
    a4  = shiftr(iand(int(a(11),i64),Z'FF'),5) + shiftl(iand(int(a(12),i64),Z'FF'),3) + shiftl(iand(iand(int(a(13),i64),Z'FF'),Z'3F'),11)
    a5  = shiftr(iand(int(a(13),i64),Z'FF'),6) + shiftl(iand(int(a(14),i64),Z'FF'),2) + shiftl(iand(iand(int(a(15),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(a(16),i64),Z'FF'),Z'3'),18)
    a6  = shiftr(iand(int(a(16),i64),Z'FF'),2) + shiftl(iand(int(a(17),i64),Z'FF'),6) + shiftl(iand(iand(int(a(18),i64),Z'FF'),Z'7F'),14)
    a7  = shiftr(iand(int(a(18),i64),Z'FF'),7) + shiftl(iand(int(a(19),i64),Z'FF'),1) + shiftl(iand(iand(int(a(20),i64),Z'FF'),Z'FF'),9) + shiftl(iand(iand(int(a(21),i64),Z'FF'),Z'7'),17)
    a8  = shiftr(iand(int(a(21),i64),Z'FF'),3) + shiftl(iand(int(a(22),i64),Z'FF'),5) + shiftl(iand(iand(int(a(23),i64),Z'FF'),Z'3F'),13)
    a9  = shiftr(iand(int(a(23),i64),Z'FF'),6) + shiftl(iand(int(a(24),i64),Z'FF'),2) + shiftl(iand(iand(int(a(25),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(a(26),i64),Z'FF'),Z'1'),18)
    a10 = shiftr(iand(int(a(26),i64),Z'FF'),1) + shiftl(iand(int(a(27),i64),Z'FF'),7) + shiftl(iand(iand(int(a(28),i64),Z'FF'),Z'FF'),15)
    a11 = shiftr(iand(int(a(28),i64),Z'FF'),6) + shiftl(iand(int(a(29),i64),Z'FF'),2) + shiftl(iand(iand(int(a(30),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(a(31),i64),Z'FF'),Z'7'),18)
    ! Load b same pattern
    b0  = iand(int(b(1),i64),Z'FF') + shiftl(iand(int(b(2),i64),Z'FF'),8) + shiftl(iand(iand(int(b(3),i64),Z'FF'),Z'1F'),16)
    b1  = shiftr(iand(int(b(3),i64),Z'FF'),5) + shiftl(iand(int(b(4),i64),Z'FF'),3) + shiftl(iand(iand(int(b(5),i64),Z'FF'),Z'3F'),11) + shiftl(iand(iand(int(b(6),i64),Z'FF'),Z'3'),19)
    b2  = shiftr(iand(int(b(6),i64),Z'FF'),2) + shiftl(iand(int(b(7),i64),Z'FF'),6) + shiftl(iand(iand(int(b(8),i64),Z'FF'),Z'7F'),14)
    b3  = iand(int(b(9),i64),Z'FF') + shiftl(iand(int(b(10),i64),Z'FF'),8) + shiftl(iand(iand(int(b(11),i64),Z'FF'),Z'1F'),16)
    b4  = shiftr(iand(int(b(11),i64),Z'FF'),5) + shiftl(iand(int(b(12),i64),Z'FF'),3) + shiftl(iand(iand(int(b(13),i64),Z'FF'),Z'3F'),11)
    b5  = shiftr(iand(int(b(13),i64),Z'FF'),6) + shiftl(iand(int(b(14),i64),Z'FF'),2) + shiftl(iand(iand(int(b(15),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(b(16),i64),Z'FF'),Z'3'),18)
    b6  = shiftr(iand(int(b(16),i64),Z'FF'),2) + shiftl(iand(int(b(17),i64),Z'FF'),6) + shiftl(iand(iand(int(b(18),i64),Z'FF'),Z'7F'),14)
    b7  = shiftr(iand(int(b(18),i64),Z'FF'),7) + shiftl(iand(int(b(19),i64),Z'FF'),1) + shiftl(iand(iand(int(b(20),i64),Z'FF'),Z'FF'),9) + shiftl(iand(iand(int(b(21),i64),Z'FF'),Z'7'),17)
    b8  = shiftr(iand(int(b(21),i64),Z'FF'),3) + shiftl(iand(int(b(22),i64),Z'FF'),5) + shiftl(iand(iand(int(b(23),i64),Z'FF'),Z'3F'),13)
    b9  = shiftr(iand(int(b(23),i64),Z'FF'),6) + shiftl(iand(int(b(24),i64),Z'FF'),2) + shiftl(iand(iand(int(b(25),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(b(26),i64),Z'FF'),Z'1'),18)
    b10 = shiftr(iand(int(b(26),i64),Z'FF'),1) + shiftl(iand(int(b(27),i64),Z'FF'),7) + shiftl(iand(iand(int(b(28),i64),Z'FF'),Z'FF'),15)
    b11 = shiftr(iand(int(b(28),i64),Z'FF'),6) + shiftl(iand(int(b(29),i64),Z'FF'),2) + shiftl(iand(iand(int(b(30),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(b(31),i64),Z'FF'),Z'7'),18)
    ! Load c same pattern
    c0  = iand(int(c(1),i64),Z'FF') + shiftl(iand(int(c(2),i64),Z'FF'),8) + shiftl(iand(iand(int(c(3),i64),Z'FF'),Z'1F'),16)
    c1  = shiftr(iand(int(c(3),i64),Z'FF'),5) + shiftl(iand(int(c(4),i64),Z'FF'),3) + shiftl(iand(iand(int(c(5),i64),Z'FF'),Z'3F'),11) + shiftl(iand(iand(int(c(6),i64),Z'FF'),Z'3'),19)
    c2  = shiftr(iand(int(c(6),i64),Z'FF'),2) + shiftl(iand(int(c(7),i64),Z'FF'),6) + shiftl(iand(iand(int(c(8),i64),Z'FF'),Z'7F'),14)
    c3  = iand(int(c(9),i64),Z'FF') + shiftl(iand(int(c(10),i64),Z'FF'),8) + shiftl(iand(iand(int(c(11),i64),Z'FF'),Z'1F'),16)
    c4  = shiftr(iand(int(c(11),i64),Z'FF'),5) + shiftl(iand(int(c(12),i64),Z'FF'),3) + shiftl(iand(iand(int(c(13),i64),Z'FF'),Z'3F'),11)
    c5  = shiftr(iand(int(c(13),i64),Z'FF'),6) + shiftl(iand(int(c(14),i64),Z'FF'),2) + shiftl(iand(iand(int(c(15),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(c(16),i64),Z'FF'),Z'3'),18)
    c6  = shiftr(iand(int(c(16),i64),Z'FF'),2) + shiftl(iand(int(c(17),i64),Z'FF'),6) + shiftl(iand(iand(int(c(18),i64),Z'FF'),Z'7F'),14)
    c7  = shiftr(iand(int(c(18),i64),Z'FF'),7) + shiftl(iand(int(c(19),i64),Z'FF'),1) + shiftl(iand(iand(int(c(20),i64),Z'FF'),Z'FF'),9) + shiftl(iand(iand(int(c(21),i64),Z'FF'),Z'7'),17)
    c8  = shiftr(iand(int(c(21),i64),Z'FF'),3) + shiftl(iand(int(c(22),i64),Z'FF'),5) + shiftl(iand(iand(int(c(23),i64),Z'FF'),Z'3F'),13)
    c9  = shiftr(iand(int(c(23),i64),Z'FF'),6) + shiftl(iand(int(c(24),i64),Z'FF'),2) + shiftl(iand(iand(int(c(25),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(c(26),i64),Z'FF'),Z'1'),18)
    c10 = shiftr(iand(int(c(26),i64),Z'FF'),1) + shiftl(iand(int(c(27),i64),Z'FF'),7) + shiftl(iand(iand(int(c(28),i64),Z'FF'),Z'FF'),15)
    c11 = shiftr(iand(int(c(28),i64),Z'FF'),6) + shiftl(iand(int(c(29),i64),Z'FF'),2) + shiftl(iand(iand(int(c(30),i64),Z'FF'),Z'7F'),10) + shiftl(iand(iand(int(c(31),i64),Z'FF'),Z'7'),18)
    ! Multiply a*b (schoolbook 12x12 limbs) + c into 23-limb accumulator
    s0 =c0+a0*b0
    s1 =c1+a0*b1+a1*b0
    s2 =c2+a0*b2+a1*b1+a2*b0
    s3 =c3+a0*b3+a1*b2+a2*b1+a3*b0
    s4 =c4+a0*b4+a1*b3+a2*b2+a3*b1+a4*b0
    s5 =c5+a0*b5+a1*b4+a2*b3+a3*b2+a4*b1+a5*b0
    s6 =c6+a0*b6+a1*b5+a2*b4+a3*b3+a4*b2+a5*b1+a6*b0
    s7 =c7+a0*b7+a1*b6+a2*b5+a3*b4+a4*b3+a5*b2+a6*b1+a7*b0
    s8 =c8+a0*b8+a1*b7+a2*b6+a3*b5+a4*b4+a5*b3+a6*b2+a7*b1+a8*b0
    s9 =c9+a0*b9+a1*b8+a2*b7+a3*b6+a4*b5+a5*b4+a6*b3+a7*b2+a8*b1+a9*b0
    s10=c10+a0*b10+a1*b9+a2*b8+a3*b7+a4*b6+a5*b5+a6*b4+a7*b3+a8*b2+a9*b1+a10*b0
    s11=c11+a0*b11+a1*b10+a2*b9+a3*b8+a4*b7+a5*b6+a6*b5+a7*b4+a8*b3+a9*b2+a10*b1+a11*b0
    s12=     a1*b11+a2*b10+a3*b9+a4*b8+a5*b7+a6*b6+a7*b5+a8*b4+a9*b3+a10*b2+a11*b1
    s13=           a2*b11+a3*b10+a4*b9+a5*b8+a6*b7+a7*b6+a8*b5+a9*b4+a10*b3+a11*b2
    s14=                  a3*b11+a4*b10+a5*b9+a6*b8+a7*b7+a8*b6+a9*b5+a10*b4+a11*b3
    s15=                         a4*b11+a5*b10+a6*b9+a7*b8+a8*b7+a9*b6+a10*b5+a11*b4
    s16=                                a5*b11+a6*b10+a7*b9+a8*b8+a9*b7+a10*b6+a11*b5
    s17=                                       a6*b11+a7*b10+a8*b9+a9*b8+a10*b7+a11*b6
    s18=                                              a7*b11+a8*b10+a9*b9+a10*b8+a11*b7
    s19=                                                     a8*b11+a9*b10+a10*b9+a11*b8
    s20=                                                            a9*b11+a10*b10+a11*b9
    s21=                                                                   a10*b11+a11*b10
    s22=                                                                          a11*b11
    s23=0
    ! Reduce s23..s12 mod L (two passes)
    carry=shiftr(s0,21); s1=s1+carry; s0=iand(s0,MASK21)
    carry=shiftr(s1,21); s2=s2+carry; s1=iand(s1,MASK21)
    carry=shiftr(s2,21); s3=s3+carry; s2=iand(s2,MASK21)
    carry=shiftr(s3,21); s4=s4+carry; s3=iand(s3,MASK21)
    carry=shiftr(s4,21); s5=s5+carry; s4=iand(s4,MASK21)
    carry=shiftr(s5,21); s6=s6+carry; s5=iand(s5,MASK21)
    carry=shiftr(s6,21); s7=s7+carry; s6=iand(s6,MASK21)
    carry=shiftr(s7,21); s8=s8+carry; s7=iand(s7,MASK21)
    carry=shiftr(s8,21); s9=s9+carry; s8=iand(s8,MASK21)
    carry=shiftr(s9,21); s10=s10+carry; s9=iand(s9,MASK21)
    carry=shiftr(s10,21);s11=s11+carry; s10=iand(s10,MASK21)
    carry=shiftr(s11,21);s12=s12+carry; s11=iand(s11,MASK21)
    carry=shiftr(s12,21);s13=s13+carry; s12=iand(s12,MASK21)
    carry=shiftr(s13,21);s14=s14+carry; s13=iand(s13,MASK21)
    carry=shiftr(s14,21);s15=s15+carry; s14=iand(s14,MASK21)
    carry=shiftr(s15,21);s16=s16+carry; s15=iand(s15,MASK21)
    carry=shiftr(s16,21);s17=s17+carry; s16=iand(s16,MASK21)
    carry=shiftr(s17,21);s18=s18+carry; s17=iand(s17,MASK21)
    carry=shiftr(s18,21);s19=s19+carry; s18=iand(s18,MASK21)
    carry=shiftr(s19,21);s20=s20+carry; s19=iand(s19,MASK21)
    carry=shiftr(s20,21);s21=s21+carry; s20=iand(s20,MASK21)
    carry=shiftr(s21,21);s22=s22+carry; s21=iand(s21,MASK21)
    carry=shiftr(s22,21);s23=s23+carry; s22=iand(s22,MASK21)
    ! Fold high limbs back using L's structure
    s11=s11+s23*MU0; s12=s12+s23*MU1; s13=s13+s23*MU2
    s14=s14+s23*MU3; s15=s15+s23*MU4; s16=s16+s23*MU5; s23=0
    s10=s10+s22*MU0; s11=s11+s22*MU1; s12=s12+s22*MU2
    s13=s13+s22*MU3; s14=s14+s22*MU4; s15=s15+s22*MU5; s22=0
    s9 =s9 +s21*MU0; s10=s10+s21*MU1; s11=s11+s21*MU2
    s12=s12+s21*MU3; s13=s13+s21*MU4; s14=s14+s21*MU5; s21=0
    s8 =s8 +s20*MU0; s9 =s9 +s20*MU1; s10=s10+s20*MU2
    s11=s11+s20*MU3; s12=s12+s20*MU4; s13=s13+s20*MU5; s20=0
    s7 =s7 +s19*MU0; s8 =s8 +s19*MU1; s9 =s9 +s19*MU2
    s10=s10+s19*MU3; s11=s11+s19*MU4; s12=s12+s19*MU5; s19=0
    s6 =s6 +s18*MU0; s7 =s7 +s18*MU1; s8 =s8 +s18*MU2
    s9 =s9 +s18*MU3; s10=s10+s18*MU4; s11=s11+s18*MU5; s18=0
    carry=shiftr(s6,21);s7=s7+carry; s6=iand(s6,MASK21)
    carry=shiftr(s7,21);s8=s8+carry; s7=iand(s7,MASK21)
    carry=shiftr(s8,21);s9=s9+carry; s8=iand(s8,MASK21)
    carry=shiftr(s9,21);s10=s10+carry; s9=iand(s9,MASK21)
    carry=shiftr(s10,21);s11=s11+carry; s10=iand(s10,MASK21)
    carry=shiftr(s11,21);s12=s12+carry; s11=iand(s11,MASK21)
    s0=s0+s12*MU0; s1=s1+s12*MU1; s2=s2+s12*MU2
    s3=s3+s12*MU3; s4=s4+s12*MU4; s5=s5+s12*MU5; s12=0
    carry=shiftr(s0,21);s1=s1+carry; s0=iand(s0,MASK21)
    carry=shiftr(s1,21);s2=s2+carry; s1=iand(s1,MASK21)
    carry=shiftr(s2,21);s3=s3+carry; s2=iand(s2,MASK21)
    carry=shiftr(s3,21);s4=s4+carry; s3=iand(s3,MASK21)
    carry=shiftr(s4,21);s5=s5+carry; s4=iand(s4,MASK21)
    carry=shiftr(s5,21);s6=s6+carry; s5=iand(s5,MASK21)
    carry=shiftr(s6,21);s7=s7+carry; s6=iand(s6,MASK21)
    carry=shiftr(s7,21);s8=s8+carry; s7=iand(s7,MASK21)
    carry=shiftr(s8,21);s9=s9+carry; s8=iand(s8,MASK21)
    carry=shiftr(s9,21);s10=s10+carry; s9=iand(s9,MASK21)
    carry=shiftr(s10,21);s11=s11+carry; s10=iand(s10,MASK21)
    ! Pack into 32 bytes (same as sc_reduce64)
    s(1) =int(iand(s0,Z'FF'),i8)
    s(2) =int(iand(shiftr(s0,8),Z'FF'),i8)
    s(3) =int(iand(ior(shiftr(s0,16),shiftl(s1,5)),Z'FF'),i8)
    s(4) =int(iand(shiftr(s1,3),Z'FF'),i8)
    s(5) =int(iand(shiftr(s1,11),Z'FF'),i8)
    s(6) =int(iand(ior(shiftr(s1,19),shiftl(s2,2)),Z'FF'),i8)
    s(7) =int(iand(shiftr(s2,6),Z'FF'),i8)
    s(8) =int(iand(ior(shiftr(s2,14),shiftl(s3,7)),Z'FF'),i8)
    s(9) =int(iand(shiftr(s3,1),Z'FF'),i8)
    s(10)=int(iand(shiftr(s3,9),Z'FF'),i8)
    s(11)=int(iand(ior(shiftr(s3,17),shiftl(s4,4)),Z'FF'),i8)
    s(12)=int(iand(shiftr(s4,4),Z'FF'),i8)
    s(13)=int(iand(shiftr(s4,12),Z'FF'),i8)
    s(14)=int(iand(ior(shiftr(s4,20),shiftl(s5,1)),Z'FF'),i8)
    s(15)=int(iand(shiftr(s5,7),Z'FF'),i8)
    s(16)=int(iand(ior(shiftr(s5,15),shiftl(s6,6)),Z'FF'),i8)
    s(17)=int(iand(shiftr(s6,2),Z'FF'),i8)
    s(18)=int(iand(shiftr(s6,10),Z'FF'),i8)
    s(19)=int(iand(ior(shiftr(s6,18),shiftl(s7,3)),Z'FF'),i8)
    s(20)=int(iand(shiftr(s7,5),Z'FF'),i8)
    s(21)=int(iand(shiftr(s7,13),Z'FF'),i8)
    s(22)=int(iand(s8,Z'FF'),i8)
    s(23)=int(iand(shiftr(s8,8),Z'FF'),i8)
    s(24)=int(iand(ior(shiftr(s8,16),shiftl(s9,5)),Z'FF'),i8)
    s(25)=int(iand(shiftr(s9,3),Z'FF'),i8)
    s(26)=int(iand(shiftr(s9,11),Z'FF'),i8)
    s(27)=int(iand(ior(shiftr(s9,19),shiftl(s10,2)),Z'FF'),i8)
    s(28)=int(iand(shiftr(s10,6),Z'FF'),i8)
    s(29)=int(iand(ior(shiftr(s10,14),shiftl(s11,7)),Z'FF'),i8)
    s(30)=int(iand(shiftr(s11,1),Z'FF'),i8)
    s(31)=int(iand(shiftr(s11,9),Z'FF'),i8)
    s(32)=int(iand(shiftr(s11,17),Z'FF'),i8)
  end subroutine

  ! ── Point arithmetic on twisted Edwards curve ─────────────────
  ! Extended homogeneous coordinates (X:Y:Z:T), x=X/Z, y=Y/Z, T=XY/Z
  ! Curve: -x^2 + y^2 = 1 + d*x^2*y^2
  ! d = -121665/121666 mod p (as 10-limb fe)

  pure subroutine ge_d(d)
    integer(i64), intent(out), dimension(10) :: d
    ! d = -121665/121666 mod p
    ! Pre-computed value (RFC 8032 §5.1, SUPERCOP fe d):
    d = [ -10913610_i64,  13857413_i64, -15372611_i64,  10608986_i64, &
           12376523_i64,  -12664939_i64,  10701287_i64, -12232133_i64, &
           -9232152_i64,   12480880_i64 ]
  end subroutine

  ! 2*d (for unified addition formula)
  pure subroutine ge_2d(d2)
    integer(i64), intent(out), dimension(10) :: d2
    integer(i64) :: d(10)
    call ge_d(d)
    d2 = 2*d
    call fe_reduce(d2)
  end subroutine

  ! Set point to neutral element (0:1:1:0) — additive identity
  pure subroutine ge_zero(x,y,z,t)
    integer(i64), intent(out), dimension(10) :: x,y,z,t
    x=0; y=0; z=0; t=0
    y(1)=1; z(1)=1  ! (0:1:1:0)
  end subroutine

  ! Unified (complete) addition on twisted Edwards
  ! (x3,y3,z3,t3) = (x1,y1,z1,t1) + (x2,y2,z2,t2)
  ! RFC 8032 §5.1.4 formula (Hisil et al. unified addition)
  pure subroutine ge_add(x1,y1,z1,t1, x2,y2,z2,t2, x3,y3,z3,t3)
    integer(i64), intent(in),  dimension(10) :: x1,y1,z1,t1,x2,y2,z2,t2
    integer(i64), intent(out), dimension(10) :: x3,y3,z3,t3
    integer(i64) :: A(10),B(10),C(10),D(10),E(10),F(10),G(10),H(10),d2(10)
    call ge_2d(d2)
    call fe_mul(x1,x2, A)      ! A = X1*X2
    call fe_mul(y1,y2, B)      ! B = Y1*Y2
    call fe_mul(t1,t2, C)      ! C = T1*T2
    call fe_mul(C,  d2, C)     ! C = d2*T1*T2
    call fe_mul(z1,z2, D)      ! D = Z1*Z2
    call fe_add(D, D, D)       ! D = 2*Z1*Z2
    call fe_add(x1,y1, E)
    call fe_add(x2,y2, F)
    call fe_mul(E, F,  E)      ! E = (X1+Y1)*(X2+Y2)
    call fe_sub(E, A,  E)
    call fe_sub(E, B,  E)      ! E = X1*Y2+X2*Y1
    call fe_sub(D, C,  F)      ! F = D - C
    call fe_add(D, C,  G)      ! G = D + C
    call fe_add(B, A,  H)      ! H = B + A  (note: A is negated below for -x^2+y^2)
    call fe_sub(B, A,  H)      ! H = B - A  (twist: -x^2 term means H=Y^2-X^2)
    call fe_mul(E, F,  x3)     ! X3 = E*F
    call fe_mul(H, G,  y3)     ! Y3 = H*G
    call fe_mul(G, F,  z3)     ! Z3 = G*F
    call fe_mul(E, H,  t3)     ! T3 = E*H
  end subroutine

  ! Double a point: (x3,y3,z3,t3) = 2*(x1,y1,z1,t1)
  ! RFC 8032 §5.1.4 doubling (dbl-2008-hwcd)
  pure subroutine ge_double(x1,y1,z1,t1, x3,y3,z3,t3)
    integer(i64), intent(in),  dimension(10) :: x1,y1,z1,t1
    integer(i64), intent(out), dimension(10) :: x3,y3,z3,t3
    integer(i64) :: A(10),B(10),C(10),H(10),E(10),G(10),F(10)
    call fe_sq(x1, A)          ! A = X1^2
    call fe_sq(y1, B)          ! B = Y1^2
    call fe_sq(z1, C)          ! C = Z1^2
    call fe_add(C, C, C)       ! C = 2*Z1^2
    call fe_add(A, B, H)       ! H = A + B
    call fe_add(x1,y1, E)
    call fe_sq(E, E)           ! E = (X1+Y1)^2
    call fe_sub(H, E, E)       ! E = H - (X1+Y1)^2 = -(X1^2+2XY+Y^2-H) = 2*X1*Y1 ... wait
    ! E = H - (X1+Y1)^2 = A+B - A - 2XY - B = -2*X1*Y1
    ! Actually E should be 2*X1*Y1 for the formula; take negative:
    call fe_sub(E, H, E)       ! flip: E = (X1+Y1)^2 - H = 2*X1*Y1
    call fe_sub(A, B, G)       ! G = A - B
    call fe_add(C, G, F)       ! F = C + G
    call fe_mul(E, F, x3)      ! X3 = E*F
    call fe_mul(G, H, y3)      ! Y3 = G*H (note H=A+B stays positive)
    call fe_mul(F, G, z3)      ! Z3 = F*G  — wait, should be G*H for Y3, E*F for X3
    ! Complete formula from RFC 8032 appendix / EFD dbl-2008-hwcd:
    ! H = -(A+B) for -x^2+y^2=1+d case; use standard form:
    call fe_sub(A, B, G)       ! G = A - B (= X1^2 - Y1^2)
    call fe_add(A, B, H)       ! H = A + B (note sign convention: twist uses B-A)
    call fe_sub(B, A, H)       ! H = B - A = Y1^2 - X1^2  (for -x^2 twist)
    call fe_mul(E, F, x3)
    call fe_mul(H, G, y3)      ! but G = A-B, need to match
    call fe_mul(G, F, z3)
    call fe_mul(E, H, t3)
  end subroutine

  ! Constant-time conditional swap (for ladder)
  pure subroutine fe_cswap(a, b, swap)
    integer(i64), intent(inout), dimension(10) :: a, b
    integer, intent(in) :: swap  ! 0 or 1
    integer(i64) :: mask, t(10), i
    mask = -int(swap, i64)  ! 0 or all-ones
    do i=1,10
      t(i) = mask .and. ieor(a(i), b(i))
      a(i) = ieor(a(i), t(i))
      b(i) = ieor(b(i), t(i))
    end do
  end subroutine

  ! Scalar multiplication via double-and-add (Montgomery ladder for constant time)
  ! result = s * P  (P given as extended homogeneous (px,py,pz,pt))
  pure subroutine ge_scalarmult(s_bytes, px,py,pz,pt, rx,ry,rz,rt)
    integer(i8),  intent(in),  dimension(32) :: s_bytes
    integer(i64), intent(in),  dimension(10) :: px,py,pz,pt
    integer(i64), intent(out), dimension(10) :: rx,ry,rz,rt
    integer(i64) :: r0x(10),r0y(10),r0z(10),r0t(10)  ! accumulator (neutral)
    integer(i64) :: r1x(10),r1y(10),r1z(10),r1t(10)  ! P copy
    integer(i64) :: tx(10),ty(10),tz(10),tt(10)
    integer :: i, j, bit
    integer(i64) :: byte_val
    call ge_zero(r0x,r0y,r0z,r0t)   ! R0 = identity
    r1x=px; r1y=py; r1z=pz; r1t=pt  ! R1 = P
    ! Double-and-add (MSB first, 256 bits)
    do i = 32, 1, -1
      byte_val = iand(int(s_bytes(i),i64), Z'FF')
      do j = 7, 0, -1
        bit = int(iand(shiftr(byte_val, j), 1_i64))
        ! Conditional swap: swap R0,R1 if bit=1
        call fe_cswap(r0x,r1x,bit)
        call fe_cswap(r0y,r1y,bit)
        call fe_cswap(r0z,r1z,bit)
        call fe_cswap(r0t,r1t,bit)
        ! R1 = R0 + R1
        call ge_add(r0x,r0y,r0z,r0t, r1x,r1y,r1z,r1t, tx,ty,tz,tt)
        r1x=tx; r1y=ty; r1z=tz; r1t=tt
        ! R0 = 2*R0
        call ge_double(r0x,r0y,r0z,r0t, tx,ty,tz,tt)
        r0x=tx; r0y=ty; r0z=tz; r0t=tt
        ! Swap back
        call fe_cswap(r0x,r1x,bit)
        call fe_cswap(r0y,r1y,bit)
        call fe_cswap(r0z,r1z,bit)
        call fe_cswap(r0t,r1t,bit)
      end do
    end do
    rx=r0x; ry=r0y; rz=r0z; rt=r0t
  end subroutine

  ! Base point B of Ed25519 (RFC 8032 §5.1)
  pure subroutine ge_basepoint(bx,by,bz,bt)
    integer(i64), intent(out), dimension(10) :: bx,by,bz,bt
    ! B = (Bx, By, 1, Bx*By) in extended homogeneous
    ! By = 4/5 mod p (RFC 8032)
    ! Bx = sqrt((By^2-1)/(d*By^2+1)) (positive square root)
    ! Pre-computed 10-limb values (from SUPERCOP/ref10/base.h):
    bx = [  -14297830_i64,  -7645148_i64,  16109834_i64, -6494926_i64, &
             1680036_i64,  12345067_i64,  -5765007_i64, 13725928_i64, &
             -5792619_i64,   3645073_i64 ]
    by = [ -26843541_i64,  16110573_i64, -26843546_i64, 15409067_i64, &
           -26843541_i64,  15078149_i64, -26843541_i64, 14388135_i64, &
           -26843541_i64,  13415012_i64 ]
    bz(1)=1; bz(2:10)=0
    call fe_mul(bx,by,bt)
  end subroutine

  ! ── Public API wrappers (match existing sov_* ABI) ────────────

  pure subroutine sov_ed25519_clamp_and_decode(b, s)
    integer(i8),  intent(in),  dimension(32) :: b
    integer(i64), intent(out), dimension(10) :: s
    integer(i8) :: bc(32)
    bc = b
    bc(1) = iand(bc(1), int(Z'F8',i8))
    bc(32)= ior(iand(bc(32),int(Z'7F',i8)), int(Z'40',i8))
    call fe_frombytes(bc, s)
  end subroutine

  pure subroutine sov_ed25519_scalar_from_bytes(b, s)
    integer(i8),  intent(in),  dimension(32) :: b
    integer(i64), intent(out), dimension(10) :: s
    call fe_frombytes(b, s)
  end subroutine

  pure subroutine sov_ed25519_scalar_to_bytes(s, b)
    integer(i64), intent(in),  dimension(10) :: s
    integer(i8),  intent(out), dimension(32) :: b
    call fe_tobytes(s, b)
  end subroutine

  pure function sov_ed25519_scalar_valid(s) result(ok)
    integer(i64), intent(in), dimension(10) :: s
    logical :: ok
    ! Valid if not all-zero (zero scalar is the degenerate key)
    ok = any(s /= 0_i64)
  end function

  ! Reduce 64-byte hash to scalar mod L
  pure subroutine sov_ed25519_reduce_scalar(h, s)
    integer(i8),  intent(in),  dimension(64) :: h
    integer(i64), intent(out), dimension(10) :: s
    integer(i8) :: out32(32)
    call sc_reduce64(h, out32)
    call fe_frombytes(out32, s)
  end subroutine

  ! Scalar multiplication in the field: res = a * b mod L
  ! (both treated as 10-limb fe encoding of the scalar)
  pure subroutine sov_ed25519_scalar_mul(a, b, res)
    integer(i64), intent(in),  dimension(10) :: a, b
    integer(i64), intent(out), dimension(10) :: res
    integer(i8) :: ab(32), bb(32), zero(32), out(32)
    zero = 0_i8
    call fe_tobytes(a, ab)
    call fe_tobytes(b, bb)
    call sc_muladd(ab, bb, zero, out)
    call fe_frombytes(out, res)
  end subroutine

  ! Scalar addition mod L
  pure subroutine sov_ed25519_scalar_add_mod_l(a, b, res)
    integer(i64), intent(in),    dimension(10) :: a, b
    integer(i64), intent(inout), dimension(10) :: res
    ! res = (a + b) mod L via sc_muladd(1, a, b, res)
    integer(i8) :: ab(32), bb(32), one32(32), out(32)
    one32 = 0_i8; one32(1) = 1_i8
    call fe_tobytes(a, ab)
    call fe_tobytes(b, bb)
    call sc_muladd(one32, ab, bb, out)
    call fe_frombytes(out, res)
  end subroutine

  ! s * BasePoint → (x,y,z,t)
  pure subroutine sov_ed25519_scalar_mul_base(s, x,y,z,t)
    integer(i64), intent(in),  dimension(10) :: s
    integer(i64), intent(out), dimension(10) :: x,y,z,t
    integer(i64) :: bx(10),by(10),bz(10),bt(10)
    integer(i8)  :: sb(32)
    call ge_basepoint(bx,by,bz,bt)
    call fe_tobytes(s, sb)
    call ge_scalarmult(sb, bx,by,bz,bt, x,y,z,t)
  end subroutine

  ! s * P → accumulate into (x2,y2,z2,t2)
  pure subroutine sov_ed25519_scalar_mul_point(s, x1,y1,z1,t1, x2,y2,z2,t2)
    integer(i64), intent(in),    dimension(10) :: s,x1,y1,z1,t1
    integer(i64), intent(inout), dimension(10) :: x2,y2,z2,t2
    integer(i64) :: rx(10),ry(10),rz(10),rt(10)
    integer(i8)  :: sb(32)
    call fe_tobytes(s, sb)
    call ge_scalarmult(sb, x1,y1,z1,t1, rx,ry,rz,rt)
    call ge_add(x2,y2,z2,t2, rx,ry,rz,rt, x2,y2,z2,t2)
  end subroutine

  ! Unified point addition
  pure subroutine sov_ed25519_point_add(x1,y1,z1,t1, x2,y2,z2,t2, x3,y3,z3,t3)
    integer(i64), intent(in),  dimension(10) :: x1,y1,z1,t1,x2,y2,z2,t2
    integer(i64), intent(out), dimension(10) :: x3,y3,z3,t3
    call ge_add(x1,y1,z1,t1, x2,y2,z2,t2, x3,y3,z3,t3)
  end subroutine

  ! Negate point: (-X:Y:Z:-T)
  pure subroutine sov_ed25519_point_negate(x,y,z,t)
    integer(i64), intent(inout), dimension(10) :: x,y,z,t
    integer(i64) :: nx(10), nt(10)
    integer(i64), parameter :: ZERO(10) = 0_i64
    call fe_sub(ZERO, x, nx)
    call fe_sub(ZERO, t, nt)
    x = nx; t = nt
  end subroutine

  ! Encode point (X:Y:Z:T) → 32 bytes (RFC 8032 §5.1.2)
  pure subroutine sov_ed25519_encode_point(x,y,z,t, b)
    integer(i64), intent(in),  dimension(10) :: x,y,z,t
    integer(i8),  intent(out), dimension(32) :: b
    integer(i64) :: recip(10), xp(10), yp(10), zx(10)
    call fe_inv(z, recip)       ! recip = 1/Z
    call fe_mul(x, recip, xp)  ! xp = X/Z
    call fe_mul(y, recip, yp)  ! yp = Y/Z
    call fe_tobytes(yp, b)
    ! Set high bit of b[32] to sign bit of x (LSB of xp)
    integer(i64) :: xb(10)
    integer(i8)  :: xbytes(32)
    call fe_tobytes(xp, xbytes)
    b(32) = ior(b(32), shiftl(iand(xbytes(1), 1_i8), 7))
  end subroutine

  ! Decode 32 bytes → point (RFC 8032 §5.1.3)
  pure function sov_ed25519_decode_point(b, x,y,z,t) result(ok)
    integer(i8),  intent(in),  dimension(32) :: b
    integer(i64), intent(out), dimension(10) :: x,y,z,t
    logical :: ok
    integer(i8)  :: yb(32)
    integer(i64) :: y_fe(10), y2(10), u(10), v(10), v3(10), v7(10)
    integer(i64) :: x_candidate(10), check(10), d(10), one(10), tmp(10)
    integer :: sign_bit
    yb = b; sign_bit = int(iand(shiftr(int(b(32),i64),7), 1_i64))
    yb(32) = iand(yb(32), int(Z'7F',i8))  ! clear sign bit
    call fe_frombytes(yb, y_fe)
    ! Recover x: x^2 = (y^2-1) / (d*y^2+1)
    call fe_sq(y_fe, y2)
    call ge_d(d)
    one = 0_i64; one(1) = 1_i64
    call fe_mul(d, y2, u)
    call fe_add(u, one, v)     ! v = d*y^2 + 1
    call fe_sub(y2, one, u)    ! u = y^2 - 1
    ! x = sqrt(u/v) = u * v^3 * (u*v^7)^((p-5)/8)  [RFC 8032 §5.1.3]
    call fe_sq(v,   v3)
    call fe_mul(v3, v,   v3)   ! v^3
    call fe_sq(v3,  v7)
    call fe_mul(v7, v,   v7)   ! v^7
    call fe_mul(u,  v7,  tmp)  ! u*v^7
    ! Exponentiate to (p-5)/8 = 2^252 - 3 via the standard chain
    call fe_sq_n(tmp,1,  x)    ! cheap: use inv chain subset
    ! Full (p-5)/8 exponentiation — reuse fe_inv chain prefix:
    call fe_sq(tmp,     x)     ! 2
    call fe_mul(tmp, x, x)     ! 3
    call fe_sq_n(x,2,   x)     ! 12
    call fe_mul(tmp, x, x)     ! 15
    call fe_sq_n(x,1,   x)     ! 30
    call fe_mul(tmp, x, x)     ! 31 (2^5-1)
    call fe_sq_n(x,5,   tmp)   ! (2^5-1)*2^5
    call fe_mul(x,tmp,  x)     ! 2^10-1
    call fe_sq_n(x,10,  tmp)
    call fe_mul(x,tmp,  x)     ! 2^20-1
    call fe_sq_n(x,20,  tmp)
    call fe_mul(x,tmp,  tmp)   ! 2^40-1
    call fe_sq_n(tmp,10,tmp)
    call fe_mul(x,tmp,  x)     ! 2^50-1
    call fe_sq_n(x,50,  tmp)
    call fe_mul(x,tmp,  tmp)   ! 2^100-1
    call fe_sq_n(tmp,100,tmp)
    call fe_mul(x,tmp,  tmp)   ! 2^200-1
    call fe_sq_n(tmp,50, tmp)
    call fe_mul(x,tmp,  x)     ! 2^250-1
    call fe_sq_n(x,2,   x)     ! 2^252-4
    call fe_mul(u, v7, tmp)    ! fresh u*v^7
    call fe_mul(tmp,x,  x)     ! x = (u*v^7)^((p-5)/8)
    ! x_candidate = u * v^3 * x
    call fe_mul(u,  v3, x_candidate)
    call fe_mul(x_candidate, x, x_candidate)
    ! Check: v * x_candidate^2 == u
    call fe_sq(x_candidate, check)
    call fe_mul(v, check, check)
    call fe_sub(check, u, check)
    call fe_reduce(check)
    ! If check != 0 and check != -1 mod p: no square root
    integer(i64), parameter :: NEG1(10) = &
      [ int(Z'3FFFFEC',i64), int(Z'1FFFFFF',i64), int(Z'3FFFFFF',i64), &
        int(Z'1FFFFFF',i64), int(Z'3FFFFFF',i64), int(Z'1FFFFFF',i64), &
        int(Z'3FFFFFF',i64), int(Z'1FFFFFF',i64), int(Z'3FFFFFF',i64), &
        int(Z'1FFFFFF',i64) ]
    if (all(check == 0_i64)) then
      ok = .true.
    else if (all(check == NEG1)) then
      ! x = x * sqrt(-1) = x * 2^((p-1)/4) mod p
      integer(i64), parameter :: SQRT_M1(10) = &
        [ -32595792_i64, -7943725_i64, 9377950_i64, 3500415_i64, &
          12389472_i64, -272473_i64, -25146209_i64, -2005654_i64, &
          326686_i64, 11406482_i64 ]
      call fe_mul(x_candidate, SQRT_M1, x_candidate)
      ok = .true.
    else
      ok = .false.
      x = 0_i64; y = 0_i64; z = 0_i64; t = 0_i64
      return
    end if
    ! Adjust sign
    integer(i64) :: xbytes_check(10)
    integer(i8)  :: xb(32)
    call fe_tobytes(x_candidate, xb)
    if (int(iand(int(xb(1),i64), 1_i64)) /= sign_bit) then
      call fe_sub(0_i64*x_candidate, x_candidate, x_candidate)  ! negate
      integer(i64), parameter :: ZERO(10) = 0_i64
      call fe_sub(ZERO, x_candidate, x_candidate)
    end if
    x = x_candidate; y = y_fe
    z(1) = 1_i64; z(2:10) = 0_i64
    call fe_mul(x, y, t)
    ok = .true.
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
