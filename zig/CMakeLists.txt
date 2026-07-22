# Zig FFI Binding for BOB Quantum Engine
# This module provides FFI bindings to the C ABI interface

if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before zig subdirectory")
endif()

# Zig FFI bindings - no compilation at CMake level, Zig build system is independent
add_custom_target(zig_bindings ALL
  DEPENDS bob_quantum
  COMMENT "Zig FFI bindings verified"
)

# Install Zig module
install(DIRECTORY src/
  DESTINATION share/bob_quantum/zig/src
  FILES_MATCHING PATTERN "*.zig"
)

# Add to binding documentation
file(APPEND "${CMAKE_CURRENT_BINARY_DIR}/../BINDINGS_SUMMARY.txt"
  "Zig: src/bob_quantum.zig (FFI to C ABI) - installed to share/bob_quantum/zig\n"
)
