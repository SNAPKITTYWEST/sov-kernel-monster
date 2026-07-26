% diff_analyzer.pl — Git diff → file metadata for Memory Bucket
%
% Deterministic extractor: same diff → bit-identical output.
% Analyzes git diff --stat output to produce files[] array.

:- module(diff_analyzer, [
    analyze_diff/2,
    file_role/2,
    diff_hash/2
]).

:- use_module(library(lists)).
:- use_module(library(sha)).

%% analyze_diff(+DiffStat, -Files)
%  Parses "git diff --stat" output into files array.
%  DiffStat is a string of lines like:
%    src/lib.rs | 12 +++---
%    README.md  |  5 +++
%    3 files changed, 10 insertions(+), 5 deletions(-)
analyze_diff(DiffStat, Files) :-
    split_string(DiffStat, "\n", "\n", Lines),
    include(is_file_line, Lines, FileLines),
    maplist(parse_file_line, FileLines, Files).

%% file_role(+Path, -Role)
%  Determines the role of a file based on its path.
file_role(Path, core) :-
    re_match("src/.*\\.rs$", Path, []), !.
file_role(Path, core) :-
    re_match("src/.*\\.cpp$", Path, []), !.
file_role(Path, core) :-
    re_match("src/.*\\.hs$", Path, []), !.
file_role(Path, core) :-
    re_match("src/.*\\.lean$", Path, []), !.
file_role(Path, test) :-
    re_match("test[s]?/.*", Path, []), !.
file_role(Path, test) :-
    re_match(".*_test\\.rs$", Path, []), !.
file_role(Path, test) :-
    re_match(".*_test\\.cpp$", Path, []), !.
file_role(Path, test) :-
    re_match(".*\\.test\\..*$", Path, []), !.
file_role(Path, doc) :-
    re_match(".*\\.md$", Path, []), !.
file_role(Path, doc) :-
    re_match(".*\\.txt$", Path, []), !.
file_role(Path, config) :-
    re_match(".*Cargo\\.toml$", Path, []), !.
file_role(Path, config) :-
    re_match(".*CMakeLists\\.txt$", Path, []), !.
file_role(Path, config) :-
    re_match(".*\\.json$", Path, []), !.
file_role(Path, config) :-
    re_match(".*\\.toml$", Path, []), !.
file_role(Path, config) :-
    re_match(".*\\.yml$", Path, []), !.
file_role(Path, config) :-
    re_match(".*\\.yaml$", Path, []), !.
file_role(Path, config) :-
    re_match(".*\\.pl$", Path, []), !.
file_role(_, modified).

%% diff_hash(+DiffContent, -Hash)
%  Computes SHA-256 of diff content.
diff_hash(DiffContent, Hash) :-
    atom_string(DiffContent, Str),
    sha256(Str, Hash).

% --- Internal helpers ---

is_file_line(Line) :-
    re_match(".*\\|.*\\d+.*", Line, []).

parse_file_line(Line, FileEntry) :-
    re_matchsub("^(.+?)\\s*\\|\\s*(\\d+)", Line, Match, [])
    ->  Match = _{1: Path0, 2: _StatsStr},
        string_trim(Path0, Path),
        file_role(Path, Role),
        % Placeholder diff_hash — computed from actual diff in production
        FileEntry = _{path: Path, role: Role, diff_hash: "0000000000000000000000000000000000000000000000000000000000000000"}
    ;   FileEntry = _{path: Line, role: modified, diff_hash: "0000000000000000000000000000000000000000000000000000000000000000"}.

string_trim(S, Trimmed) :-
    string_codes(S, Codes),
    trim_codes(Codes, TrimmedCodes),
    string_codes(Trimmed, TrimmedCodes).

trim_codes([], []).
trim_codes([C|Cs], Rest) :-
    (   C =< 0x20 -> trim_codes(Cs, Rest)
    ;   reverse_trim([C|Cs], Rest)
    ).

reverse_trim([], []).
reverse_trim([C|Cs], Result) :-
    (   C =< 0x20 -> reverse_trim(Cs, Result)
    ;   Result = [C|Cs]
    ).
