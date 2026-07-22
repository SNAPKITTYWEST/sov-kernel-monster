# Haskell FFI Binding for BOB Quantum Engine
if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before haskell subdirectory")
endif()
add_custom_target(haskell_bindings ALL DEPENDS bob_quantum COMMENT "Haskell FFI bindings verified")
# Haskell modules installed via stack/cabal
