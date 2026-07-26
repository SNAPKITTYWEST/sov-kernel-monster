%%%-------------------------------------------------------------------
%% @doc SEB P/NP Bridge — Erlang gen_server
%%
%% Watches the convergence_log.jsonl, translates each entry into a
%% SEB event, and appends it to the WAL kernel via seb_kernel_nif.
%%
%% Event type codes (from SEB_Protocol.idr EventTypeRegistry):
%%   0x0400  PROBLEM_SOLVED   — positive universeSumDelta
%%   0x0401  ATTACK_DETECTED  — negative universeSumDelta
%%   0x0402  CHAIN_VERIFY     — periodic integrity check
%%
%% Payload layout (64 bytes, matches seb_convergence.mjs):
%%   [0:8]   event_type  uint64 LE
%%   [8:16]  timestamp   uint64 LE nanoseconds
%%   [16:48] problem_id  SHA-256 of problemId string
%%   [48:56] delta       float64 LE
%%   [56:64] reserved    zeros
%%
%% On ATTACK_DETECTED: emits the event, then calls verify_chain.
%% If verify_chain fails: supervisor escalates to Compromised state.
%% @end
%%%-------------------------------------------------------------------
-module(seb_pnp_bridge).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(POLL_MS, 10000).     %% check convergence_log every 10s
-define(ATTACK_THRESHOLD, -1.0).  %% universe sum below this = halt

-record(state, {
    conv_log    :: string(),    %% path to convergence_log.jsonl
    last_pos    :: non_neg_integer(),   %% byte offset read so far
    kernel      :: reference(),  %% seb_kernel_nif handle
    universe_sum :: float()
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(ConvLogPath) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [ConvLogPath], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([ConvLogPath]) ->
    {ok, Handle} = seb_kernel_nif:init_kernel(4, 0),  %% segment 4, seq 0 (L4 = bridge layer)
    erlang:send_after(?POLL_MS, self(), poll),
    {ok, #state{
        conv_log     = ConvLogPath,
        last_pos     = 0,
        kernel       = Handle,
        universe_sum = 0.0
    }}.

handle_info(poll, State) ->
    NewState = poll_and_seal(State),
    erlang:send_after(?POLL_MS, self(), poll),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%===================================================================
%%% Internal
%%%===================================================================

poll_and_seal(#state{conv_log = Path, last_pos = Pos,
                     kernel = Handle, universe_sum = Sum} = State) ->
    case file:open(Path, [read, binary]) of
        {error, _} ->
            State;
        {ok, Fd} ->
            {ok, _} = file:position(Fd, Pos),
            {Lines, NewPos} = read_lines(Fd, Pos),
            file:close(Fd),
            process_entries(Lines, State#state{last_pos = NewPos})
    end.

read_lines(Fd, Pos) ->
    read_lines(Fd, Pos, []).

read_lines(Fd, Pos, Acc) ->
    case file:read_line(Fd) of
        eof          -> {lists:reverse(Acc), Pos};
        {error, _}   -> {lists:reverse(Acc), Pos};
        {ok, Line}   ->
            {ok, NewPos} = file:position(Fd, cur),
            read_lines(Fd, NewPos, [Line | Acc])
    end.

process_entries([], State) -> State;
process_entries([Line | Rest], State) ->
    case catch jiffy:decode(Line, [return_maps]) of
        {'EXIT', _} ->
            process_entries(Rest, State);
        Entry ->
            NewState = seal_entry(Entry, State),
            process_entries(Rest, NewState)
    end.

seal_entry(Entry, #state{kernel = Handle, universe_sum = Sum} = State) ->
    Delta     = maps:get(<<"universeSumDelta">>, Entry, 0.0),
    ProblemId = maps:get(<<"problemId">>, Entry, <<>>),
    Timestamp = maps:get(<<"timestamp">>, Entry, <<>>),
    NewSum    = Sum + Delta,

    %% Build 64-byte payload
    Payload = build_payload(Entry, Delta),

    %% Build minimal header (68 bytes matching seb_types.ads)
    EventType = if Delta < 0 -> 16#0401; true -> 16#0400 end,
    Header = build_header(EventType, byte_size(Payload)),

    %% Build footer: prev_hash=tip, event_hash=circuit(tip||header[0:64]), sig=zeros
    {ok, PrevTip} = seb_kernel_nif:get_tip_hash(Handle),
    %% commitment computed by NIF internally — send zeros for event_hash, NIF fills it
    Footer = <<PrevTip/binary, (binary:copy(<<0>>, 32))/binary, (binary:copy(<<0>>, 64))/binary>>,

    case seb_kernel_nif:append_event(Handle, Header, Payload, Footer) of
        {ok, Offset} ->
            if Delta < 0 ->
                error_logger:warning_msg(
                    "seb_pnp_bridge: ATTACK EVENT sealed at offset ~p, delta=~p, problem=~s~n",
                    [Offset, Delta, ProblemId]),
                handle_attack(Handle, NewSum);
            true ->
                ok
            end;
        {error, Reason} ->
            error_logger:error_msg(
                "seb_pnp_bridge: failed to seal ~s: ~p~n", [ProblemId, Reason])
    end,

    State#state{universe_sum = NewSum}.

handle_attack(Handle, Sum) ->
    %% Verify full chain integrity
    case seb_kernel_nif:verify_chain(Handle) of
        {ok, Count} ->
            error_logger:warning_msg(
                "seb_pnp_bridge: chain intact (~p records), sum=~p~n", [Count, Sum]);
        {error, Reason} ->
            error_logger:error_msg(
                "seb_pnp_bridge: CHAIN INTEGRITY FAILURE: ~p — escalating~n", [Reason]),
            exit({chain_integrity_failure, Sum})
    end,
    %% Hard halt if universe sum crosses threshold
    if Sum < ?ATTACK_THRESHOLD ->
        error_logger:error_msg(
            "seb_pnp_bridge: universe_sum=~p < threshold ~p — HALT~n",
            [Sum, ?ATTACK_THRESHOLD]),
        exit({attack_threshold_exceeded, Sum});
    true -> ok
    end.

%% Build 68-byte event header
build_header(EventType, PayloadSize) ->
    Timestamp = erlang:system_time(nanosecond),
    <<EventType:64/little-unsigned,
      Timestamp:64/little-unsigned,
      0:64/little-unsigned,    %% agent_id (bridge agent = 0)
      PayloadSize:32/little-unsigned,
      0:32/little-unsigned,    %% partition_id
      0:64/little-unsigned,    %% prev_offset (kernel tracks)
      0:64/little-unsigned,    %% sequence_no
      0:64/little-unsigned,    %% reserved
      0:32/little-unsigned,    %% reserved2
      0:32/little-unsigned>>.  %% reserved3

%% Build 64-byte payload (matches seb_convergence.mjs layout)
build_payload(Entry, Delta) ->
    EventType = if Delta < 0 -> 16#0401; true -> 16#0400 end,
    Timestamp = erlang:system_time(nanosecond),
    ProblemId = maps:get(<<"problemId">>, Entry, <<>>),
    PidHash   = crypto:hash(sha256, ProblemId),
    DeltaBin  = <<Delta:64/little-float>>,
    Reserved  = binary:copy(<<0>>, 8),
    <<EventType:64/little-unsigned,
      Timestamp:64/little-unsigned,
      PidHash/binary,
      DeltaBin/binary,
      Reserved/binary>>.
