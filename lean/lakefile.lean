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

-- Full matrix-level formalization (Ahmad Ali Parr, PAR-011)
lean_lib «SovMonster_Matrix» where
  roots := #[`SovMonster_Matrix]

-- Closed formalization — Ahmad's systematic sorry audit
lean_lib «SovMonster_Matrix_Closed» where
  roots := #[`SovMonster_Matrix_Closed]

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
