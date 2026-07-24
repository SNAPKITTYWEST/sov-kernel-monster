import Lake
open Lake DSL

package «agda-invariants» where
  version : String := "0.1.0"
  authors : List String := ["Jessica Ali", "SNAPKITTYWEST"]
  description : "BOB Quantum Kernel Loop Invariant Formalization (Phase 2)"
  homepage : String := "https://github.com/SNAPKITTYWEST/sov-kernel-monster"
  repository : String := "https://github.com/SNAPKITTYWEST/sov-kernel-monster.git"
  license : String := "BSD-3-Clause"

@[default_target]
lean_lib Invariants where
  roots := #[`src.Core, `src.Invariants]
  globs := #["src/**/*.lean"]
