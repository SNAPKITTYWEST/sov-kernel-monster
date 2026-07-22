% SOV-KERNEL-MONSTER Logic Layer
% Loaded by pre-receive hook via swipl.

:- use_module(library(process)).

% ---- Key Registry (MOCK) ----
% These are deterministic test fingerprints — safe to commit.
% Replace with real Ed25519 fingerprints after running provision/sov-bootstrap.yml
% and reading the audit output. NEVER commit real private keys.
architect_key('mock:arch:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC').
engineer_key('mock:eng1:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF').
engineer_key('mock:eng2:BC:DE:F0:12:34:56:78:9A:BC:DE:F0:12:34:56:78:9A:BC:DE:F0').
engineer_key('mock:eng3:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01').
engineer_key('mock:eng4:DE:F0:12:34:56:78:9A:BC:DE:F0:12:34:56:78:9A:BC:DE:F0:12').
engineer_key('mock:eng5:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23').
ci_bot_key('mock:hauki:F0:12:34:56:78:9A:BC:DE:F0:12:34:56:78:9A:BC:DE:F0:12:34').

authorized_key(K) :- architect_key(K).
authorized_key(K) :- engineer_key(K).
authorized_key(K) :- ci_bot_key(K).

% ---- ASP_MAXIMAL: main branch requires Architect counter-signature ----
verify_push(NewRev, 'refs/heads/main') :-
    !,
    get_commit_signer(NewRev, Signer),
    ( architect_key(Signer) -> true
    ; format(user_error, "[ASP_MAXIMAL] Main branch push requires Architect counter-signature. Got: ~w~n", [Signer]),
      fail
    ).

% ---- ASP_STRICT: feature branches require any authorized signer ----
verify_push(NewRev, Ref) :-
    Ref \= 'refs/heads/main',
    get_commit_signer(NewRev, Signer),
    ( authorized_key(Signer) -> true
    ; format(user_error, "[ASP_STRICT] Unauthorized committer: ~w~n", [Signer]),
      fail
    ).

% ---- Fallback: allow if no signer info available (warn only) ----
verify_push(_, Ref) :-
    format(user_error, "[ASP_WARN] Could not verify signer for ref: ~w~n", [Ref]).

% ---- Helper: extract signing key from commit ----
get_commit_signer(Commit, KeyID) :-
    process_create(path(git), ['show', '-s', '--format=%GK', Commit],
                   [stdout(pipe(Out)), stderr(null)]),
    read_line_to_string(Out, Line),
    close(Out),
    ( Line \= "" -> atom_string(KeyID, Line)
    ; KeyID = 'UNSIGNED'
    ).
