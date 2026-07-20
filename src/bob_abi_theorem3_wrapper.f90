! ═════════════════════════════════════════════════════════════════════════
! BOB ABI THEOREM 3 WRAPPER — C ABI Entry Point
! Sprint 2 Phase 2.2
! ═════════════════════════════════════════════════════════════════════════

module bob_abi_theorem3_wrapper
  use, intrinsic :: iso_c_binding
  use bob_kinds
  use bob_abi
  use fortran_haskell_bridge
  implicit none
  private

  public :: bob_theorem3_enforce_genus_zero
  public :: bob_theorem3_parse_polynomial
  public :: bob_theorem3_destroy

contains

  ! ─────────────────────────────────────────────────────────────────────
  ! Main entry: enforce genus zero constraint
  ! ─────────────────────────────────────────────────────────────────────
  subroutine bob_theorem3_enforce_genus_zero(poly_str, energy_budget, status, genus) &
             bind(C, name="bob_theorem3_enforce_genus_zero")
    character(kind=c_char), intent(in) :: poly_str(*)
    integer(c_int), value :: energy_budget
    integer(c_int), intent(out) :: status
    integer(c_int), intent(out) :: genus

    character(len=1024) :: poly_fortran
    integer :: i, len_poly

    ! Convert C string to Fortran string
    i = 1
    do while (poly_str(i) /= c_null_char .and. i <= 1024)
      poly_fortran(i:i) = poly_str(i)
      i = i + 1
    end do
    len_poly = i - 1

    ! Call Haskell kernel via Fortran bridge
    call fortran_call_theorem3_kernel(poly_fortran(1:len_poly), int(energy_budget), status)
    genus = status  ! For now, status encodes genus
  end subroutine bob_theorem3_enforce_genus_zero

  ! ─────────────────────────────────────────────────────────────────────
  ! Parse polynomial string to coefficient array
  ! ─────────────────────────────────────────────────────────────────────
  function bob_theorem3_parse_polynomial(poly_str, coeffs, max_coeffs) &
           bind(C, name="bob_theorem3_parse_polynomial") result(num_coeffs)
    character(kind=c_char), intent(in) :: poly_str(*)
    real(c_double), intent(out) :: coeffs(*)
    integer(c_int), value :: max_coeffs
    integer(c_int) :: num_coeffs

    ! TODO: Implement polynomial string parser
    ! For now, stub returns 0 coefficients
    num_coeffs = 0
  end function bob_theorem3_parse_polynomial

  ! ─────────────────────────────────────────────────────────────────────
  ! Cleanup Haskell RTS if needed
  ! ─────────────────────────────────────────────────────────────────────
  subroutine bob_theorem3_destroy() bind(C, name="bob_theorem3_destroy")
    ! TODO: Cleanup Haskell RTS if needed
  end subroutine bob_theorem3_destroy

end module bob_abi_theorem3_wrapper
