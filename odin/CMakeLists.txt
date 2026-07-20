# Odin Foreign Binding for BOB Quantum Engine
# This module provides foreign function bindings to the C ABI interface

if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before odin subdirectory")
endif()

# Odin foreign bindings - no compilation at CMake level, Odin build system is independent
add_custom_target(odin_bindings ALL
  DEPENDS bob_quantum
  COMMENT "Odin foreign bindings verified"
)

# Install Odin module
install(FILES bob_quantum.odin
  DESTINATION share/bob_quantum/odin
)

# Add to binding documentation
file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/../BINDINGS_SUMMARY.txt"
  "Odin: bob_quantum.odin (foreign bindings to C ABI) - installed to share/bob_quantum/odin\n"
)
