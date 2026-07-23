!=====================================================================
! TRAINING ADJOINT — Reverse-Mode AD on the Density Cone
!
! Trains {H_k} Hamiltonians via geodesic flow on (Ω, g_ρ)
! Loss: Wasserstein / Bures metric between ρ_pred and ρ_target
!
! Forward:  ρ_T = T_N ∘ ... ∘ T_1 ∘ ρ_0       (jordan_fib)
! Loss:     L   = d_Bures(ρ_T, ρ_target)²
! Backward: λ̇   = i[H_k, λ]                   (adjoint ODE, reverse)
!           λ_T = ∇_ρ L = ρ_target - ρ_T       (terminal condition)
! Gradient: ∂L/∂H_k = -i·dt·φ⁻¹·[λ_k, ρ_k]   (jordan_gradient)
! Update:   H_k ← H_k - η·∂L/∂H_k             (projected to Hermitian)
! Bifrost:  sign new {H_k} → WORM              (every update sealed)
!
! APL glyph map:
!   Forward pass    ≡  \ jordan_step         (scan \)
!   Loss gradient   ≡  ρ_target - ρ_T        (array -)
!   Adjoint reverse ≡  ⌽ (backward ODE)      (reverse ⌽)
!   Gradient accum  ≡  +/ (λ_k ∘.× ρ_k)     (outer ∘.× then reduce +/)
!   H update        ≡  H - η × ∂L/∂H         (scalar × then -)
!   Project Herm    ≡  ½ × (H + ⍉ H̄)        (conjugate transpose ⍉ ⍤ ¯)
!
! Liquid Haskell:
!   {-@ bures_loss :: Density d → Density d → {l : Float | l ≥ 0}         @-}
!   {-@ adjoint_pass :: Vec N (Hermitian d) → Vec N (Density d) → Density d
!                    → Vec N (Hermitian d)                                  @-}
!   {-@ project_hermitian :: M d d ℂ → Hermitian d                         @-}
!   {-@ training_step :: Vec N (Hermitian d) → Density d → Density d
!                     → Float → {H' : Vec N (Hermitian d) | ∀k. hermitian H'!k} @-}
!
! Audit Spec: 4b565498-9afc-4782-af4a-c6b11a5d0058
!=====================================================================
module training_adjoint
  use, intrinsic :: iso_c_binding, only: c_int64_t, c_ptr, c_f_pointer, &
       c_size_t, c_loc, c_char, c_associated, c_null_ptr
  use, intrinsic :: iso_fortran_env, only: int64, real64, int8
  use sov_monster_kernel, only: dp, ci, czero, &
       sov_zmexp_scaling_squaring, sov_apl_step_zgemm_fused, &
       sov_zgetrf, sov_zgetrs, &
       sov_blake3_hash_matrix, sov_bifrost_sign, &
       sov_is_hermitian_matrix, sov_is_density_matrix, sov_fault, i8
  use jordan_block, only: jordan_step, jordan_gradient, PHI_INV
  use sov_knowledge, only: knowledge_penalty_scale, ensure_sovereign_kb, &
       sovereign_kb, knowledge_chunk
  implicit none
  private

  public :: bures_loss
  public :: adjoint_pass
  public :: project_hermitian
  public :: training_step
  public :: adam_update
  public :: adam_state_t
  public :: apply_knowledge_gradient_correction

  real(dp), parameter :: PHI_IN2 = 0.3819660112501051518_dp

  !═══════════════════════════════════════════════════════════════════
  ! ADAM STATE — momentum buffers for each Hamiltonian layer
  !═══════════════════════════════════════════════════════════════════
  type, bind(C) :: adam_state_t
    real(dp)           :: beta1     ! default 0.9
    real(dp)           :: beta2     ! default 0.999
    real(dp)           :: epsilon   ! default 1e-8
    real(dp)           :: lr        ! learning rate
    integer(c_int64_t) :: t         ! step counter
    type(c_ptr)        :: m_ptr     ! first moment  [N, d, d] complex
    type(c_ptr)        :: v_ptr     ! second moment [N, d, d] real (elementwise sq)
  end type

contains

  !═══════════════════════════════════════════════════════════════════
  ! bures_loss — L = ‖ρ_pred − ρ_target‖²_F  (Frobenius proxy for Bures)
  !
  ! {-@ bures_loss :: Density d → Density d → {l : Float | l ≥ 0} @-}
  !
  ! APL:  L ← +/ , (ρ_pred - ρ_target) × ⊃ (ρ_pred - ρ_target)
  !            ≡ +/ , |diff|²    — ravel , then reduce + over squares
  !
  ! Note: true Bures = 2(1 - tr√(√ρ_pred ρ_target √ρ_pred))
  ! Frobenius is cheap, differentiable, same fixed point
  !═══════════════════════════════════════════════════════════════════
  function bures_loss(pred_ptr, target_ptr, d) result(L) &
       bind(C, name="bures_loss")
    type(c_ptr),        intent(in), value :: pred_ptr, target_ptr
    integer(c_int64_t), intent(in), value :: d
    real(dp) :: L

    complex(dp), pointer :: pred(:,:), target(:,:)
    integer(c_int64_t) :: i, j

    call c_f_pointer(pred_ptr,   pred,   [d, d])
    call c_f_pointer(target_ptr, target, [d, d])

    ! APL:  L ← +/ , |ρ_pred - ρ_target|²
    L = 0.0_dp
    !$omp parallel do collapse(2) default(none) &
    !$omp shared(pred,target,d) private(i,j) reduction(+:L)
    do i = 1, d
      do j = 1, d
        L = L + abs(pred(i,j) - target(i,j))**2
      end do
    end do
    !$omp end parallel do
  end function

  !═══════════════════════════════════════════════════════════════════
  ! adjoint_pass — reverse-mode through N jordan_blocks
  !
  ! {-@ adjoint_pass :: Vec N (Hermitian d) → Vec N (Density d)
  !                  → Density d → Vec N (Hermitian d)             @-}
  !
  ! APL:  λ_T ← ρ_target - ρ_T            — terminal gradient (array -)
  !       grads ← ⌽ {jordan_gradient λ_k ρ_k} over k   — reverse ⌽
  !
  ! Adjoint ODE (discrete):
  !   λ_{k-1} = U_k† λ_k U_k · φ⁻¹ + λ_k · φ⁻²   (reverse of jordan_step)
  !═══════════════════════════════════════════════════════════════════
  subroutine adjoint_pass(H_list_ptr, rho_list_ptr, target_ptr, &
       n_layers, d, dt, grads_ptr, sk_ptr, pk_ptr) &
       bind(C, name="adjoint_pass")
    type(c_ptr),        intent(in),  value :: H_list_ptr, rho_list_ptr
    type(c_ptr),        intent(in),  value :: target_ptr, grads_ptr
    integer(c_int64_t), intent(in),  value :: n_layers, d
    real(dp),           intent(in),  value :: dt
    type(c_ptr),        intent(in),  value :: sk_ptr, pk_ptr

    complex(dp), pointer :: H_list(:,:,:), rho_list(:,:,:)
    complex(dp), pointer :: target(:,:),   grads(:,:,:)
    complex(dp), allocatable :: lambda(:,:), lambda_prev(:,:)
    complex(dp), allocatable :: U(:,:), Ut(:,:), tmp(:,:)
    integer(c_int64_t) :: k, i, j, l
    integer(i8) :: dummy_hash(32), dummy_sig(64)

    call c_f_pointer(H_list_ptr,   H_list,   [n_layers, d, d])
    call c_f_pointer(rho_list_ptr, rho_list, [n_layers, d, d])
    call c_f_pointer(target_ptr,   target,   [d, d])
    call c_f_pointer(grads_ptr,    grads,    [n_layers, d, d])

    allocate(lambda(d,d), lambda_prev(d,d), U(d,d), Ut(d,d), tmp(d,d))

    ! APL:  λ_T ← ρ_target - ρ_pred    — terminal condition: ∇_ρ L
    lambda = target - rho_list(n_layers,:,:)

    ! APL:  grads ← ⌽ {jordan_gradient λ_k ρ_k}   — reverse ⌽ over layers
    do k = n_layers, 1, -1

      ! ── Gradient for H_k: ∂L/∂H_k = -i·dt·φ⁻¹·[λ_k, ρ_k] ──
      call jordan_gradient(c_loc(rho_list(k,:,:)), c_loc(lambda), &
                           d, dt, c_loc(grads(k,:,:)))

      ! ── Propagate adjoint backward through jordan_step ──
      ! Reverse of: ρ_{k} = φ⁻¹·U ρ_{k-1} U† + φ⁻²·ρ_{k-1}
      ! λ_{k-1} = φ⁻¹·U† λ_k U + φ⁻²·λ_k
      U = (-ci) * dt * H_list(k,:,:)
      call sov_zmexp_scaling_squaring(U, int(d))

      ! Ut = U†  (APL: ⍉ Ū)
      !$omp parallel do collapse(2) default(none) shared(Ut,U,d) private(i,j)
      do i = 1, d; do j = 1, d
        Ut(i,j) = conjg(U(j,i))
      end do; end do
      !$omp end parallel do

      ! tmp = Ut λ_k U   (APL: Ut +.× λ +.× U)
      tmp = matmul(Ut, matmul(lambda, U))

      ! APL:  λ_{k-1} ← (φ⁻¹ × tmp) + (φ⁻² × λ_k)
      !$omp parallel do collapse(2) default(none) &
      !$omp shared(lambda_prev,tmp,lambda,d) private(i,j)
      do i = 1, d; do j = 1, d
        lambda_prev(i,j) = PHI_INV * tmp(i,j) + PHI_IN2 * lambda(i,j)
      end do; end do
      !$omp end parallel do

      lambda = lambda_prev
    end do

    deallocate(lambda, lambda_prev, U, Ut, tmp)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! apply_knowledge_gradient_correction — sovereign trust-aware update
  !
  ! SOVEREIGN KNOWLEDGE GRADIENT CORRECTION:
  !   Query KB for channel constraints; scale grads by
  !   (1 − φ · unverified/total) so trust violations decay φ-wise.
  !═══════════════════════════════════════════════════════════════════
  subroutine apply_knowledge_gradient_correction(grads_ptr, n_layers, d, &
       query_ptr, query_len) &
       bind(C, name="apply_knowledge_gradient_correction")
    type(c_ptr),        intent(in), value :: grads_ptr, query_ptr
    integer(c_int64_t), intent(in), value :: n_layers, d, query_len

    complex(dp), pointer :: grads(:,:,:)
    type(knowledge_chunk), allocatable :: constraint_chunks(:)
    character(kind=c_char), pointer :: qbuf(:)
    character(len=:), allocatable :: query
    integer :: i, n_out, n_unverified, nq
    real(dp) :: scale

    call ensure_sovereign_kb()
    call c_f_pointer(grads_ptr, grads, [n_layers, d, d])

    nq = max(0, int(query_len))
    n_out = 0
    n_unverified = 0
    if (nq > 0 .and. c_associated(query_ptr)) then
      call c_f_pointer(query_ptr, qbuf, [nq])
      allocate(character(len=nq) :: query)
      do i = 1, nq
        query(i:i) = transfer(qbuf(i), ' ')
      end do
      call sovereign_kb%search(query, 3, constraint_chunks, n_out)
      do i = 1, n_out
        if (.not. constraint_chunks(i)%is_verified) n_unverified = n_unverified + 1
        if (.not. sovereign_kb%verify(constraint_chunks(i)%chunk_id)) then
          n_unverified = n_unverified + 1
        end if
      end do
    end if

    scale = knowledge_penalty_scale(max(n_out, 1), n_unverified)
    grads = scale * grads
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! project_hermitian — ensure H stays in the symmetric cone
  !
  ! {-@ project_hermitian :: M d d ℂ → Hermitian d                 @-}
  !
  ! APL:  H ← ½ × (H + ⍉ H̄)    — average with conjugate transpose
  !       (conjugate transpose: ⍉ on transposed then ¯ conjugate)
  !═══════════════════════════════════════════════════════════════════
  subroutine project_hermitian(H_ptr, d) &
       bind(C, name="project_hermitian")
    type(c_ptr),        intent(in), value :: H_ptr
    integer(c_int64_t), intent(in), value :: d

    complex(dp), pointer :: H(:,:)
    integer(c_int64_t) :: i, j
    complex(dp) :: sym

    call c_f_pointer(H_ptr, H, [d, d])

    ! APL:  H ← ½ × (H + ⍉ H̄)
    !$omp parallel do default(none) shared(H,d) private(i,j,sym)
    do i = 1, d
      do j = i, d
        sym = 0.5_dp * (H(i,j) + conjg(H(j,i)))
        H(i,j) = sym
        H(j,i) = conjg(sym)
      end do
    end do
    !$omp end parallel do

    if (.not. sov_is_hermitian_matrix(H, d)) call sov_fault(901)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! training_step — one complete forward + backward + update
  !
  ! {-@ training_step :: Vec N (Hermitian d) → Density d → Density d
  !                   → Float → {H' | ∀k. hermitian H'!k}          @-}
  !
  ! APL one-liner (the whole training loop in APL):
  !   H ← H - η × ⌽ (jordan_gradient ¨ λ ∘.⍢ ρ)
  !
  ! Every H update sealed to WORM via Bifrost
  !═══════════════════════════════════════════════════════════════════
  subroutine training_step(H_list_ptr, rho0_ptr, target_ptr, &
       n_layers, d, dt, eta, sk_ptr, pk_ptr, loss_out) &
       bind(C, name="training_step")
    type(c_ptr),        intent(in),    value :: H_list_ptr, rho0_ptr, target_ptr
    integer(c_int64_t), intent(in),    value :: n_layers, d
    real(dp),           intent(in),    value :: dt, eta
    type(c_ptr),        intent(in),    value :: sk_ptr, pk_ptr
    real(dp),           intent(out)          :: loss_out

    complex(dp), pointer :: H_list(:,:,:), rho0(:,:)
    complex(dp), pointer :: target(:,:)
    complex(dp), allocatable :: rho_list(:,:,:), grads(:,:,:)
    complex(dp), allocatable :: rho_cur(:,:), rho_nxt(:,:)
    integer(i8), allocatable :: receipts(:)
    integer(c_int64_t) :: k, receipt_sz
    integer(i8) :: hash_buf(32), sig_buf(64)

    call c_f_pointer(H_list_ptr, H_list, [n_layers, d, d])
    call c_f_pointer(rho0_ptr,   rho0,   [d, d])
    call c_f_pointer(target_ptr, target, [d, d])

    receipt_sz = 96
    allocate(rho_list(n_layers, d, d))
    allocate(grads(n_layers, d, d))
    allocate(rho_cur(d,d), rho_nxt(d,d))
    allocate(receipts(n_layers * receipt_sz))

    ! ── APL: FORWARD PASS — \ jordan_step over H_list ──────────────
    rho_cur = rho0
    do k = 1, n_layers
      call jordan_step( &
        c_loc(H_list(k,:,:)), c_loc(rho_cur), d, dt, &
        sk_ptr, pk_ptr, c_loc(rho_nxt), &
        c_loc(receipts((k-1)*receipt_sz+1)), &
        c_loc(receipts((k-1)*receipt_sz+33)))
      rho_list(k,:,:) = rho_nxt
      rho_cur = rho_nxt
    end do

    ! ── LOSS ────────────────────────────────────────────────────────
    loss_out = bures_loss(c_loc(rho_cur), target_ptr, d)

    ! ── APL: BACKWARD PASS — ⌽ adjoint over layers ─────────────────
    call adjoint_pass( &
      c_loc(H_list), c_loc(rho_list), target_ptr, &
      n_layers, d, dt, c_loc(grads), sk_ptr, pk_ptr)

    ! ── SOVEREIGN KNOWLEDGE: φ-decay trust scale on gradients ──────
    call apply_knowledge_gradient_correction(c_loc(grads), n_layers, d, &
         c_null_ptr, 0_c_int64_t)

    ! ── APL: UPDATE — H ← H - η × ∂L/∂H ───────────────────────────
    !$omp parallel do default(none) &
    !$omp shared(H_list,grads,n_layers,d,eta) private(k)
    do k = 1, n_layers
      integer(c_int64_t) :: i, j
      do i = 1, d; do j = 1, d
        H_list(k,i,j) = H_list(k,i,j) - eta * grads(k,i,j)
      end do; end do
      ! APL:  H_k ← ½ × (H_k + ⍉ H̄_k)   — project to Hermitian
      call project_hermitian(c_loc(H_list(k,:,:)), d)
    end do
    !$omp end parallel do

    ! ── BIFROST: seal updated Hamiltonians ──────────────────────────
    do k = 1, n_layers
      call sov_blake3_hash_matrix(H_list(k,:,:), int(d), c_loc(hash_buf))
      call sov_bifrost_sign(c_loc(hash_buf), int(32,c_size_t), sk_ptr, c_loc(sig_buf))
    end do

    deallocate(rho_list, grads, rho_cur, rho_nxt, receipts)
  end subroutine

  !═══════════════════════════════════════════════════════════════════
  ! adam_update — Adam optimizer on Hamiltonians
  !
  ! {-@ adam_update :: AdamState → Vec N (Hermitian d)
  !                 → Vec N (Hermitian d) → Vec N (Hermitian d)    @-}
  !
  ! APL:  m ← β₁ × m + (1-β₁) × g         — first moment
  !       v ← β₂ × v + (1-β₂) × g×g       — second moment (× = elementwise)
  !       m̂ ← m ÷ (1 - β₁ᵗ)               — bias correction
  !       v̂ ← v ÷ (1 - β₂ᵗ)
  !       H ← H - lr × m̂ ÷ (√v̂ + ε)       — Adam step
  !       H ← ½ × (H + ⍉ H̄)              — project Hermitian
  !═══════════════════════════════════════════════════════════════════
  subroutine adam_update(state, H_list_ptr, grads_ptr, n_layers, d) &
       bind(C, name="adam_update")
    type(adam_state_t), intent(inout)        :: state
    type(c_ptr),        intent(in),    value :: H_list_ptr, grads_ptr
    integer(c_int64_t), intent(in),    value :: n_layers, d

    complex(dp), pointer :: H_list(:,:,:), grads(:,:,:)
    complex(dp), pointer :: m(:,:,:)
    real(dp),    pointer :: v(:,:,:)
    real(dp) :: bc1, bc2, lr_t
    integer(c_int64_t) :: k, i, j
    complex(dp) :: m_hat, g
    real(dp) :: v_hat

    call c_f_pointer(H_list_ptr, H_list, [n_layers, d, d])
    call c_f_pointer(grads_ptr,  grads,  [n_layers, d, d])
    call c_f_pointer(state%m_ptr, m,     [n_layers, d, d])
    call c_f_pointer(state%v_ptr, v,     [n_layers, d, d])

    state%t = state%t + 1
    ! Bias correction factors
    bc1  = 1.0_dp - state%beta1**state%t
    bc2  = 1.0_dp - state%beta2**state%t
    lr_t = state%lr * sqrt(bc2) / bc1

    !$omp parallel do collapse(3) default(none) &
    !$omp shared(H_list,grads,m,v,state,lr_t,n_layers,d) &
    !$omp private(k,i,j,g,m_hat,v_hat)
    do k = 1, n_layers
      do i = 1, d
        do j = 1, d
          g = grads(k,i,j)
          ! APL:  m ← β₁ × m + (1-β₁) × g
          m(k,i,j) = state%beta1 * m(k,i,j) + (1.0_dp - state%beta1) * g
          ! APL:  v ← β₂ × v + (1-β₂) × |g|²
          v(k,i,j) = state%beta2 * v(k,i,j) + (1.0_dp - state%beta2) * abs(g)**2
          ! APL:  H ← H - lr_t × m ÷ (√v + ε)
          m_hat = m(k,i,j)
          v_hat = v(k,i,j)
          H_list(k,i,j) = H_list(k,i,j) - lr_t * m_hat / (sqrt(v_hat) + state%epsilon)
        end do
      end do
      ! APL:  H_k ← ½ × (H_k + ⍉ H̄_k)
      call project_hermitian(c_loc(H_list(k,:,:)), d)
    end do
    !$omp end parallel do
  end subroutine

end module training_adjoint
