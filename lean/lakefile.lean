import Lake
open Lake DSL

package «sov-monster» where
  name := "sov-monster"

lean_lib «SovMonster» where
  roots := #[`SovMonster]

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
