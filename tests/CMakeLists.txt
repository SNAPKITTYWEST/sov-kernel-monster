# BOB Quantum Test Suite
if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before tests subdirectory")
endif()

# Test executable framework
# This directory will contain test files for the quantum engine
# Tests can be added via add_test() commands

message(STATUS "BOB Quantum Test Suite - configure as needed")
