defmodule BobQuantum do
  @moduledoc """
  BOB Quantum Civilization Engine - Elixir OTP Bridge
  
  High-performance quantum simulation engine with Rustler NIF bindings
  for cryptographic RNG, lattice evolution, and quantum state management.
  """

  use Rustler, otp_app: :bob_quantum, crate: "bob_quantum_nif"

  @type rng_ref :: reference()
  @type lattice_ref :: reference()
  @type state_ref :: reference()
  @type energy :: float()
  @type entropy :: float()
  @type amplitude :: {float(), float()}
  @type amplitudes :: [amplitude()]

  # =========================================================================
  # NIF Declarations - RNG Subsystem
  # =========================================================================

  @doc """
  Initialize a new quantum RNG instance with entropy seed.
  
  Returns: {:ok, rng_ref} | {:error, :initialization_failed}
  """
  @spec rng_init(binary()) :: {:ok, rng_ref()} | {:error, atom()}
  def rng_init(_seed), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Generate uniform random float in [0, 1).
  
  Returns: {:ok, float()} | {:error, :rng_exhausted}
  """
  @spec rng_uniform(rng_ref()) :: {:ok, float()} | {:error, atom()}
  def rng_uniform(_ref), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Generate normally distributed random float (Box-Muller transform).
  
  Returns: {:ok, float()} | {:error, :rng_exhausted}
  """
  @spec rng_normal(rng_ref(), float(), float()) :: {:ok, float()} | {:error, atom()}
  def rng_normal(_ref, _mean, _stddev), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Generate cryptographically secure random integer in range [min, max].
  
  Returns: {:ok, integer()} | {:error, :invalid_range} | {:error, :rng_exhausted}
  """
  @spec rng_integer(rng_ref(), integer(), integer()) :: {:ok, integer()} | {:error, atom()}
  def rng_integer(_ref, _min, _max), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Reseed RNG with additional entropy.
  
  Returns: :ok | {:error, :reseed_failed}
  """
  @spec rng_reseed(rng_ref(), binary()) :: :ok | {:error, atom()}
  def rng_reseed(_ref, _entropy), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get RNG internal state for checkpointing.
  
  Returns: {:ok, binary()} | {:error, :state_capture_failed}
  """
  @spec rng_get_state(rng_ref()) :: {:ok, binary()} | {:error, atom()}
  def rng_get_state(_ref), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Restore RNG from checkpointed state.
  
  Returns: {:ok, rng_ref()} | {:error, :invalid_state}
  """
  @spec rng_set_state(binary()) :: {:ok, rng_ref()} | {:error, atom()}
  def rng_set_state(_state), do: :erlang.nif_error(:nif_not_loaded)

  # =========================================================================
  # NIF Declarations - Lattice Subsystem
  # =========================================================================

  @doc """
  Initialize quantum lattice with dimensions and boundary conditions.
  
  Args:
    - dimensions: {x, y, z} tuple
    - boundary: :periodic | :open | :reflective
    - coupling: float() - interaction strength
    - temperature: float() - initial temperature
  
  Returns: {:ok, lattice_ref} | {:error, :invalid_parameters}
  """
  @spec lattice_init({integer(), integer(), integer()}, atom(), float(), float()) ::
          {:ok, lattice_ref()} | {:error, atom()}
  def lattice_init(_dims, _boundary, _coupling, _temp), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Evolve lattice by one Monte Carlo step using Metropolis-Hastings.
  
  Returns: {:ok, {energy(), entropy()}} | {:error, :evolution_failed}
  """
  @spec lattice_evolve(lattice_ref(), integer()) :: {:ok, {energy(), entropy()}} | {:error, atom()}
  def lattice_evolve(_ref, _steps), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Compute total system energy (Hamiltonian expectation value).
  
  Returns: {:ok, energy()} | {:error, :computation_failed}
  """
  @spec lattice_energy(lattice_ref()) :: {:ok, energy()} | {:error, atom()}
  def lattice_energy(_ref), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Compute von Neumann entropy of lattice density matrix.
  
  Returns: {:ok, entropy()} | {:error, :computation_failed}
  """
  @spec lattice_entropy(lattice_ref()) :: {:ok, entropy()} | {:error, atom()}
  def lattice_entropy(_ref), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get lattice correlation function at distance r.
  
  Returns: {:ok, float()} | {:error, :invalid_distance}
  """
  @spec lattice_correlation(lattice_ref(), integer()) :: {:ok, float()} | {:error, atom()}
  def lattice_correlation(_ref, _distance), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Measure local magnetization at site (x, y, z).
  
  Returns: {:ok, float()} | {:error, :invalid_site}
  """
  @spec lattice_magnetization(lattice_ref(), {integer(), integer(), integer()}) ::
          {:ok, float()} | {:error, atom()}
  def lattice_magnetization(_ref, _site), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Apply external field to lattice region.
  
  Returns: :ok | {:error, :invalid_region}
  """
  @spec lattice_apply_field(lattice_ref(), {integer(), integer(), integer()}, {integer(), integer(), integer()}, float()) ::
          :ok | {:error, atom()}
  def lattice_apply_field(_ref, _min, _max, _strength), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get lattice configuration snapshot for visualization.
  
  Returns: {:ok, binary()} | {:error, :snapshot_failed}
  """
  @spec lattice_snapshot(lattice_ref()) :: {:ok, binary()} | {:error, atom()}
  def lattice_snapshot(_ref), do: :erlang.nif_error(:nif_not_loaded)

  # =========================================================================
  # NIF Declarations - Quantum State Subsystem
  # =========================================================================

  @doc """
  Initialize quantum state vector with n qubits.
  
  Args:
    - n_qubits: integer() - number of qubits (max 32)
    - initial_state: :zero | :plus | :random | binary() (amplitude data)
  
  Returns: {:ok, state_ref} | {:error, :invalid_qubit_count} | {:error, :invalid_initial_state}
  """
  @spec state_init(integer(), atom() | binary()) :: {:ok, state_ref()} | {:error, atom()}
  def state_init(_n_qubits, _initial), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Apply single-qubit gate to quantum state.
  
  Gates: :h, :x, :y, :z, :s, :t, :rx, :ry, :rz, :u3
  For parameterized gates, params = [theta] or [theta, phi, lambda]
  
  Returns: :ok | {:error, :invalid_gate} | {:error, :invalid_qubit} | {:error, :invalid_params}
  """
  @spec state_apply_gate(state_ref(), atom(), integer(), [float()]) :: :ok | {:error, atom()}
  def state_apply_gate(_ref, _gate, _qubit, _params), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Apply two-qubit controlled gate.
  
  Gates: :cx, :cy, :cz, :crx, :cry, :crz, :swap, :iswap
  
  Returns: :ok | {:error, :invalid_gate} | {:error, :invalid_qubit}
  """
  @spec state_apply_controlled(state_ref(), atom(), integer(), integer(), [float()]) :: :ok | {:error, atom()}
  def state_apply_controlled(_ref, _gate, _control, _target, _params), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Measure qubit in computational basis.
  
  Returns: {:ok, 0 | 1, probability()} | {:error, :invalid_qubit} | {:error, :measurement_failed}
  """
  @spec state_measure(state_ref(), integer()) :: {:ok, 0 | 1, float()} | {:error, atom()}
  def state_measure(_ref, _qubit), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Measure multiple qubits simultaneously.
  
  Returns: {:ok, [0 | 1], probability()} | {:error, :invalid_qubits}
  """
  @spec state_measure_multi(state_ref(), [integer()]) :: {:ok, [0 | 1], float()} | {:error, atom()}
  def state_measure_multi(_ref, _qubits), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get full amplitude vector (2^n complex numbers as {re, im} tuples).
  
  Returns: {:ok, amplitudes()} | {:error, :state_too_large}
  """
  @spec state_amplitudes(state_ref()) :: {:ok, amplitudes()} | {:error, atom()}
  def state_amplitudes(_ref), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get reduced density matrix for subsystem.
  
  Returns: {:ok, amplitudes()} | {:error, :invalid_subsystem}
  """
  @spec state_reduced_density(state_ref(), [integer()]) :: {:ok, amplitudes()} | {:error, atom()}
  def state_reduced_density(_ref, _qubits), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Normalize quantum state vector (L2 norm = 1).
  
  Returns: :ok | {:error, :zero_norm}
  """
  @spec state_normalize(state_ref()) :: :ok | {:error, atom()}
  def state_normalize(_ref), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Compute expectation value of Pauli operator string.
  
  Operator: string of 'I', 'X', 'Y', 'Z' (e.g., "XYZI")
  
  Returns: {:ok, float()} | {:error, :invalid_operator}
  """
  @spec state_expectation(state_ref(), String.t()) :: {:ok, float()} | {:error, atom()}
  def state_expectation(_ref, _operator), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Compute fidelity with target state.
  
  Returns: {:ok, float()} | {:error, :dimension_mismatch}
  """
  @spec state_fidelity(state_ref(), amplitudes()) :: {:ok, float()} | {:error, atom()}
  def state_fidelity(_ref, _target), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get entanglement entropy for bipartition.
  
  Returns: {:ok, entropy()} | {:error, :invalid_partition}
  """
  @spec state_entanglement_entropy(state_ref(), [integer()]) :: {:ok, entropy()} | {:error, atom()}
  def state_entanglement_entropy(_ref, _partition), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Apply quantum channel (Kraus operators).
  
  Returns: :ok | {:error, :invalid_kraus}
  """
  @spec state_apply_channel(state_ref(), [amplitudes()]) :: :ok | {:error, atom()}
  def state_apply_channel(_ref, _kraus), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Clone quantum state (deep copy).
  
  Returns: {:ok, state_ref()} | {:error, :clone_failed}
  """
  @spec state_clone(state_ref()) :: {:ok, state_ref()} | {:error, atom()}
  def state_clone(_ref), do: :erlang.nif_error(:nif_not_loaded)

  # =========================================================================
  # High-Level API Delegates
  # =========================================================================

  defdelegate rng_init(seed), to: BobQuantum.RNG
  defdelegate rng_uniform(ref), to: BobQuantum.RNG
  defdelegate rng_normal(ref, mean, stddev), to: BobQuantum.RNG
  defdelegate rng_integer(ref, min, max), to: BobQuantum.RNG
  defdelegate rng_reseed(ref, entropy), to: BobQuantum.RNG
  defdelegate rng_get_state(ref), to: BobQuantum.RNG
  defdelegate rng_set_state(state), to: BobQuantum.RNG

  defdelegate lattice_init(dims, boundary, coupling, temp), to: BobQuantum.Lattice
  defdelegate lattice_evolve(ref, steps), to: BobQuantum.Lattice
  defdelegate lattice_energy(ref), to: BobQuantum.Lattice
  defdelegate lattice_entropy(ref), to: BobQuantum.Lattice
  defdelegate lattice_correlation(ref, distance), to: BobQuantum.Lattice
  defdelegate lattice_magnetization(ref, site), to: BobQuantum.Lattice
  defdelegate lattice_apply_field(ref, min, max, strength), to: BobQuantum.Lattice
  defdelegate lattice_snapshot(ref), to: BobQuantum.Lattice

  defdelegate state_init(n_qubits, initial), to: BobQuantum.State
  defdelegate state_apply_gate(ref, gate, qubit, params), to: BobQuantum.State
  defdelegate state_apply_controlled(ref, gate, control, target, params), to: BobQuantum.State
  defdelegate state_measure(ref, qubit), to: BobQuantum.State
  defdelegate state_measure_multi(ref, qubits), to: BobQuantum.State
  defdelegate state_amplitudes(ref), to: BobQuantum.State
  defdelegate state_reduced_density(ref, qubits), to: BobQuantum.State
  defdelegate state_normalize(ref), to: BobQuantum.State
  defdelegate state_expectation(ref, operator), to: BobQuantum.State
  defdelegate state_fidelity(ref, target), to: BobQuantum.State
  defdelegate state_entanglement_entropy(ref, partition), to: BobQuantum.State
  defdelegate state_apply_channel(ref, kraus), to: BobQuantum.State
  defdelegate state_clone(ref), to: BobQuantum.State

  # =========================================================================
  # Application Lifecycle
  # =========================================================================

  @doc """
  Start all BobQuantum subsystems.
  Typically called during application startup.
  """
  @spec start() :: :ok | {:error, term()}
  def start do
    children = [
      {BobQuantum.RNG, name: :bob_quantum_rng},
      {BobQuantum.Lattice, name: :bob_quantum_lattice},
      {BobQuantum.State, name: :bob_quantum_state}
    ]

    opts = [strategy: :one_for_one, name: BobQuantum.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Stop all BobQuantum subsystems gracefully.
  """
  @spec stop() :: :ok
  def stop do
    Supervisor.stop(BobQuantum.Supervisor)
  end

  @doc """
  Health check for all subsystems.
  
  Returns: %{rng: :ok | :error, lattice: :ok | :error, state: :ok | :error}
  """
  @spec health_check() :: map()
  def health_check do
    %{
      rng: check_rng(),
      lattice: check_lattice(),
      state: check_state()
    }
  end

  defp check_rng do
    case BobQuantum.RNG.uniform() do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp check_lattice do
    case BobQuantum.Lattice.energy() do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp check_state do
    case BobQuantum.State.amplitudes() do
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end
end

# =============================================================================
# Supervisor
# =============================================================================

defmodule BobQuantum.Supervisor do
  use Supervisor

  @impl true
  def init(children) do
    Supervisor.init(children, strategy: :one_for_one)
  end
end

# =============================================================================
# RNG GenServer
# =============================================================================

defmodule BobQuantum.RNG do
  @moduledoc """
  GenServer wrapper for quantum random number generator.
  Manages RNG lifecycle, state persistence, and concurrent access.
  """

  use GenServer

  @type state :: %{
    ref: BobQuantum.rng_ref(),
    algorithm: atom(),
    seed: binary(),
    generation_count: integer(),
    last_reseed: DateTime.t()
  }

  # -------------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------------

  @doc """
  Start RNG GenServer with optional seed.
  
  Options:
    - :seed - binary entropy (default: crypto:strong_rand_bytes(32))
    - :algorithm - :chacha20 | :aes256_ctr | :philox (default: :chacha20)
    - :name - registration name (default: __MODULE__)
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Generate uniform random float in [0, 1).
  """
  @spec uniform() :: {:ok, float()} | {:error, :not_started}
  def uniform do
    call(__MODULE__, :uniform)
  end

  @spec uniform(pid()) :: {:ok, float()} | {:error, :not_started}
  def uniform(pid) do
    call(pid, :uniform)
  end

  @doc """
  Generate normally distributed random float.
  """
  @spec normal(mean :: float(), stddev :: float()) :: {:ok, float()} | {:error, :not_started}
  def normal(mean, stddev) do
    call(__MODULE__, {:normal, mean, stddev})
  end

  @spec normal(pid(), mean :: float(), stddev :: float()) :: {:ok, float()} | {:error, :not_started}
  def normal(pid, mean, stddev) do
    call(pid, {:normal, mean, stddev})
  end

  @doc """
  Generate random integer in range [min, max].
  """
  @spec integer(min :: integer(), max :: integer()) :: {:ok, integer()} | {:error, :not_started | :invalid_range}
  def integer(min, max) do
    call(__MODULE__, {:integer, min, max})
  end

  @spec integer(pid(), min :: integer(), max :: integer()) :: {:ok, integer()} | {:error, :not_started | :invalid_range}
  def integer(pid, min, max) do
    call(pid, {:integer, min, max})
  end

  @doc """
  Reseed RNG with additional entropy.
  """
  @spec reseed(entropy :: binary()) :: :ok | {:error, :not_started | :reseed_failed}
  def reseed(entropy) do
    call(__MODULE__, {:reseed, entropy})
  end

  @spec reseed(pid(), entropy :: binary()) :: :ok | {:error, :not_started | :reseed_failed}
  def reseed(pid, entropy) do
    call(pid, {:reseed, entropy})
  end

  @doc """
  Get current RNG state for checkpointing.
  """
  @spec get_state() :: {:ok, binary()} | {:error, :not_started}
  def get_state do
    call(__MODULE__, :get_state)
  end

  @spec get_state(pid()) :: {:ok, binary()} | {:error, :not_started}
  def get_state(pid) do
    call(pid, :get_state)
  end

  @doc """
  Get server statistics.
  """
  @spec stats() :: {:ok, map()} | {:error, :not_started}
  def stats do
    call(__MODULE__, :stats)
  end

  @spec stats(pid()) :: {:ok, map()} | {:error, :not_started}
  def stats(pid) do
    call(pid, :stats)
  end

  # -------------------------------------------------------------------------
  # Server Callbacks
  # -------------------------------------------------------------------------

  @impl true
  def init(opts) do
    seed = Keyword.get(opts, :seed, :crypto.strong_rand_bytes(32))
    algorithm = Keyword.get(opts, :algorithm, :chacha20)

    case BobQuantum.rng_init(seed) do
      {:ok, ref} ->
        state = %{
          ref: ref,
          algorithm: algorithm,
          seed: seed,
          generation_count: 0,
          last_reseed: DateTime.utc_now()
        }
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:uniform, _from, state) do
    case BobQuantum.rng_uniform(state.ref) do
      {:ok, value} ->
        {:reply, {:ok, value}, update_count(state)}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:normal, mean, stddev}, _from, state) do
    case BobQuantum.rng_normal(state.ref, mean, stddev) do
      {:ok, value} ->
        {:reply, {:ok, value}, update_count(state)}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:integer, min, max}, _from, state) when min <= max do
    case BobQuantum.rng_integer(state.ref, min, max) do
      {:ok, value} ->
        {:reply, {:ok, value}, update_count(state)}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:integer, _min, _max}, _from, state) do
    {:reply, {:error, :invalid_range}, state}
  end

  @impl true
  def handle_call({:reseed, entropy}, _from, state) do
    case BobQuantum.rng_reseed(state.ref, entropy) do
      :ok ->
        {:reply, :ok, %{state | last_reseed: DateTime.utc_now(), generation_count: 0}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    case BobQuantum.rng_get_state(state.ref) do
      {:ok, data} ->
        {:reply, {:ok, data}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, {:ok, format_stats(state)}, state}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cleanup if needed
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  # -------------------------------------------------------------------------
  # Internal Functions
  # -------------------------------------------------------------------------

  defp update_count(state) do
    %{state | generation_count: state.generation_count + 1}
  end

  defp format_stats(state) do
    %{
      algorithm: state.algorithm,
      generation_count: state.generation_count,
      last_reseed: state.last_reseed,
      uptime: DateTime.diff(DateTime.utc_now(), state.last_reseed, :second)
    }
  end
end

# =============================================================================
# Lattice GenServer
# =============================================================================

defmodule BobQuantum.Lattice do
  @moduledoc """
  GenServer wrapper for quantum lattice simulation.
  Manages lattice evolution, thermodynamic quantities, and spatial correlations.
  """

  use GenServer

  @type state :: %{
    ref: BobQuantum.lattice_ref(),
    dimensions: {integer(), integer(), integer()},
    boundary: atom(),
    coupling: float(),
    temperature: float(),
    step_count: integer(),
    last_energy: float(),
    last_entropy: float()
  }

  # -------------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------------

  @doc """
  Start Lattice GenServer.
  
  Options:
    - :dimensions - {x, y, z} tuple (default: {16, 16, 16})
    - :boundary - :periodic | :open | :reflective (default: :periodic)
    - :coupling - interaction strength (default: 1.0)
    - :temperature - initial temperature (default: 2.0)
    - :name - registration name (default: __MODULE__)
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Evolve lattice by n Monte Carlo steps.
  """
  @spec evolve(steps :: integer()) :: {:ok, {energy(), entropy()}} | {:error, :not_started}
  def evolve(steps) do
    call(__MODULE__, {:evolve, steps})
  end

  @spec evolve(pid(), steps :: integer()) :: {:ok, {energy(), entropy()}} | {:error, :not_started}
  def evolve(pid, steps) do
    call(pid, {:evolve, steps})
  end

  @doc """
  Get current system energy.
  """
  @spec energy() :: {:ok, energy()} | {:error, :not_started}
  def energy do
    call(__MODULE__, :energy)
  end

  @spec energy(pid()) :: {:ok, energy()} | {:error, :not_started}
  def energy(pid) do
    call(pid, :energy)
  end

  @doc """
  Get current system entropy.
  """
  @spec entropy() :: {:ok, entropy()} | {:error, :not_started}
  def entropy do
    call(__MODULE__, :entropy)
  end

  @spec entropy(pid()) :: {:ok, entropy()} | {:error, :not_started}
  def entropy(pid) do
    call(pid, :entropy)
  end

  @doc """
  Get correlation function at distance r.
  """
  @spec correlation(distance :: integer()) :: {:ok, float()} | {:error, :not_started | :invalid_distance}
  def correlation(distance) do
    call(__MODULE__, {:correlation, distance})
  end

  @spec correlation(pid(), distance :: integer()) :: {:ok, float()} | {:error, :not_started | :invalid_distance}
  def correlation(pid, distance) do
    call(pid, {:correlation, distance})
  end

  @doc """
  Get magnetization at site.
  """
  @spec magnetization(site :: {integer(), integer(), integer()}) :: {:ok, float()} | {:error, :not_started | :invalid_site}
  def magnetization(site) do
    call(__MODULE__, {:magnetization, site})
  end

  @spec magnetization(pid(), site :: {integer(), integer(), integer()}) :: {:ok, float()} | {:error, :not_started | :invalid_site}
  def magnetization(pid, site) do
    call(pid, {:magnetization, site})
  end

  @doc """
  Apply external field to region.
  """
  @spec apply_field(min :: {integer(), integer(), integer()}, max :: {integer(), integer(), integer()}, strength :: float()) :: :ok | {:error, :not_started | :invalid_region}
  def apply_field(min, max, strength) do
    call(__MODULE__, {:apply_field, min, max, strength})
  end

  @spec apply_field(pid(), min :: {integer(), integer(), integer()}, max :: {integer(), integer(), integer()}, strength :: float()) :: :ok | {:error, :not_started | :invalid_region}
  def apply_field(pid, min, max, strength) do
    call(pid, {:apply_field, min, max, strength})
  end

  @doc """
  Get lattice snapshot for visualization.
  """
  @spec snapshot() :: {:ok, binary()} | {:error, :not_started}
  def snapshot do
    call(__MODULE__, :snapshot)
  end

  @spec snapshot(pid()) :: {:ok, binary()} | {:error, :not_started}
  def snapshot(pid) do
    call(pid, :snapshot)
  end

  @doc """
  Get server statistics.
  """
  @spec stats() :: {:ok, map()} | {:error, :not_started}
  def stats do
    call(__MODULE__, :stats)
  end

  @spec stats(pid()) :: {:ok, map()} | {:error, :not_started}
  def stats(pid) do
    call(pid, :stats)
  end

  # -------------------------------------------------------------------------
  # Server Callbacks
  # -------------------------------------------------------------------------

  @impl true
  def init(opts) do
    dimensions = Keyword.get(opts, :dimensions, {16, 16, 16})
    boundary = Keyword.get(opts, :boundary, :periodic)
    coupling = Keyword.get(opts, :coupling, 1.0)
    temperature = Keyword.get(opts, :temperature, 2.0)

    case BobQuantum.lattice_init(dimensions, boundary, coupling, temperature) do
      {:ok, ref} ->
        state = %{
          ref: ref,
          dimensions: dimensions,
          boundary: boundary,
          coupling: coupling,
          temperature: temperature,
          step_count: 0,
          last_energy: 0.0,
          last_entropy: 0.0
        }
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:evolve, steps}, _from, state) when steps > 0 do
    case BobQuantum.lattice_evolve(state.ref, steps) do
      {:ok, {energy, entropy}} ->
        new_state = %{
          state
          | step_count: state.step_count + steps,
            last_energy: energy,
            last_entropy: entropy
        }
        {:reply, {:ok, {energy, entropy}}, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:evolve, _steps}, _from, state) do
    {:reply, {:error, :invalid_steps}, state}
  end

  @impl true
  def handle_call(:energy, _from, state) do
    case BobQuantum.lattice_energy(state.ref) do
      {:ok, energy} ->
        {:reply, {:ok, energy}, %{state | last_energy: energy}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:entropy, _from, state) do
    case BobQuantum.lattice_entropy(state.ref) do
      {:ok, entropy} ->
        {:reply, {:ok, entropy}, %{state | last_entropy: entropy}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:correlation, distance}, _from, state) do
    case BobQuantum.lattice_correlation(state.ref, distance) do
      {:ok, value} ->
        {:reply, {:ok, value}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:magnetization, site}, _from, state) do
    case BobQuantum.lattice_magnetization(state.ref, site) do
      {:ok, value} ->
        {:reply, {:ok, value}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:apply_field, min, max, strength}, _from, state) do
    case BobQuantum.lattice_apply_field(state.ref, min, max, strength) do
      :ok ->
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    case BobQuantum.lattice_snapshot(state.ref) do
      {:ok, data} ->
        {:reply, {:ok, data}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, {:ok, format