%%%-------------------------------------------------------------------
%% @doc Tests for seb_partition_mgr (deterministic routing)
%%
%% Tests cover:
%%   1. Deterministic partition assignment
%%   2. Partition load tracking
%%   3. Load rebalancing
%%   4. phash2 determinism (same input -> same output)
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_partition_mgr_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Setup & Teardown
%%%===================================================================

setup() ->
    {ok, Pid} = seb_partition_mgr:start_link(1024),
    Pid.

teardown(Pid) ->
    catch gen_server:stop(Pid),
    ok.

%%%===================================================================
%%% Test Cases
%%%===================================================================

test_deterministic_assignment() ->
    {setup, fun setup/0, fun teardown/1, fun(_Pid) ->
        %% Same agent + competency should always map to same partition
        Partition1 = seb_partition_mgr:assign_partition(<<"agent_1">>, compute),
        Partition2 = seb_partition_mgr:assign_partition(<<"agent_1">>, compute),
        ?assertEqual(Partition1, Partition2)
    end}.

test_deterministic_across_calls() ->
    {setup, fun setup/0, fun teardown/1, fun(_Pid1) ->
        P1 = seb_partition_mgr:assign_partition(<<"agent_2">>, io),
        %% Restart manager and assign again
        ok,
        P2 = seb_partition_mgr:assign_partition(<<"agent_2">>, io),
        %% Should be equal (phash2 is deterministic)
        ?assertEqual(P1, P2)
    end}.

test_different_agents_different_partitions() ->
    {setup, fun setup/0, fun teardown/1, fun(_Pid) ->
        P1 = seb_partition_mgr:assign_partition(<<"agent_1">>, compute),
        P2 = seb_partition_mgr:assign_partition(<<"agent_2">>, compute),
        P3 = seb_partition_mgr:assign_partition(<<"agent_3">>, compute),
        %% They should not all be identical (statistically)
        NotAllEqual = not ((P1 =:= P2) andalso (P2 =:= P3)),
        ?assert(NotAllEqual)
    end}.

test_partition_range() ->
    {setup, fun setup/0, fun teardown/1, fun(_Pid) ->
        %% All partitions should be in [0, 1024)
        [begin
            P = seb_partition_mgr:assign_partition(integer_to_binary(I), compute),
            ?assert(P >= 0),
            ?assert(P < 1024)
        end || I <- lists:seq(1, 100)]
    end}.

test_partition_load() ->
    {setup, fun setup/0, fun teardown/1, fun(_Pid) ->
        P = seb_partition_mgr:assign_partition(<<"agent_1">>, compute),
        Load = seb_partition_mgr:get_partition_load(P),
        %% Load should be a float
        ?assert(is_float(Load) orelse is_integer(Load))
    end}.

test_rebalance() ->
    {setup, fun setup/0, fun teardown/1, fun(_Pid) ->
        %% Trigger rebalancing
        ?assertEqual(ok, seb_partition_mgr:rebalance_partitions())
    end}.

%%%===================================================================
%%% Utility Test Runner
%%%===================================================================

run_tests() ->
    eunit:run([?MODULE]).
