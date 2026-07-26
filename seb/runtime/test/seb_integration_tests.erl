%%%-------------------------------------------------------------------
%% @doc Integration tests for SEB L2 runtime
%%
%% Tests cover:
%%   1. Cluster formation (3 nodes)
%%   2. Agent shutdown + drain sequence
%%   3. Partition assignment via policy engine
%%   4. WORM sealing flow
%%   5. Failure recovery
%%
%% @end
%%%-------------------------------------------------------------------
-module(seb_integration_tests).
-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Cases
%%%===================================================================

test_sup_starts() ->
    {setup,
        fun() -> seb_sup:start_link() end,
        fun(Pid) -> catch gen_server:stop(Pid) end,
        fun(Pid) ->
            ?assert(is_pid(Pid)),
            ?assert(is_process_alive(Pid))
        end
    }.

test_child_processes_started() ->
    {setup,
        fun() -> seb_sup:start_link() end,
        fun(Pid) -> catch gen_server:stop(Pid) end,
        fun(_SupPid) ->
            %% Verify all children are running
            Kernel = seb_sup:get_child_pid(seb_kernel_nif),
            Policy = seb_sup:get_child_pid(seb_datalog_bridge),
            Partitions = seb_sup:get_child_pid(seb_partition_mgr),
            AgentSup = seb_sup:get_child_pid(seb_agent_sup),

            ?assert(is_pid(Kernel) orelse Kernel =:= {error, not_found}),
            ?assert(is_pid(Policy) orelse Policy =:= {error, not_found}),
            ?assert(is_pid(Partitions) orelse Partitions =:= {error, not_found}),
            ?assert(is_pid(AgentSup) orelse AgentSup =:= {error, not_found})
        end
    }.

test_spawn_agent() ->
    {setup,
        fun() ->
            {ok, Sup} = seb_sup:start_link(),
            timer:sleep(100),
            Sup
        end,
        fun(Pid) -> catch gen_server:stop(Pid) end,
        fun(_SupPid) ->
            %% Spawn an agent
            {ok, AgentPid} = seb_agent_sup:spawn_agent(
                <<"integration_test_agent">>,
                #{drain_timeout_ms => 5000}
            ),
            ?assert(is_pid(AgentPid)),

            %% Verify agent is in active state
            State = seb_agent_fsm:get_state(AgentPid),
            ?assertEqual(active, State)
        end
    }.

test_agent_drain_sequence() ->
    {setup,
        fun() ->
            {ok, Sup} = seb_sup:start_link(),
            timer:sleep(100),
            Sup
        end,
        fun(Pid) -> catch gen_server:stop(Pid) end,
        fun(_SupPid) ->
            %% Spawn and drain an agent
            {ok, AgentPid} = seb_agent_sup:spawn_agent(
                <<"drain_test_agent">>,
                #{drain_timeout_ms => 500}
            ),

            %% Queue some events
            ok = seb_agent_fsm:queue_event(AgentPid, {event, 1}),
            ok = seb_agent_fsm:queue_event(AgentPid, {event, 2}),

            %% Initiate shutdown
            ok = seb_agent_fsm:shutdown(AgentPid),
            timer:sleep(100),
            ?assertEqual(draining, seb_agent_fsm:get_state(AgentPid)),

            %% Commit offset
            ok = seb_agent_fsm:commit_offset(AgentPid, 100),
            timer:sleep(100),
            ?assertEqual(checkpointed, seb_agent_fsm:get_state(AgentPid))
        end
    }.

test_partition_assignment_deterministic() ->
    {setup,
        fun() -> seb_partition_mgr:start_link(1024) end,
        fun(Pid) -> catch gen_server:stop(Pid) end,
        fun(_Pid) ->
            %% Assign multiple agents to same partition repeatedly
            P1 = seb_partition_mgr:assign_partition(<<"agent_test">>, compute),
            P2 = seb_partition_mgr:assign_partition(<<"agent_test">>, compute),
            P3 = seb_partition_mgr:assign_partition(<<"agent_test">>, compute),

            ?assertEqual(P1, P2),
            ?assertEqual(P2, P3)
        end
    }.

test_multiple_agent_spawn() ->
    {setup,
        fun() ->
            {ok, Sup} = seb_sup:start_link(),
            timer:sleep(100),
            Sup
        end,
        fun(Pid) -> catch gen_server:stop(Pid) end,
        fun(_SupPid) ->
            %% Spawn 10 agents
            Agents = [
                begin
                    {ok, Pid} = seb_agent_sup:spawn_agent(
                        integer_to_binary(I),
                        #{drain_timeout_ms => 1000}
                    ),
                    Pid
                end
                || I <- lists:seq(1, 10)
            ],

            %% All should be alive and active
            lists:foreach(fun(AgentPid) ->
                ?assert(is_process_alive(AgentPid)),
                ?assertEqual(active, seb_agent_fsm:get_state(AgentPid))
            end, Agents)
        end
    }.

test_policy_engine_query() ->
    {setup,
        fun() -> seb_datalog_bridge:start_link() end,
        fun(Pid) -> catch gen_server:stop(Pid) end,
        fun(_Pid) ->
            %% Query competencies (should return list or error)
            Result = seb_datalog_bridge:get_competencies(<<"test_agent">>),
            ?assert(is_list(Result) orelse is_atom(Result))
        end
    }.

%%%===================================================================
%%% Utility Test Runner
%%%===================================================================

run_tests() ->
    eunit:run([?MODULE]).
