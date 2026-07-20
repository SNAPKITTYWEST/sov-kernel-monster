! ═════════════════════════════════════════════════════════════════════════
! FORTRAN HASKELL BRIDGE — Theorem 3 Integration
! Sprint 2 Phase 2.2
! ═════════════════════════════════════════════════════════════════════════

module fortran_haskell_bridge
  use, intrinsic :: iso_c_binding
  use bob_kinds
  implicit none
  private

  ! ═════════════════════════════════════════════════════════════════════
  ! Haskell entry points via QuantumFortranBridge.hs
  ! ═════════════════════════════════════════════════════════════════════

  interface
    function haskell_theorem3_offload(poly_str, energy_budget) &
             bind(C, name="haskell_theorem3_offload")
      use iso_c_binding
      character(kind=c_char) :: poly_str(*)
      integer(c_int), value :: energy_budget
      integer(c_int) :: haskell_theorem3_offload
    end function haskell_theorem3_offload

    function haskell_verify_genus_zero(polynomial_coeffs, num_coeffs) &
             bind(C, name="haskell_verify_genus_zero")
      use iso_c_binding
      real(c_double) :: polynomial_coeffs(*)
      integer(c_int), value :: num_coeffs
      integer(c_int) :: haskell_verify_genus_zero
    end function haskell_verify_genus_zero
  end interface

  public :: fortran_call_theorem3_kernel
  public :: fortran_verify_polynomial_genus
  public :: fortran_theorem3_energy_accounting

contains

  ! ─────────────────────────────────────────────────────────────────────
  ! Call Theorem 3 kernel with polynomial string
  ! ─────────────────────────────────────────────────────────────────────
  subroutine fortran_call_theorem3_kernel(poly_str, energy_budget, status)
    character(len=*), intent(in) :: poly_str
    integer, intent(in) :: energy_budget
    integer, intent(out) :: status

    status = haskell_theorem3_offload(trim(poly_str) // c_null_char, int(energy_budget, c_int))
  end subroutine fortran_call_theorem3_kernel

  ! ─────────────────────────────────────────────────────────────────────
  ! Verify polynomial genus with coefficient array
  ! ─────────────────────────────────────────────────────────────────────
  subroutine fortran_verify_polynomial_genus(coeffs, num_coeffs, genus_status)
    real(c_double), intent(in) :: coeffs(:)
    integer, intent(in) :: num_coeffs
    integer, intent(out) :: genus_status

    genus_status = haskell_verify_genus_zero(coeffs, int(num_coeffs, c_int))
  end subroutine fortran_verify_polynomial_genus

  ! ─────────────────────────────────────────────────────────────────────
  ! Energy accounting wrapper
  ! ─────────────────────────────────────────────────────────────────────
  subroutine fortran_theorem3_energy_accounting(energy_spent, energy_budget, energy_remaining)
    integer, intent(in) :: energy_spent, energy_budget
    integer, intent(out) :: energy_remaining

    energy_remaining = energy_budget - energy_spent
  end subroutine fortran_theorem3_energy_accounting

end module fortran_haskell_bridge
