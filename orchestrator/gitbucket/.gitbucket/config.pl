% GitBucket Configuration
% Prolog config — extractor versions, trust policy, key material

:- module(config, [
    extractor_version/2,
    trust_policy/1,
    worm_algorithm/1,
    schema_version/1,
    repo_root/1
]).

% Schema version
schema_version(memory_bucket_v1).

% WORM signing algorithm
worm_algorithm(ed25519).

% Extractor versions (deterministic — same version = same output)
extractor_version(commit_message_parser, '1.0.0').
extractor_version(diff_analyzer, '1.0.0').
extractor_version(entity_linker, '1.0.0').
extractor_version(trust_evaluator, '1.0.0').

% Trust policy
%   verified  — signed by known key, on main branch
%   pending   — signed but untrusted branch or BREAKING CHANGE
%   disputed  — signature mismatch or revoked key
trust_policy(trusted_keys([
    'ed25519:SnapKitty',
    'ed25519:Plasma_Gate'
])).

trust_policy(branch_trust([
    main: verified,
    develop: pending,
    _: pending
])).

trust_policy(breaking_change_trust(pending)).

% Repo root (set at runtime by CLI)
repo_root('.').
