# SNAPKITTY-PROOFS Receipts

## Lean 4
Command: `cd lean4 && lake build`
Status: PENDING (no Idris 2/Lean 4 toolchain on Windows)
Sorry check: zero `sorry`, zero `admit`

## Haskell (Runtime Witnesses)
Command: `runghc haskell/no_cloning.hs`
Status: PENDING
Invariant: linear observation consumed exactly once

## Haskell (Liquid Refinement Layer)
Command: `liquid haskell-liquid/src/SnapKitty/Liquid/ThermalWindow.hs`
Status: PENDING
Invariant: every constructed ThermalWindow has lo < hi and positive span

Command: `liquid haskell-liquid/src/SnapKitty/Liquid/ERE5.hs`
Status: PENDING
Invariant: if ERE accepts, P5 audit hash exists and P2 no-eval holds

Command: `liquid haskell-liquid/src/SnapKitty/Liquid/NoCloningWitness.hs`
Status: PENDING
Invariant: Destroyed state is absorbing, failed pass destroys

## Prolog
Command: `swipl -g main -t halt prolog/quantum_monad.pl -- 53 49 106 7`
Status: PENDING
Invariant: watchtower certification / 49th Call identity

## Idris
Command: `cd idris-gate && idris2 --build idris-gate.ipkg`
Status: PENDING (no Idris 2 toolchain on Windows)
Invariant: dependent gate witness, compile-time rejection of invalid gates

## Toolchain Versions
- GHC: PENDING
- Liquid Haskell: PENDING
- SWI-Prolog: 10.0.2 (installed)
- Idris 2: NOT INSTALLED
- Lean 4: NOT INSTALLED
