# Smalltalk VM Plugin for BOB Quantum Engine
if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before smalltalk subdirectory")
endif()
add_custom_target(smalltalk_bindings ALL DEPENDS bob_quantum COMMENT "Smalltalk bindings verified")
install(FILES BobQuantum.st DESTINATION share/bob_quantum/smalltalk)
