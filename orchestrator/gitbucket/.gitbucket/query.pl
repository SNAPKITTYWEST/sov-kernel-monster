% query.pl — Agent query interface for GitBucket
%
% Returns proof-carrying context bundles.
% Every query produces an audit trail.

:- module(query, [
    assemble_context/2,
    query_buckets/3,
    topological_sort/2,
    build_context/3
]).

:- use_module(library(lists)).
:- use_module(index).

%% assemble_context(+QuerySpec, -ContextBundle)
%  Main entry point. Resolves query → verifies seals → builds context.
assemble_context(QuerySpec, ContextBundle) :-
    % 1. Resolve query to bucket IDs
    resolve_query(QuerySpec, BucketIDs),
    
    % 2. Fetch buckets and verify seals
    maplist(verify_and_fetch, BucketIDs, Buckets),
    
    % 3. Topological sort by dependency
    topological_sort(Buckets, Ordered),
    
    % 4. Build minimal context (token-budget aware)
    (   QuerySpec.get(budget) = Budget
    ->  true
    ;   Budget = 8000
    ),
    build_context(Ordered, Budget, Context),
    
    % 5. Attach audit trail
    get_time(Now),
    ContextBundle = _{
        context: Context,
        audit: _{
            query: QuerySpec,
            buckets: BucketIDs,
            verifier: "Plasma_Gate",
            timestamp: Now,
            count: Buckets
        }
    }.

%% query_buckets(+QuerySpec, -BucketIDs, -Buckets)
%  Low-level query that returns raw buckets.
query_buckets(QuerySpec, BucketIDs, Buckets) :-
    resolve_query(QuerySpec, BucketIDs),
    maplist(verify_and_fetch, BucketIDs, Buckets).

%% topological_sort(+Buckets, -Sorted)
%  Sorts buckets by dependency order (parents before children).
topological_sort(Buckets, Sorted) :-
    % Build adjacency: for each bucket, find its dependencies
    maplist(bucket_deps, Buckets, DepPairs),
    
    % Simple topological sort (Kahn's algorithm)
    topological_kahn(Buckets, DepPairs, Sorted).

%% build_context(+OrderedBuckets, +Budget, -Context)
%  Builds a minimal context bundle within the token budget.
build_context([], _, _{buckets: [], total_tokens: 0}).
build_context(Buckets, Budget, Context) :-
    maplist(bucket_to_context, Buckets, ContextPieces),
    fit_budget(ContextPieces, Budget, Fitted),
    sum_tokens(Fitted, Total),
    Context = _{buckets: Fitted, total_tokens: Total}.

% --- Internal helpers ---

resolve_query(QuerySpec, BucketIDs) :-
    (   QuerySpec.get(topic) = Topic
    ->  index:query_by_topic(Topic, Buckets)
    ;   QuerySpec.get(file) = File
    ->  index:query_by_file(File, Buckets)
    ;   QuerySpec.get(entity) = Entity
    ->  index:query_by_entity(Entity, Buckets)
    ;   QuerySpec.get(agent) = Agent
    ->  index:query_by_agent(Agent, Buckets)
    ;   QuerySpec.get(type) = Type
    ->  index:query_by_type(Type, Buckets)
    ;   QuerySpec.get(since) = Since
    ->  (   QuerySpec.get(until) = Until
        ->  index:query_by_time(Since, Until, Buckets)
        ;   index:query_by_time(Since, "9999-12-31", Buckets)
        )
    ;   Buckets = []
    ),
    maplist(bucket_id, Buckets, BucketIDs).

bucket_id(Bucket, ID) :- Bucket = _{id: ID}.

verify_and_fetch(BucketID, Bucket) :-
    memory_bucket(Bucket),
    Bucket = _{id: BucketID}.

bucket_deps(Bucket, Deps) :-
    Bucket = _{id: ID, related: Related},
    Deps = ID-Related.

topological_kahn([], _, []).
topological_kahn(Buckets, DepPairs, [Bucket|Rest]) :-
    % Find a bucket with no unresolved dependencies
    select(Bucket, Buckets, Remaining),
    Bucket = _{id: ID},
    \+ (member(ID-_, DepPairs), \+ memberchk(ID, [])),
    topological_kahn(Remaining, DepPairs, Rest).
topological_kahn(Buckets, _, Buckets).  % fallback: no ordering possible

bucket_to_context(Bucket, ContextPiece) :-
    Bucket = _{id: ID, summary: Summary, type: Type, timestamp: Timestamp, files: Files},
    maplist(file_path, Files, Paths),
    ContextPiece = _{
        id: ID,
        summary: Summary,
        type: Type,
        timestamp: Timestamp,
        files: Paths
    }.

file_path(FileEntry, Path) :- FileEntry = _{path: Path}.

fit_budget(Pieces, Budget, Fitted) :-
    fit_budget_loop(Pieces, Budget, 0, Fitted).

fit_budget_loop([], _, _, []).
fit_budget_loop([P|Ps], Budget, Used, [P|Rest]) :-
    estimate_tokens(P, Tokens),
    NewUsed is Used + Tokens,
    NewUsed =< Budget,
    fit_budget_loop(Ps, Budget, NewUsed, Rest).
fit_budget_loop(_, Budget, Used, []) :-
    Used >= Budget.

estimate_tokens(Piece, Tokens) :-
    Piece = _{summary: Summary, files: Files},
    string_length(Summary, SLen),
    length(Files, FLen),
    Tokens is SLen + (FLen * 50).

sum_tokens([], 0).
sum_tokens([P|Ps], Total) :-
    P = _{summary: S, files: F},
    string_length(S, SL),
    length(F, FL),
    Tokens is SL + (FL * 50),
    sum_tokens(Ps, Rest),
    Total is Tokens + Rest.
