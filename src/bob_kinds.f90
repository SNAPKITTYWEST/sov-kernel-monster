! BOB Quantum Civilization Engine - Type Definitions
! Module: bob_kinds
! Purpose: Explicit kind parameters for portable numeric types
! Standard: Fortran 2018
! Compiler: GNU Fortran (gfortran)

module bob_kinds
    use, intrinsic :: iso_c_binding, only: c_int, c_int64_t, c_double, c_float, c_bool, c_char
    implicit none
    private
    
    ! Export C-compatible types
    public :: c_int, c_int64_t, c_double, c_float, c_bool, c_char
    
    ! Integer kinds
    integer, parameter, public :: i4 = c_int           ! 32-bit integer
    integer, parameter, public :: i8 = c_int64_t       ! 64-bit integer
    
    ! Real kinds
    integer, parameter, public :: sp = c_float         ! Single precision (32-bit)
    integer, parameter, public :: dp = c_double        ! Double precision (64-bit)
    
    ! Default working precision for quantum states
    integer, parameter, public :: wp = dp              ! Working precision = double
    
    ! Complex kinds
    integer, parameter, public :: cwp = wp             ! Complex working precision
    
    ! Logical kind
    integer, parameter, public :: lk = c_bool          ! Logical/boolean
    
    ! Character kind
    integer, parameter, public :: ck = c_char          ! Character
    
    ! Constants
    real(wp), parameter, public :: PI = 3.141592653589793238462643383279502884197_wp
    real(wp), parameter, public :: HBAR = 1.054571817e-34_wp  ! Reduced Planck constant (J·s)
    real(wp), parameter, public :: ZERO = 0.0_wp
    real(wp), parameter, public :: ONE = 1.0_wp
    real(wp), parameter, public :: TWO = 2.0_wp
    real(wp), parameter, public :: HALF = 0.5_wp
    
    ! Complex constants
    complex(cwp), parameter, public :: CZERO = (0.0_wp, 0.0_wp)
    complex(cwp), parameter, public :: CONE = (1.0_wp, 0.0_wp)
    complex(cwp), parameter, public :: CI = (0.0_wp, 1.0_wp)  ! Imaginary unit
    
    ! Numerical tolerances
    real(wp), parameter, public :: TOL_NORM = 1.0e-10_wp      ! Normalization tolerance
    real(wp), parameter, public :: TOL_HERMITIAN = 1.0e-12_wp ! Hermiticity tolerance
    real(wp), parameter, public :: TOL_UNITARY = 1.0e-10_wp   ! Unitarity tolerance
    
end module bob_kinds

! Made with Bob
