%%%-------------------------------------------------------------------
%% @doc Sovereign Event Bus - Agent Lifecycle Supervisor
%%
%% Supervises dynamic agents spawned via spawn_agent/2.
%% Each agent runs seb_agent_fsm (4-state corrected FSM).
%%
%% Agent States (per XML spec):
%%   1. active - Processing events normally
%%   2. draining - Rejecting new events, processing queue
%%   3. checkpointed - Committed offset to L0 kernel
%%   4. stopped - Shutdown complete
%%
%% Drain Timeout: 30 seconds (per XML)
%% Offset Commit: Via L0 kernel NIF
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_agent_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([spawn_agent/2, terminate_agent/1]).
-export([init/1]).
-export([get_agent_pids/0]).

-define(SERVER, ?MODULE).
-define(AGENT_RESTART_INTENSITY, 10).
-define(AGENT_RESTART_PERIOD, 60).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start the agent supervisor
-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Spawn a new agent FSM
%%
%% AgentId: Unique identifier for this agent
%% Config: Configuration map with options
%%
%% Returns: {ok, Pid} | {error, Reason}
-spec spawn_agent(binary(), map()) -> {ok, pid()} | {error, term()}.
spawn_agent(AgentId, Config) when is_binary(AgentId), is_map(Config) ->
    ChildSpec = #{
        id => AgentId,
        start => {seb_agent_fsm, start_link, [AgentId, Config]},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [seb_agent_fsm]
    },
    supervisor:start_child(?SERVER, ChildSpec).

%% @doc Terminate a specific agent
%%
%% Initiates drain sequence:
%%   1. Agent transitions to draining state
%%   2. Processes remaining queue items (< 30s)
%%   3. Commits offset to L0 kernel
%%   4. Transitions to stopped state
%%
-spec terminate_agent(binary()) -> ok | {error, not_found}.
terminate_agent(AgentId) when is_binary(AgentId) ->
    case supervisor:terminate_child(?SERVER, AgentId) of
        ok ->
            supervisor:delete_child(?SERVER, AgentId);
        {error, not_found} ->
            {error, not_found}
    end.

%% @doc Get all active agent PIDs
-spec get_agent_pids() -> [pid()].
get_agent_pids() ->
    case supervisor:which_children(?SERVER) of
        Children ->
            [Pid || {_Id, Pid, worker, _Modules} <- Children, is_pid(Pid)];
        _ ->
            []
    end.

%%%===================================================================
%%% Supervisor Callbacks
%%%===================================================================

%% @doc Initialize the agent supervisor
%%
%% Uses one_for_one strategy: if an agent fails, only that agent restarts.
%% Max 10 restarts per 60 seconds per agent.
%%
-spec init([]) -> {ok, {supervisor:sup_flags(), []}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => ?AGENT_RESTART_INTENSITY,
        period => ?AGENT_RESTART_PERIOD
    },
    {ok, {SupFlags, []}}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

% No internal functions at this time
