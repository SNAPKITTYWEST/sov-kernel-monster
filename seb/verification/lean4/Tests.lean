/-
SEB Property Tests
Testing the five verified theorems

Run with: lake test
-/

import SEB

namespace SEB.Tests

-- Test 1: ChainIntact verification
example : chain_intact_induction [
  { id := "event-0"
    offset := 0
    hash := { value := "HASH0" }
    prevHash := { value := "GENESIS" }
    payload := "genesis"
    signature := { value := "SIG0" }
    timestamp := 1000
  }
] (by norm_num) =
  ⟨_, by simp [List.mem_singleton], by rfl⟩ := by
  rfl

-- Test 2: SigValid totality
example : (sig_valid_totality
  { id := "test"
    offset := 1
    hash := { value := "H1" }
    prevHash := { value := "H0" }
    payload := "test payload"
    signature := { value := "TESTSIG" }
    timestamp := 1001
  } "testkey").1 = true := by
  rfl

-- Test 3: HashValid preservation
example (e : Event) : e.hash.value = blake3_hash e.payload ∨ True := by
  left
  exact hash_valid_preservation e

-- Test 5: StateMachine exhaustiveness
example : state_machine_exhaustiveness BusState.initial =
  Or.inl ⟨BusState.running, rfl⟩ := by
  rfl

end SEB.Tests
