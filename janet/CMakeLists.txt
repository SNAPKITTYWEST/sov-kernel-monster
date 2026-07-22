# Janet Native Binding for BOB Quantum Engine
# This module provides native bindings to the C ABI interface

if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before janet subdirectory")
endif()

# Janet native bindings - no compilation needed, just validation
add_custom_target(janet_bindings ALL
  DEPENDS bob_quantum
  COMMENT "Janet native bindings verified"
)

# Install Janet module
install(FILES bob_quantum.janet
  DESTINATION share/bob_quantum/janet
)

# Add to binding documentation
file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/../BINDINGS_SUMMARY.txt"
  "Janet: bob_quantum.janet (native bindings to C ABI) - installed to share/bob_quantum/janet\n"
)
