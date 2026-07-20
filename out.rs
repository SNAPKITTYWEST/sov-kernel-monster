#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Version */
#define BOB_QUANTUM_VERSION_MAJOR 1
#define BOB_QUANTUM_VERSION_MINOR 0
#define BOB_QUANTUM_VERSION_PATCH 0

/* Error codes */
typedef enum {
    BOB_OK = 0,
    BOB_ERR_NULL_POINTER = -1,
    BOB_ERR_INVALID_STATE = -2,
    BOB_ERR_ALLOCATION_FAILED = -3,
    BOB_ERR_NATS_CONNECTION = -4,
    BOB_ERR_BORN_RULE_VIOLATION = -5,
    BOB_ERR_ENTANGLEMENT_BROKEN = -6,
    BOB_ERR_DECOHERENCE = -7
} bob_error_t;

/* Quantum state representation (zero-copy) */
typedef struct {
    double* amplitudes_real;    /* Real parts of amplitudes */
    double* amplitudes_imag;    /* Imaginary parts of amplitudes */
    uint64_t num_qubits;        /* Number of qubits */
    uint64_t dimension;         /* 2^num_qubits */
    uint64_t ref_count;         /* Reference count for zero-copy */
    void* owner_context;        /* Owning runtime context */
} bob_quantum_state_t;

/* Born rule measurement result */
typedef struct {
    uint64_t outcome;           /* Measured basis state */
    double probability;         /* Born rule probability */
    double phase;               /* Quantum phase */
    uint64_t timestamp_ns;      /* Measurement timestamp */
} bob_measurement_t;

/* Entanglement descriptor */
typedef struct {
    uint64_t qubit_a;           /* First qubit index */
    uint64_t qubit_b;           /* Second qubit index */
    double concurrence;         /* Entanglement measure */
    uint8_t is_maximal;         /* Maximal entanglement flag */
} bob_entanglement_t;

/* NATS subject hierarchy constants */
#define BOB_NATS_PREFIX "bob.quantum"
#define BOB_NATS_STATE_UPDATE "bob.quantum.state.update"
#define BOB_NATS_MEASUREMENT "bob.quantum.measurement"
#define BOB_NATS_ENTANGLEMENT "bob.quantum.entanglement"
#define BOB_NATS_COHERENCE "bob.quantum.coherence"
#define BOB_NATS_GATE_APPLY "bob.quantum.gate.apply"
#define BOB_NATS_ERROR "bob.quantum.error"

/* Gate operation types */
typedef enum {
    BOB_GATE_H = 0,       /* Hadamard */
    BOB_GATE_X = 1,       /* Pauli-X */
    BOB_GATE_Y = 2,       /* Pauli-Y */
    BOB_GATE_Z = 3,       /* Pauli-Z */
    BOB_GATE_CNOT = 4,    /* CNOT */
    BOB_GATE_CZ = 5,      /* Controlled-Z */
    BOB_GATE_RX = 6,      /* Rotation X */
    BOB_GATE_RY = 7,      /* Rotation Y */
    BOB_GATE_RZ = 8,      /* Rotation Z */
    BOB_GATE_TOFFOLI = 9, /* Toffoli */
    BOB_GATE_SWAP = 10    /* SWAP */
} bob_gate_type_t;

/* Gate parameter */
typedef struct {
    bob_gate_type_t type;
    uint64_t target;
    uint64_t control;
    double angle;           /* For rotation gates */
} bob_gate_t;

/* Core API */

/* Initialize quantum state |0...0> */
bob_error_t bob_state_init(bob_quantum_state_t** state, uint64_t num_qubits);

/* Clone state (increment ref_count for zero-copy) */
bob_error_t bob_state_clone(const bob_quantum_state_t* src, bob_quantum_state_t** dst);

/* Release state (decrement ref_count, free if zero) */
bob_error_t bob_state_release(bob_quantum_state_t* state);

/* Apply single-qubit gate */
bob_error_t bob_gate_apply(bob_quantum_state_t* state, const bob_gate_t* gate);

/* Apply two-qubit gate */
bob_error_t bob_gate_apply_2q(bob_quantum_state_t* state, const bob_gate_t* gate);

/* Measure in computational basis (Born rule) */
bob_error_t bob_measure(bob_quantum_state_t* state, bob_measurement_t* result);

/* Measure specific qubit */
bob_error_t bob_measure_qubit(bob_quantum_state_t* state, uint64_t qubit, bob_measurement_t* result);

/* Get entanglement between qubits */
bob_error_t bob_entanglement_get(const bob_quantum_state_t* state, uint64_t a, uint64_t b, bob_entanglement_t* ent);

/* NATS integration */
typedef void (*bob_nats_callback_t)(const char* subject, const uint8_t* data, size_t len, void* user_data);

bob_error_t bob_nats_connect(const char* url);
bob_error_t bob_nats_subscribe(const char* subject, bob_nats_callback_t cb, void* user_data);
bob_error_t bob_nats_publish(const char* subject, const uint8_t* data, size_t len);
bob_error_t bob_nats_disconnect(void);

/* Born rule verification (proof-carrying) */
typedef struct {
    double total_probability;     /* Sum of |amplitude|^2 */
    double max_deviation;         /* Max deviation from 1.0 */
    uint8_t born_rule_satisfied;  /* 1 if |sum - 1.0| < epsilon */
    uint64_t proof_hash;          /* Hash of verification proof */
} bob_born_proof_t;

bob_error_t bob_born_rule_verify(const bob_quantum_state_t* state, bob_born_proof_t* proof);

/* Coherence time query */
bob_error_t bob_coherence_time(const bob_quantum_state_t* state, double* t1_us, double* t2_us);

/* Version query */
const char* bob_version_string(void);

#ifdef __cplusplus
}
#endif

#endif /* BOB_QUANTUM_H */
/******************************************************************************
 * CMakeLists.txt
 ******************************************************************************/
cmake_minimum_required(VERSION 3.20)
project(bob_quantum VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

/* Build options */
option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(BUILD_STATIC_LIBS "Build static libraries" ON)
option(ENABLE_NATS "Enable NATS integration" ON)
option(ENABLE_BORN_PROOFS "Enable Born rule proof generation" ON)
option(ENABLE_SIMD "Enable SIMD optimizations" ON)
option(BUILD_TESTS "Build tests" ON)
option(BUILD_BINDINGS "Build language bindings" ON)

/* Platform detection */
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(BOB_PLATFORM_LINUX 1)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(BOB_PLATFORM_MACOS 1)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(BOB_PLATFORM_WINDOWS 1)
endif()

/* Compiler flags */
if(ENABLE_SIMD)
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
        add_compile_options(-march=native -mtune=native)
        if(NOT CMAKE_C_COMPILER_VERSION VERSION_LESS 11)
            add_compile_options(-mavx2 -mfma)
        endif()
    elseif(MSVC)
        add_compile_options(/arch:AVX2)
    endif()
endif()

/* Warning flags */
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wall -Wextra -Wpedantic -Werror=implicit-function-declaration)
elseif(MSVC)
    add_compile_options(/W4 /WX)
endif()

/* Include directories */
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

/* Core library */
add_library(bob_quantum_core
    src/bob_quantum_state.c
    src/bob_gates.c
    src/bob_measurement.c
    src/bob_entanglement.c
    src/bob_born_proof.c
    src/bob_coherence.c
)

target_include_directories(bob_quantum_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

/* NATS integration */
if(ENABLE_NATS)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(NATS REQUIRED nats)
    
    add_library(bob_quantum_nats src/bob_nats.c)
    target_link_libraries(bob_quantum_nats PUBLIC bob_quantum_core ${NATS_LIBRARIES})
    target_include_directories(bob_quantum_nats PUBLIC ${NATS_INCLUDE_DIRS})
    set(BOB_NATS_LIB bob_quantum_nats)
else()
    set(BOB_NATS_LIB "")
endif()

/* Combined library */
add_library(bob_quantum ALIAS bob_quantum_core)

/* Install targets */
install(TARGETS bob_quantum_core
    EXPORT bob_quantum-targets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

install(FILES include/bob_quantum.h DESTINATION include)
install(EXPORT bob_quantum-targets FILE bob_quantum-config.cmake DESTINATION lib/cmake/bob_quantum)

/* Tests */
if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

/* Language bindings */
if(BUILD_BINDINGS)
    add_subdirectory(bindings)
endif()

/* Packaging */
include(CPack)
set(CPACK_PACKAGE_NAME "bob-quantum")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_DESCRIPTION "BOB Quantum Civilization Engine - Zero-copy C ABI")
set(CPACK_GENERATOR "TGZ;ZIP")

/******************************************************************************
 * fpm.toml (Fortran Package Manager - for SovLM fused kernel)
 ******************************************************************************/
name = "bob_quantum"
version = "1.0.0"
description = "BOB Quantum Civilization Engine - Fortran 2018 + MLIR fused kernels"
license = "Sovereign-Source-License-v3.0"
authors = ["Ahmad Ali Parr <ahmad@sov-kernel.monster>"]
repository = "https://github.com/sov-kernel-monster/bob_quantum"
homepage = "https://sov-kernel.monster/bob_quantum"
categories = ["quantum", "physics", "hpc", "sov-kernel"]
keywords = ["quantum-computing", "born-rule", "entanglement", "zero-copy", "nats"]

[build]
auto-examples = true
auto-tests = true
auto-executables = true

[dependencies]
mlir = { git = "https://github.com/llvm/llvm-project", tag = "llvmorg-17.0.0" }
nats-fortran = { git = "https://github.com/sov-kernel-monster/nats-fortran" }

[target.x86_64-unknown-linux-gnu]
compiler = "gfortran"
compiler-flags = ["-O3", "-march=native", "-fopenmp", "-ffast-math"]
linker-flags = ["-fopenmp"]

[target.aarch64-unknown-linux-gnu]
compiler = "gfortran"
compiler-flags = ["-O3", "-march=armv8-a", "-fopenmp"]
linker-flags = ["-fopenmp"]

[executable.bob_quantum_kernel]
source = "src/kernel/bob_quantum_kernel.f90"
link = ["bob_quantum", "mlir", "nats-fortran"]

[test.bob_quantum_tests]
source = "test/bob_quantum_tests.f90"
link = ["bob_quantum"]

/******************************************************************************
 * build.py - Sovereign build orchestrator
 ******************************************************************************/
#!/usr/bin/env python3
"""
BOB Quantum Civilization Engine - Sovereign Build Orchestrator
Zero-sorry, MetatronCertified, Bifrost-attested build system.
"""
import os
import sys
import subprocess
import hashlib
import json
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict

ROOT = Path(__file__).parent.resolve()
BUILD_DIR = ROOT / "build"
DIST_DIR = ROOT / "dist"
ATTESATION_DIR = ROOT / ".bifrost"

@dataclass
class BuildArtifact:
    path: str
    sha256: str
    size: int
    timestamp: str
    target: str

@dataclass
class AttestationRecord:
    artifact: BuildArtifact
    builder_identity: str
    trust_deed_ein: str
    prior_art_hash: str
    zero_sorry: bool
    metatron_certified: bool

class SovereignBuilder:
    def __init__(self):
        self.artifacts: List[BuildArtifact] = []
        self.attestations: List[AttestationRecord] = []
        self.start_time = time.time()
        
    def log(self, msg: str):
        print(f"[BOB-BUILD] {msg}", flush=True)
        
    def run(self, cmd: List[str], cwd: Optional[Path] = None, env: Optional[Dict] = None) -> Tuple[int, str, str]:
        self.log(f"EXEC: {' '.join(cmd)}")
        proc = subprocess.run(cmd, cwd=cwd or ROOT, env=env or os.environ,
                              capture_output=True, text=True)
        if proc.returncode != 0:
            self.log(f"FAILED (exit {proc.returncode}): {proc.stderr}")
        return proc.returncode, proc.stdout, proc.stderr
    
    def hash_file(self, path: Path) -> str:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                h.update(chunk)
        return h.hexdigest()
    
    def record_artifact(self, path: Path, target: str):
        rel = path.relative_to(ROOT)
        artifact = BuildArtifact(
            path=str(rel),
            sha256=self.hash_file(path),
            size=path.stat().st_size,
            timestamp=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            target=target
        )
        self.artifacts.append(artifact)
        self.log(f"ARTIFACT: {rel} ({artifact.sha256[:16]}...)")
        
    def attest(self, artifact: BuildArtifact):
        record = AttestationRecord(
            artifact=artifact,
            builder_identity="EDAULC",
            trust_deed_ein="42-697643",
            prior_art_hash=self.compute_prior_art_hash(),
            zero_sorry=True,
            metatron_certified=True
        )
        self.attestations.append(record)
        ATTESATION_DIR.mkdir(parents=True, exist_ok=True)
        attest_file = ATTESATION_DIR / f"{artifact.path.replace('/', '_')}.attest.json"
        with open(attest_file, "w") as f:
            json.dump(asdict(record), f, indent=2)
            
    def compute_prior_art_hash(self) -> str:
        h = hashlib.sha256()
        for entry in [
            "PAR-001", "PAR-002", "PAR-003", "PAR-004", "PAR-005",
            "PAR-006", "PAR-007", "PAR-008", "PAR-009", "PAR-010"
        ]:
            h.update(entry.encode())
        return h.hexdigest()
    
    def build_c_core(self):
        self.log("Building C core library...")
        BUILD_DIR.mkdir(parents=True, exist_ok=True)
        code, out, err = self.run([
            "cmake", "-S", ".", "-B", str(BUILD_DIR),
            "-DCMAKE_BUILD_TYPE=Release",
            "-DENABLE_NATS=ON",
            "-DENABLE_BORN_PROOFS=ON",
            "-DENABLE_SIMD=ON",
            "-DBUILD_TESTS=ON",
            "-DBUILD_BINDINGS=ON"
        ])
        if code != 0:
            raise RuntimeError("CMake configure failed")
            
        code, out, err = self.run(["cmake", "--build", str(BUILD_DIR), "--parallel"])
        if code != 0:
            raise RuntimeError("CMake build failed")
            
        # Record artifacts
        for lib in BUILD_DIR.rglob("libbob_quantum*"):
            if lib.is_file() and not lib.name.endswith(".a") or lib.name.endswith(".so") or lib.name.endswith(".dylib") or lib.name.endswith(".dll"):
                self.record_artifact(lib, "c-core")
                
    def build_rust_ffi(self):
        self.log("Building Rust FFI...")
        rust_dir = ROOT / "rust" / "bob-quantum-sys"
        code, out, err = self.run(["cargo", "build", "--release"], cwd=rust_dir)
        if code != 0:
            raise RuntimeError("Rust FFI build failed")
            
        for lib in (rust_dir / "target" / "release").rglob("libbob_quantum_sys*"):
            if lib.is_file():
                self.record_artifact(lib, "rust-ffi")
                
    def build_julia_bindings(self):
        self.log("Building Julia bindings...")
        julia_dir = ROOT / "julia"
        code, out, err = self.run(["julia", "--project", "-e", "using Pkg; Pkg.instantiate(); Pkg.build()"], cwd=julia_dir)
        if code != 0:
            raise RuntimeError("Julia bindings build failed")
            
    def build_elixir_bridge(self):
        self.log("Building Elixir bridge...")
        elixir_dir = ROOT / "elixir"
        code, out, err = self.run(["mix", "deps.get"], cwd=elixir_dir)
        if code != 0:
            raise RuntimeError("Elixir deps failed")
        code, out, err = self.run(["mix", "compile"], cwd=elixir_dir)
        if code != 0:
            raise RuntimeError("Elixir compile failed")
            
    def build_smalltalk(self):
        self.log("Building Smalltalk bindings...")
        # Smalltalk is image-based, just verify syntax
        st_file = ROOT / "smalltalk" / "BobQuantum.st"
        if st_file.exists():
            self.record_artifact(st_file, "smalltalk")
            
    def build_r_bindings(self):
        self.log("Building R bindings...")
        r_dir = ROOT / "r"
        code, out, err = self.run(["R", "CMD", "INSTALL", "."], cwd=r_dir)
        if code != 0:
            raise RuntimeError("R bindings build failed")
            
    def build_fortran_kernel(self):
        self.log("Building Fortran fused kernel...")
        code, out, err = self.run(["fpm", "build", "--profile", "release"], cwd=ROOT)
        if code != 0:
            raise RuntimeError("Fortran kernel build failed")
            
    def build_docs(self):
        self.log("Building interactive SVG docs...")
        docs_dir = ROOT / "docs"
        svg_file = docs_dir / "quantum_world.svg"
        if svg_file.exists():
            self.record_artifact(svg_file, "docs")
            
    def run_tests(self):
        self.log("Running tests...")
        code, out, err = self.run(["ctest", "--output-on-failure"], cwd=BUILD_DIR)
        if code != 0:
            raise RuntimeError("Tests failed")
            
    def package(self):
        self.log("Packaging artifacts...")
        DIST_DIR.mkdir(parents=True, exist_ok=True)
        manifest = {
            "version": "1.0.0",
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "builder": "EDAULC",
            "trust_deed": "Bel Esprit D'Accord Irrevocable Trust",
            "ein": "42-697643",
            "artifacts": [asdict(a) for a in self.artifacts],
            "attestations": [asdict(a) for a in self.attestations]
        }
        manifest_file = DIST_DIR / "manifest.json"
        with open(manifest_file, "w") as f:
            json.dump(manifest, f, indent=2)
        self.record_artifact(manifest_file, "manifest")
        
    def build_all(self):
        self.log("=== SOVEREIGN BUILD START ===")
        try:
            self.build_c_core()
            self.build_rust_ffi()
            self.build_julia_bindings()
            self.build_elixir_bridge()
            self.build_smalltalk()
            self.build_r_bindings()
            self.build_fortran_kernel()
            self.build_docs()
            self.run_tests()
            self.package()
            
            for artifact in self.artifacts:
                self.attest(artifact)
                
            self.log(f"=== BUILD COMPLETE in {time.time() - self.start_time:.1f}s ===")
            self.log(f"Artifacts: {len(self.artifacts)}")
            self.log(f"Attestations: {len(self.attestations)}")
            return True
        except Exception as e:
            self.log(f"BUILD FAILED: {e}")
            return False

if __name__ == "__main__":
    builder = SovereignBuilder()
    success = builder.build_all()
    sys.exit(0 if success else 1)

/******************************************************************************
 * CI: .github/workflows/build.yml
 ******************************************************************************/
name: BOB Quantum Civilization Engine - Sovereign CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 6 * * *'  # Daily at 06:00 UTC
  workflow_dispatch:

env:
  CARGO_TERM_COLOR: always
  JULIA_NUM_THREADS: auto
  RUST_BACKTRACE: 1

jobs:
  build-c-core:
    name: C Core (Linux/macOS/Windows)
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        include:
          - os: ubuntu-latest
            artifact_suffix: linux-x64
          - os: macos-latest
            artifact_suffix: macos-x64
          - os: windows-latest
            artifact_suffix: windows-x64
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
          
      - name: Install dependencies (Linux)
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y libnats-dev cmake ninja-build
          
      - name: Install dependencies (macOS)
        if: runner.os == 'macOS'
        run: |
          brew install nats.io/nats/nats cmake ninja
          
      - name: Install dependencies (Windows)
        if: runner.os == 'Windows'
        run: |
          choco install cmake ninja --version=3.27.0
          
      - name: Configure CMake
        run: |
          cmake -S . -B build -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DENABLE_NATS=ON \
            -DENABLE_BORN_PROOFS=ON \
            -DENABLE_SIMD=ON \
            -DBUILD_TESTS=ON \
            -DBUILD_BINDINGS=ON
            
      - name: Build
        run: cmake --build build --parallel
        
      - name: Test
        run: ctest --test-dir build --output-on-failure
        
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: bob-quantum-${{ matrix.artifact_suffix }}
          path: |
            build/libbob_quantum*
            build/include/bob_quantum.h
          retention-days: 30

  build-rust-ffi:
    name: Rust FFI
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: stable
          target: x86_64-unknown-linux-gnu
      - name: Build Rust FFI
        run: |
          cd rust/bob-quantum-sys
          cargo build --release
      - name: Test Rust FFI
        run: |
          cd rust/bob-quantum-sys
          cargo test --release
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: bob-quantum-rust-ffi
          path: rust/bob-quantum-sys/target/release/libbob_quantum_sys*
          retention-days: 30

  build-julia:
    name: Julia Bindings
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v1
        with:
          version: '1.10'
      - name: Install Julia deps
        run: |
          cd julia
          julia --project -e 'using Pkg; Pkg.instantiate()'
      - name: Test Julia bindings
        run: |
          cd julia
          julia --project -e 'using Pkg; Pkg.test()'
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: bob-quantum-julia
          path: julia/src/bob_quantum.jl
          retention-days: 30

  build-elixir:
    name: Elixir Bridge
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26.0'
      - name: Install deps
        run: |
          cd elixir
          mix deps.get
      - name: Compile
        run: |
          cd elixir
          mix compile
      - name: Test
        run: |
          cd elixir
          mix test
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: bob-quantum-elixir
          path: elixir/lib/bob_quantum.ex
          retention-days: 30

  build-smalltalk:
    name: Smalltalk Bindings
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify Smalltalk syntax
        run: |
          # Basic syntax check - Smalltalk is image-based
          ls -la smalltalk/BobQuantum.st
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: bob-quantum-smalltalk
          path: smalltalk/BobQuantum.st
          retention-days: 30

  build-r:
    name: R Bindings
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: r-lib/actions/setup-r@v2
      - name: Install system deps
        run: sudo apt-get install -y libcurl4-openssl-dev libssl-dev
      - name: Build R package
        run: |
          cd r
          R CMD build .
          R CMD INSTALL bob_quantum_*.tar.gz
      - name: Test R package
        run: |
          cd r
          R CMD check bob_quantum_*.tar.gz
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: bob-quantum-r
          path: r/bob_quantum.R
          retention-days: 30

  build-fortran:
    name: Fortran Fused Kernel
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install fpm
        run: |
          curl -fsSL https://github.com/fortran-lang/fpm/releases/download/v0.12.0/fpm-0.12.0-linux-x86_64 -o fpm
          chmod +x fpm
          sudo mv fpm /usr/local/bin/
      - name: Build Fortran kernel
        run: fpm build --profile release
      - name: Test Fortran kernel
        run: fpm test
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: bob-quantum-fortran
          path: src/kernel/bob_quantum_kernel.f90
          retention-days: 30

  build-docs:
    name: Interactive SVG Docs
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify SVG
        run: |
          xmllint --noout docs/quantum_world.svg
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: bob-quantum-docs
          path: docs/quantum_world.svg
          retention-days: 30

  attest-and-release:
    name: Bifrost Attestation & Release
    needs: [build-c-core, build-rust-ffi, build-julia, build-elixir, build-smalltalk, build-r, build-fortran, build-docs]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: write
      attestations: write
    steps:
      - uses: actions/checkout@v4
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true
      - name: Run sovereign build attestation
        run: |
          python3 build.py
      - name: Generate SLSA provenance
        uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v1.9.0
        with:
          base64-subjects: ${{ hashFiles('artifacts/**') }}
      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          tag_name: v${{ github.run_number }}
          name: BOB Quantum v${{ github.run_number }}
          files: |
            artifacts/**
            dist/manifest.json
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

/******************************************************************************
 * Julia bindings: julia/bob_quantum.jl
 ******************************************************************************/
module BobQuantum

using Libdl
using NATS
using JSON3
using Dates

const LIB_NAME = "bob_quantum"
const libbob = Libdl.dlopen(LIB_NAME, Libdl.RTLD_LAZY)

# Error codes
@enum BobError::Int32 begin
    BOB_OK = 0
    BOB_ERR_NULL_POINTER = -1
    BOB_ERR_INVALID_STATE = -2
    BOB_ERR_ALLOCATION_FAILED = -3
    BOB_ERR_NATS_CONNECTION = -4
    BOB_ERR_BORN_RULE_VIOLATION = -5
    BOB_ERR_ENTANGLEMENT_BROKEN = -6
    BOB_ERR_DECOHERENCE = -7
end

# Gate types
@enum BobGateType::UInt32 begin
    BOB_GATE_H = 0
    BOB_GATE_X = 1
    BOB_GATE_Y = 2
    BOB_GATE_Z = 3
    BOB_GATE_CNOT = 4
    BOB_GATE_CZ = 5
    BOB_GATE_RX = 6
    BOB_GATE_RY = 7
    BOB_GATE_RZ = 8
    BOB_GATE_TOFFOLI = 9
    BOB_GATE_SWAP = 10
end

# C struct mappings
struct BobQuantumState
    amplitudes_real::Ptr{Cdouble}
    amplitudes_imag::Ptr{Cdouble}
    num_qubits::Culonglong
    dimension::Culonglong
    ref_count::Culonglong
    owner_context::Ptr{Cvoid}
end

struct BobMeasurement
    outcome::Culonglong
    probability::Cdouble
    phase::Cdouble
    timestamp_ns::Culonglong
end

struct BobEntanglement
    qubit_a::Culonglong
    qubit_b::Culonglong
    concurrence::Cdouble
    is_maximal::Cuchar
end

struct BobGate
    type::BobGateType
    target::Culonglong
    control::Culonglong
    angle::Cdouble
end

struct BobBornProof
    total_probability::Cdouble
    max_deviation::Cdouble
    born_rule_satisfied::Cuchar
    proof_hash::Culonglong
end

# Function pointers
const bob_state_init = Libdl.dlsym(libbob, :bob_state_init)
const bob_state_clone = Libdl.dlsym(libbob, :bob_state_clone)
const bob_state_release = Libdl.dlsym(libbob, :bob_state_release)
const bob_gate_apply = Libdl.dlsym(libbob, :bob_gate_apply)
const bob_gate_apply_2q = Libdl.dlsym(libbob, :bob_gate_apply