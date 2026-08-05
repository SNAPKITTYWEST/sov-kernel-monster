!=======================================================================
! bh_numerics.f90 -- Black Hole Mechanics Numerical Kernel
! Fortran 2018. Surface gravity, entropy, first law.
! Schwarzschild, Kerr, Wald, LQG, String corrections.
!=======================================================================

module bh_numerics
  use, intrinsic :: iso_c_binding, only: c_double, c_bool, c_int64_t
  implicit none
  private
  public :: schwarzschild_kappa, schwarzschild_entropy, schwarzschild_first_law
  public :: kerr_kappa, kerr_entropy, kerr_angular_velocity
  public :: lqg_entropy_correction, string_entropy_correction

  integer, parameter :: dp = selected_real_kind(15, 307)
  real(dp), parameter :: pi      = 3.141592653589793238462643383279502884197_dp
  real(dp), parameter :: two_pi  = 2.0_dp * pi
  real(dp), parameter :: four_pi = 4.0_dp * pi

contains

  ! Schwarzschild surface gravity: kappa = 1/(4M)
  pure function schwarzschild_kappa(M) result(kappa) bind(C, name="schwarzschild_kappa")
    real(c_double), intent(in), value :: M
    real(c_double) :: kappa
    if (M > 0.0_c_double) then
      kappa = 1.0_c_double / (4.0_c_double * M)
    else
      kappa = -1.0_c_double
    end if
  end function

  ! Schwarzschild entropy: S = 4 pi M^2
  pure function schwarzschild_entropy(M) result(S) bind(C, name="schwarzschild_entropy")
    real(c_double), intent(in), value :: M
    real(c_double) :: S
    if (M > 0.0_c_double) then
      S = four_pi * M * M
    else
      S = -1.0_c_double
    end if
  end function

  ! First law: dM = (kappa/2pi) dS
  pure function schwarzschild_first_law(M, dM) result(holds) bind(C, name="schwarzschild_first_law")
    real(c_double), intent(in), value :: M, dM
    logical(c_bool) :: holds
    real(c_double) :: kappa, dS, eps
    if (M > 0.0_c_double) then
      kappa = 1.0_c_double / (4.0_c_double * M)
      dS = 8.0_c_double * pi * M * dM
      eps = max(epsilon(1.0_c_double) * abs(dM), tiny(1.0_c_double))
      holds = (abs(dM - (kappa / two_pi) * dS) < eps)
    else
      holds = .false.
    end if
  end function

  ! Kerr surface gravity: kappa = (r+ - M)/(2 M r+)
  pure function kerr_kappa(M, a) result(kappa) bind(C, name="kerr_kappa")
    real(c_double), intent(in), value :: M, a
    real(c_double) :: kappa, r_plus
    if (M > 0.0_c_double .and. M*M >= a*a) then
      r_plus = M + sqrt(M*M - a*a)
      kappa = (r_plus - M) / (2.0_c_double * M * r_plus)
    else
      kappa = -1.0_c_double
    end if
  end function

  ! Kerr entropy: S = 2 pi (r+^2 + a^2)
  pure function kerr_entropy(M, a) result(S) bind(C, name="kerr_entropy")
    real(c_double), intent(in), value :: M, a
    real(c_double) :: S, r_plus
    if (M > 0.0_c_double .and. M*M >= a*a) then
      r_plus = M + sqrt(M*M - a*a)
      S = two_pi * (r_plus*r_plus + a*a)
    else
      S = -1.0_c_double
    end if
  end function

  ! Kerr angular velocity: Omega = a/(2 M r+)
  pure function kerr_angular_velocity(M, a) result(Omega) bind(C, name="kerr_angular_velocity")
    real(c_double), intent(in), value :: M, a
    real(c_double) :: Omega, r_plus
    if (M > 0.0_c_double .and. M*M >= a*a) then
      r_plus = M + sqrt(M*M - a*a)
      Omega = a / (2.0_c_double * M * r_plus)
    else
      Omega = -1.0_c_double
    end if
  end function

  ! LQG correction: S = A/4 + alpha*ln(A) + beta
  pure function lqg_entropy_correction(A, alpha, beta) result(S) bind(C, name="lqg_entropy_correction")
    real(c_double), intent(in), value :: A, alpha, beta
    real(c_double) :: S
    if (A > 0.0_c_double) then
      S = A/4.0_c_double + alpha * log(A) + beta
    else
      S = -1.0_c_double
    end if
  end function

  ! String correction: S = A/4 + gamma*sqrt(A)
  pure function string_entropy_correction(A, gamma) result(S) bind(C, name="string_entropy_correction")
    real(c_double), intent(in), value :: A, gamma
    real(c_double) :: S
    if (A > 0.0_c_double) then
      S = A/4.0_c_double + gamma * sqrt(A)
    else
      S = -1.0_c_double
    end if
  end function

end module bh_numerics
