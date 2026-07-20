! BOB Quantum Civilization Engine - Error Handling
! Module: bob_errors
! Purpose: Stable error codes and diagnostic message management
! Standard: Fortran 2018

module bob_errors
    use bob_kinds
    implicit none
    private
    
    ! Error codes (stable ABI)
    integer(i4), parameter, public :: BOB_SUCCESS = 0
    integer(i4), parameter, public :: BOB_ERROR_INVALID_ARGUMENT = 1
    integer(i4), parameter, public :: BOB_ERROR_ALLOCATION = 2
    integer(i4), parameter, public :: BOB_ERROR_DIMENSION_MISMATCH = 3
    integer(i4), parameter, public :: BOB_ERROR_NOT_NORMALIZED = 4
    integer(i4), parameter, public :: BOB_ERROR_NOT_HERMITIAN = 5
    integer(i4), parameter, public :: BOB_ERROR_NOT_UNITARY = 6
    integer(i4), parameter, public :: BOB_ERROR_INVALID_STATE = 7
    integer(i4), parameter, public :: BOB_ERROR_INVALID_GATE = 8
    integer(i4), parameter, public :: BOB_ERROR_INVALID_LATTICE = 9
    integer(i4), parameter, public :: BOB_ERROR_INTEGRATION_FAILED = 10
    integer(i4), parameter, public :: BOB_ERROR_IO = 11
    integer(i4), parameter, public :: BOB_ERROR_NOT_IMPLEMENTED = 99
    
    ! Maximum diagnostic message length
    integer, parameter, public :: BOB_MAX_ERROR_MSG_LEN = 512
    
    ! Thread-local error state
    type, public :: bob_error_state
        integer(i4) :: code = BOB_SUCCESS
        character(len=BOB_MAX_ERROR_MSG_LEN) :: message = ""
        character(len=256) :: location = ""
    end type bob_error_state
    
    ! Global error state (thread-local in OpenMP builds)
    type(bob_error_state), save :: g_error_state
    !$omp threadprivate(g_error_state)
    
    public :: bob_set_error
    public :: bob_get_last_error
    public :: bob_clear_error
    public :: bob_error_message
    
contains

    !> Set error state with code, message, and location
    subroutine bob_set_error(code, message, location)
        integer(i4), intent(in) :: code
        character(len=*), intent(in) :: message
        character(len=*), intent(in), optional :: location
        
        g_error_state%code = code
        g_error_state%message = trim(message)
        
        if (present(location)) then
            g_error_state%location = trim(location)
        else
            g_error_state%location = ""
        end if
    end subroutine bob_set_error
    
    !> Get last error code
    function bob_get_last_error() result(code)
        integer(i4) :: code
        code = g_error_state%code
    end function bob_get_last_error
    
    !> Clear error state
    subroutine bob_clear_error()
        g_error_state%code = BOB_SUCCESS
        g_error_state%message = ""
        g_error_state%location = ""
    end subroutine bob_clear_error
    
    !> Get human-readable error message for error code
    function bob_error_message(code) result(message)
        integer(i4), intent(in) :: code
        character(len=256) :: message
        
        select case (code)
        case (BOB_SUCCESS)
            message = "Success"
        case (BOB_ERROR_INVALID_ARGUMENT)
            message = "Invalid argument"
        case (BOB_ERROR_ALLOCATION)
            message = "Memory allocation failed"
        case (BOB_ERROR_DIMENSION_MISMATCH)
            message = "Dimension mismatch"
        case (BOB_ERROR_NOT_NORMALIZED)
            message = "State not normalized"
        case (BOB_ERROR_NOT_HERMITIAN)
            message = "Operator not Hermitian"
        case (BOB_ERROR_NOT_UNITARY)
            message = "Operator not unitary"
        case (BOB_ERROR_INVALID_STATE)
            message = "Invalid quantum state"
        case (BOB_ERROR_INVALID_GATE)
            message = "Invalid quantum gate"
        case (BOB_ERROR_INVALID_LATTICE)
            message = "Invalid lattice configuration"
        case (BOB_ERROR_INTEGRATION_FAILED)
            message = "Time integration failed"
        case (BOB_ERROR_IO)
            message = "I/O error"
        case (BOB_ERROR_NOT_IMPLEMENTED)
            message = "Feature not implemented"
        case default
            message = "Unknown error"
        end select
    end function bob_error_message

end module bob_errors

! Made with Bob
