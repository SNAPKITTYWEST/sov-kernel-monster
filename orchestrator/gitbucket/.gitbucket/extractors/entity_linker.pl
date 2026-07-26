% entity_linker.pl — Extract named entities from commit content
%
% Links code symbols, file paths, and concepts to entity references.

:- module(entity_linker, [
    extract_entities/3,
    link_entity/2,
    symbol_table/2
]).

:- use_module(library(lists)).

%% extract_entities(+Files, +Summary, -Entities)
%  Extracts named entities from file paths and summary text.
extract_entities(Files, Summary, Entities) :-
    maplist(file_to_entity, Files, FileEntities),
    summary_to_entities(Summary, SummaryEntities),
    append(FileEntities, SummaryEntities, AllRaw),
    list_to_set(AllRaw, Entities).

%% link_entity(+Entity, -RelatedBuckets)
%  Looks up an entity in the index to find related buckets.
link_entity(Entity, RelatedBuckets) :-
    idx_entity(Entity, RelatedBuckets).

%% symbol_table(+Path, -Symbols)
%  Extracts public symbols from a Rust source file (simplified).
symbol_table(Path, Symbols) :-
    re_match(".*\\.rs$", Path, []),
    % In production: parse the file for pub fn/struct/enum/impl
    % Simplified: extract from diff content
    Symbols = [].
symbol_table(_, []).

% --- Internal helpers ---

file_to_entity(FileEntry, Entity) :-
    FileEntry = _{path: Path, role: _},
    path_to_entity_name(Path, Entity).

path_to_entity_name(Path, Entity) :-
    % Extract the module name from path
    % e.g., "src/engine/scheduler.rs" → "scheduler"
    split_string(Path, "/", "/", Parts),
    last(Parts, LastPart),
    split_string(LastPart, ".", ".", NameParts),
    nth0(0, NameParts, EntityName),
    string_lower(EntityName, Entity).

summary_to_entities(Summary, Entities) :-
    % Extract capitalized words that look like entity names
    split_string(Summary, " \t", " \t", Words),
    include(is_entity_candidate, Words, Entities).

is_entity_candidate(Word) :-
    string_codes(Word, [First|_]),
    First >= 0'A, First =< 0'Z,
    string_length(Word, Len),
    Len > 2.
