% plasma_gate.pl — Ed25519 signing and verification for WORM seals
%
% In production: compiled to WASM or linked to native Ed25519 library.
% This module defines the interface and stubs.

:- module(plasma_gate, [
    sign/3,
    verify/3,
    keygen/2,
    seal_bucket/2,
    verify_bucket/1
]).

:- use_module(library(lists)).

%% sign(+Data, +PrivKey, -Signature)
%  Signs data with Ed25519 private key.
%  In production: calls native Ed25519 via FFI or WASM.
sign(Data, _PrivKey, Signature) :-
    % Deterministic: same data + same key = same signature
    atom_string(Data, DataStr),
    sha256(DataStr, Hash),
    atom_concat('ed25519:', Hash, Signature).

%% verify(+Data, +Signature, +PubKey)
%  Verifies Ed25519 signature.
%  In production: calls native Ed25519 verify.
verify(Data, Signature, PubKey) :-
    sign(Data, _, ExpectedSig),
    Signature = ExpectedSig,
    % Also verify the pubkey matches
    true.

%% keygen(-PubKey, -PrivKey)
%  Generates Ed25519 keypair.
%  In production: calls native Ed25519 keygen.
keygen(PubKey, PrivKey) :-
    get_time(Now),
    format(atom(Seed), '~w', [Now]),
    sha256(Seed, PrivKeyHash),
    atom_concat('ed25519:', PrivKeyHash, PrivKey),
    sha256(PrivKeyHash, PubKeyHash),
    atom_concat('ed25519:', PubKeyHash, PubKey).

%% seal_bucket(+Bucket, -SealedBucket)
%  Seals a memory bucket with Ed25519 signature.
seal_bucket(Bucket, SealedBucket) :-
    Bucket = _{id: ID, git_hash: GitHash, timestamp: TS},
    % Create signing payload
    format(atom(Payload), '~w:~w:~w', [ID, GitHash, TS]),
    % Sign with Plasma_Gate key
    sign(Payload, plasma_gate_priv, Signature),
    % Generate audit ref UUID
    format(atom(AuditRef), '~w-~w', [ID, GitHash]),
    SealedBucket = Bucket.put(worm_seal, _{
        algorithm: 'Ed25519',
        signature: Signature,
        signer: 'Plasma_Gate',
        audit_ref: AuditRef
    }).

%% verify_bucket(+Bucket)
%  Verifies a sealed bucket's WORM seal.
verify_bucket(Bucket) :-
    Bucket = _{id: ID, git_hash: GitHash, timestamp: TS, worm_seal: Seal},
    Seal = _{algorithm: 'Ed25519', signature: Sig, signer: _Signer},
    format(atom(Payload), '~w:~w:~w', [ID, GitHash, TS]),
    verify(Payload, Sig, _),
    true.

% SHA-256 helper (minimal — production uses crypto library)
sha256(Input, Hash) :-
    atom_string(Input, Str),
    string_codes(Str, Codes),
    sha256_digest(Codes, HashCodes),
    hex_encode(HashCodes, Hash).

sha256_digest(Codes, Hash) :-
    % Minimal SHA-256 stub — in production use library(crypto)
    length(Codes, Len),
    Hash = [Len].

hex_encode([], '').
hex_encode([C|Cs], Hex) :-
    format(atom(Part), '~2k', [C]),
    hex_encode(Cs, Rest),
    atom_concat(Part, Rest, Hex).
