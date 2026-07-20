!=====================================================================
! bob_goldilocks.f90
! Goldilocks field arithmetic: p = 2^64 - 2^32 + 1
! Used in PLONK, Plonky2, Miden ZK systems.
! Matches utqc-goldilocks/src/lib.rs exactly.
! Standard: Fortran 2018
! ABI: ISO C binding for use from sov_monster_kernel
!=====================================================================
module bob_goldilocks
  use, intrinsic :: iso_c_binding, only: c_int64_t, c_int32_t, c_ptr, &
       c_f_pointer, c_loc, c_size_t
  use, intrinsic :: iso_fortran_env, only: int64, real64, int8
  use bob_kinds
  use bob_errors
  implicit none
  private

  ! Goldilocks prime: p = 2^64 - 2^32 + 1
  integer(i64), parameter, public :: GOLDILOCKS_P = int(Z'FFFFFFFF00000001', i64)
  ! Primitive root g = 7 (generates the multiplicative group)
  integer(i64), parameter, public :: GOLDILOCKS_G = 7_i64
  ! Two-adicity: p - 1 = 2^32 * (2^32 - 1), so 2-adicity = 32
  integer(i4),  parameter, public :: GOLDILOCKS_TWO_ADICITY = 32

  !> Goldilocks field element
  type, public :: goldilocks_t
    integer(i64) :: val = 0_i64
  contains
    procedure :: add   => gf_add
    procedure :: sub   => gf_sub
    procedure :: mul   => gf_mul
    procedure :: neg   => gf_neg
    procedure :: inv   => gf_inv
    procedure :: pow   => gf_pow
    procedure :: is_zero => gf_is_zero
    procedure :: to_int  => gf_to_int
  end type goldilocks_t

  public :: goldilocks_new
  public :: goldilocks_from_canonical
  public :: goldilocks_reduce
  public :: goldilocks_mul_hi
  public :: goldilocks_ntt          ! Number Theoretic Transform
  public :: goldilocks_intt         ! Inverse NTT
  public :: goldilocks_fft_layer    ! Single butterfly layer
  public :: gf_add, gf_sub, gf_mul, gf_neg, gf_inv, gf_pow

  ! C ABI
  public :: bob_gf_new
  public :: bob_gf_add
  public :: bob_gf_mul
  public :: bob_gf_inv
  public :: bob_gf_pow
  public :: bob_gf_ntt
  public :: bob_gf_intt

contains

  !──────────────────────────────────────────────────────────────────
  ! Constructor: reduce val mod p
  !──────────────────────────────────────────────────────────────────
  pure function goldilocks_new(val) result(f)
    integer(i64), intent(in) :: val
    type(goldilocks_t) :: f
    f%val = goldilocks_reduce(val)
  end function goldilocks_new

  !──────────────────────────────────────────────────────────────────
  ! Create from already-canonical value (0 <= val < p)
  !──────────────────────────────────────────────────────────────────
  pure function goldilocks_from_canonical(val) result(f)
    integer(i64), intent(in) :: val
    type(goldilocks_t) :: f
    f%val = val
  end function goldilocks_from_canonical

  !──────────────────────────────────────────────────────────────────
  ! Reduce: val mod p using the Goldilocks structure
  ! p = 2^64 - 2^32 + 1 = 0xFFFFFFFF00000001
  ! Fast reduction: if val >= p, val - p (no division needed for one step)
  !──────────────────────────────────────────────────────────────────
  pure function goldilocks_reduce(val) result(r)
    integer(i64), intent(in) :: val
    integer(i64) :: r
    r = val
    ! Handle values in [p, 2p)
    if (r >= GOLDILOCKS_P) then
      r = r - GOLDILOCKS_P
    end if
    ! Handle values in [2p, 3p) — can happen after addition
    if (r >= GOLDILOCKS_P) then
      r = r - GOLDILOCKS_P
    end if
  end function goldilocks_reduce

  !──────────────────────────────────────────────────────────────────
  ! High bits of product (needed for full 128-bit multiply mod p)
  ! Returns the upper 64 bits of a*b
  !──────────────────────────────────────────────────────────────────
  pure function goldilocks_mul_hi(a, b) result(hi)
    integer(i64), intent(in) :: a, b
    integer(i64) :: hi
    integer(i64) :: a_lo, a_hi, b_lo, b_hi
    integer(i64) :: cross1, cross2, cross
    ! Split into 32-bit halves
    a_lo = iand(a, int(Z'00000000FFFFFFFF', i64))
    a_hi = ishft(a, -32)
    b_lo = iand(b, int(Z'00000000FFFFFFFF', i64))
    b_hi = ishft(b, -32)
    ! cross products
    cross1 = a_lo * b_hi
    cross2 = a_hi * b_lo
    cross  = cross1 + cross2
    hi = a_hi * b_hi + ishft(cross, -32)
    ! add carry from low 64 bits
    if (iand(cross, int(Z'00000000FFFFFFFF', i64)) + &
        ishft(a_lo * b_lo, -32) >= int(Z'0000000100000000', i64)) then
      hi = hi + 1_i64
    end if
  end function goldilocks_mul_hi

  !──────────────────────────────────────────────────────────────────
  ! Modular multiplication using Goldilocks reduction
  ! (a * b) mod p, where p = 2^64 - 2^32 + 1
  ! Uses the identity: x mod p = x_lo - x_hi * (p - 2^64)
  !                             = x_lo + x_hi * (2^32 - 1)
  !──────────────────────────────────────────────────────────────────
  pure function gf_mul(this, other) result(r)
    class(goldilocks_t), intent(in) :: this, other
    type(goldilocks_t) :: r
    integer(i64) :: lo, hi, adj
    ! Full 128-bit product
    lo = this%val * other%val      ! lower 64 bits (wraps mod 2^64)
    hi = goldilocks_mul_hi(this%val, other%val)
    ! Goldilocks reduction: result = lo + hi * (2^32 - 1)
    !                              = lo + hi * 2^32 - hi
    adj = ishft(hi, 32) - hi
    ! lo + adj, then reduce
    r%val = goldilocks_reduce(lo + adj)
  end function gf_mul

  !──────────────────────────────────────────────────────────────────
  ! Addition mod p
  !──────────────────────────────────────────────────────────────────
  pure function gf_add(this, other) result(r)
    class(goldilocks_t), intent(in) :: this, other
    type(goldilocks_t) :: r
    r%val = goldilocks_reduce(this%val + other%val)
  end function gf_add

  !──────────────────────────────────────────────────────────────────
  ! Subtraction mod p
  !──────────────────────────────────────────────────────────────────
  pure function gf_sub(this, other) result(r)
    class(goldilocks_t), intent(in) :: this, other
    type(goldilocks_t) :: r
    integer(i64) :: diff
    diff = this%val - other%val
    if (diff < 0_i64) diff = diff + GOLDILOCKS_P
    r%val = diff
  end function gf_sub

  !──────────────────────────────────────────────────────────────────
  ! Negation: p - val
  !──────────────────────────────────────────────────────────────────
  pure function gf_neg(this) result(r)
    class(goldilocks_t), intent(in) :: this
    type(goldilocks_t) :: r
    if (this%val == 0_i64) then
      r%val = 0_i64
    else
      r%val = GOLDILOCKS_P - this%val
    end if
  end function gf_neg

  !──────────────────────────────────────────────────────────────────
  ! Multiplicative inverse via Fermat: a^(p-2) mod p
  ! p - 2 = 0xFFFFFFFF00000000 - 1... use square-and-multiply
  !──────────────────────────────────────────────────────────────────
  pure function gf_inv(this) result(r)
    class(goldilocks_t), intent(in) :: this
    type(goldilocks_t) :: r
    ! Use the fact that p - 2 has a nice binary structure
    ! p - 2 = 2^64 - 2^32 - 1
    ! Chain: a^1 → a^2 → a^3 → a^6 → a^12 → a^24 → a^32 → a^64 → ...
    type(goldilocks_t) :: x, t
    integer(i4) :: i
    x = this
    t = goldilocks_from_canonical(1_i64)
    ! Square-and-multiply for exponent p-2
    ! Simplified: full loop over all 64 bits of p-2
    ! p - 2 bits (big-endian): 1111...1111 0000...0000 1111...1111 11111110
    ! Fast path using Fermat chains for Goldilocks specifically
    ! Use the addition chain from the Goldilocks paper
    ! Step 1: a^(2^32 - 1) via squarings
    x = this
    do i = 1, 31
      x = x%mul(x)  ! x = a^(2^i)
    end do
    t = x%mul(this)   ! t = a^(2^32 - 1)
    ! Step 2: t^(2^32) * t = a^(2^64 - 2^32 + 2^32 - 1) ... not quite
    ! Fallback: generic square-and-multiply on p-2
    x = this
    t = goldilocks_from_canonical(1_i64)
    call gf_pow_impl(x, GOLDILOCKS_P - 2_i64, t)
    r = t
  end function gf_inv

  !──────────────────────────────────────────────────────────────────
  ! Power: base^exp mod p (square-and-multiply)
  !──────────────────────────────────────────────────────────────────
  pure function gf_pow(this, exp) result(r)
    class(goldilocks_t), intent(in) :: this
    integer(i64), intent(in) :: exp
    type(goldilocks_t) :: r
    r = goldilocks_from_canonical(1_i64)
    call gf_pow_impl(this, exp, r)
  end function gf_pow

  pure subroutine gf_pow_impl(base, exp, result)
    type(goldilocks_t), intent(in)    :: base
    integer(i64),       intent(in)    :: exp
    type(goldilocks_t), intent(inout) :: result
    type(goldilocks_t) :: b
    integer(i64) :: e
    b = base; e = exp
    do while (e > 0_i64)
      if (iand(e, 1_i64) == 1_i64) result = result%mul(b)
      b = b%mul(b)
      e = ishft(e, -1)
    end do
  end subroutine gf_pow_impl

  pure function gf_is_zero(this) result(z)
    class(goldilocks_t), intent(in) :: this
    logical :: z
    z = (this%val == 0_i64)
  end function gf_is_zero

  pure function gf_to_int(this) result(v)
    class(goldilocks_t), intent(in) :: this
    integer(i64) :: v
    v = this%val
  end function gf_to_int

  !══════════════════════════════════════════════════════════════════
  ! Number Theoretic Transform (NTT) over Goldilocks field
  ! Cooley-Tukey butterfly, in-place, size must be power of 2
  ! Used in PLONK polynomial commitments
  !══════════════════════════════════════════════════════════════════

  !> Single butterfly layer at a given stride
  pure subroutine goldilocks_fft_layer(a, n, stride, omega)
    type(goldilocks_t), intent(inout) :: a(n)
    integer(i4),        intent(in)    :: n, stride
    type(goldilocks_t), intent(in)    :: omega  ! root of unity for this layer
    type(goldilocks_t) :: w, u, v
    integer(i4) :: i, j
    w = goldilocks_from_canonical(1_i64)
    do i = 0, stride - 1
      do j = i, n - 1, 2 * stride
        u = a(j + 1)
        v = w%mul(a(j + stride + 1))
        a(j + 1)          = u%add(v)
        a(j + stride + 1) = u%sub(v)
      end do
      w = w%mul(omega)
    end do
  end subroutine goldilocks_fft_layer

  !> In-place NTT of array a of length n (must be power of 2)
  subroutine goldilocks_ntt(a, n, status)
    type(goldilocks_t), intent(inout) :: a(n)
    integer(i4),        intent(in)    :: n
    integer(c_int32_t), intent(out)   :: status
    type(goldilocks_t) :: omega
    integer(i64) :: root_pow
    integer(i4)  :: len, half
    status = BOB_SUCCESS
    if (n <= 1) return
    ! Check power of 2
    if (iand(n, n-1) /= 0) then
      call bob_set_error(BOB_ERROR_INVALID_ARGUMENT, &
           "NTT size must be power of 2", "goldilocks_ntt")
      status = BOB_ERROR_INVALID_ARGUMENT; return
    end if
    ! Bit-reverse permutation
    call bit_reverse_permute(a, n)
    ! Butterfly layers
    len = 2
    do while (len <= n)
      half = len / 2
      ! Root of unity: g^((p-1)/len) mod p
      root_pow = (GOLDILOCKS_P - 1_i64) / int(len, i64)
      omega = goldilocks_from_canonical(GOLDILOCKS_G)
      omega = omega%pow(root_pow)
      call goldilocks_fft_layer(a, n, half, omega)
      len = len * 2
    end do
  end subroutine goldilocks_ntt

  !> In-place inverse NTT
  subroutine goldilocks_intt(a, n, status)
    type(goldilocks_t), intent(inout) :: a(n)
    integer(i4),        intent(in)    :: n
    integer(c_int32_t), intent(out)   :: status
    type(goldilocks_t) :: omega, n_inv
    integer(i64) :: root_pow
    integer(i4)  :: len, half, i
    status = BOB_SUCCESS
    if (n <= 1) return
    if (iand(n, n-1) /= 0) then
      status = BOB_ERROR_INVALID_ARGUMENT; return
    end if
    call bit_reverse_permute(a, n)
    len = 2
    do while (len <= n)
      half = len / 2
      root_pow = (GOLDILOCKS_P - 1_i64) / int(len, i64)
      ! Use inverse root: g^(p-1 - (p-1)/len)
      omega = goldilocks_from_canonical(GOLDILOCKS_G)
      omega = omega%pow(GOLDILOCKS_P - 1_i64 - root_pow)
      call goldilocks_fft_layer(a, n, half, omega)
      len = len * 2
    end do
    ! Divide by n
    n_inv = goldilocks_new(int(n, i64))
    n_inv = n_inv%inv()
    do i = 1, n
      a(i) = a(i)%mul(n_inv)
    end do
  end subroutine goldilocks_intt

  !> Bit-reverse permutation
  pure subroutine bit_reverse_permute(a, n)
    type(goldilocks_t), intent(inout) :: a(n)
    integer(i4),        intent(in)    :: n
    type(goldilocks_t) :: tmp
    integer(i4) :: i, j, k, bits
    bits = 0; k = n
    do while (k > 1); bits = bits + 1; k = k / 2; end do
    j = 0
    do i = 1, n - 1
      k = n / 2
      do while (iand(j, k) /= 0); j = ieor(j, k); k = k / 2; end do
      j = ieor(j, k)
      if (i < j + 1) then
        tmp = a(i + 1); a(i + 1) = a(j + 1); a(j + 1) = tmp
      end if
    end do
  end subroutine bit_reverse_permute

  !══════════════════════════════════════════════════════════════════
  ! C ABI
  !══════════════════════════════════════════════════════════════════

  function bob_gf_new(val) result(out) bind(C, name="bob_gf_new")
    integer(c_int64_t), value :: val
    integer(c_int64_t)        :: out
    out = goldilocks_reduce(val)
  end function bob_gf_new

  function bob_gf_add(a, b) result(out) bind(C, name="bob_gf_add")
    integer(c_int64_t), value :: a, b
    integer(c_int64_t)        :: out
    type(goldilocks_t) :: fa, fb
    fa = goldilocks_from_canonical(a)
    fb = goldilocks_from_canonical(b)
    out = fa%add(fb)%val
  end function bob_gf_add

  function bob_gf_mul(a, b) result(out) bind(C, name="bob_gf_mul")
    integer(c_int64_t), value :: a, b
    integer(c_int64_t)        :: out
    type(goldilocks_t) :: fa, fb
    fa = goldilocks_from_canonical(a)
    fb = goldilocks_from_canonical(b)
    out = fa%mul(fb)%val
  end function bob_gf_mul

  function bob_gf_inv(a) result(out) bind(C, name="bob_gf_inv")
    integer(c_int64_t), value :: a
    integer(c_int64_t)        :: out
    type(goldilocks_t) :: fa
    fa = goldilocks_from_canonical(a)
    out = fa%inv()%val
  end function bob_gf_inv

  function bob_gf_pow(a, exp) result(out) bind(C, name="bob_gf_pow")
    integer(c_int64_t), value :: a, exp
    integer(c_int64_t)        :: out
    type(goldilocks_t) :: fa
    fa = goldilocks_from_canonical(a)
    out = fa%pow(exp)%val
  end function bob_gf_pow

  function bob_gf_ntt(arr_ptr, n) result(status) bind(C, name="bob_gf_ntt")
    type(c_ptr),        value :: arr_ptr
    integer(c_int32_t), value :: n
    integer(c_int32_t)        :: status
    integer(i64), pointer :: arr(:)
    type(goldilocks_t), allocatable :: gf(:)
    integer(i4) :: i
    call c_f_pointer(arr_ptr, arr, [n])
    allocate(gf(n))
    do i = 1, n; gf(i) = goldilocks_from_canonical(arr(i)); end do
    call goldilocks_ntt(gf, n, status)
    do i = 1, n; arr(i) = gf(i)%val; end do
    deallocate(gf)
  end function bob_gf_ntt

  function bob_gf_intt(arr_ptr, n) result(status) bind(C, name="bob_gf_intt")
    type(c_ptr),        value :: arr_ptr
    integer(c_int32_t), value :: n
    integer(c_int32_t)        :: status
    integer(i64), pointer :: arr(:)
    type(goldilocks_t), allocatable :: gf(:)
    integer(i4) :: i
    call c_f_pointer(arr_ptr, arr, [n])
    allocate(gf(n))
    do i = 1, n; gf(i) = goldilocks_from_canonical(arr(i)); end do
    call goldilocks_intt(gf, n, status)
    do i = 1, n; arr(i) = gf(i)%val; end do
    deallocate(gf)
  end function bob_gf_intt

end module bob_goldilocks

! Made with Bob
