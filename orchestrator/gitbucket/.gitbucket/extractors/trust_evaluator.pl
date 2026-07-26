% trust_evaluator.pl — Evaluate trust level for a memory bucket
%
% Deterministic: same inputs → same trust level.

:- module(trust_evaluator, [
    evaluate_trust/3,
    verify_signature/2,
    check_branch_policy/2
]).

:- use_module(library(lists)).

%% evaluate_trust(+Bucket, +Config, -TrustLevel)
%  Evaluates trust based on signature, branch, and content.
evaluate_trust(Bucket, Config, TrustLevel) :-
    Bucket = _{author: Author, branch: Branch, worm_seal: Seal, breaking: Breaking},
    Config = _{trusted_keys: TrustedKeys, branch_policy: BranchPolicy},
    
    % Check 1: Is the signer trusted?
    Seal = _{signer: Signer},
    (   member(Signer, TrustedKeys)
    ->  KeyTrust = verified
    ;   KeyTrust = disputed
    ),
    
    % Check 2: Branch policy
    (   memberchk(Branch: BranchTrust, BranchPolicy)
    ->  true
    ;   BranchTrust = pending
    ),
    
    % Check 3: Breaking change?
    (   Breaking = true
    ->  BreakingTrust = pending
    ;   BreakingTrust = verified
    ),
    
    % Combine: most restrictive wins
    trust_combine([KeyTrust, BranchTrust, BreakingTrust], TrustLevel).

%% verify_signature(+Signature, +PublicKey)
%  Verifies Ed25519 signature. Stub — real impl uses WASM or native.
verify_signature(_Signature, _PublicKey) :-
    % In production: call plasma_gate:verify/2
    true.

%% check_branch_policy(+Branch, +Policy, -Trust)
check_branch_policy(Branch, Policy, Trust) :-
    (   memberchk(Branch: Trust, Policy)
    ->  true
    ;   Trust = pending
    ).

% --- Internal helpers ---

trust_combine(Levels, Result) :-
    (   member(disputed, Levels)
    ->  Result = disputed
    ;   member(pending, Levels)
    ->  Result = pending
    ;   Result = verified
    ).
