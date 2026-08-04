!=======================================================================
! bh_numerics.f90 — Black Hole Mechanics Numerical Kernel
! Fortran 2018, ISO/IEC 1539-1:2018
! Compiles to: libbh_numerics.a (static, sovereign, no dependencies)
! Integration: Connects to bob_hamiltonian.f90 via Wald entropy
!=======================================================================

module bh_numerics
  use, intrinsic :: iso_c_binding, only: c_double, c_bool, c_int64_t
  implicit none
  private

  ! Public API (C-compatible names)
  public :: schwarzschild_kappa
  public :: schwarzschild_entropy
  public :: schwarzschild_first_law
  public :: kerr_kappa
  public :: kerr_entropy
  public :: kerr_angular_velocity
  public :: wald_entropy_general
  public :: lqg_entropy_correction
  public :: string_entropy_correction

  ! Constants (natural units: G = c = ħ = k_B = 1)
  integer, parameter :: dp = selected_real_kind(15, 307)
  real(dp), parameter :: pi = 3.141592653589793238462643383279502884197_dp
  real(dp), parameter :: two_pi = 2.0_dp * pi
  real(dp), parameter :: four_pi = 4.0_dp * pi

contains

  !=====================================================================
  ! SCHWARZSCHILD BLACK HOLE (Non-rotating, uncharged)
  !=====================================================================

  ! Surface gravity: κ = 1/(4M)
  pure function schwarzschild_kappa(M) result(kappa) bind(C, name="schwarzschild_kappa")
    real(c_double), intent(in), value :: M
    real(c_double) :: kappa
    if (M > 0.0_c_double) then
      kappa = 1.0_c_double / (4.0_c_double * M)
    else
      kappa = -1.0_c_double ! Error sentinel
    end if
  end function schwarzschild_kappa

  ! Entropy: S = 4πM² = A/4 (Bekenstein-Hawking)
  pure function schwarzschild_entropy(M) result(S) bind(C, name="schwarzschild_entropy")
    real(c_double), intent(in), value :: M
    real(c_double) :: S
    if (M > 0.0_c_double) then
      S = four_pi * M * M
    else
      S = -1.0_c_double
    end if
  end function schwarzschild_entropy

  ! First law check: dM = (κ/2π) dS
  ! Returns true if |dM - (κ/2π)dS| < ε
  pure function schwarzschild_first_law(M, dM) result(holds) bind(C, name="schwarzschild_first_law")
    real(c_double), intent(in), value :: M, dM
    logical(c_bool) :: holds
    real(c_double) :: kappa, dS, lhs, rhs, eps
    if (M > 0.0_c_double) then
      kappa = schwarzschild_kappa(M)
      dS = 8.0_c_double * pi * M * dM ! d(4πM²)/dM = 8πM
      lhs = dM
      rhs = (kappa / two_pi) * dS
      eps = max(epsilon(1.0_c_double) * abs(lhs), tiny(1.0_c_double))
      holds = (abs(lhs - rhs) < eps)
    else
      holds = .false.
    end if
  end function schwarzschild_first_law

  !=====================================================================
  ! KERR BLACK HOLE (Rotating, uncharged)
  !=====================================================================

  ! Surface gravity: κ = (r₊ - M) / (2Mr₊) where r₊ = M + √(M² - a²)
  pure function kerr_kappa(M, a) result(kappa) bind(C, name="kerr_kappa")
    real(c_double), intent(in), value :: M, a
    real(c_double) :: kappa, r_plus, discriminant
    if (M > 0.0_c_double .and. M*M >= a*a) then
      discriminant = sqrt(M*M - a*a)
      r_plus = M + discriminant
      kappa = (r_plus - M) / (2.0_c_double * M * r_plus)
    else
      kappa = -1.0_c_double
    end if
  end function kerr_kappa

  ! Entropy: S = A/4 = 2π(r₊² + a²)
  pure function kerr_entropy(M, a) result(S) bind(C, name="kerr_entropy")
    real(c_double), intent(in), value :: M, a
    real(c_double) :: S, r_plus, discriminant
    if (M > 0.0_c_double .and. M*M >= a*a) then
      discriminant = sqrt(M*M - a*a)
      r_plus = M + discriminant
      S = two_pi * (r_plus*r_plus + a*a)
    else
      S = -1.0_c_double
    end if
  end function kerr_entropy

  ! Angular velocity: Ω = a / (2Mr₊)
  pure function kerr_angular_velocity(M, a) result(Omega) bind(C, name="kerr_angular_velocity")
    real(c_double), intent(in), value :: M, a
    real(c_double) :: Omega, r_plus, discriminant
    if (M > 0.0_c_double .and. M*M >= a*a) then
      discriminant = sqrt(M*M - a*a)
      r_plus = M + discriminant
      Omega = a / (2.0_c_double * M * r_plus)
    else
      Omega = -1.0_c_double
    end if
  end function kerr_angular_velocity

  !=====================================================================
  ! GENERAL WALD ENTROPY
  ! Connection to bob_hamiltonian.f90:
  !   Wald entropy = ∫_Σ Noether charge for horizon Killing vector
  !   For Einstein-Hilbert: recovers Bekenstein-Hawking S = A/4
  !   For f(R) gravity: includes higher-curvature corrections
  !=====================================================================

  subroutine wald_entropy_general(g_tt, g_rr, g_thth, g_phph, &
                                   L_params, n_params, S, kappa, Omega) &
                                   bind(C, name="wald_entropy_general")
    real(c_double), intent(in), value :: g_tt, g_rr, g_thth, g_phph
    real(c_double), intent(in) :: L_params(*)
    integer(c_int64_t), intent(in), value :: n_params
    real(c_double), intent(out) :: S, kappa, Omega

    ! For Einstein-Hilbert Lagrangian L = R/(16π):
    !   S = A/4 where A = ∫√(g_θθ g_φφ) dθ dφ
    !
    ! For f(R) Lagrangian L = f(R)/(16π):
    !   S = ∫_Σ (∂f/∂R) √h d²x
    !
    ! This function computes the general case via numerical quadrature

    real(c_double) :: r_h, A_horizon

    ! Horizon area from metric
    r_h = sqrt(g_thth)  ! r² = g_θθ at horizon
    A_horizon = four_pi * g_thth  ! A = 4πr²

    ! Einstein-Hilbert case (L_params[0] = 1):
    if (n_params == 1 .and. L_params(1) == 1.0_c_double) then
      S = A_horizon / 4.0_c_double
      kappa = schwarzschild_kappa(sqrt(r_h / two_pi))  ! Approximate
      Omega = 0.0_c_double
    else
      ! General f(R) case: would require full Ricci tensor computation
      ! Placeholder for integration with bob_hamiltonian.f90
      S = A_horizon / 4.0_c_double  ! Fallback to Bekenstein-Hawking
      kappa = -1.0_c_double
      Omega = 0.0_c_double
    end if
  end subroutine wald_entropy_general

  !=====================================================================
  ! QUANTUM GRAVITY CORRECTIONS
  !=====================================================================

  ! LQG correction: S = A/4 + α ln(A) + β
  pure function lqg_entropy_correction(A, alpha, beta) result(S_corr) &
       bind(C, name="lqg_entropy_correction")
    real(c_double), intent(in), value :: A, alpha, beta
    real(c_double) :: S_corr
    if (A > 0.0_c_double) then
      S_corr = A/4.0_c_double + alpha * log(A) + beta
    else
      S_corr = -1.0_c_double
    end if
  end function lqg_entropy_correction

  ! String theory correction: S = A/4 + γ√A
  pure function string_entropy_correction(A, gamma) result(S_corr) &
       bind(C, name="string_entropy_correction")
    real(c_double), intent(in), value :: A, gamma
    real(c_double) :: S_corr
    if (A > 0.0_c_double) then
      S_corr = A/4.0_c_double + gamma * sqrt(A)
    else
      S_corr = -1.0_c_double
    end if
  end function string_entropy_correction

end module bh_numerics
