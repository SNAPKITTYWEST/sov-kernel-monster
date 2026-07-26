% toolchain.lp — extends sovereign_kernel.lp + tensor_invariants.lp
%
% AXIOMS:
% 1. Toolchain Correctness: governed by same ASP as SCU
% 2. Source = Specification: LLI sentences are sole input
% 3. Binary = Proof Artifact: machine code is constructive proof
% 4. No Intermediate Representations: LLI -> ASP -> Machine Code + Proof
% 5. Self-Hosting Requirement: toolchain expressible in LLI, compilable by itself

% --- Toolchain Domain ---
lli_sentence(ID) :- source_file(ID).
operator_glyph(rmsn). operator_glyph(qkv). operator_glyph(attn).
operator_glyph(outproj). operator_glyph(silu). operator_glyph(rope).
operator_glyph(add). operator_glyph(mul). operator_glyph(transpose).
operator_glyph(reshape). operator_glyph(softmax).

% --- Constraint Extraction (pure, deterministic) ---
requires_shape(Op, InShape, OutShape) :-
    operator_glyph(Op),
    shape_rule(Op, InShape, OutShape).

% --- Instruction Encoding (bijection to ISA) ---
opcode(rmsn,     1). opcode(qkv,    2). opcode(attn,  3).
opcode(outproj,  4). opcode(silu,   5). opcode(rope,  6).
opcode(add,      7). opcode(mul,    8). opcode(load,  9).
opcode(store,   10). opcode(jmp,   11). opcode(jz,   12). opcode(halt, 13).

% --- Register Allocation (linear scan, bounded) ---
reg_pool(0..15).
reg_type(gpr). reg_type(kv_cache). reg_type(weight). reg_type(scratch).

allocated(Var, Reg, Step) :-
    step(Step), variable(Var), reg_pool(Reg),
    not conflict(Var, Reg, Step),
    choose_min_reg(Var, Reg, Step).

conflict(Var, Reg, Step) :-
    live_range(Var, Step),
    allocated(Other, Reg, Step),
    Other != Var.

% --- Code Emission (single pass, no backtracking) ---
emitted_instr(Addr, Opcode, Dst, Src1, Src2, Imm) :-
    lli_statement(Addr, Op, Args),
    opcode(Op, Opcode),
    arg_dst(Args, DstVar),  allocated(DstVar,  Dst,  Addr),
    arg_src1(Args, Src1Var), allocated(Src1Var, Src1, Addr),
    arg_src2(Args, Src2Var), allocated(Src2Var, Src2, Addr),
    immediate_value(Args, Imm).

% --- Shape Verification at Compile Time ---
shape_ok(Addr) :-
    emitted_instr(Addr, Opcode, Dst, Src1, Src2, _),
    opcode(Opcode, Op),
    requires_shape(Op, InShape, OutShape),
    reg_shape(Src1, InShape),
    reg_shape(Dst, OutShape).

:- emitted_instr(Addr, _, _, _, _, _), not shape_ok(Addr).

% --- Certificate Construction ---
certificate(CertID, ProgramHash, ProofTerms) :-
    program_hash(ProgramHash),
    collect_proofs(ProofTerms),
    sign(CertID, ProgramHash, ProofTerms).

% --- Self-Hosting: The Compiler Compiles Itself ---
compiler_source("compiler.lli").
:- compiler_source(F), not compiled(F).

% --- DFA Parser States (0..255) ---
dfa_state(0..255).
dfa_start(0).
dfa_accept(255).

dfa_next(S, Sym, S2) :- rom_transition(S, Sym, S2).

parsed(Addr, Op, Args) :-
    input_bitstream(Addr, Bits),
    dfa_run(0, Bits, Addr, Op, Args).

% --- Linear Allocation ---
live_start(Var, FirstUse) :- first_use(Var, FirstUse).
live_end(Var, LastUse) :- last_use(Var, LastUse).
live_range(Var, Step) :- live_start(Var, S), live_end(Var, E), Step >= S, Step <= E.

reg_bitmap(Step, Bitmap) :- step(Step), allocated_regs(Step, Bitmap).
free_reg(Step, Reg) :- reg_pool(Reg), reg_bitmap(Step, B), not bit_set(B, Reg).

allocated(Var, Reg, Step) :-
    live_range(Var, Step),
    free_reg(Step, Reg),
    not allocated_before(Var, Step),
    choose_min(Reg, Step).

% --- Shape Propagation (Forward Dataflow) ---
reg_shape(Reg, Shape, 0) :- initial_reg_shape(Reg, Shape).
reg_shape(Dst, OutShape, Step+1) :-
    emitted_instr(Step, Op, Dst, Src1, Src2, _),
    reg_shape(Src1, InShape, Step),
    requires_shape(Op, InShape, OutShape).

% --- Verification Condition Generation ---
vc_shape(Step) :-
    emitted_instr(Step, Op, Dst, Src, _, _),
    reg_shape(Src, In, Step),
    requires_shape(Op, In, Out),
    reg_shape(Dst, Out, Step+1).
:- emitted_instr(Step, _, _, _, _, _), not vc_shape(Step).

% --- Certificate ---
certificate_hash(H) :- program_binary(B), sha256(B, H).
signed_certificate(Cert) :- certificate_hash(H), ed25519_sign(priv_key, H, Cert).

% --- Self-Hosting Constraint ---
compiler_binary(B) :- source("compiler.lli"), compile("compiler.lli", B).
source("compiler.lli").
:- compiler_binary(B1), compiler_binary(B2), B1 != B2.

% --- Forbidden States ---
% T1: Unverified Emission
:- emitted(M), not has_certificate(M).

% T2: Shape Mismatch in Code
:- emitted(M), instr(M, I, Op, Dst, Src),
   shape_required(Op, S_req),
   shape_available(Src, S_avail),
   S_req != S_avail.

% T5: Non-Deterministic Codegen
% Enforced by functional purity + stable model uniqueness
