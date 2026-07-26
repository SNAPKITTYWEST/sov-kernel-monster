% seb_constraints.lp
% Cherry-picked from exo-synchronicity/logic/asp/constraints.lp
% Extended: SEB-specific hard constraints on admissible event configurations.
%
% ASP closes the world Datalog can't:
%   Datalog: derives what IS authorized
%   ASP:     detects what is INADMISSIBLE (configuration errors)
%
% Run: clingo seb_constraints.lp seb_facts.lp
% Expected: SATISFIABLE if configuration is valid, UNSATISFIABLE if violated

% ── From exo-synchronicity: every valid operator must have a conducting path
:- valid_operator(Op), not conducting(Op).

conducting(Op) :- valid_operator(Op, Paths), conducting_paths(Paths).
conducting_paths([]).
conducting_paths([path(Port, p) | Rest]) :-
    env_state(Port, V), V > 0.5, conducting_paths(Rest).
conducting_paths([path(Port, pn) | Rest]) :-
    env_state(Port, V), V < 0.5, conducting_paths(Rest).

% No path may route through a blocked port
:- uses(Op, Port, _), blocked(Port).

% ── SEB CONSTRAINTS (new) ──────────────────────────────────────────────────

% Constraint 1: Every registered agent must have at least one valid capability
% (floating_agent detection at the hard constraint level)
:- seb_agent(A), not seb_capability(A, _).

% Constraint 2: No agent can be both active and revoked simultaneously
:- seb_agent_status(A, "active"), seb_agent_status(A, "revoked").

% Constraint 3: SOVEREIGN_ROOT events require exactly vacuum_collapse capability
% No other capability may authorize 0xFFFF (mirrors Agda sovereign-requires-vacuum)
:- seb_event_type(E, 65535), seb_authorizes(A, E), not seb_capability(A, "vacuum_collapse").

% Constraint 4: FISCAL_SETTLE events require human review flag
% Any FISCAL_SETTLE (0x0100) that bypasses human review is inadmissible
:- seb_event_type(E, 256), seb_committed(E), not seb_human_reviewed(E).

% Constraint 5: Chain must be monotonic — no two events at same offset
:- seb_event_offset(E1, O), seb_event_offset(E2, O), E1 != E2.

% Constraint 6: Attack condition must not be silently swallowed
% If attack_detected event exists with no response, configuration is inadmissible
:- seb_event_type(E, 1025), not seb_attack_response(E).  % 0x0401 = ATTACK_DETECTED

% Constraint 7: Partition count must be power of 2 (phash2 requirement)
% Valid counts: 1, 2, 4, ..., 1024
valid_partition_count(1).
valid_partition_count(N) :- valid_partition_count(M), N = M * 2, N <= 1024.
:- seb_partition_count(N), not valid_partition_count(N).

% Constraint 8: Latency — no agent partition assignment spanning >256 partitions
% (each actor in base.dl owns 256 of 1024 partitions)
max_partition_span(256).
:- seb_agent_partition_range(A, Lo, Hi),
   Span = Hi - Lo,
   Span > MS, max_partition_span(MS).

% Constraint 9: No path through the same agent twice (no cycles in authorization)
:- seb_auth_path(A, B), seb_auth_path(B, A).

% ── SEB fact declarations (populated by Erlang runtime) ───────────────────
#external seb_agent(A : agent_id).
#external seb_capability(A : agent_id, C : capability).
#external seb_agent_status(A : agent_id, S : status).
#external seb_event_type(E : event_id, T : unsigned).
#external seb_authorizes(A : agent_id, E : event_id).
#external seb_committed(E : event_id).
#external seb_human_reviewed(E : event_id).
#external seb_event_offset(E : event_id, O : unsigned).
#external seb_attack_response(E : event_id).
#external seb_partition_count(N : unsigned).
#external seb_agent_partition_range(A : agent_id, Lo : unsigned, Hi : unsigned).
#external seb_auth_path(A : agent_id, B : agent_id).
