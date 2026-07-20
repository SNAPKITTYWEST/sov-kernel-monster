#======================================================================
# SOV-KERNEL-MONSTER — Sovereign Quantum Compute Engine
# GNU Fortran 2018 + MLIR → ARM64 SVE2 / x86_64 AVX-512 / PTX
#
# Targets:
#   all         Build libbob_quantum (static + shared)
#   monster     Build full sovereign binary via LLVM pipeline
#   wasm        Build Rust WASM bridge (requires wasm-pack)
#   debug       Debug build with sanitizers
#   clean       Remove build artifacts
#   install     Install to /usr/local
#   info        Show build info
#
# Structure:
#   src/        Fortran 2018 sources (bob_*.f90 + monster kernel)
#   mlir/       MLIR pipeline files
#   wasm/       Rust WASM bridge (wasm-pack build --target web)
#   lean/       Lean 4 FFI specifications
#   docs/       Documentation and universe.svg
#   build/      Object files and module files
#   lib/        Output libraries
#======================================================================

FC       = gfortran
FFLAGS   = -O3 -march=native -ffast-math -funroll-loops -fopenmp -std=f2018
FFLAGS_DEBUG = -g -O0 -Wall -Wextra -fcheck=all -fbacktrace -fopenmp -std=f2018
LDFLAGS  = -fopenmp

LLVM_VER ?= 19
FLANG    = flang-new-$(LLVM_VER)
MLIR_OPT = mlir-opt-$(LLVM_VER)
LLC      = llc-$(LLVM_VER)
LLD      = ld.lld-$(LLVM_VER)

SRC_DIR   = src
BUILD_DIR = build
LIB_DIR   = lib
OBJ_DIR   = $(BUILD_DIR)/obj
MLIR_DIR  = mlir
WASM_DIR  = wasm

LIB_NAME   = libbob_quantum
STATIC_LIB = $(LIB_DIR)/$(LIB_NAME).a
SHARED_LIB = $(LIB_DIR)/$(LIB_NAME).so
MONSTER    = $(LIB_DIR)/sov_monster

# ── BOB quantum modules (dependency order) ─────────────────────────────
BOB_SOURCES = \
	$(SRC_DIR)/bob_kinds.f90 \
	$(SRC_DIR)/bob_errors.f90 \
	$(SRC_DIR)/bob_rng.f90 \
	$(SRC_DIR)/bob_state.f90 \
	$(SRC_DIR)/bob_gates.f90 \
	$(SRC_DIR)/bob_lattice.f90 \
	$(SRC_DIR)/bob_measurement.f90 \
	$(SRC_DIR)/bob_hamiltonian.f90 \
	$(SRC_DIR)/bob_integrator.f90 \
	$(SRC_DIR)/bob_metrics.f90 \
	$(SRC_DIR)/bob_goldilocks.f90 \
	$(SRC_DIR)/bob_worm.f90 \
	$(SRC_DIR)/bob_circuit.f90 \
	$(SRC_DIR)/bob_phdae.f90 \
	$(SRC_DIR)/bob_abi.f90

# ── Monster kernel sources ──────────────────────────────────────────────
MONSTER_SOURCES = \
	$(SRC_DIR)/sov_monster_kernel.f90 \
	$(SRC_DIR)/boolean_spectral_lens.f90 \
	$(SRC_DIR)/measurement_head.f90 \
	$(SRC_DIR)/jordan_block.f90 \
	$(SRC_DIR)/spe_encoder.f90 \
	$(SRC_DIR)/training_adjoint.f90

ALL_SOURCES = $(BOB_SOURCES) $(MONSTER_SOURCES)
OBJECTS     = $(patsubst $(SRC_DIR)/%.f90,$(OBJ_DIR)/%.o,$(ALL_SOURCES))

.PHONY: all directories clean debug install uninstall wasm monster info help

all: directories $(STATIC_LIB) $(SHARED_LIB)

directories:
	@mkdir -p $(OBJ_DIR) $(LIB_DIR)

$(STATIC_LIB): $(OBJECTS)
	@echo "[AR]  $@"
	ar rcs $@ $^

$(SHARED_LIB): $(OBJECTS)
	@echo "[LD]  $@"
	$(FC) -shared $(LDFLAGS) -o $@ $^

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.f90
	@echo "[FC]  $<"
	$(FC) $(FFLAGS) -J$(OBJ_DIR) -c $< -o $@

# ── Full LLVM monster binary ────────────────────────────────────────────
monster: directories
	@echo "[FLANG] Fortran → MLIR"
	$(FLANG) -fc1 -emit-mlir -fopenmp $(SRC_DIR)/sov_monster_kernel.f90 \
	  -o $(BUILD_DIR)/sov_kernel.mlir
	@echo "[MLIR]  Fuse + vectorize"
	$(MLIR_OPT) \
	  --affine-loop-fusion --linalg-tile="tile-sizes=16,16" \
	  --vectorize --convert-linalg-to-loops \
	  --convert-scf-to-llvm --convert-func-to-llvm \
	  $(BUILD_DIR)/sov_kernel.mlir $(MLIR_DIR)/sov_pipeline.mlir \
	  -o $(BUILD_DIR)/sov_llvm.mlir
	@echo "[LLC]   MLIR → ARM64 SVE2"
	mlir-translate-$(LLVM_VER) --mlir-to-llvmir $(BUILD_DIR)/sov_llvm.mlir \
	  -o $(BUILD_DIR)/sov.ll
	$(LLC) -mtriple=aarch64-linux-gnu -mattr=+sve2,+aes,+sha3 \
	  -O3 -filetype=obj $(BUILD_DIR)/sov.ll -o $(BUILD_DIR)/sov_arm64.o
	as -mabi=lp64 $(SRC_DIR)/start.S -o $(BUILD_DIR)/start.o
	$(LLD) --static -e _start $(BUILD_DIR)/start.o $(BUILD_DIR)/sov_arm64.o \
	  -o $(MONSTER)_arm64
	@echo "[DONE] $(MONSTER)_arm64"

# ── Rust WASM bridge ────────────────────────────────────────────────────
wasm:
	@echo "[WASM] Building Rust bridge → quantum_wasm_bg.wasm"
	cd $(WASM_DIR) && wasm-pack build --target web --out-dir pkg
	@echo "[DONE] $(WASM_DIR)/pkg/"

# ── Debug build ─────────────────────────────────────────────────────────
debug: FFLAGS = $(FFLAGS_DEBUG)
debug: clean all

# ── Install ─────────────────────────────────────────────────────────────
install: all
	install -d /usr/local/lib /usr/local/include/bob
	install -m 644 $(STATIC_LIB) /usr/local/lib/
	install -m 755 $(SHARED_LIB) /usr/local/lib/
	install -m 644 $(OBJ_DIR)/*.mod /usr/local/include/bob/
	@echo "Installed to /usr/local"

uninstall:
	rm -f /usr/local/lib/$(LIB_NAME).*
	rm -rf /usr/local/include/bob

clean:
	rm -rf $(BUILD_DIR) $(LIB_DIR)

info:
	@echo "SOV-KERNEL-MONSTER"
	@echo "=================="
	@echo "FC:            $(FC)"
	@echo "FFLAGS:        $(FFLAGS)"
	@echo "BOB modules:   $(words $(BOB_SOURCES))"
	@echo "Monster files: $(words $(MONSTER_SOURCES))"
	@echo "Total sources: $(words $(ALL_SOURCES))"
	@echo ""
	@echo "Targets: all  monster  wasm  debug  clean  install  info"

help: info

# ── Dependency graph ────────────────────────────────────────────────────
$(OBJ_DIR)/bob_errors.o:       $(OBJ_DIR)/bob_kinds.o
$(OBJ_DIR)/bob_rng.o:          $(OBJ_DIR)/bob_kinds.o $(OBJ_DIR)/bob_errors.o
$(OBJ_DIR)/bob_state.o:        $(OBJ_DIR)/bob_kinds.o $(OBJ_DIR)/bob_errors.o
$(OBJ_DIR)/bob_gates.o:        $(OBJ_DIR)/bob_state.o
$(OBJ_DIR)/bob_lattice.o:      $(OBJ_DIR)/bob_state.o $(OBJ_DIR)/bob_rng.o
$(OBJ_DIR)/bob_measurement.o:  $(OBJ_DIR)/bob_state.o $(OBJ_DIR)/bob_rng.o
$(OBJ_DIR)/bob_hamiltonian.o:  $(OBJ_DIR)/bob_state.o
$(OBJ_DIR)/bob_integrator.o:   $(OBJ_DIR)/bob_state.o $(OBJ_DIR)/bob_hamiltonian.o
$(OBJ_DIR)/bob_metrics.o:      $(OBJ_DIR)/bob_state.o $(OBJ_DIR)/bob_lattice.o
$(OBJ_DIR)/bob_goldilocks.o:   $(OBJ_DIR)/bob_kinds.o $(OBJ_DIR)/bob_errors.o
$(OBJ_DIR)/bob_worm.o:         $(OBJ_DIR)/bob_kinds.o $(OBJ_DIR)/bob_errors.o
$(OBJ_DIR)/bob_circuit.o:      $(OBJ_DIR)/bob_kinds.o $(OBJ_DIR)/bob_errors.o $(OBJ_DIR)/bob_goldilocks.o
$(OBJ_DIR)/bob_phdae.o:        $(OBJ_DIR)/bob_state.o $(OBJ_DIR)/bob_worm.o
$(OBJ_DIR)/bob_abi.o:          $(OBJ_DIR)/bob_kinds.o $(OBJ_DIR)/bob_errors.o \
                                $(OBJ_DIR)/bob_state.o $(OBJ_DIR)/bob_gates.o \
                                $(OBJ_DIR)/bob_rng.o $(OBJ_DIR)/bob_lattice.o \
                                $(OBJ_DIR)/bob_measurement.o $(OBJ_DIR)/bob_metrics.o \
                                $(OBJ_DIR)/bob_hamiltonian.o $(OBJ_DIR)/bob_integrator.o
$(OBJ_DIR)/sov_monster_kernel.o: $(OBJ_DIR)/bob_kinds.o
$(OBJ_DIR)/boolean_spectral_lens.o: $(OBJ_DIR)/sov_monster_kernel.o $(OBJ_DIR)/spe_encoder.o
$(OBJ_DIR)/measurement_head.o: $(OBJ_DIR)/sov_monster_kernel.o
$(OBJ_DIR)/jordan_block.o:     $(OBJ_DIR)/sov_monster_kernel.o
$(OBJ_DIR)/spe_encoder.o:      $(OBJ_DIR)/bob_kinds.o
$(OBJ_DIR)/training_adjoint.o: $(OBJ_DIR)/sov_monster_kernel.o
