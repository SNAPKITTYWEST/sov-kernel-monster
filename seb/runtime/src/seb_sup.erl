%%%-------------------------------------------------------------------
%% @doc Sovereign Event Bus (SEB) Supervision Tree Root
%%
%% Per SEB_SOVEREIGN_EVENT_BUS_MASTER_SPECIFICATION.xml L2 layer:
%% - Root supervisor for entire SEB runtime
%% - Spawns kernel_nif worker (Ada kernel interface)
%% - Spawns policy_engine (seb_datalog) worker
%% - Spawns partition_manager worker
%% - Spawns agent_sup supervisor (agent lifecycle)
%%
%% L0 Invariants Enforced:
%%   1. Plasma Gate: Ed25519 signature valid (kernel_nif)
%%   2. Hash Chain: Prev_Hash == current tip hash (kernel_nif)
%%   3. Offset Monotonic: Event offset > prior offset (kernel_nif)
%%   4. Payload Hash: blake3(header || payload) matches footer (kernel_nif)
%%   5. Segment Chain: Prev_Seg_Hash links to prior segment (kernel_nif)
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%% Internal exports for testing
-export([get_child_pid/1]).

-define(SERVER, ?MODULE).
-define(CHILD_TIMEOUT, 30000).
-define(STARTUP_TIMEOUT, 60000).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start the supervision tree
-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Get child process PID by name
-spec get_child_pid(atom()) -> pid() | {error, not_found}.
get_child_pid(ChildName) ->
    case supervisor:get_children(?SERVER) of
        Children ->
            case lists:keyfind(ChildName, 1, Children) of
                {ChildName, Pid, _Type, _Modules} ->
                    Pid;
                false ->
                    {error, not_found}
            end;
        Error ->
            {error, Error}
    end.

%%%===================================================================
%%% Supervisor Callbacks
%%%===================================================================

%% @doc Initialize the supervision tree
%%
%% Starts the following workers/supervisors:
%%   1. seb_kernel_nif - Ada kernel interface (worker)
%%   2. seb_datalog_bridge - Policy engine (worker)
%%   3. seb_partition_mgr - Partition assignment (worker)
%%   4. seb_agent_sup - Agent lifecycle supervisor (supervisor)
%%
%% All children are permanent with escalation strategy one_for_all.
%% This ensures if any critical component fails, entire SEB restarts.
%%
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 3,
        period => 30
    },

    ChildSpecs = [
        %% L0 Kernel NIF - Ada binding (worker)
        #{
            id => seb_kernel_nif,
            start => {seb_kernel_nif, start_link, []},
            restart => permanent,
            shutdown => ?CHILD_TIMEOUT,
            type => worker,
            modules => [seb_kernel_nif]
        },

        %% Policy Engine - Datalog + Souffle (worker)
        #{
            id => seb_datalog_bridge,
            start => {seb_datalog_bridge, start_link, []},
            restart => permanent,
            shutdown => ?CHILD_TIMEOUT,
            type => worker,
            modules => [seb_datalog_bridge]
        },

        %% Partition Manager - Deterministic routing (worker)
        #{
            id => seb_partition_mgr,
            start => {seb_partition_mgr, start_link, [1024]},
            restart => permanent,
            shutdown => ?CHILD_TIMEOUT,
            type => worker,
            modules => [seb_partition_mgr]
        },

        %% Agent Lifecycle Supervisor (supervisor)
        #{
            id => seb_agent_sup,
            start => {seb_agent_sup, start_link, []},
            restart => permanent,
            shutdown => ?STARTUP_TIMEOUT,
            type => supervisor,
            modules => [seb_agent_sup]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% Trace startup for debugging
trace_startup(Stage) ->
    io:format("SEB[~s] ~s~n", [Stage, calendar:local_time()]).
