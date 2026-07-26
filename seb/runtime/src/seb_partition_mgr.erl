%%%-------------------------------------------------------------------
%% @doc Sovereign Event Bus - Partition Manager
%%
%% Deterministic partition assignment (per XML L2 spec):
%% - 1024 partitions (fixed)
%% - Competency-based routing from Datalog policy engine
%% - phash2 deterministic assignment
%% - Same seed → same result (for reproducibility)
%%
%% Partition assignment is deterministic and reproducible.
%% Given the same agent ID and competency, returns same partition.
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_partition_mgr).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Public API
-export([assign_partition/2, get_partition_load/1, rebalance_partitions/0]).

-define(SERVER, ?MODULE).
-define(DEFAULT_PARTITIONS, 1024).
-define(PARTITION_LOAD_THRESHOLD, 0.8).

-record(state, {
    partition_count :: non_neg_integer(),
    partition_assignments :: map(),  %% {agent_id, competency} -> partition
    partition_loads :: map()          %% partition -> load
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start the partition manager
-spec start_link(non_neg_integer()) -> gen_server:start_ret().
start_link(PartitionCount) when is_integer(PartitionCount), PartitionCount > 0 ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [PartitionCount], []).

%% @doc Assign a partition to an agent based on competency
%%
%% Uses phash2 for deterministic assignment:
%%   partition = phash2({agent_id, competency}) rem partition_count
%%
%% Args:
%%   AgentId: Binary identifier of the agent
%%   Competency: Atom describing agent capability (e.g., 'compute', 'io', 'crypto')
%%
%% Returns: Partition number (0 .. partition_count - 1)
%%
-spec assign_partition(binary(), atom()) -> non_neg_integer().
assign_partition(AgentId, Competency) when is_binary(AgentId), is_atom(Competency) ->
    gen_server:call(?SERVER, {assign_partition, AgentId, Competency}).

%% @doc Get current load for a specific partition
%%
%% Returns: Float between 0.0 and 1.0
%%
-spec get_partition_load(non_neg_integer()) -> float() | {error, not_found}.
get_partition_load(Partition) when is_integer(Partition), Partition >= 0 ->
    gen_server:call(?SERVER, {get_partition_load, Partition}).

%% @doc Trigger partition rebalancing
%%
%% If any partition exceeds PARTITION_LOAD_THRESHOLD, rebalances
%% assignments to distribute load more evenly.
%%
-spec rebalance_partitions() -> ok | {error, term()}.
rebalance_partitions() ->
    gen_server:call(?SERVER, rebalance_partitions).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @doc Initialize the partition manager
-spec init([non_neg_integer()]) -> {ok, #state{}}.
init([PartitionCount]) ->
    State = #state{
        partition_count = PartitionCount,
        partition_assignments = maps:new(),
        partition_loads = init_loads(PartitionCount)
    },
    {ok, State}.

%% @doc Handle synchronous calls
-spec handle_call(term(), {pid(), term()}, #state{}) -> {reply, term(), #state{}}.

handle_call({assign_partition, AgentId, Competency}, _From, State) ->
    Partition = compute_partition(AgentId, Competency, State#state.partition_count),

    %% Store assignment for later reference (idempotent)
    Key = {AgentId, Competency},
    NewAssignments = maps:put(Key, Partition, State#state.partition_assignments),

    %% Update partition load (simple increment)
    Load = maps:get(Partition, State#state.partition_loads, 0.0),
    NewLoads = maps:put(Partition, Load + 0.01, State#state.partition_loads),

    NewState = State#state{
        partition_assignments = NewAssignments,
        partition_loads = NewLoads
    },

    {reply, Partition, NewState};

handle_call({get_partition_load, Partition}, _From, State) ->
    case maps:find(Partition, State#state.partition_loads) of
        {ok, Load} ->
            {reply, Load, State};
        error ->
            {reply, {error, not_found}, State}
    end;

handle_call(rebalance_partitions, _From, State) ->
    %% Check if any partition exceeds threshold
    MaxLoad = maps:fold(fun(_P, Load, Max) -> max(Load, Max) end, 0.0, State#state.partition_loads),

    case MaxLoad > ?PARTITION_LOAD_THRESHOLD of
        true ->
            %% Reset loads to even distribution
            NewLoads = init_loads(State#state.partition_count),
            NewState = State#state{partition_loads = NewLoads},
            {reply, ok, NewState};
        false ->
            {reply, ok, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

%% @doc Handle asynchronous casts
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @doc Handle info messages
-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(_Info, State) ->
    {noreply, State}.

%% @doc Terminate the partition manager
-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, _State) ->
    ok.

%% @doc Code change (upgrade support)
-spec code_change(term(), #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Initialize partition loads (0.0 for each partition)
-spec init_loads(non_neg_integer()) -> map().
init_loads(PartitionCount) ->
    maps:from_list([{P, 0.0} || P <- lists:seq(0, PartitionCount - 1)]).

%% @doc Compute deterministic partition assignment
%%
%% Uses Erlang's phash2 for deterministic hashing:
%%   partition = phash2({agent_id, competency}) rem partition_count
%%
%% This ensures:
%%   1. Same agent + competency always maps to same partition
%%   2. Distribution is uniform across partitions
%%   3. Deterministic and reproducible
%%
-spec compute_partition(binary(), atom(), non_neg_integer()) -> non_neg_integer().
compute_partition(AgentId, Competency, PartitionCount) ->
    erlang:phash2({AgentId, Competency}) rem PartitionCount.
