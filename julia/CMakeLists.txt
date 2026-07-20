# Julia Binding for BOB Quantum Engine
if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before julia subdirectory")
endif()
add_custom_target(julia_bindings ALL DEPENDS bob_quantum COMMENT "Julia bindings verified")
install(FILES bob_quantum.jl DESTINATION share/bob_quantum/julia)
