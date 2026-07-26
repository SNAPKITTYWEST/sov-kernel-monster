# Quick Start: Fortran → Quantum Offload

**5-minute build & test guide for Theorem 3 genus-0 forcing integration.**

## TL;DR

```bash
cd sov-kernel-monster
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make test_fortran_quantum
./bin/test_fortran_quantum
```

Expected: **5 tests pass** in ~100ms.

---

## Prerequisites

### macOS

```bash
brew install ghc cabal gfortran cmake
```

### Linux (Debian/Ubuntu)

```bash
apt-get install -y \
  ghc cabal-install \
  gfortran gnat \
  cmake build-essential
```

### Windows (MSYS2)

```bash
pacman -S \
  mingw-w64-x86_64-ghc \
  mingw-w64-x86_64-gcc-fortran \
  cmake
```

---

## Build Steps

### Step 1: Configure

From repository root:

```bash
cd sov-kernel-monster
mkdir build
cd build

cmake .. -DCMAKE_BUILD_TYPE=Release
```

**Output:**
```
=== Fortran Quantum Integration ===
GHC: /usr/bin/ghc
gfortran: /usr/bin/gfortran
Haskell bridge: .../lib/libQuantumFortranBridge.so
Test executable: .../bin/test_fortran_quantum
```

### Step 2: Build Haskell Bridge

```bash
make haskell_bridge
```

**Output:**
```
[ 50%] Building Haskell Quantum bridge → .so
Linking haskell ...
[100%] Built target haskell_bridge
```

### Step 3: Build Fortran Test

```bash
make test_fortran_quantum
```

**Output:**
```
[ 75%] Compiling Fortran quantum interface module
[ 99%] Linking Fortran executable bin/test_fortran_quantum
[100%] Built target test_fortran_quantum
```

### Step 4: Run Tests

```bash
./bin/test_fortran_quantum
```

**Or via ctest:**

```bash
ctest --verbose
```

---

## Test Output

Expected output (5 tests):

```
========================================================
FORTRAN QUANTUM INTEGRATION TEST SUITE
Theorem 3: Genus-0 Forcing via Quantum Offload
========================================================

TEST 1: u^2 + x^2 (should be genus-0)
  Polynomial: '1*u^2 + 1*x^2'
  Energy budget: 100
  Result status: 0
  Result genus: 0
  ✓ PASSED (genus-0 verified + quantum success)

TEST 2: u^4 + 2*u^2*x + x^4 (degree-4)
  Polynomial: '1*u^4 + 2*u^2*x + 1*x^4'
  Energy budget: 200
  Result status: 0
  Result genus: 0
  ✓ PASSED (rational curve verified)

TEST 3: u^3 + x^3 (fermat cubic, should have genus)
  Polynomial: '1*u^3 + 1*x^3'
  Energy budget: 150
  Result status: 2
  Result genus: 1
  ✓ PASSED (counterexample detected, genus > 0)

TEST 4: Energy budget exhaustion (budget=1)
  Polynomial: '1*u^6 + 1*x^6' (high degree)
  Energy budget: 1 (insufficient)
  Result status: 1
  Result genus: -1
  ✓ PASSED (correctly blocked due to energy)

TEST 5: Round-trip with polynomial_to_string
  Built polynomial: '1.0*u^2 + 2.0*u^1*x^1 + 1.0*x^2'
  Energy budget: 100
  Result status: 0
  Result genus: 0
  ✓ PASSED (round-trip completed)

========================================================
TEST SUMMARY
========================================================
Passed: 5
Failed: 0
Total:  5

✓ ALL TESTS PASSED
```

---

## Troubleshooting

### Error: "ghc: command not found"

```bash
# Install GHC
brew install ghc        # macOS
apt-get install ghc     # Ubuntu
# Then retry cmake
```

### Error: "gfortran: command not found"

```bash
# Install GNU Fortran
brew install gcc        # macOS
apt-get install gfortran  # Ubuntu
```

### Error: "CMake: command not found"

```bash
# Install CMake
brew install cmake      # macOS
apt-get install cmake   # Ubuntu
```

### Error: "libQuantumFortranBridge.so not found"

```bash
# Rebuild Haskell bridge explicitly
cd build
make clean
make haskell_bridge
make test_fortran_quantum
```

### Test Hangs

- Haskell GHC compilation can take 30-60s on first build
- Be patient; subsequent builds are faster (cached)

### Linking Errors with `.so`

On macOS, if linker complains about undefined symbols:

```bash
# Force Haskell to export all symbols
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_Fortran_FLAGS="-Wl,--whole-archive"
make clean
make all
```

---

## What's Being Tested

### Test 1: Simple Genus-0 (u² + x²)
- Verifies basic Fortran → Haskell call works
- Polynomial parsing succeeds
- Kernel computes genus = 0
- Quantum verification returns success

### Test 2: Degree-4 Rational Curve (u⁴ + 2u²x + x⁴)
- Tests higher-degree polynomial handling
- Checks Plücker formula with multiple terms
- Verifies energy budget sufficient for analysis

### Test 3: Fermat Cubic (u³ + x³)
- Tests counterexample detection
- Genus 1 (elliptic curve) correctly identified
- Should return status = 2 (counterexample)

### Test 4: Energy Budget Exhaustion
- Tests early termination on low budget
- Verifies energy accounting (spent ≤ budget)
- Returns blocked status gracefully

### Test 5: Round-Trip with Helper
- Tests `polynomial_to_string` helper function
- Dynamically builds polynomial from coefficients
- Offloads and verifies result

---

## Next Steps

### Run Your Own Polynomial

Create `test_custom.f90`:

```fortran
program test_custom
  use quantum_theorem3
  implicit none
  
  integer :: status, genus
  
  ! Your polynomial here
  call offload_theorem3_to_quantum("YOUR_POLY_STRING", 100_i4, status, genus)
  
  select case (status)
    case (THEOREM3_SUCCESS)
      print *, "✓ Genus-0 verified"
    case default
      print *, "Status:", status, "Genus:", genus
  end select
  
end program test_custom
```

Compile and run:

```bash
gfortran -I../modules -L../lib \
  ../src/bob_kinds.f90 \
  ../src/fortran_quantum_interface.f90 \
  test_custom.f90 \
  -o test_custom -lQuantumFortranBridge \
  -Wl,-rpath,../lib

./test_custom
```

### Inspect Build Artifacts

```bash
# Check Haskell .so was built
file lib/libQuantumFortranBridge.so

# Check Fortran modules exist
ls -la modules/

# Check test executable
ldd bin/test_fortran_quantum  # Linux
otool -L bin/test_fortran_quantum  # macOS
```

### Clean & Rebuild

```bash
cd build
make clean
cmake ..
make
```

---

## Architecture Reference

```
Fortran Supercomputer
        ↓
fortran_quantum_interface.f90 (Fortran module)
        ↓ (C FFI)
QuantumFortranBridge.hs (Haskell export)
        ↓
Theorem3Entry.theorem3EnforceGenusZero (kernel)
        ↓
Mora + SingularityAnalysis (classical)
        ↓
QuantumChipInterface.ibm_verify_genus_zero (quantum)
        ↓
Result back to Fortran
```

---

## Files

| File | Purpose |
|------|---------|
| `src/fortran_quantum_interface.f90` | Fortran API + C FFI binding |
| `src/test_fortran_quantum.f90` | 5 test cases |
| `haskell/.../QuantumFortranBridge.hs` | C export of Haskell kernel |
| `haskell/.../QuantumChipInterface.hs` | IBM Quantum mock interface |
| `CMakeLists.fortran_quantum` | Build configuration |
| `docs/FORTRAN_QUANTUM_OFFLOAD.md` | Full documentation |

---

## Questions?

See `docs/FORTRAN_QUANTUM_OFFLOAD.md` for:
- Full API reference
- Polynomial string format
- Performance scaling
- Integration examples
- Phase 2 roadmap

---

**Status:** Phase 1 (Mock quantum, deterministic)  
**Updated:** 2026-07-20
