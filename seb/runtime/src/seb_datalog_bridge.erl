%%%-------------------------------------------------------------------
%% @doc Sovereign Event Bus - Datalog Policy Engine Bridge
%%
%% Bridge to Souffle policy engine (per XML L2 spec):
%% - Port driver for compiled policy
%% - async_authorize callback for policy decisions
%% - Stratified Datalog evaluation
%%
%% Policy engine determines:
%%   1. Whether event satisfies governance rules
%%   2. Authority constraints
%%   3. Risk thresholds
%%   4. Competency routing
%%
%% The bridge communicates via Erlang ports to a compiled Souffle binary.
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_datalog_bridge).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Public API
-export([authorize/2, get_competencies/1, query/2]).

-define(SERVER, ?MODULE).
-define(SOUFFLE_BINARY, "seb_policy_engine").
-define(QUERY_TIMEOUT_MS, 5000).

-record(state, {
    port :: port() | undefined,
    pending_queries :: map(),
    query_counter :: non_neg_integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start the datalog bridge
-spec start_link() -> gen_server:start_ret().
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Authorize an event against policy
%%
%% Async authorization:
%%   1. Extract intent, context, authority from event envelope
%%   2. Query Datalog engine: can_authorize(Agent, Action, Resource)?
%%   3. Return {ok, approved} | {error, denied}
%%
%% Per XML: Authority constraints and risk thresholds evaluated here.
%%
-spec authorize(map(), pid()) -> ok | {error, term()}.
authorize(EventEnvelope, ReplyTo) when is_map(EventEnvelope), is_pid(ReplyTo) ->
    gen_server:cast(?SERVER, {authorize, EventEnvelope, ReplyTo}).

%% @doc Get competencies for an agent
%%
%% Queries: competency(Agent, Competency)?
%% Returns list of atom competencies
%%
-spec get_competencies(binary()) -> [atom()].
get_competencies(AgentId) when is_binary(AgentId) ->
    gen_server:call(?SERVER, {get_competencies, AgentId}).

%% @doc Generic Datalog query interface
%%
%% QueryString: Souffle query syntax (e.g., "can_authorize(agent1, read, file1)?")
%% Returns: Results or error
%%
-spec query(string(), pid()) -> ok | {error, term()}.
query(QueryString, ReplyTo) when is_list(QueryString), is_pid(ReplyTo) ->
    gen_server:cast(?SERVER, {query, QueryString, ReplyTo}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @doc Initialize the datalog bridge
-spec init([]) -> {ok, #state{}} | {error, term()}.
init([]) ->
    case open_souffle_port() of
        {ok, Port} ->
            State = #state{
                port = Port,
                pending_queries = maps:new(),
                query_counter = 0
            },
            {ok, State};
        {error, Reason} ->
            {error, {souffle_init_failed, Reason}}
    end.

%% @doc Handle synchronous calls
-spec handle_call(term(), {pid(), term()}, #state{}) -> {reply, term(), #state{}}.

handle_call({get_competencies, AgentId}, From, State) ->
    %% Query Datalog: competency(AgentId, X)?
    QueryId = State#state.query_counter + 1,
    QueryString = io_lib:format("competency(~s, X)?", [binary_to_list(AgentId)]),

    NewState = State#state{
        query_counter = QueryId,
        pending_queries = maps:put(QueryId, {From, competencies}, State#state.pending_queries)
    },

    send_to_port(State#state.port, {query, QueryId, QueryString}),
    {noreply, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

%% @doc Handle asynchronous casts
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.

handle_cast({authorize, EventEnvelope, ReplyTo}, State) ->
    QueryId = State#state.query_counter + 1,

    %% Extract fields from envelope
    Intent = maps:get(<<"intent">>, EventEnvelope, #{}),
    Authority = maps:get(<<"authority">>, EventEnvelope, #{}),
    Context = maps:get(<<"context">>, EventEnvelope, #{}),

    %% Build Datalog query
    Agent = maps:get(<<"agent_id">>, Authority, <<"unknown">>),
    Action = maps:get(<<"action">>, Intent, <<"unknown">>),
    Resource = maps:get(<<"resource">>, Intent, <<"unknown">>),

    QueryString = io_lib:format(
        "can_authorize(~s, ~s, ~s)?",
        [binary_to_list(Agent), binary_to_list(Action), binary_to_list(Resource)]
    ),

    NewState = State#state{
        query_counter = QueryId,
        pending_queries = maps:put(QueryId, {ReplyTo, authorize}, State#state.pending_queries)
    },

    send_to_port(State#state.port, {query, QueryId, QueryString}),
    {noreply, NewState};

handle_cast({query, QueryString, ReplyTo}, State) ->
    QueryId = State#state.query_counter + 1,

    NewState = State#state{
        query_counter = QueryId,
        pending_queries = maps:put(QueryId, {ReplyTo, generic}, State#state.pending_queries)
    },

    send_to_port(State#state.port, {query, QueryId, QueryString}),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @doc Handle info messages (port responses)
-spec handle_info(term(), #state{}) -> {noreply, #state{}}.

handle_info({Port, {data, Data}}, State) when Port =:= State#state.port ->
    %% Parse response from Souffle
    case parse_souffle_response(Data) of
        {QueryId, Result} ->
            case maps:find(QueryId, State#state.pending_queries) of
                {ok, {ReplyTo, Type}} ->
                    handle_query_result(Type, Result, ReplyTo),
                    NewPending = maps:remove(QueryId, State#state.pending_queries),
                    {noreply, State#state{pending_queries = NewPending}};
                error ->
                    {noreply, State}
            end;
        {error, _Reason} ->
            {noreply, State}
    end;

handle_info({Port, closed}, State) when is_port(Port) ->
    {stop, souffle_port_closed, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% @doc Terminate the datalog bridge
-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, State) ->
    case State#state.port of
        undefined -> ok;
        Port -> catch port_close(Port)
    end.

%% @doc Code change (upgrade support)
-spec code_change(term(), #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @doc Open port to Souffle policy engine
%%
%% In a real implementation, this would:
%%   1. Check if compiled Souffle binary exists
%%   2. Open an Erlang port
%%   3. Initialize connection
%%
-spec open_souffle_port() -> {ok, port()} | {error, term()}.
open_souffle_port() ->
    try
        %% For now, return a dummy port indicator
        %% In production, use: open_port({spawn, ?SOUFFLE_BINARY}, [...])
        {ok, undefined}
    catch
        _Type:_Reason ->
            {error, souffle_not_available}
    end.

%% @doc Send a query to the Souffle port
-spec send_to_port(port() | undefined, term()) -> ok.
send_to_port(undefined, _Query) ->
    %% Souffle not available - this is a test configuration
    ok;
send_to_port(Port, Query) ->
    catch port_command(Port, term_to_binary(Query)),
    ok.

%% @doc Parse response from Souffle
%%
%% Expected format: {QueryId, Results} where Results is list of tuples
%%
-spec parse_souffle_response(term()) -> {non_neg_integer(), list()} | {error, term()}.
parse_souffle_response(Data) ->
    try
        case binary_to_term(Data) of
            {QueryId, Results} when is_integer(QueryId), is_list(Results) ->
                {QueryId, Results};
            _ ->
                {error, parse_error}
        end
    catch
        _Type:_Reason ->
            {error, parse_error}
    end.

%% @doc Handle a query result based on its type
-spec handle_query_result(atom(), list(), pid()) -> ok.

handle_query_result(authorize, Results, ReplyTo) ->
    case Results of
        [true] ->
            ReplyTo ! {authorize_result, ok};
        [false] ->
            ReplyTo ! {authorize_result, {error, denied}};
        _ ->
            ReplyTo ! {authorize_result, {error, policy_error}}
    end;

handle_query_result(competencies, Results, ReplyTo) ->
    Competencies = [Comp || [Comp] <- Results, is_atom(Comp)],
    ReplyTo ! {competencies_result, Competencies};

handle_query_result(generic, Results, ReplyTo) ->
    ReplyTo ! {query_result, Results}.
