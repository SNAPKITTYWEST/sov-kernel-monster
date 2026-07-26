%%%-------------------------------------------------------------------
%% @doc Sovereign Event Bus — WAL Kernel NIF Bridge
%%
%% Bridges Erlang/OTP to the C WAL kernel (seb_wal_nif.c) which
%% enforces all five L0 invariants on every append:
%%   1. Lattice commitment: circuit(prev_tip || header[0:64]) == footer.event_hash
%%   2. Hash chain:         footer.prev_hash == handle.tip_hash
%%   3. Offset monotonic:   header.offset > tip_offset
%%   4. Segment bounds:     event fits in 1 GiB segment
%%   5. Sequence monotonic: on segment rotation
%%
%% The commitment uses the GF(2^8) lattice circuit (seb_lattice.c),
%% which unifies the WAL kernel with the formal lattice specification.
%%
%% Wire constants (from SEB_Protocol.idr / seb_types.ads):
%%   Header = 68 bytes, Footer = 128 bytes, Overhead = 196 bytes
%%   Tip hash = 32 bytes (lattice commitment)
%% @end
%%%-------------------------------------------------------------------
-module(seb_kernel_nif).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([
    init_kernel/2,        %% (SegmentId, Sequence) -> {ok, Handle} | {error, Reason}
    append_event/4,       %% (Handle, Header68, Payload, Footer128) -> {ok, Offset} | {error, Reason}
    rotate_segment/3,     %% (Handle, NewSegId, NewSeq) -> {ok, 0} | {error, Reason}
    verify_chain/1,       %% (Handle) -> {ok, EventsSealed} | {error, Reason}
    worm_flush/1,         %% (Handle) -> ok
    get_state/1,          %% (Handle) -> {SegId, Seq, Sealed, Rotated, TipOffset}
    get_tip_hash/1        %% (Handle) -> {ok, Hash32::binary} | {error, Reason}
]).

-define(SERVER, ?MODULE).
-define(NIF_LIB, "seb_wal_nif").  %% built from seb_wal_nif.c

-record(state, {handle}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec init_kernel(non_neg_integer(), non_neg_integer()) ->
    {ok, reference()} | {error, term()}.
init_kernel(SegId, Seq) ->
    gen_server:call(?SERVER, {init_kernel, SegId, Seq}).

-spec append_event(reference(), binary(), binary(), binary()) ->
    {ok, non_neg_integer()} | {error, term()}.
append_event(Handle, Header, Payload, Footer) ->
    gen_server:call(?SERVER, {append_event, Handle, Header, Payload, Footer}).

-spec rotate_segment(reference(), non_neg_integer(), non_neg_integer()) ->
    {ok, 0} | {error, term()}.
rotate_segment(Handle, NewSegId, NewSeq) ->
    gen_server:call(?SERVER, {rotate_segment, Handle, NewSegId, NewSeq}).

-spec verify_chain(reference()) -> {ok, non_neg_integer()} | {error, term()}.
verify_chain(Handle) ->
    gen_server:call(?SERVER, {verify_chain, Handle}).

-spec worm_flush(reference()) -> ok.
worm_flush(Handle) ->
    gen_server:call(?SERVER, {worm_flush, Handle}).

-spec get_state(reference()) ->
    {non_neg_integer(), non_neg_integer(), non_neg_integer(),
     non_neg_integer(), non_neg_integer()}.
get_state(Handle) ->
    gen_server:call(?SERVER, {get_state, Handle}).

-spec get_tip_hash(reference()) -> {ok, binary()} | {error, term()}.
get_tip_hash(Handle) ->
    gen_server:call(?SERVER, {get_tip_hash, Handle}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    SoPath = filename:join([code:priv_dir(seb), ?NIF_LIB]),
    case erlang:load_nif(SoPath, []) of
        ok ->
            {ok, Handle} = nif_init_kernel(0, 0),
            {ok, #state{handle = Handle}};
        {error, {reload, _}} ->
            {ok, Handle} = nif_init_kernel(0, 0),
            {ok, #state{handle = Handle}};
        {error, Reason} ->
            {stop, {nif_load_failed, SoPath, Reason}}
    end.

handle_call({init_kernel, SegId, Seq}, _From, State) ->
    {reply, nif_init_kernel(SegId, Seq), State};
handle_call({append_event, Handle, Hdr, Pay, Ftr}, _From, State) ->
    {reply, nif_append_event(Handle, Hdr, Pay, Ftr), State};
handle_call({rotate_segment, Handle, Id, Seq}, _From, State) ->
    {reply, nif_rotate_segment(Handle, Id, Seq), State};
handle_call({verify_chain, Handle}, _From, State) ->
    {reply, nif_verify_chain(Handle), State};
handle_call({worm_flush, Handle}, _From, State) ->
    {reply, nif_worm_flush(Handle), State};
handle_call({get_state, Handle}, _From, State) ->
    {reply, nif_get_state(Handle), State};
handle_call({get_tip_hash, Handle}, _From, State) ->
    {reply, nif_get_tip_hash(Handle), State};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%%===================================================================
%%% NIF stubs — replaced by C dispatch after load_nif succeeds
%%%===================================================================

nif_init_kernel(_SegId, _Seq)                  -> erlang:nif_error(nif_not_loaded).
nif_append_event(_H, _Hdr, _Pay, _Ftr)         -> erlang:nif_error(nif_not_loaded).
nif_rotate_segment(_H, _Id, _Seq)              -> erlang:nif_error(nif_not_loaded).
nif_verify_chain(_H)                           -> erlang:nif_error(nif_not_loaded).
nif_worm_flush(_H)                             -> erlang:nif_error(nif_not_loaded).
nif_get_state(_H)                              -> erlang:nif_error(nif_not_loaded).
nif_get_tip_hash(_H)                           -> erlang:nif_error(nif_not_loaded).
