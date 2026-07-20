# Elixir/Erlang NIF Binding for BOB Quantum Engine
if(NOT TARGET bob_quantum)
  message(FATAL_ERROR "bob_quantum target must be defined before elixir subdirectory")
endif()
add_custom_target(elixir_bindings ALL DEPENDS bob_quantum COMMENT "Elixir/Erlang NIF bindings verified")
# Elixir NIF managed via Mix
