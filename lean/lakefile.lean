import Lake
open Lake DSL

package «sov-monster» where
  name := "sov-monster"

require mathlib from git
  "https://github.com/leanprover-community/mathlib4" @ "v4.14.0"

lean_lib «SovMonster» where
  roots := #[`SovMonster]

-- Matrix-level Jordan commutativity proof (requires Mathlib)
lean_lib «JordanMatrixProof» where
  roots := #[`JordanMatrixProof]

-- Link against the Fortran object (built by build_monster.sh)
-- Run `build_monster.sh` first, then `lake build`
@[defaultTarget]
lean_exe «sov-monster» where
  root := `SovMonster
  moreLinkArgs := #[
    "-L./build",
    "-Wl,-rpath,./build",
    "./build/sov_arm64.o"   -- or sov_x86.o on x86_64
  ]
