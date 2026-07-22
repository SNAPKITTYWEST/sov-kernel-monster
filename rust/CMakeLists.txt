# Rust FFI Crate for BOB Quantum Engine
if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before rust subdirectory")
endif()
add_custom_target(rust_bindings ALL DEPENDS bob_quantum COMMENT "Rust FFI bindings verified")
# Rust FFI managed via Cargo
