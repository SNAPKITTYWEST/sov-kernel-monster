% commit_message_parser.pl — Conventional Commit → Memory Bucket fields
%
% Deterministic extractor: same input → bit-identical JSON output.
% Parses conventional commit format:
%   type(scope): summary
%   BREAKING CHANGE: description
%   Refs: #123
%
% Usage:
%   ?- parse_commit_message("feat(auth): add Ed25519 verification\n\nRefs: #42", Bucket).
%   Bucket = _{type:implementation, summary:"add Ed25519 verification",
%              keywords:["auth","ed25519","verification"], related:["issue_42"],
%              trust:verified, breaking:false}

:- module(commit_message_parser, [
    parse_commit_message/2,
    classify_type/2,
    extract_scope/2,
    extract_keywords/2,
    extract_refs/2,
    has_breaking_change/1
]).

:- use_module(library(lists)).
:- use_module(library(readutil)).

%% parse_commit_message(+Message, -BucketFields)
%  Parses a conventional commit message into bucket fields.
%  Returns a dict with: type, summary, keywords, related, trust, breaking.
parse_commit_message(Message, Bucket) :-
    split_string(Message, "\n", "\n", [FirstLine|RestLines]),
    parse_first_line(FirstLine, TypeAtom, Summary, Scope),
    parse_body(RestLines, Keywords, Related, Breaking),
    classify_type(TypeAtom, BucketType),
    extract_scope_keywords(Scope, TypeAtom, Summary, Keywords, AllKeywords),
    trust_from_breaking(Breaking, Trust),
    Bucket = _{
        type: BucketType,
        summary: Summary,
        keywords: AllKeywords,
        related: Related,
        trust: Trust,
        breaking: Breaking
    }.

%% parse_first_line(+Line, -Type, -Summary, -Scope)
%  Parses "type(scope): summary" or "type: summary"
parse_first_line(Line, Type, Summary, Scope) :-
    % Try type(scope): summary
    (   re_matchsub("^(\\w+)\\(([^)]+)\\):\\s*(.+)$", Line, Match, [])
    ->  Match = _{0: _, 1: TypeStr, 2: ScopeStr, 3: SummaryStr},
        string_lower(TypeStr, Type),
        Scope = ScopeStr,
        Summary = SummaryStr
    ;   % Try type: summary
        re_matchsub("^(\\w+):\\s*(.+)$", Line, Match, [])
    ->  Match = _{0: _, 1: TypeStr, 2: SummaryStr},
        string_lower(TypeStr, Type),
        Scope = "",
        Summary = SummaryStr
    ;   % Fallback: entire line is summary
        Type = "chore",
        Scope = "",
        Summary = Line
    ).

%% parse_body(+Lines, -Keywords, -Related, -Breaking)
%  Parses body lines for BREAKING CHANGE, Refs:, and keyword extraction.
parse_body(Lines, Keywords, Related, Breaking) :-
    parse_body_lines(Lines, [], [], [], Keywords, Related, Breaking).

parse_body_lines([], KW, Rel, Br, KW, Rel, Br).
parse_body_lines([Line|Rest], KW0, Rel0, Br0, KW, Rel, Br) :-
    (   re_matchsub("^BREAKING CHANGE:\\s*(.+)$", Line, Match, [])
    ->  Match = _{0: _, 1: _BreakDesc},
        parse_body_lines(Rest, KW0, Rel0, true, KW, Rel, true)
    ;   re_matchsub("^Refs?:\\s*(.+)$", Line, Match, [])
    ->  Match = _{0: _, 1: RefsStr},
        parse_refs_string(RefsStr, NewRefs),
        append(Rel0, NewRefs, Rel1),
        parse_body_lines(Rest, KW0, Rel1, Br0, KW, Rel, Br)
    ;   re_matchsub("^BREAKING:", Line, _, [])
    ->  parse_body_lines(Rest, KW0, Rel0, true, KW, Rel, true)
    ;   % Extract potential keywords from line
        extract_inline_keywords(Line, InlineKW),
        append(KW0, InlineKW, KW1),
        parse_body_lines(Rest, KW1, Rel0, Br0, KW, Rel, Br)
    ).

%% classify_type(+TypeStr, -TypeAtom)
%  Maps conventional commit type to bucket type.
classify_type("feat", implementation).
classify_type("fix", repair).
classify_type("docs", architecture).
classify_type("style", architecture).
classify_type("refactor", implementation).
classify_type("perf", implementation).
classify_type("test", audit).
classify_type("build", architecture).
classify_type("ci", audit).
classify_type("chore", audit).
classify_type("revert", repair).
classify_type("security", audit).
classify_type("decision", decision).
classify_type("audit", audit).
classify_type("fiscal", fiscal_decision).
classify_type(_, audit).  % default

%% extract_scope(+ScopeStr, -Scope)
%  Normalizes scope string.
extract_scope("", none).
extract_scope(Scope, Scope) :- Scope \= "".

%% extract_keywords(+Summary, -Keywords)
%  Extracts keywords from summary text (split on whitespace, lowercase).
extract_keywords(Summary, Keywords) :-
    split_string(Summary, " \t", " \t", Words),
    maplist(string_lower, Words, LowerWords),
    exclude(is_stop_word, LowerWords, Keywords).

%% extract_refs(+Message, -Related)
%  Extracts issue/PR references from full message.
extract_refs(Message, Related) :-
    findall(Ref, (
        re_matchsub("(?:Refs?|Fixes|Closes|See):\\s*#(\\d+)", Message, Match, []),
        Match = _{1: NumStr},
        atom_string(Num, NumStr),
        atom_concat("issue_", Num, Ref)
    ), Related).

%% has_breaking_change(+Message)
%  Succeeds if message contains a breaking change marker.
has_breaking_change(Message) :-
    re_match("BREAKING CHANGE:|BREAKING:", Message, []).

% --- Internal helpers ---

extract_scope_keywords(Scope, Type, Summary, BaseKW, AllKW) :-
    split_string(Summary, " \t", " \t", SummaryWords),
    maplist(string_lower, SummaryWords, SummaryKW),
    (   Scope \= "" -> ScopeKW = [Scope] ; ScopeKW = []),
    (   Type \= "" -> TypeKW = [Type] ; TypeKW = []),
    append([TypeKW, ScopeKW, SummaryKW, BaseKW], AllRaw),
    exclude(is_stop_word, AllRaw, AllDups),
    list_to_set(AllDups, AllKW).

extract_inline_keywords(Line, Keywords) :-
    split_string(Line, " \t", " \t", Words),
    maplist(string_lower, Words, LowerWords),
    exclude(is_stop_word, LowerWords, Keywords).

parse_refs_string(RefsStr, Related) :-
    split_string(RefsStr, ",", " ", RefParts),
    maplist(parse_single_ref, RefParts, Related).

parse_single_ref(RefStr, Related) :-
    re_matchsub("#(\\d+)", RefStr, Match, [])
    ->  Match = _{1: NumStr},
        atom_string(Num, NumStr),
        atom_concat("issue_", Num, Related)
    ;   Related = RefStr.

trust_from_breaking(true, pending).
trust_from_breaking(false, verified).

is_stop_word(W) :-
    member(W, ["the", "a", "an", "is", "are", "was", "were", "be", "been",
               "being", "have", "has", "had", "do", "does", "did", "will",
               "would", "could", "should", "may", "might", "shall", "can",
               "to", "of", "in", "for", "on", "with", "at", "by", "from",
               "as", "into", "through", "during", "before", "after", "and",
               "but", "or", "nor", "not", "so", "yet", "both", "either",
               "neither", "each", "every", "all", "any", "few", "more",
               "most", "other", "some", "such", "no", "only", "own", "same",
               "than", "too", "very", "just", "because", "if", "when",
               "while", "this", "that", "these", "those", "it", "its"]).

string_lower(S, Lower) :-
    string_codes(S, Codes),
    maplist(to_lower_code, Codes, LowerCodes),
    string_codes(Lower, LowerCodes).

to_lower_code(C, Lower) :-
    (   C >= 0'A, C =< 0'Z
    ->  Lower is C + 32
    ;   Lower = C
    ).
