% index.pl — Multi-dimensional fact base for memory buckets
%
% Loaded at runtime. All facts are dynamic (asserted/retracted).
% Same bucket data → same index state (deterministic).

:- module(index, [
    load_buckets/1,
    assert_bucket/1,
    assert_index/1,
    query_by_file/2,
    query_by_entity/2,
    query_by_topic/2,
    query_by_agent/2,
    query_by_time/3,
    query_by_dep/2,
    query_by_type/2
]).

:- use_module(library(lists)).

:- dynamic memory_bucket/1.
:- dynamic idx_file/2.
:- dynamic idx_entity/2.
:- dynamic idx_topic/2.
:- dynamic idx_agent/2.
:- dynamic idx_time/2.
:- dynamic idx_dep/2.
:- dynamic idx_type/2.

%% load_buckets(+BucketDir)
%  Loads all JSON bucket files from directory into the fact base.
load_buckets(BucketDir) :-
    directory_files(BucketDir, Files),
    include(is_bucket_file, Files, BucketFiles),
    maplist(load_bucket_file(BucketDir), BucketFiles).

%% assert_bucket(+Bucket)
%  Asserts a single bucket and updates all indices.
assert_bucket(Bucket) :-
    Bucket = _{id: ID},
    assertz(memory_bucket(Bucket)),
    index_bucket(Bucket).

%% assert_index(+Buckets)
%  Asserts a list of buckets.
assert_index([]).
assert_index([B|Bs]) :-
    assert_bucket(B),
    assert_index(Bs).

%% query_by_file(+Path, -Buckets)
query_by_file(Path, Buckets) :-
    findall(B, (idx_file(Path, ID), memory_bucket(B), B.id = ID), Buckets).

%% query_by_entity(+Entity, -Buckets)
query_by_entity(Entity, Buckets) :-
    findall(B, (idx_entity(Entity, ID), memory_bucket(B), B.id = ID), Buckets).

%% query_by_topic(+Topic, -Buckets)
query_by_topic(Topic, Buckets) :-
    findall(B, (idx_topic(Topic, ID), memory_bucket(B), B.id = ID), Buckets).

%% query_by_agent(+AgentID, -Buckets)
query_by_agent(AgentID, Buckets) :-
    findall(B, (idx_agent(AgentID, ID), memory_bucket(B), B.id = ID), Buckets).

%% query_by_time(+From, +To, -Buckets)
query_by_time(From, To, Buckets) :-
    findall(B, (
        idx_time(Time, ID),
        memory_bucket(B),
        B.id = ID,
        B.timestamp >= From,
        B.timestamp =< To
    ), Buckets).

%% query_by_dep(+ParentID, -Children)
query_by_dep(ParentID, Children) :-
    findall(ChildID, idx_dep(ParentID, ChildID), Children).

%% query_by_type(+Type, -Buckets)
query_by_type(Type, Buckets) :-
    findall(B, (idx_type(Type, ID), memory_bucket(B), B.id = ID), Buckets).

% --- Internal helpers ---

is_bucket_file(Name) :-
    re_match("^mem_.*\\.json$", Name, []).

load_bucket_file(Dir, File) :-
    atom_concat(Dir, '/', DirSlash),
    atom_concat(DirSlash, File, Path),
    open(Path, read, Stream),
    read_json(Stream, Bucket),
    close(Stream),
    assert_bucket(Bucket).

index_bucket(Bucket) :-
    Bucket = _{id: ID, files: Files, entities: Entities, keywords: Keywords,
               author: Author, timestamp: Timestamp, type: Type, related: Related},
    
    % Index files
    maplist(index_file(ID), Files),
    
    % Index entities
    maplist(index_entity(ID), Entities),
    
    % Index topics (keywords)
    maplist(index_topic(ID), Keywords),
    
    % Index agent
    Author = _{id: AgentID},
    assertz(idx_agent(AgentID, ID)),
    
    % Index time
    assertz(idx_time(Timestamp, ID)),
    
    % Index type
    assertz(idx_type(Type, ID)),
    
    % Index dependencies
    maplist(index_dep(ID), Related).

index_file(ID, FileEntry) :-
    FileEntry = _{path: Path},
    assertz(idx_file(Path, ID)).

index_entity(ID, Entity) :-
    assertz(idx_entity(Entity, ID)).

index_topic(ID, Topic) :-
    assertz(idx_topic(Topic, ID)).

index_dep(ID, RelatedID) :-
    assertz(idx_dep(RelatedID, ID)).

read_json(Stream, Dict) :-
    read_term(Stream, Term, []),
    (   Term = end_of_file
    ->  Dict = _{}
    ;   Dict = Term
    ).
