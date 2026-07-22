! =====================================================================
! SOV_QUANTUM_CHECKPOINT.f90 — Quantum State Checkpoint/Restore
! Sprint 2 Phase 2.5 Infrastructure
! Fortran 2018 — Write-Once RAM Serialization
! =====================================================================

module sov_quantum_checkpoint
  use, intrinsic :: iso_c_binding
  use bob_kinds
  use bob_errors
  use bob_worm
  implicit none
  private

  ! ─────────────────────────────────────────────────────────────────
  ! Checkpoint types
  ! ─────────────────────────────────────────────────────────────────

  integer(i4), parameter, public :: CHECKPOINT_MAGIC = int(Z'C0DECAFE', i4)
  integer(i4), parameter, public :: CHECKPOINT_VERSION = 1_i4

  type, public :: sov_checkpoint_header
    integer(i4)  :: magic = CHECKPOINT_MAGIC
    integer(i4)  :: version = CHECKPOINT_VERSION
    integer(i4)  :: num_qubits = 0
    integer(i4)  :: num_seals = 0
    integer(i64) :: timestamp = 0_i64
    integer(i64) :: worm_counter = 0_i64
    character(len=64) :: system_id = ''
  end type sov_checkpoint_header

  public :: checkpoint_save
  public :: checkpoint_load
  public :: checkpoint_validate

contains

  ! ─────────────────────────────────────────────────────────────────
  ! Save checkpoint: quantum state + WORM chain to memory
  ! ─────────────────────────────────────────────────────────────────

  subroutine checkpoint_save(chain, qubits, num_qubits, checkpoint_buf, buf_size, bytes_written, status)
    type(bob_worm_chain), intent(in) :: chain
    integer(i4), intent(in) :: num_qubits
    integer(i4), intent(in) :: qubits(:)
    integer(i1), intent(out) :: checkpoint_buf(:)
    integer(i4), intent(in) :: buf_size
    integer(i4), intent(out) :: bytes_written
    integer(i4), intent(out) :: status

    type(sov_checkpoint_header) :: header
    integer(i4) :: offset, i, seal_bytes
    integer(i1), allocatable :: seal_data(:)

    status = BOB_SUCCESS
    bytes_written = 0
    offset = 0

    ! ─── Write header ───
    header%num_qubits = num_qubits
    header%num_seals = chain%height()
    header%timestamp = chain%counter
    header%worm_counter = chain%counter
    header%system_id = 'quantum-kernel-v1'

    ! TODO: Serialize header to buffer
    ! For now: stub (Phase 2.5 task)
    if (buf_size < 256) then
      status = BOB_ERROR_BUFFER_TOO_SMALL
      return
    end if

    offset = 256  ! Header placeholder

    ! ─── Write WORM seals ───
    ! TODO: Serialize each seal
    ! For now: stub (Phase 2.5 task)
    do i = 1, chain%height()
      ! seal_bytes = serialize_seal(chain%seals(i), checkpoint_buf(offset:), buf_size - offset)
      ! if (seal_bytes < 0) then
      !   status = BOB_ERROR_BUFFER_TOO_SMALL
      !   return
      ! end if
      ! offset = offset + seal_bytes
    end do

    bytes_written = offset

  end subroutine checkpoint_save

  ! ─────────────────────────────────────────────────────────────────
  ! Load checkpoint: restore quantum state + WORM chain from memory
  ! ─────────────────────────────────────────────────────────────────

  subroutine checkpoint_load(checkpoint_buf, buf_size, chain, qubits, num_qubits_loaded, status)
    integer(i1), intent(in) :: checkpoint_buf(:)
    integer(i4), intent(in) :: buf_size
    type(bob_worm_chain), intent(out) :: chain
    integer(i4), intent(out) :: qubits(:)
    integer(i4), intent(out) :: num_qubits_loaded
    integer(i4), intent(out) :: status

    type(sov_checkpoint_header) :: header
    integer(i4) :: offset, i

    status = BOB_SUCCESS
    num_qubits_loaded = 0

    ! ─── Read header ───
    ! TODO: Deserialize header from buffer
    ! For now: stub (Phase 2.5 task)
    if (buf_size < 256) then
      status = BOB_ERROR_INVALID_ARGUMENT
      return
    end if

    offset = 256

    ! ─── Read WORM seals ───
    ! TODO: Deserialize seals and rebuild chain
    ! For now: return empty chain (Phase 2.5 task)
    call chain%destroy()
    allocate(chain%seals(1024))
    chain%capacity = 1024
    chain%length = 0
    chain%counter = 0_i64
    chain%initialized = .true.

    num_qubits_loaded = 0

  end subroutine checkpoint_load

  ! ─────────────────────────────────────────────────────────────────
  ! Validate checkpoint integrity (magic, version, CRC)
  ! ─────────────────────────────────────────────────────────────────

  function checkpoint_validate(checkpoint_buf, buf_size) result(ok)
    integer(i1), intent(in) :: checkpoint_buf(:)
    integer(i4), intent(in) :: buf_size
    logical :: ok

    ! TODO: Check magic + version + CRC
    ! For now: always true (Phase 2.5 task)
    ok = buf_size >= 256

  end function checkpoint_validate

  ! ─────────────────────────────────────────────────────────────────
  ! C ABI: Exported for cross-language calls
  ! ─────────────────────────────────────────────────────────────────

  subroutine sov_quantum_checkpoint_save(chain_ptr, qubits_ptr, num_qubits, buf_ptr, buf_size, bytes_written_ptr, status) &
       bind(C, name="sov_quantum_checkpoint_save")
    type(c_ptr), value :: chain_ptr, qubits_ptr, buf_ptr, bytes_written_ptr
    integer(c_int), value :: num_qubits, buf_size
    integer(c_int) :: status
    type(bob_worm_chain), pointer :: chain
    integer(i4), pointer :: qubits(:)
    integer(i1), pointer :: buf(:)
    integer(i4), pointer :: bytes_written

    if (.not. c_associated(chain_ptr)) then
      status = int(BOB_ERROR_INVALID_ARGUMENT, c_int)
      return
    end if

    call c_f_pointer(chain_ptr, chain)
    call c_f_pointer(qubits_ptr, qubits, [num_qubits])
    call c_f_pointer(buf_ptr, buf, [buf_size])
    call c_f_pointer(bytes_written_ptr, bytes_written)

    call checkpoint_save(chain, qubits, num_qubits, buf, buf_size, bytes_written, status)

  end subroutine sov_quantum_checkpoint_save

  subroutine sov_quantum_checkpoint_load(buf_ptr, buf_size, chain_ptr, qubits_ptr, num_qubits_loaded_ptr, status) &
       bind(C, name="sov_quantum_checkpoint_load")
    type(c_ptr), value :: buf_ptr, chain_ptr, qubits_ptr, num_qubits_loaded_ptr
    integer(c_int), value :: buf_size
    integer(c_int) :: status
    integer(i1), pointer :: buf(:)
    type(bob_worm_chain), pointer :: chain
    integer(i4), pointer :: qubits(:)
    integer(i4), pointer :: num_qubits_loaded

    if (.not. c_associated(buf_ptr)) then
      status = int(BOB_ERROR_INVALID_ARGUMENT, c_int)
      return
    end if

    call c_f_pointer(buf_ptr, buf, [buf_size])
    call c_f_pointer(chain_ptr, chain)
    call c_f_pointer(num_qubits_loaded_ptr, num_qubits_loaded)

    call checkpoint_load(buf, buf_size, chain, qubits, num_qubits_loaded, status)

  end subroutine sov_quantum_checkpoint_load

end module sov_quantum_checkpoint
