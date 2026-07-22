import Lake
open Lake DSL

package «qataaum-verification» where
  -- Package metadata
  version := v!"0.1.0"
  keywords := #["quantum", "compiler", "verification", "formal-methods"]
  description := "Lean 4 formal verification for QATAAUM quantum compiler"

-- Main library
@[default_target]
lean_lib «QATAAUMVerification» where
  -- Library configuration
  globs := #[.submodules `QATAAUMVerification]

-- Require Mathlib for standard mathematical structures
require mathlib from git
  "https://github.com/leanprover-community/mathlib4.git"