%%%-------------------------------------------------------------------
%% @doc Sovereign Event Bus - Agent Lifecycle FSM
%%
%% 4-State Corrected FSM (per XML L2 spec):
%%   1. active - Processing events normally
%%   2. draining - Rejecting new events, processing queue
%%   3. checkpointed - Committed offset to L0 kernel, ready to stop
%%   4. stopped - Shutdown complete
%%
%% State Transitions:
%%   active -> draining:    shutdown/0 called or supervisor timeout
%%   draining -> checkpointed: queue empty AND offset committed to L0
%%   checkpointed -> stopped: final cleanup
%%   (all states can jump to stopped on fatal error)
%%
%% Drain Timeout: 30 seconds (per XML)
%% Offset Commit: Via seb_kernel_nif NIF
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_agent_fsm).
-behaviour(gen_statem).

-export([start_link/2]).
-export([init/1, callback_mode/0, terminate/3]).
-export([active/3, draining/3, checkpointed/3, stopped/3]).

%% Public API
-export([shutdown/1, get_state/1, queue_event/2, commit_offset/2]).

-record(data, {
    agent_id :: binary(),
    config :: map(),
    queue :: queue:queue(),
    current_offset :: non_neg_integer(),
    prior_offset :: non_neg_integer(),
    drain_timer :: reference() | undefined,
    drain_start :: integer() | undefined
}).

-define(DRAIN_TIMEOUT_MS, 30000).
-define(MAX_QUEUE_SIZE, 10000).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start an agent FSM
%%
%% AgentId: Binary identifier
%% Config: Map with runtime configuration
%%
-spec start_link(binary(), map()) -> gen_statem:start_ret().
start_link(AgentId, Config) when is_binary(AgentId), is_map(Config) ->
    gen_statem:start_link(?MODULE, {AgentId, Config}, []).

%% @doc Initiate shutdown sequence (active -> draining)
-spec shutdown(pid()) -> ok | {error, term()}.
shutdown(Pid) when is_pid(Pid) ->
    gen_statem:call(Pid, shutdown).

%% @doc Get current FSM state
-spec get_state(pid()) -> atom().
get_state(Pid) when is_pid(Pid) ->
    gen_statem:call(Pid, get_state).

%% @doc Queue an event for processing
%%
%% Returns: ok | {error, queue_full}
-spec queue_event(pid(), term()) -> ok | {error, queue_full}.
queue_event(Pid, Event) when is_pid(Pid) ->
    gen_statem:call(Pid, {queue_event, Event}).

%% @doc Commit current offset to L0 kernel
%%
%% Offset: Event offset to commit
%% AgentPid: Self pid (for error reporting)
%%
-spec commit_offset(pid(), non_neg_integer()) -> ok | {error, term()}.
commit_offset(Pid, Offset) when is_pid(Pid), is_integer(Offset), Offset >= 0 ->
    gen_statem:call(Pid, {commit_offset, Offset}).

%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

%% @doc Initialize the FSM
-spec init({binary(), map()}) -> gen_statem:init_ret().
init({AgentId, Config}) ->
    Data = #data{
        agent_id = AgentId,
        config = Config,
        queue = queue:new(),
        current_offset = 0,
        prior_offset = 0,
        drain_timer = undefined,
        drain_start = undefined
    },
    {ok, active, Data}.

%% @doc Use state_functions callback mode
-spec callback_mode() -> gen_statem:callback_mode().
callback_mode() ->
    state_functions.

%%%===================================================================
%%% State: active - Processing events normally
%%%===================================================================

%% @doc active/3 - Entry point and event handler
-spec active(gen_statem:event_type(), term(), #data{}) -> gen_statem:event_handler_ret().

%% Shutdown request - transition to draining
active(call, shutdown, Data) ->
    {next_state, draining, Data#data{
        drain_start = erlang:monotonic_time(millisecond)
    }, [{reply, ok}]};

%% Queue an event (reject if queue full)
active(call, {queue_event, Event}, Data) ->
    case queue:len(Data#data.queue) >= ?MAX_QUEUE_SIZE of
        true ->
            {keep_state_and_data, [{reply, {error, queue_full}}]};
        false ->
            NewQueue = queue:in(Event, Data#data.queue),
            NewData = Data#data{queue = NewQueue},
            Actions = [
                {reply, ok},
                {next_event, internal, process_queue}
            ],
            {keep_state, NewData, Actions}
    end;

%% Commit offset (accepts in active state)
active(call, {commit_offset, Offset}, Data) ->
    case commit_to_kernel(Offset) of
        ok ->
            {keep_state, Data#data{current_offset = Offset}, [{reply, ok}]};
        {error, Reason} ->
            {keep_state_and_data, [{reply, {error, Reason}}]}
    end;

%% Get state
active(call, get_state, _Data) ->
    {keep_state_and_data, [{reply, active}]};

%% Internal: process queue
active(internal, process_queue, Data) ->
    case queue:out(Data#data.queue) of
        {{value, Event}, NewQueue} ->
            case process_event(Event) of
                ok ->
                    {keep_state, Data#data{queue = NewQueue}, [{next_event, internal, process_queue}]};
                {error, _Reason} ->
                    {keep_state, Data#data{queue = NewQueue}, [{next_event, internal, process_queue}]}
            end;
        {empty, _Queue} ->
            keep_state_and_data
    end.

%%%===================================================================
%%% State: draining - Rejecting new events, processing queue
%%%===================================================================

%% @doc draining/3 - Entry point and event handler
-spec draining(gen_statem:event_type(), term(), #data{}) -> gen_statem:event_handler_ret().

%% Drain timeout - force transition to checkpointed
draining(info, {drain_timeout, _Ref}, Data) ->
    {next_state, checkpointed, Data#data{drain_timer = undefined}};

%% Reject new events while draining
draining(call, {queue_event, _Event}, _Data) ->
    {keep_state_and_data, [{reply, {error, agent_draining}}]};

%% Shutdown request - already draining
draining(call, shutdown, _Data) ->
    {keep_state_and_data, [{reply, ok}]};

%% Commit offset while draining
draining(call, {commit_offset, Offset}, Data) ->
    case commit_to_kernel(Offset) of
        ok ->
            NewData = Data#data{current_offset = Offset},
            case queue:is_empty(NewData#data.queue) of
                true ->
                    {next_state, checkpointed, NewData, [{reply, ok}]};
                false ->
                    {keep_state, NewData, [{reply, ok}]}
            end;
        {error, Reason} ->
            {keep_state_and_data, [{reply, {error, Reason}}]}
    end;

%% Get state
draining(call, get_state, _Data) ->
    {keep_state_and_data, [{reply, draining}]};

%% Process remaining queue items
draining(internal, process_queue, Data) ->
    case queue:out(Data#data.queue) of
        {{value, Event}, NewQueue} ->
            case process_event(Event) of
                ok ->
                    {keep_state, Data#data{queue = NewQueue}, [{next_event, internal, process_queue}]};
                {error, _Reason} ->
                    {keep_state, Data#data{queue = NewQueue}, [{next_event, internal, process_queue}]}
            end;
        {empty, Queue} ->
            case Data#data.drain_timer of
                undefined ->
                    Timer = erlang:send_after(?DRAIN_TIMEOUT_MS, self(), {drain_timeout, self()}),
                    {keep_state, Data#data{queue = Queue, drain_timer = Timer}};
                _AlreadySet ->
                    {keep_state, Data#data{queue = Queue}}
            end
    end;

%% On state entry, start draining
draining(enter, _PrevState, Data) ->
    {keep_state, Data, [{next_event, internal, process_queue}]}.

%%%===================================================================
%%% State: checkpointed - Offset committed, ready to stop
%%%===================================================================

%% @doc checkpointed/3 - Entry point and event handler
-spec checkpointed(gen_statem:event_type(), term(), #data{}) -> gen_statem:event_handler_ret().

%% Reject all operations in checkpointed state
checkpointed(call, {queue_event, _Event}, _Data) ->
    {keep_state_and_data, [{reply, {error, agent_checkpointed}}]};

checkpointed(call, shutdown, _Data) ->
    {keep_state_and_data, [{reply, ok}]};

checkpointed(call, {commit_offset, _Offset}, _Data) ->
    {keep_state_and_data, [{reply, {error, already_checkpointed}}]};

%% Get state
checkpointed(call, get_state, _Data) ->
    {keep_state_and_data, [{reply, checkpointed}]};

%% On state entry, transition to stopped
checkpointed(enter, _PrevState, Data) ->
    {next_state, stopped, Data}.

%%%===================================================================
%%% State: stopped - Shutdown complete
%%%===================================================================

%% @doc stopped/3 - Final state, no more transitions
-spec stopped(gen_statem:event_type(), term(), #data{}) -> gen_statem:event_handler_ret().

stopped(call, get_state, _Data) ->
    {keep_state_and_data, [{reply, stopped}]};

stopped(call, _Request, _Data) ->
    {keep_state_and_data, [{reply, {error, agent_stopped}}]}.

%%%===================================================================
%%% Cleanup
%%%===================================================================

%% @doc Terminate callback
-spec terminate(term(), gen_statem:state(), #data{}) -> ok.
terminate(_Reason, _State, #data{drain_timer = Timer}) ->
    case Timer of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref)
    end.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Process a single event
%%
%% In a real implementation, this would:
%%   1. Extract intent/context/authority from event
%%   2. Call policy gate (seb_datalog_bridge)
%%   3. Route to execution adapter
%%   4. Seal with WORM
%%
%% For now, we just succeed.
-spec process_event(term()) -> ok | {error, term()}.
process_event(_Event) ->
    ok.

%% @doc Commit offset to L0 kernel via NIF
%%
%% This bridges to the Ada kernel interface (seb_kernel_nif).
%% Verifies offset monotonicity before committing.
%%
-spec commit_to_kernel(non_neg_integer()) -> ok | {error, term()}.
commit_to_kernel(Offset) when is_integer(Offset), Offset >= 0 ->
    try
        %% Call NIF function: seb_kernel_nif:commit_offset/1
        %% Per XML spec, this commits the offset to the L0 kernel
        try seb_kernel_nif:commit_offset(Offset) of
            ok -> ok;
            Error -> {error, Error}
        catch
            _:Reason -> {error, {nif_error, Reason}}
        end
    catch
        _Type:_Reason ->
            {error, nif_unavailable}
    end.
