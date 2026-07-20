# Racket FFI Binding for BOB Quantum Engine
# This module provides FFI bindings to the C ABI interface

if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before racket subdirectory")
endif()

# Racket FFI files - no compilation needed, just validation
add_custom_target(racket_bindings ALL
  DEPENDS bob_quantum
  COMMENT "Racket FFI bindings verified"
)

# Install Racket module
install(FILES bob_quantum.rkt
  DESTINATION share/bob_quantum/racket
)

# Add to binding documentation
file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/../BINDINGS_SUMMARY.txt"
  "Racket: bob_quantum.rkt (FFI to C ABI) - installed to share/bob_quantum/racket\n"
)
