%%%-------------------------------------------------------------------
%% @doc SEB-Shrew Bridge — NATS sovereign.shrew.worm.v1 → SEB lattice
%%
%% Every SkerProven or SkerShrewd verdict on sovereign.shrew.worm.v1
%% becomes a 64-byte payload appended to the SEB WORM chain.
%%
%% Payload layout (64 bytes, matches seb_convergence.mjs):
%%   [0:8]   event_type  uint64 LE: 0x0600=SHREW_PROVEN, 0x0601=SHREW_SHREWD
%%   [8:16]  tick        uint64 LE: Shrew tick counter
%%   [16:24] timestamp   uint64 LE: Unix ms
%%   [24:56] agent_hash  32 bytes: SHA-256 of agent_key
%%   [56:64] seal_head   8 bytes: first 8 bytes of shrew_seal
%%
%% The Shrew runtime runs at 1000Hz (sovereign-shrew.service, SCHED_FIFO/80).
%% This bridge subscribes to the WORM-eligible subset only.
%% attach to the SEB kernel via seb_kernel_nif:append_event/4.
%%
%% NATS connection: NATS_URL env var (default nats://127.0.0.1:4222)
%% @end
%%%-------------------------------------------------------------------
-module(seb_shrew_bridge).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(SHREW_WORM_SUBJECT, <<"sovereign.shrew.worm.v1">>).
-define(SHREWD_INFER_SUBJECT, <<"sovereign.shrewd.inference.v1">>).

%% SEB event type codes for Shrew verdicts
-define(EVENT_SHREW_PROVEN,  16#0600).
-define(EVENT_SHREW_SHREWD,  16#0601).
-define(EVENT_SHREWD_GOVERN, 16#0602).  %% GovernanceCommand from SHREWD unit

-record(state, {
    nats_conn :: pid() | undefined,
    kernel    :: reference() | undefined,
    tick_sealed :: non_neg_integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    %% Connect to NATS
    NatsUrl = os:getenv("NATS_URL", "nats://127.0.0.1:4222"),
    Conn = case teacupnats:connect(NatsUrl) of
        {ok, C}    -> C;
        {error, _} -> undefined
    end,

    %% Init SEB kernel on segment 6 (Shrew layer)
    Kernel = case seb_kernel_nif:init_kernel(6, 0) of
        {ok, H}    -> H;
        {error, _} -> undefined
    end,

    %% Subscribe to WORM-eligible verdicts
    case Conn of
        undefined -> ok;
        C ->
            teacupnats:sub(C, ?SHREW_WORM_SUBJECT),
            teacupnats:sub(C, ?SHREWD_INFER_SUBJECT)
    end,

    {ok, #state{nats_conn = Conn, kernel = Kernel, tick_sealed = 0}}.

handle_info({nats, msg, #{subject := ?SHREW_WORM_SUBJECT, body := Body}}, State) ->
    NewState = handle_shrew_worm(Body, State),
    {noreply, NewState};

handle_info({nats, msg, #{subject := ?SHREWD_INFER_SUBJECT, body := Body}}, State) ->
    NewState = handle_shrewd_governance(Body, State),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State)        -> {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%===================================================================
%%% Internal — Shrew WORM entry → SEB lattice append
%%%===================================================================

handle_shrew_worm(Body, #state{kernel = undefined} = State) ->
    error_logger:warning_msg("[SHREW_BRIDGE] kernel not connected, dropping: ~p~n",
                             [byte_size(Body)]),
    State;
handle_shrew_worm(Body, #state{kernel = Kernel, tick_sealed = N} = State) ->
    case catch jiffy:decode(Body, [return_maps]) of
        {'EXIT', _} ->
            State;
        Entry ->
            Verdict  = maps:get(<<"verdict">>,   Entry, <<"SKER_NOISE">>),
            Tick     = maps:get(<<"tick">>,      Entry, 0),
            Ts       = maps:get(<<"ts">>,        Entry, 0),
            AgentKey = maps:get(<<"agent_key">>, Entry, <<>>),
            Seal     = maps:get(<<"shrew_seal">>,Entry, <<>>),

            EventType = case Verdict of
                <<"SKER_PROVEN">> -> ?EVENT_SHREW_PROVEN;
                <<"SKER_SHREWD">> -> ?EVENT_SHREW_SHREWD;
                _                 -> ?EVENT_SHREW_PROVEN  %% only WORM-eligible arrive here
            end,

            Payload = build_payload(EventType, Tick, Ts, AgentKey, Seal),
            Header  = build_header(EventType, byte_size(Payload)),

            %% Get current tip for hash chain
            {ok, PrevTip} = seb_kernel_nif:get_tip_hash(Kernel),
            Footer = build_footer(PrevTip, Payload),

            case seb_kernel_nif:append_event(Kernel, Header, Payload, Footer) of
                {ok, Offset} ->
                    if N rem 100 =:= 0 ->
                        error_logger:info_msg(
                            "[SHREW_BRIDGE] ~s tick=~p offset=~p total=~p~n",
                            [Verdict, Tick, Offset, N+1]);
                    true -> ok
                    end,
                    State#state{tick_sealed = N + 1};
                {error, Reason} ->
                    error_logger:error_msg(
                        "[SHREW_BRIDGE] append failed tick=~p: ~p~n", [Tick, Reason]),
                    State
            end
    end.

handle_shrewd_governance(Body, #state{kernel = Kernel} = State) ->
    %% GovernanceCommand from SHREWD unit → seal as 0x0602 event
    case catch jiffy:decode(Body, [return_maps]) of
        {'EXIT', _} -> State;
        Cmd ->
            Command = maps:get(<<"command">>, Cmd, <<"UNKNOWN">>),
            Ts = erlang:system_time(millisecond),
            Payload = build_governance_payload(Command, Ts),
            Header  = build_header(?EVENT_SHREWD_GOVERN, byte_size(Payload)),
            {ok, PrevTip} = seb_kernel_nif:get_tip_hash(Kernel),
            Footer = build_footer(PrevTip, Payload),
            case seb_kernel_nif:append_event(Kernel, Header, Payload, Footer) of
                {ok, _} -> ok;
                {error, R} ->
                    error_logger:warning_msg("[SHREW_BRIDGE] governance seal failed: ~p~n", [R])
            end,
            State
    end.

%%%===================================================================
%%% Wire builders
%%%===================================================================

%% 64-byte payload: event_type(8) tick(8) ts(8) agent_sha256(32) seal_head(8)
build_payload(EventType, Tick, Ts, AgentKey, Seal) ->
    AgentHash = crypto:hash(sha256, AgentKey),           %% 32 bytes
    SealHead  = binary:part(
        crypto:hash(sha256, Seal), 0, 8),               %% 8 bytes
    <<EventType:64/little-unsigned,
      Tick:64/little-unsigned,
      Ts:64/little-unsigned,
      AgentHash/binary,
      SealHead/binary>>.

%% 64-byte governance payload: event_type(8) ts(8) command_sha256(32) zeros(16)
build_governance_payload(Command, Ts) ->
    CmdHash = crypto:hash(sha256, Command),
    Zeros   = binary:copy(<<0>>, 16),
    <<(?EVENT_SHREWD_GOVERN):64/little-unsigned,
      Ts:64/little-unsigned,
      CmdHash/binary,
      Zeros/binary>>.

%% 68-byte event header (matches seb_types.ads)
build_header(EventType, PayloadSize) ->
    Ts = erlang:system_time(nanosecond),
    <<EventType:64/little-unsigned,
      Ts:64/little-unsigned,
      0:64/little-unsigned,           %% agent_id: Shrew bridge = 0
      PayloadSize:32/little-unsigned,
      6:32/little-unsigned,           %% partition_id: Shrew = 6
      0:64/little-unsigned,           %% prev_offset
      0:64/little-unsigned,           %% sequence_no
      0:64/little-unsigned,           %% reserved
      0:32/little-unsigned,           %% reserved2
      0:32/little-unsigned>>.         %% reserved3

%% 128-byte footer: prev_hash(32) event_hash(32) sig(64)
%% event_hash = lattice circuit(prev_tip || header[0:64])
%% computed by the NIF — we send zeros and it fills commitment
build_footer(PrevTip, _Payload) ->
    <<PrevTip/binary,
      (binary:copy(<<0>>, 32))/binary,  %% event_hash: NIF fills
      (binary:copy(<<0>>, 64))/binary>>. %% signature: policy layer fills
