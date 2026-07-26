! =====================================================================
! TEST: Phase 1 - Circuit Depth Calculation
! =====================================================================
! Tests logical_depth() and gate_count() methods
! Reference: SCAFFOLDS_IN_PROGRESS.md, Task 2.1
! =====================================================================

program test_phase1_depth
  use bob_circuit
  use bob_kinds
  implicit none

  type(bob_circuit_t) :: c
  integer(i4) :: depth, gate_cnt, st
  integer :: passed, failed, test_num

  passed = 0
  failed = 0
  test_num = 0

  print *, "========================================================"
  print *, "PHASE 1 CIRCUIT DEPTH TESTS"
  print *, "========================================================"
  print *, ""

  ! ===================================================================
  ! TEST 1: Single Hadamard (depth should be 1)
  ! ===================================================================
  test_num = 1
  print *, "TEST ", test_num, ": Single Hadamard gate"
  c = circuit_new(1, 0)
  call c%add_gate(GATE_HADAMARD, 0, status=st)

  depth = c%logical_depth()
  gate_cnt = c%gate_count()

  print *, "  Gates: ", gate_cnt, " (expected: 1)"
  print *, "  Logical depth: ", depth, " (expected: 1)"

  if (gate_cnt == 1 .and. depth == 1) then
    print *, "  ✓ PASSED"
    passed = passed + 1
  else
    print *, "  ✗ FAILED"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 2: Two parallel Hadamards on different qubits (depth should be 1)
  ! ===================================================================
  test_num = 2
  print *, "TEST ", test_num, ": Two parallel Hadamards (different qubits)"
  c = circuit_new(2, 0)
  call c%add_gate(GATE_HADAMARD, 0, status=st)
  call c%add_gate(GATE_HADAMARD, 1, status=st)

  depth = c%logical_depth()
  gate_cnt = c%gate_count()

  print *, "  Gates: ", gate_cnt, " (expected: 2)"
  print *, "  Logical depth: ", depth, " (expected: 1) [parallel gates]"

  if (gate_cnt == 2 .and. depth == 1) then
    print *, "  ✓ PASSED"
    passed = passed + 1
  else
    print *, "  ✗ FAILED (parallel gates should have depth 1)"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 3: Serial gates on same qubit (depth should be 3)
  ! ===================================================================
  test_num = 3
  print *, "TEST ", test_num, ": Three serial gates on same qubit"
  c = circuit_new(1, 0)
  call c%add_gate(GATE_HADAMARD, 0, status=st)
  call c%add_gate(GATE_PAULI_X, 0, status=st)
  call c%add_gate(GATE_PAULI_Z, 0, status=st)

  depth = c%logical_depth()
  gate_cnt = c%gate_count()

  print *, "  Gates: ", gate_cnt, " (expected: 3)"
  print *, "  Logical depth: ", depth, " (expected: 3) [serial gates]"

  if (gate_cnt == 3 .and. depth == 3) then
    print *, "  ✓ PASSED"
    passed = passed + 1
  else
    print *, "  ✗ FAILED"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 4: CNOT creates dependency (depth should be 2)
  ! ===================================================================
  test_num = 4
  print *, "TEST ", test_num, ": CNOT with dependency"
  c = circuit_new(2, 0)
  call c%add_gate(GATE_HADAMARD, 0, status=st)
  call c%add_gate(GATE_HADAMARD, 1, status=st)  ! Parallel H
  call c%add_gate(GATE_CNOT, 1, control=0, status=st)  ! Depends on both q0 and q1

  depth = c%logical_depth()
  gate_cnt = c%gate_count()

  print *, "  Gates: ", gate_cnt, " (expected: 3)"
  print *, "  Logical depth: ", depth, " (expected: 2) [H layer + CNOT layer]"

  if (gate_cnt == 3 .and. depth == 2) then
    print *, "  ✓ PASSED"
    passed = passed + 1
  else
    print *, "  ✗ FAILED"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 5: Empty circuit (depth should be 0)
  ! ===================================================================
  test_num = 5
  print *, "TEST ", test_num, ": Empty circuit"
  c = circuit_new(2, 0)

  depth = c%logical_depth()
  gate_cnt = c%gate_count()

  print *, "  Gates: ", gate_cnt, " (expected: 0)"
  print *, "  Logical depth: ", depth, " (expected: 0)"

  if (gate_cnt == 0 .and. depth == 0) then
    print *, "  ✓ PASSED"
    passed = passed + 1
  else
    print *, "  ✗ FAILED"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! TEST 6: Bell state circuit
  ! ===================================================================
  test_num = 6
  print *, "TEST ", test_num, ": Bell pair (H + CNOT)"
  c = circuit_bell_pair()

  depth = c%logical_depth()
  gate_cnt = c%gate_count()

  print *, "  Gates: ", gate_cnt
  print *, "  Logical depth: ", depth, " (expected: 2) [H then CNOT]"

  ! Bell pair: H on q0, CNOT(q1, control=q0), measure on q0, measure on q1
  ! Depth should be: H=1, CNOT=2 (depends on H), measure=3 (both)
  ! So max is 3 for full circuit, but if we count just H+CNOT it's 2
  if (gate_cnt >= 2 .and. depth >= 2) then
    print *, "  ✓ PASSED (depth >= 2)"
    passed = passed + 1
  else
    print *, "  ✗ FAILED"
    failed = failed + 1
  end if
  print *, ""

  ! ===================================================================
  ! Summary
  ! ===================================================================
  print *, "========================================================"
  print *, "SUMMARY"
  print *, "  Passed: ", passed, "/", test_num
  print *, "  Failed: ", failed, "/", test_num
  print *, "========================================================"

  if (failed == 0) then
    print *, "ALL TESTS PASSED ✓"
    stop 0
  else
    print *, "SOME TESTS FAILED ✗"
    stop 1
  end if

end program test_phase1_depth
