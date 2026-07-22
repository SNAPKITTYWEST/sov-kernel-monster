cmake_minimum_required(VERSION 3.15)
project(BOBQuantumCivilizationEngine
  VERSION 1.0.0
  DESCRIPTION "Quantum simulation engine for distributed civilization mesh"
  LANGUAGES C CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD 11)

# =========================================================================
# Core Library Options
# =========================================================================

option(BOB_BUILD_SHARED_LIBS "Build shared libraries" ON)
option(BOB_BUILD_TESTS "Build test suite" ON)
option(BOB_BUILD_BENCHMARKS "Build benchmark suite" ON)
option(BOB_BUILD_DOCS "Build documentation" OFF)
option(BOB_ENABLE_RTTI "Enable RTTI for bindings" ON)
option(BOB_ENABLE_EXCEPTIONS "Enable C++ exceptions" ON)

if(BOB_BUILD_SHARED_LIBS)
  set(BUILD_SHARED_LIBS ON)
else()
  set(BUILD_SHARED_LIBS OFF)
endif()

# =========================================================================
# Language Binding Options
# =========================================================================

option(BOB_BINDING_PYTHON "Build Python bindings (ctypes)" ON)
option(BOB_BINDING_JULIA "Build Julia bindings" ON)
option(BOB_BINDING_ELIXIR "Build Elixir/Erlang NIF bindings" OFF)
option(BOB_BINDING_RACKET "Build Racket FFI bindings" ON)
option(BOB_BINDING_JANET "Build Janet native bindings" ON)
option(BOB_BINDING_ZIG "Build Zig FFI bindings" ON)
option(BOB_BINDING_ODIN "Build Odin foreign bindings" ON)
option(BOB_BINDING_RUST "Build Rust FFI crate" OFF)
option(BOB_BINDING_HASKELL "Build Haskell FFI bindings" OFF)
option(BOB_BINDING_SMALLTALK "Build Smalltalk VM plugin" OFF)
option(BOB_BINDING_R "Build R/C++ bindings" ON)

# =========================================================================
# Find Dependencies
# =========================================================================

find_package(OpenMP REQUIRED)
find_package(Threads REQUIRED)

# Optional: BLAS/LAPACK for linear algebra
find_package(BLAS QUIET)
find_package(LAPACK QUIET)

# =========================================================================
# Core Library
# =========================================================================

set(BOB_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(BOB_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src)

file(GLOB BOB_SOURCES
  ${BOB_SRC_DIR}/*.c
  ${BOB_SRC_DIR}/*.cpp
)

file(GLOB BOB_HEADERS
  ${BOB_INCLUDE_DIR}/*.h
)

# Create main shared library
add_library(bob_quantum ${BOB_SOURCES} ${BOB_HEADERS})

target_include_directories(bob_quantum PUBLIC
  $<BUILD_INTERFACE:${BOB_INCLUDE_DIR}>
  $<INSTALL_INTERFACE:include>
)

target_link_libraries(bob_quantum PUBLIC
  OpenMP::OpenMP_C
  OpenMP::OpenMP_CXX
  Threads::Threads
)

if(BLAS_FOUND AND LAPACK_FOUND)
  target_link_libraries(bob_quantum PUBLIC
    ${BLAS_LIBRARIES}
    ${LAPACK_LIBRARIES}
  )
endif()

# Compiler-specific optimizations
if(MSVC)
  target_compile_options(bob_quantum PRIVATE /O2 /arch:AVX2)
else()
  target_compile_options(bob_quantum PRIVATE -O3 -march=native -ffast-math)
endif()

# =========================================================================
# Language Bindings
# =========================================================================

# Racket FFI bindings
if(BOB_BINDING_RACKET)
  add_subdirectory(racket)
endif()

# Janet native bindings
if(BOB_BINDING_JANET)
  add_subdirectory(janet)
endif()

# Zig FFI bindings
if(BOB_BINDING_ZIG)
  add_subdirectory(zig)
endif()

# Odin foreign bindings
if(BOB_BINDING_ODIN)
  add_subdirectory(odin)
endif()

# Julia bindings
if(BOB_BINDING_JULIA)
  add_subdirectory(julia)
endif()

# R bindings
if(BOB_BINDING_R)
  add_subdirectory(r)
endif()

# Haskell FFI
if(BOB_BINDING_HASKELL)
  add_subdirectory(haskell)
endif()

# Smalltalk VM plugin
if(BOB_BINDING_SMALLTALK)
  add_subdirectory(smalltalk)
endif()

# Rust FFI crate
if(BOB_BINDING_RUST)
  add_subdirectory(rust)
endif()

# Elixir/Erlang NIF
if(BOB_BINDING_ELIXIR)
  add_subdirectory(elixir)
endif()

# =========================================================================
# Test Suite
# =========================================================================

if(BOB_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()

# =========================================================================
# Benchmark Suite
# =========================================================================

if(BOB_BUILD_BENCHMARKS)
  add_subdirectory(benchmarks)
endif()

# =========================================================================
# Installation
# =========================================================================

install(TARGETS bob_quantum
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  RUNTIME DESTINATION bin
)

install(FILES ${BOB_HEADERS}
  DESTINATION include
)

install(FILES
  ${CMAKE_CURRENT_SOURCE_DIR}/README.md
  ${CMAKE_CURRENT_SOURCE_DIR}/CONTRIBUTING.md
  ${CMAKE_CURRENT_SOURCE_DIR}/LICENSE
  DESTINATION share/bob_quantum
)

# =========================================================================
# Summary
# =========================================================================

message(STATUS "")
message(STATUS "=== BOB Quantum Civilization Engine Configuration ===")
message(STATUS "")
message(STATUS "Core Library:")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "  Shared: ${BUILD_SHARED_LIBS}")
message(STATUS "")
message(STATUS "Language Bindings:")
message(STATUS "  Python: ${BOB_BINDING_PYTHON}")
message(STATUS "  Julia: ${BOB_BINDING_JULIA}")
message(STATUS "  Racket: ${BOB_BINDING_RACKET}")
message(STATUS "  Janet: ${BOB_BINDING_JANET}")
message(STATUS "  Zig: ${BOB_BINDING_ZIG}")
message(STATUS "  Odin: ${BOB_BINDING_ODIN}")
message(STATUS "  Haskell: ${BOB_BINDING_HASKELL}")
message(STATUS "  R: ${BOB_BINDING_R}")
message(STATUS "  Smalltalk: ${BOB_BINDING_SMALLTALK}")
message(STATUS "  Rust: ${BOB_BINDING_RUST}")
message(STATUS "  Elixir: ${BOB_BINDING_ELIXIR}")
message(STATUS "")
message(STATUS "Optional Features:")
message(STATUS "  Build Tests: ${BOB_BUILD_TESTS}")
message(STATUS "  Build Benchmarks: ${BOB_BUILD_BENCHMARKS}")
message(STATUS "  Build Documentation: ${BOB_BUILD_DOCS}")
message(STATUS "  OpenMP: ${OPENMP_FOUND}")
message(STATUS "  BLAS/LAPACK: ${BLAS_FOUND}")
message(STATUS "")
message(STATUS "Install Prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "")
