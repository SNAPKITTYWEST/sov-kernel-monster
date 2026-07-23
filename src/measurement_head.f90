!=====================================================================
! MEASUREMENT HEAD — Born Rule on the Jordan Symmetric Cone
!
! The output layer. No softmax over vocab. No unembedding matrix.
! Pure spectral measurement: project ρ onto idempotents, read eigenvalues.
!
! Born rule:  p_j = tr(q_j ∘ ρ) = tr(q_j ρ)  (q_j Hermitian projector)
! Reconstruction:  x̂ = Σ_j p_j ψ_j            (inverse spectral synthesis)
!
! APL glyph map:
!   tr(q_j ρ)     ≡  +/ (q_j × ρ)     — reduce + over elementwise ×
!   Σ_j p_j ψ_j  ≡  p +.× ψ           — inner product +.×
!   p ∈ Δ^{m-1}  ≡  (+/p) = 1          — reduce + equals 1
!   argmax p      ≡  ⍒p               — grade down ⍒
!   sample p      ≡  p ⌸ ⍳m            — key ⌸ over index ⍳
!   entropy       ≡  -+/(p × ⍟p)       — reduce + of p × log p
!
! Liquid Haskell:
!   {-@ type Projector d = {q : M d d ℂ | hermitian q ∧ q·q = q ∧ tr q = 1} @-}
!   {-@ type Simplex  m  = {p : Vec m ℝ  | ∀i. p!i ≥ 0 ∧ sum p = 1}         @-}
!   {-@ born_rule  :: Vec m (Projector d) → Density d → Simplex m            @-}
!   {-@ reconstruct :: Simplex m → Frame m d → Signal d                       @-}
!
! Fibonacci temperature schedule:
!   τ_k = φ⁻ᵏ  (temperature decays by golden ratio each annealing step)
!   p_j(τ) = exp(tr(q_j ρ)/τ) / Σ exp(tr(q_k ρ)/τ)
!   τ→0: argmax  (mode collapse to sharpest eigenvalue)
!   τ→∞: uniform (maximum entropy, pure spectral democracy)
!
! Audit Spec: 4b565498-9afc-4782-af4a-c6b11a5d0058
!=====================================================================
module measurement_head
  use, intrinsic :: iso_c_binding, only: c_int64_t, c_ptr, c_f_pointer, &
       c_size_t, c_loc, c_char, c_associated
  use, intrinsic :: iso_fortran_env, only: int64, real64, int8
  use sov_monster_kernel, only: dp, czero, &
       sov_blake3_hash_matrix, sov_bifrost_sign, &
       sov_is_hermitian_matrix, sov_is_density_matrix, sov_fault, i8
  use sov_knowledge, only: knowledge_tau, ensure_sovereign_kb, sovereign_kb, &
       knowledge_chunk
  implicit none
  private

  public :: born_rule
  public :: born_rule_temperature
  public :: born_rule_knowledge
  public :: reconstruct
  public :: entropy
  public :: argmax_spectral
  public :: sample_spectral
  public :: fib_anneal

  real(dp), parameter :: PHI_INV = 0.6180339887498948482_dp
  real(dp), parameter :: LOG2    = 0.6931471805599453094_dp

contains

  !═══════════════════════════════════════════════════════════════════
  ! born_rule — p_j = tr(q_j ρ)  (zero temperature: exact projection)
  !
  ! {-@ born_rule :: {m:Int | m>0} → {d:Int | d>0}
  !               → Vec m (Projector d) → Density d
  !               → Simplex m                                       @-}
  !
  ! APL:  p ← +/ (q_j × ρ)   for each j    — inner +.× across d×d
  !       assert (+/p) = 1                  — reduce + equals 1
  !═══════════════════════════════════════════════════════════════════
  subroutine born_rule(q_ptr, rho_ptr, m, d, p_ptr, plasma_ok) &
       bind(C, name="born_rule")
    type(c_ptr),        intent(in),  value :: q_ptr, rho_ptr, p_ptr
    integer(c_int64_t), intent(in),  value :: m, d
    integer(c_int64_t), intent(out)        :: plasma_ok

    complex(dp), pointer :: q(:,:,:), rho(:,:)
    real(dp),    pointer :: p(:)
    integer(c_int64_t) :: j, k, l
    real(dp) :: p_sum

    call c_f_pointer(q_ptr,   q,   [m, d, d])
    call c_f_pointer(rho_ptr, rho, [d, d])
    call c_f_pointer(p_ptr,   p,   [m])

    ! {-@ assert density rho @-}
    if (.not. sov_is_density_matrix(rho, d)) call sov_fault(801)

    ! APL:  p_j ← +/ (q_j × ρ)    — tr(q_j ρ) = Σ_{kl} (q_j)_{kl} ρ_{lk}
    !$omp parallel do default(none) shared(p,q,rho,m,d) private(j,k,l)
    do j = 1, m
      real(dp) :: s; s = 0.0_dp
      do k = 1, d
        do l = 1, d
          ! tr(q_j ρ) = Σ_k (q_j ρ)_{kk} = Σ_{kl} q_j(k,l) ρ(l,k)
          s = s + real(q(j,k,l) * rho(l,k))
        end do
      end do
      p(j) = max(s, 0.0_dp)   ! Born probabilities ≥ 0
    end do
    !$omp end parallel do

    ! APL:  assert (+/p) = 1    — normalize (should already be ~1 for tight frame)
    p_sum = sum(p)
    if (p_sum < epsilon(0.0_dp)) call sov_fault(802)
    p = p / p_sum

    plasma_ok = 1
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! born_rule_temperature — softmax Born rule at temperature τ
  !
  ! {-@ born_rule_temperature :: τ:Float → Vec m (Projector d)
  !                           → Density d → Simplex m              @-}
  !
  ! APL:  raw_j ← tr(q_j ρ)                  — exact Born
  !       p_j   ← ⍟ raw_j ÷ τ               — divide by temperature
  !       p     ← *p ÷ +/*p                  — softmax: exp ÷ sum exp
  !       τ→0: argmax  τ→∞: uniform
  !═══════════════════════════════════════════════════════════════════
  subroutine born_rule_temperature(q_ptr, rho_ptr, m, d, tau, p_ptr, plasma_ok) &
       bind(C, name="born_rule_temperature")
    type(c_ptr),        intent(in),  value :: q_ptr, rho_ptr, p_ptr
    integer(c_int64_t), intent(in),  value :: m, d
    real(dp),           intent(in),  value :: tau
    integer(c_int64_t), intent(out)        :: plasma_ok

    complex(dp), pointer :: q(:,:,:), rho(:,:)
    real(dp),    pointer :: p(:)
    real(dp),    allocatable :: raw(:)
    integer(c_int64_t) :: j, k, l
    real(dp) :: max_raw, s

    call c_f_pointer(q_ptr,   q,   [m, d, d])
    call c_f_pointer(rho_ptr, rho, [d, d])
    call c_f_pointer(p_ptr,   p,   [m])

    if (tau <= 0.0_dp) call sov_fault(803)
    if (.not. sov_is_density_matrix(rho, d)) call sov_fault(804)

    allocate(raw(m))

    ! APL:  raw ← {tr(q_j ρ)}_j    — exact Born projections
    !$omp parallel do default(none) shared(raw,q,rho,m,d) private(j,k,l)
    do j = 1, m
      real(dp) :: acc; acc = 0.0_dp
      do k = 1, d; do l = 1, d
        acc = acc + real(q(j,k,l) * rho(l,k))
      end do; end do
      raw(j) = acc
    end do
    !$omp end parallel do

    ! APL:  p ← *((raw - ⌈/raw) ÷ τ)   — numerically stable softmax
    !       ⌈/ = max reduction
    max_raw = maxval(raw)
    s = 0.0_dp
    do j = 1, m
      p(j) = exp((raw(j) - max_raw) / tau)
      s = s + p(j)
    end do
    p = p / s

    plasma_ok = 1
    deallocate(raw)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! born_rule_knowledge — Born rule with sovereign knowledge annealing
  !
  ! SOVEREIGN KNOWLEDGE INJECTION (before output signing):
  !   1. Query KB for measurement context
  !   2. τ_k = τ₀ · φ⁻ⁿ  where n = # verified context chunks
  !   3. Softmax Born at knowledge-derived temperature
  !
  ! No softmax inversion. No external vector DB. WORM-attested only.
  !═══════════════════════════════════════════════════════════════════
  subroutine born_rule_knowledge(q_ptr, rho_ptr, m, d, tau_0, &
       context_ptr, context_len, p_ptr, plasma_ok) &
       bind(C, name="born_rule_knowledge")
    type(c_ptr),        intent(in),  value :: q_ptr, rho_ptr, p_ptr, context_ptr
    integer(c_int64_t), intent(in),  value :: m, d, context_len
    real(dp),           intent(in),  value :: tau_0
    integer(c_int64_t), intent(out)        :: plasma_ok

    type(knowledge_chunk), allocatable :: context_chunks(:)
    character(len=:), allocatable :: context
    character(kind=c_char), pointer :: cbuf(:)
    integer :: i, n_hits, nctx
    real(dp) :: tau_k
    integer :: n_verified

    call ensure_sovereign_kb()

    nctx = max(0, int(context_len))
    if (nctx > 0 .and. c_associated(context_ptr)) then
      call c_f_pointer(context_ptr, cbuf, [nctx])
      allocate(character(len=nctx) :: context)
      do i = 1, nctx
        context(i:i) = transfer(cbuf(i), ' ')
      end do
      call sovereign_kb%search(context, 5, context_chunks, n_hits)
    else
      n_hits = 0
    end if

    n_verified = 0
    if (allocated(context_chunks)) then
      do i = 1, size(context_chunks)
        if (context_chunks(i)%is_verified) n_verified = n_verified + 1
      end do
    end if

    tau_k = knowledge_tau(tau_0, n_verified)
    call born_rule_temperature(q_ptr, rho_ptr, m, d, tau_k, p_ptr, plasma_ok)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! reconstruct — x̂ = Σ_j p_j ψ_j  (inverse spectral synthesis)
  !
  ! {-@ reconstruct :: Simplex m → Frame m d → Signal d            @-}
  !
  ! APL:  x̂ ← p +.× ψ    — inner product: weights dotted into frame
  !       This is the EXACT inverse of SPE encode when frame is tight
  !═══════════════════════════════════════════════════════════════════
  subroutine reconstruct(p_ptr, psi_ptr, m, d, signal_ptr) &
       bind(C, name="reconstruct")
    type(c_ptr),        intent(in),  value :: p_ptr, psi_ptr, signal_ptr
    integer(c_int64_t), intent(in),  value :: m, d

    real(dp),    pointer :: p(:)
    complex(dp), pointer :: psi(:,:,:), signal(:,:)
    integer(c_int64_t) :: j, k, l

    call c_f_pointer(p_ptr,      p,      [m])
    call c_f_pointer(psi_ptr,    psi,    [m, d, d])
    call c_f_pointer(signal_ptr, signal, [d, d])

    ! APL:  x̂ ← p +.× ψ    — Σ_j p_j · ψ_j(k,l)
    signal = czero
    !$omp parallel do collapse(2) default(none) shared(signal,p,psi,m,d) private(j,k,l)
    do k = 1, d
      do l = 1, d
        complex(dp) :: s; s = czero
        do j = 1, m; s = s + p(j) * psi(j,k,l); end do
        signal(k,l) = s
      end do
    end do
    !$omp end parallel do
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! entropy — von Neumann / Shannon entropy of measurement distribution
  !
  ! {-@ entropy :: Simplex m → {e : Float | e ≥ 0}                 @-}
  !
  ! APL:  H ← - +/ (p × ⍟p)    — reduce + of p × log p
  !       H = 0: pure state (one eigenvalue dominates)
  !       H = log m: maximally mixed (all eigenvalues equal 1/m)
  !═══════════════════════════════════════════════════════════════════
  function entropy(p_ptr, m) result(H) &
       bind(C, name="spectral_entropy")
    type(c_ptr),        intent(in), value :: p_ptr
    integer(c_int64_t), intent(in), value :: m
    real(dp) :: H

    real(dp), pointer :: p(:)
    integer(c_int64_t) :: j

    call c_f_pointer(p_ptr, p, [m])

    ! APL:  H ← - +/ (p × ⍟p)
    H = 0.0_dp
    do j = 1, m
      if (p(j) > epsilon(0.0_dp)) then
        H = H - p(j) * log(p(j))
      end if
    end do
    ! Normalize to [0,1]: divide by log(m)  (APL: H ÷ ⍟m)
    if (m > 1) H = H / log(real(m, dp))
  end function

  !═══════════════════════════════════════════════════════════════════
  ! argmax_spectral — ⍒p: grade down (index of maximum eigenvalue)
  !
  ! {-@ argmax_spectral :: Simplex m → {i : Int | 0 ≤ i < m}      @-}
  !
  ! APL:  ⊃⍒p    — first of grade-down = argmax
  !═══════════════════════════════════════════════════════════════════
  function argmax_spectral(p_ptr, m) result(idx) &
       bind(C, name="argmax_spectral")
    type(c_ptr),        intent(in), value :: p_ptr
    integer(c_int64_t), intent(in), value :: m
    integer(c_int64_t) :: idx

    real(dp),    pointer :: p(:)
    real(dp)             :: max_val
    integer(c_int64_t)   :: j

    call c_f_pointer(p_ptr, p, [m])

    ! APL:  ⊃⍒p    — index of maximum (1-based → 0-based for C ABI)
    idx = 0; max_val = -huge(0.0_dp)
    do j = 1, m
      if (p(j) > max_val) then; max_val = p(j); idx = j - 1; end if
    end do
  end function

  !═══════════════════════════════════════════════════════════════════
  ! sample_spectral — p ⌸ ⍳m: sample index from Born distribution
  !
  ! {-@ sample_spectral :: Simplex m → Uniform01 → {i : Int | 0 ≤ i < m} @-}
  !
  ! APL:  (p ⌸ ⍳m) u    — key ⌸: partition ⍳m by cumulative p, pick bucket u
  !       Uses quantum entropy seed u ∈ [0,1) (passed from ANU QRNG)
  !═══════════════════════════════════════════════════════════════════
  function sample_spectral(p_ptr, m, u) result(idx) &
       bind(C, name="sample_spectral")
    type(c_ptr),        intent(in), value :: p_ptr
    integer(c_int64_t), intent(in), value :: m
    real(dp),           intent(in), value :: u    ! ∈ [0,1) from QRNG
    integer(c_int64_t) :: idx

    real(dp), pointer :: p(:)
    real(dp)          :: cdf
    integer(c_int64_t) :: j

    call c_f_pointer(p_ptr, p, [m])

    ! APL:  p ⌸ ⍳m    — cumulative sum (APL +\p), find first bucket ≥ u
    idx = m - 1   ! default: last bucket
    cdf = 0.0_dp
    do j = 1, m
      cdf = cdf + p(j)
      if (u < cdf) then; idx = j - 1; exit; end if
    end do
  end function

  !═══════════════════════════════════════════════════════════════════
  ! fib_anneal — Fibonacci temperature schedule for annealing inference
  !
  ! {-@ fib_anneal :: {k:Int | k≥0} → {τ:Float | τ > 0}           @-}
  !
  ! APL:  τ_k ← φ⁻ᵏ × τ_0    — φ⁻¹ contraction each step
  !       k=0: τ_0 (hot, explores)
  !       k→∞: 0   (cold, argmax)
  !       Converges at Fibonacci rate: exactly the Banach rate of jordan_block
  !═══════════════════════════════════════════════════════════════════
  function fib_anneal(tau_0, k) result(tau_k) &
       bind(C, name="fib_anneal")
    real(dp),           intent(in), value :: tau_0
    integer(c_int64_t), intent(in), value :: k
    real(dp) :: tau_k

    ! APL:  τ_k ← τ_0 × φ⁻ᵏ   — power of golden ratio inverse
    tau_k = tau_0 * PHI_INV**k
    tau_k = max(tau_k, 1.0e-12_dp)  ! Never exactly zero
  end function

end module measurement_head
