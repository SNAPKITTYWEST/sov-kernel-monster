# BOB Quantum Benchmark Suite
if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before benchmarks subdirectory")
endif()

# Benchmark executable
add_executable(bob_benchmarks bob_benchmarks.c)
target_link_libraries(bob_benchmarks PRIVATE bob_quantum)
target_include_directories(bob_benchmarks PRIVATE ${BOB_INCLUDE_DIR})

if(MSVC)
  target_compile_options(bob_benchmarks PRIVATE /O2 /arch:AVX2)
else()
  target_compile_options(bob_benchmarks PRIVATE -O3 -march=native -ffast-math)
endif()

# Installation
install(TARGETS bob_benchmarks
  RUNTIME DESTINATION bin
)
