# R/C++ Binding for BOB Quantum Engine
if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before r subdirectory")
endif()
add_custom_target(r_bindings ALL DEPENDS bob_quantum COMMENT "R bindings verified")
install(FILES bob_quantum.R DESTINATION share/bob_quantum/r)
