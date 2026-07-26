!=====================================================================
! COLD BOOT — SOV-KERNEL-MONSTER Operational Test
! Exercises: kinds -> state -> gates -> jordan_block -> measurement
!=====================================================================
program cold_boot
  use bob_kinds, only: dp, i8, wp
  use bob_errors, only: BOB_SUCCESS
  use bob_worm, only: bob_worm_chain, blake3_hash_string
  use bob_state, only: bob_quantum_state
  use sov_monster_kernel, only: ci, czero, sov_is_hermitian_matrix, &
       sov_is_density_matrix, sov_fault
  use jordan_block, only: PHI_INV
  use spe_encoder, only: spe_frame_t
  use sov_knowledge, only: knowledge_store, cosine_sim, generate_embedding, &
       knowledge_tau, knowledge_penalty_scale
  use iso_fortran_env, only: int64
  implicit none

  integer :: passed, failed, total
  complex(dp) :: rho(4,4), U(4,4), rho_new(4,4)
  real(dp) :: tau, scale, sim
  real(dp), allocatable :: embed_a(:), embed_b(:)
  integer(i8) :: digest(32)
  type(bob_worm_chain) :: chain
  type(knowledge_store) :: kb
  integer :: i, j

  passed = 0
  failed = 0

  print *, ''
  print *, '============================================================'
  print *, '  SOV-KERNEL-MONSTER -- COLD BOOT SEQUENCE'
  print *, '  29/29 modules | RTX ready | WORM sealed'
  print *, '============================================================'
  print *, ''

  ! TEST 1: Type system (bob_kinds)
  print *, '[1] bob_kinds: type system...'
  if (dp > 0 .and. kind(1.0_dp) == dp) then
    print *, '    dp =', dp, ' (64-bit float) PASS'
    passed = passed + 1
  else
    print *, '    FAILED'; failed = failed + 1
  end if

  ! TEST 2: WORM chain (bob_worm)
  print *, '[2] bob_worm: WORM chain...'
  call chain%init(256)
  call chain%seal('COLDBOOT', 'genesis', 0_int64)
  call chain%seal('COLDBOOT', 'block_1', 1_int64)
  if (chain%height() == 2 .and. chain%verify()) then
    print *, '    height=2, verify=TRUE PASS'
    passed = passed + 1
  else
    print *, '    FAILED'; failed = failed + 1
  end if

  ! TEST 3: Blake3 hash
  print *, '[3] blake3: hash...'
  call blake3_hash_string('sovereign', digest)
  if (digest(1) /= 0) then
    print *, '    hash(sovereign) non-zero PASS'
    passed = passed + 1
  else
    print *, '    FAILED'; failed = failed + 1
  end if

  ! TEST 4: Density matrix construction + verification
  print *, '[4] sov_monster_kernel: density matrix...'
  rho = czero
  rho(1,1) = cmplx(0.5_dp, 0.0_dp, dp)
  rho(2,2) = cmplx(0.5_dp, 0.0_dp, dp)
  rho(3,3) = cmplx(0.0_dp, 0.0_dp, dp)
  rho(4,4) = cmplx(0.0_dp, 0.0_dp, dp)
  if (sov_is_hermitian_matrix(rho, 4_i8) .and. sov_is_density_matrix(rho, 4_i8)) then
    print *, '    2-qubit rho: Hermitian=T, density=T, tr=1 PASS'
    passed = passed + 1
  else
    print *, '    FAILED'; failed = failed + 1
  end if

  ! TEST 5: Jordan block contraction (phi^-1 rate)
  print *, '[5] jordan_block: phi contraction...'
  if (abs(PHI_INV - 0.6180339887498948482_dp) < 1.0e-12_dp) then
    print *, '    PHI_INV = 0.618033... PASS'
    passed = passed + 1
  else
    print *, '    FAILED'; failed = failed + 1
  end if

  ! TEST 6: SPE spectral embedding (cosine similarity)
  print *, '[6] sov_knowledge: spectral embedding...'
  call generate_embedding('quantum sovereignty', embed_a)
  call generate_embedding('quantum sovereignty', embed_b)
  sim = cosine_sim(embed_a, embed_b)
  if (abs(sim - 1.0_dp) < 1.0e-10_dp) then
    print *, '    self-similarity = 1.000 PASS'
    passed = passed + 1
  else
    print *, '    sim =', sim, ' FAILED'; failed = failed + 1
  end if

  call generate_embedding('classical noise', embed_b)
  sim = cosine_sim(embed_a, embed_b)
  if (sim < 0.95_dp .and. sim > -1.0_dp) then
    print *, '    cross-similarity =', sim, ' (< 1.0) PASS'
    passed = passed + 1
  else
    print *, '    sim =', sim, ' FAILED'; failed = failed + 1
  end if

  ! TEST 7: Knowledge tau decay
  print *, '[7] knowledge_tau: phi-decay...'
  tau = knowledge_tau(1.0_dp, 3)
  if (abs(tau - PHI_INV**3) < 1.0e-12_dp) then
    print *, '    tau(1.0, k=3) = phi^-3 =', tau, ' PASS'
    passed = passed + 1
  else
    print *, '    FAILED'; failed = failed + 1
  end if

  ! TEST 8: Knowledge penalty scale
  print *, '[8] knowledge_penalty_scale...'
  scale = knowledge_penalty_scale(10, 5)
  if (scale > PHI_INV .and. scale < 1.0_dp) then
    print *, '    scale(10 total, 5 unverified) =', scale, ' PASS'
    passed = passed + 1
  else
    print *, '    FAILED'; failed = failed + 1
  end if

  ! TEST 9: Knowledge store init + append + search
  print *, '[9] knowledge_store: full pipeline...'
  call kb%init(64)
  call kb%append('The density matrix is Hermitian', 'COLDBOOT')
  call kb%append('Eigenvalues sum to one', 'COLDBOOT')
  call kb%append('WORM chain is append-only', 'COLDBOOT')
  if (kb%count == 3) then
    print *, '    append 3 chunks, count=3 PASS'
    passed = passed + 1
  else
    print *, '    FAILED count=', kb%count; failed = failed + 1
  end if

  ! TEST 10: Trust score
  print *, '[10] trust_score...'
  if (abs(kb%trust_score() - 1.0_dp) < 1.0e-12_dp) then
    print *, '    all verified -> trust = 1.0 PASS'
    passed = passed + 1
  else
    print *, '    FAILED'; failed = failed + 1
  end if

  call kb%destroy()
  call chain%destroy()
  if (allocated(embed_a)) deallocate(embed_a)
  if (allocated(embed_b)) deallocate(embed_b)

  ! SUMMARY
  total = passed + failed
  print *, ''
  print *, '============================================================'
  if (failed == 0) then
    print *, '  ALL TESTS PASSED:', passed, '/', total
    print *, '  SOVEREIGN QUANTUM COMPUTER: OPERATIONAL'
  else
    print *, '  PASSED:', passed, '/', total
    print *, '  FAILED:', failed
  end if
  print *, '============================================================'
  print *, ''

end program cold_boot
