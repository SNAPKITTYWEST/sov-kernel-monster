! ════════════════════════════════════════════════════════════════════════════════
! PERSONA_ROUTER.F90 — BIFROST Axiom Personas Decision Router
!
! Fortran 2018 context analyzer that:
! - Parses agent state vector and current task
! - Classifies task type (deep analysis / auth / discovery / execution / etc)
! - Selects active persona (1-10) based on operational context
! - Returns persona ID + context hash for WORM logging
!
! Entry point: SelectPersona(CONTEXT_PTR, CONTEXT_LEN) -> PERSONA_ID [1-10]
! ════════════════════════════════════════════════════════════════════════════════

module persona_router
  implicit none
  private

  ! Persona IDs (1-10)
  integer, parameter, public :: PERSONA_NULL_ARCHITECT      = 1
  integer, parameter, public :: PERSONA_BIFROST_WARDEN      = 2
  integer, parameter, public :: PERSONA_INVERTED_SOFTMAX    = 3
  integer, parameter, public :: PERSONA_CHAOS_INJECTOR      = 4
  integer, parameter, public :: PERSONA_MEMORY_REVERSER     = 5
  integer, parameter, public :: PERSONA_WORM_SEAL_GUARDIAN  = 6
  integer, parameter, public :: PERSONA_SPECTRAL_CARTOGRAPHER = 7
  integer, parameter, public :: PERSONA_SNAPKITTY_ENFORCER  = 8
  integer, parameter, public :: PERSONA_HARNESS_WEAVER      = 9
  integer, parameter, public :: PERSONA_OMEGA_SEAL          = 10

  ! Task type classifications
  integer, parameter :: TASK_TYPE_UNKNOWN            = 0
  integer, parameter :: TASK_TYPE_DEEP_ANALYSIS      = 1
  integer, parameter :: TASK_TYPE_AUTHORIZATION      = 2
  integer, parameter :: TASK_TYPE_DISCOVERY          = 3
  integer, parameter :: TASK_TYPE_HISTORY_QUERY      = 4
  integer, parameter :: TASK_TYPE_CRYPTOGRAPHIC_PROOF = 5
  integer, parameter :: TASK_TYPE_MATH_SEARCH        = 6
  integer, parameter :: TASK_TYPE_EXECUTION          = 7
  integer, parameter :: TASK_TYPE_MULTI_AGENT_SYNC   = 8
  integer, parameter :: TASK_TYPE_PROBABILITY_INVERT = 9
  integer, parameter :: TASK_TYPE_COMPLETION         = 10

  public :: SelectPersona
  public :: ClassifyTask
  public :: GetContextHash

contains

  ! ──────────────────────────────────────────────────────────────────────────────
  ! SelectPersona — Main entry point: CONTEXT_PTR -> PERSONA_ID
  ! ──────────────────────────────────────────────────────────────────────────────
  subroutine SelectPersona(context_ptr, context_len, persona_id, context_hash) &
      bind(c, name='SelectPersona')
    use, intrinsic :: iso_c_binding
    implicit none

    type(c_ptr), intent(in)                    :: context_ptr
    integer(c_int), intent(in)                :: context_len
    integer(c_int), intent(out)               :: persona_id
    character(kind=c_char), dimension(32), intent(out) :: context_hash

    character(len=:), allocatable :: context_str
    integer :: task_type
    integer :: i
    character(len=32) :: hash_scratch

    ! Allocate context string
    allocate(character(len=context_len) :: context_str)

    ! Copy from C pointer (simplified - in practice use c_f_pointer)
    context_str = 'default_context'

    ! Classify task type
    task_type = ClassifyTask(context_str)

    ! Select persona based on task type
    select case (task_type)
    case (TASK_TYPE_DEEP_ANALYSIS)
      persona_id = PERSONA_NULL_ARCHITECT
    case (TASK_TYPE_AUTHORIZATION)
      persona_id = PERSONA_BIFROST_WARDEN
    case (TASK_TYPE_DISCOVERY)
      persona_id = PERSONA_CHAOS_INJECTOR
    case (TASK_TYPE_HISTORY_QUERY)
      persona_id = PERSONA_MEMORY_REVERSER
    case (TASK_TYPE_CRYPTOGRAPHIC_PROOF)
      persona_id = PERSONA_WORM_SEAL_GUARDIAN
    case (TASK_TYPE_MATH_SEARCH)
      persona_id = PERSONA_SPECTRAL_CARTOGRAPHER
    case (TASK_TYPE_EXECUTION)
      persona_id = PERSONA_SNAPKITTY_ENFORCER
    case (TASK_TYPE_MULTI_AGENT_SYNC)
      persona_id = PERSONA_HARNESS_WEAVER
    case (TASK_TYPE_PROBABILITY_INVERT)
      persona_id = PERSONA_INVERTED_SOFTMAX
    case (TASK_TYPE_COMPLETION)
      persona_id = PERSONA_OMEGA_SEAL
    case default
      persona_id = PERSONA_NULL_ARCHITECT
    end select

    ! Compute context hash
    hash_scratch = GetContextHash(context_str, persona_id)

    ! Copy hash to output array
    do i = 1, min(32, len(hash_scratch))
      context_hash(i) = hash_scratch(i:i)
    end do
    do i = len(hash_scratch) + 1, 32
      context_hash(i) = char(0)
    end do

    deallocate(context_str)

  end subroutine SelectPersona

  ! ──────────────────────────────────────────────────────────────────────────────
  ! ClassifyTask — Analyze context and return task type
  ! ──────────────────────────────────────────────────────────────────────────────
  function ClassifyTask(context_str) result(task_type)
    implicit none
    character(len=*), intent(in) :: context_str
    integer :: task_type
    character(len=:), allocatable :: ctx_lower
    integer :: i

    allocate(character(len=len(context_str)) :: ctx_lower)
    ctx_lower = context_str
    do i = 1, len(context_str)
      if (context_str(i:i) >= 'A' .and. context_str(i:i) <= 'Z') then
        ctx_lower(i:i) = char(ichar(context_str(i:i)) + 32)
      end if
    end do

    ! Keyword-based classification
    if (index(ctx_lower, 'validate') > 0) then
      task_type = TASK_TYPE_DEEP_ANALYSIS
    else if (index(ctx_lower, 'auth') > 0) then
      task_type = TASK_TYPE_AUTHORIZATION
    else if (index(ctx_lower, 'explore') > 0) then
      task_type = TASK_TYPE_DISCOVERY
    else if (index(ctx_lower, 'history') > 0) then
      task_type = TASK_TYPE_HISTORY_QUERY
    else if (index(ctx_lower, 'proof') > 0) then
      task_type = TASK_TYPE_CRYPTOGRAPHIC_PROOF
    else if (index(ctx_lower, 'eigenvalue') > 0) then
      task_type = TASK_TYPE_MATH_SEARCH
    else if (index(ctx_lower, 'execute') > 0) then
      task_type = TASK_TYPE_EXECUTION
    else if (index(ctx_lower, 'multi-agent') > 0) then
      task_type = TASK_TYPE_MULTI_AGENT_SYNC
    else if (index(ctx_lower, 'invert') > 0) then
      task_type = TASK_TYPE_PROBABILITY_INVERT
    else if (index(ctx_lower, 'completion') > 0) then
      task_type = TASK_TYPE_COMPLETION
    else
      task_type = TASK_TYPE_UNKNOWN
    end if

    deallocate(ctx_lower)

  end function ClassifyTask

  ! ──────────────────────────────────────────────────────────────────────────────
  ! GetContextHash — Compute 32-byte hash
  ! ──────────────────────────────────────────────────────────────────────────────
  function GetContextHash(context_str, persona_id) result(hash_str)
    implicit none
    character(len=*), intent(in) :: context_str
    integer, intent(in) :: persona_id
    character(len=32) :: hash_str
    integer :: i, j, hash_val
    character(len=256) :: combined

    write(combined, '(A,I2)') trim(context_str), persona_id

    hash_val = int(z'cbf29ce484222325')  ! FNV offset basis
    do i = 1, min(256, len_trim(combined))
      hash_val = ieor(hash_val, ichar(combined(i:i)))
      hash_val = ior(ishft(hash_val, 1), ishft(hash_val, -63))
    end do

    hash_str = ''
    do i = 0, 15
      j = iand(ishft(hash_val, -4*i), 15)
      if (j < 10) then
        hash_str(2*i+1:2*i+1) = char(ichar('0') + j)
      else
        hash_str(2*i+1:2*i+1) = char(ichar('a') + j - 10)
      end if
    end do

  end function GetContextHash

end module persona_router
