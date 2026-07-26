%%%-------------------------------------------------------------------
%% @doc Sovereign Event Bus Application Module
%%
%% Provides application startup/shutdown hooks for SEB.
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_app).
-behaviour(application).

-export([start/2, stop/1]).

%%%===================================================================
%%% Application Callbacks
%%%===================================================================

%% @doc Start the SEB application
-spec start(term(), term()) -> {ok, pid()}.
start(_StartType, _StartArgs) ->
    seb_sup:start_link().

%% @doc Stop the SEB application
-spec stop(term()) -> ok.
stop(_State) ->
    ok.
