! =====================================================================
! FORTRAN QUANTUM INTERFACE MODULE
! Supercomputer ↔ Haskell/Quantum Bridge for Theorem 3 Offload
! =====================================================================
! Purpose:
!   - Provides Fortran API for offloading Theorem 3 (genus-0 forcing) to
!     Haskell kernel via C FFI
!   - Marshals polynomial coefficients from Fortran to C string
!   - Handles energy budget accounting
!   - Returns genus proof status (0=success, 1=blocked, 2=counterexample)
!
! Usage:
!   use quantum_theorem3
!   call offload_theorem3_to_quantum(poly_str, energy_budget, status, genus)
!
! Standard: Fortran 2018, C Interop
! Compiler: GNU Fortran (gfortran)
! =====================================================================

module quantum_theorem3
  use iso_c_binding
  use bob_kinds, only: i4, dp
  implicit none

  private

  ! Public interface
  public :: offload_theorem3_to_quantum
  public :: polynomial_to_string
  public :: THEOREM3_SUCCESS
  public :: THEOREM3_BLOCKED
  public :: THEOREM3_COUNTEREXAMPLE
  public :: THEOREM3_PARSE_ERROR
  public :: THEOREM3_QUANTUM_FAILED

  ! Status codes (must match Haskell return values)
  integer, parameter :: THEOREM3_SUCCESS         = 0  ! Genus-0 proved + quantum verified
  integer, parameter :: THEOREM3_BLOCKED         = 1  ! Obstruction hit (singular point, etc.)
  integer, parameter :: THEOREM3_COUNTEREXAMPLE  = 2  ! Higher genus detected
  integer, parameter :: THEOREM3_PARSE_ERROR     = 3  ! Polynomial string parse failed
  integer, parameter :: THEOREM3_QUANTUM_FAILED  = 4  ! Quantum verification rejected

  ! ===================================================================
  ! C INTERFACE TO HASKELL FFI
  ! ===================================================================

  interface
    function haskell_theorem3_offload(poly_str, energy_budget) bind(C, name="haskell_theorem3_offload")
      use iso_c_binding
      implicit none
      character(kind=c_char), intent(in) :: poly_str(*)
      integer(c_int), value :: energy_budget
      integer(c_int) :: haskell_theorem3_offload
    end function haskell_theorem3_offload
  end interface

contains

  ! ===================================================================
  ! MAIN PUBLIC SUBROUTINE: Offload Theorem 3 to Quantum Chip
  ! ===================================================================

  subroutine offload_theorem3_to_quantum(poly_str, energy_budget, result_status, result_genus)
    ! ================================================================
    ! Arguments:
    !   poly_str (in)      : Polynomial string "1*u^2 + 2*u*x + 3*x^2"
    !   energy_budget (in) : Energy budget (integer)
    !   result_status (out): Status code (0,1,2,3,4)
    !   result_genus (out) : Genus bound (0 if success, >0 if counterex)
    ! ================================================================

    character(len=*), intent(in) :: poly_str
    integer(i4), intent(in) :: energy_budget
    integer(i4), intent(out) :: result_status
    integer(i4), intent(out) :: result_genus

    integer(c_int) :: haskell_result
    character(kind=c_char, len=:), allocatable :: c_poly_str
    integer(c_int) :: c_budget

    ! Convert Fortran string to C string (null-terminated)
    allocate(character(kind=c_char, len=len_trim(poly_str)+1) :: c_poly_str)
    c_poly_str = trim(poly_str) // c_null_char

    ! Convert energy budget to C int
    c_budget = int(energy_budget, c_int)

    ! Call Haskell bridge
    haskell_result = haskell_theorem3_offload(c_poly_str, c_budget)

    ! Marshal result back to Fortran
    result_status = int(haskell_result, i4)

    ! Extract genus from status code
    ! In this simplified API:
    !   0 = success, genus = 0 (rational curve)
    !   1 = blocked, genus = -1 (unknown)
    !   2 = counterexample, genus = unknown (reported separately from kernel)
    !   3 = parse error, genus = -1
    !   4 = quantum failed, genus = -1
    select case (result_status)
      case (THEOREM3_SUCCESS)
        result_genus = 0  ! Genus-0 proved
      case (THEOREM3_BLOCKED)
        result_genus = -1 ! Unknown (obstruction)
      case (THEOREM3_COUNTEREXAMPLE)
        result_genus = 1  ! At least genus > 0
      case default
        result_genus = -1 ! Error
    end select

    ! Cleanup
    deallocate(c_poly_str)

  end subroutine offload_theorem3_to_quantum

  ! ===================================================================
  ! HELPER: Convert Polynomial Coefficients to String
  ! ===================================================================

  function polynomial_to_string(coeffs, degrees_u, degrees_x) result(poly_str)
    ! ================================================================
    ! Purpose: Build polynomial string from Fortran arrays
    ! Input arrays must be same length
    ! Example: coeffs=[1,2,3], degrees_u=[2,1,0], degrees_x=[0,1,2]
    !         → "1*u^2 + 2*u^1*x^1 + 3*x^2"
    ! ================================================================

    real(dp), intent(in) :: coeffs(:)
    integer(i4), intent(in) :: degrees_u(:)
    integer(i4), intent(in) :: degrees_x(:)
    character(len=:), allocatable :: poly_str

    integer :: i, n, str_len
    character(len=4096) :: buffer
    character(len=256) :: term_str

    n = size(coeffs)

    if (n == 0) then
      poly_str = "0"
      return
    end if

    ! Build polynomial string
    buffer = ""
    do i = 1, n
      ! Format coefficient
      if (i == 1) then
        ! First term: no leading + sign
        write(term_str, '(F0.1, A, I0, A, I0)') &
          coeffs(i), "*u^", degrees_u(i), "*x^", degrees_x(i)
      else
        ! Subsequent terms: add + sign (or - for negative coeffs)
        if (coeffs(i) >= 0.0_dp) then
          write(term_str, '(A, F0.1, A, I0, A, I0)') &
            " + ", coeffs(i), "*u^", degrees_u(i), "*x^", degrees_x(i)
        else
          write(term_str, '(A, F0.1, A, I0, A, I0)') &
            " ", coeffs(i), "*u^", degrees_u(i), "*x^", degrees_x(i)
        end if
      end if

      ! Append to buffer
      str_len = len_trim(buffer)
      buffer = buffer(1:str_len) // trim(adjustl(term_str))
    end do

    ! Return trimmed result
    poly_str = trim(buffer)

  end function polynomial_to_string

  ! ===================================================================
  ! HELPER: Parse Genus Bound from Genus Code
  ! ===================================================================

  function extract_genus_from_result(status_code) result(genus)
    integer(i4), intent(in) :: status_code
    integer(i4) :: genus

    select case (status_code)
      case (THEOREM3_SUCCESS)
        genus = 0
      case (THEOREM3_COUNTEREXAMPLE)
        genus = 1  ! At least 1 (higher genus detected)
      case default
        genus = -1  ! Unknown/error
    end select

  end function extract_genus_from_result

end module quantum_theorem3
