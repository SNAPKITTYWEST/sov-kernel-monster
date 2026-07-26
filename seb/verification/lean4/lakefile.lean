import Lake
open Lake DSL

package seb_verification

require mathlib from git "https://github.com/leanprover-community/mathlib4.git" @ "v4.7.0"

@[default_target]
lean_lib SEB_Verification
