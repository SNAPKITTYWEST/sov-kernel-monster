%%%-------------------------------------------------------------------
%% @doc Tests for seb_agent_fsm (4-state corrected FSM)
%%
%% Tests cover:
%%   1. State transitions (active -> draining -> checkpointed -> stopped)
%%   2. Drain timeout (30 seconds)
%%   3. Offset commitment via NIF
%%   4. Queue operations
%%   5. Error handling
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_agent_fsm_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test cases
-export([
    test_initial_state/0,
    test_active_to_draining/0,
    test_draining_to_checkpointed/0,
    test_queue_operations/0,
    test_queue_full/0,
    test_drain_timeout/0,
    test_offset_commitment/0
]).

%%%===================================================================
%%% Setup & Teardown
%%%===================================================================

setup() ->
    {ok, Pid} = seb_agent_fsm:start_link(<<"test_agent_1">>, #{
        drain_timeout_ms => 1000,
        max_queue_size => 100
    }),
    Pid.

teardown(Pid) ->
    catch gen_statem:stop(Pid),
    ok.

%%%===================================================================
%%% Test Cases
%%%===================================================================

test_initial_state() ->
    {setup, fun setup/0, fun teardown/1, fun(Pid) ->
        ?assertEqual(active, seb_agent_fsm:get_state(Pid))
    end}.

test_active_to_draining() ->
    {setup, fun setup/0, fun teardown/1, fun(Pid) ->
        ok = seb_agent_fsm:shutdown(Pid),
        timer:sleep(100),
        ?assertEqual(draining, seb_agent_fsm:get_state(Pid))
    end}.

test_draining_to_checkpointed() ->
    {setup, fun setup/0, fun teardown/1, fun(Pid) ->
        ok = seb_agent_fsm:shutdown(Pid),
        timer:sleep(100),
        %% Commit offset while draining
        ok = seb_agent_fsm:commit_offset(Pid, 100),
        timer:sleep(100),
        ?assertEqual(checkpointed, seb_agent_fsm:get_state(Pid))
    end}.

test_queue_operations() ->
    {setup, fun setup/0, fun teardown/1, fun(Pid) ->
        %% Queue should accept items while active
        ?assertEqual(ok, seb_agent_fsm:queue_event(Pid, {event, 1})),
        ?assertEqual(ok, seb_agent_fsm:queue_event(Pid, {event, 2})),
        ?assertEqual(ok, seb_agent_fsm:queue_event(Pid, {event, 3})),
        ?assertEqual(active, seb_agent_fsm:get_state(Pid))
    end}.

test_queue_full() ->
    {setup, fun setup/0, fun teardown/1, fun(Pid) ->
        %% Fill queue to capacity (100)
        [ok = seb_agent_fsm:queue_event(Pid, {event, I}) || I <- lists:seq(1, 100)],
        %% Next event should fail
        ?assertEqual({error, queue_full}, seb_agent_fsm:queue_event(Pid, {event, 101}))
    end}.

test_drain_timeout() ->
    {setup, fun setup/0, fun teardown/1, fun(Pid) ->
        ok = seb_agent_fsm:shutdown(Pid),
        timer:sleep(100),
        ?assertEqual(draining, seb_agent_fsm:get_state(Pid)),
        %% Wait for drain timeout (1000ms + buffer)
        timer:sleep(1500),
        ?assertEqual(checkpointed, seb_agent_fsm:get_state(Pid))
    end}.

test_offset_commitment() ->
    {setup, fun setup/0, fun teardown/1, fun(Pid) ->
        %% Commit offset while active
        ok = seb_agent_fsm:commit_offset(Pid, 50),
        ?assertEqual(active, seb_agent_fsm:get_state(Pid)),

        %% Commit again with higher offset
        ok = seb_agent_fsm:commit_offset(Pid, 100),
        ?assertEqual(active, seb_agent_fsm:get_state(Pid))
    end}.

%%%===================================================================
%%% Utility Test Runner
%%%===================================================================

run_tests() ->
    eunit:run([?MODULE]).
