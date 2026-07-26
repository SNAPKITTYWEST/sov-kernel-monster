# FLTC Backend Contract

## Scope

FLTC and LLI define the computation and its invariants. The `rtx/` tree is one
concrete NVIDIA execution backend:

```
FLTC / LLI semantics
        |
        v
backend refinement contract
        |
        v
zero-CRT host code + PTX sm_89
        |
        v
CUDA Driver API + NVIDIA GPU
```

Passing a build or a numerical test is implementation evidence. It is not, by
itself, a proof of semantic refinement. A claim is "proved" only when a
checkable proof artifact and its verifier are present in the repository.

## Scalar Contract

- GEMM inputs and output storage are IEEE binary16.
- GEMM products accumulate in IEEE binary32 before conversion to binary16.
- Attention Q, K, V, and output storage are IEEE binary16.
- RMSNorm and SiLU use binary16 storage with binary32 intermediate arithmetic.
- Sampling has distinct binary32 and binary16 entry points.
- GGUF F32, F16, and BF16 tensors may be copied directly only when the
  consuming kernel declares the same storage type.
- Quantized GGUF tensors are not direct GEMM operands. Q4_0, Q8_0, and Q4_K
  require a proved dequantization or native quantized-kernel path.

Floating-point addition and multiplication are not treated as associative.
Numerical refinement obligations must state the rounding mode, exceptional
value policy, accumulation order, and an accepted error bound.

## KV Layout

The allocator owns one device allocation split into a K plane followed by a V
plane. Each plane has this byte layout:

```
[layer][physical_block][token_in_block][kv_head][head_dim]
```

The strides are:

```
token_stride = kv_heads * head_dim * element_bytes
page_stride  = SOV_KV_BLOCK_SIZE * token_stride
layer_stride = physical_blocks * page_stride
plane_stride = layers * layer_stride
```

For a logical `(sequence, token)` pair:

```
logical_block = token / SOV_KV_BLOCK_SIZE
token_offset  = token % SOV_KV_BLOCK_SIZE
physical      = block_table[sequence][logical_block]
address       = plane_base
              + layer * layer_stride
              + physical * page_stride
              + token_offset * token_stride
```

The attention wrapper obtains K/V bases, dimensions, and strides from the
allocator. Callers do not supply an independent K/V layout.

## Parallel Safety

The backend must discharge these obligations before it is considered a valid
realization of an FLTC operator:

1. Every output element is covered.
2. Every non-atomic output address has one writer.
3. Every global and shared-memory access is in bounds and aligned for its
   instruction.
4. Every barrier is reached by the complete participating work-group.
5. Register, shared-memory, code, KV, and activation bounds are explicit.
6. A non-active power state prevents output mutation.
7. Host/device ABI parameter order, widths, and signedness match exactly.
8. Numerical results satisfy an operator-specific error contract.

Current host and GPU tests exercise selected instances of these obligations.
They do not yet constitute exhaustive proofs.

## Layer 21 Boundary

The existing `src/c--/scheduler.cmm` is a design scaffold, not a wired runtime.
Its imported allocator and CUDA signatures do not match the current C ABI, and
the repository does not yet implement the declared WORM and Janet functions.
The zero-CRT entry point therefore halts after backend diagnostics instead of
claiming that inference is available.

Layer 21 must provide a deterministic scheduler transition with this ordering:

```
validate request
allocate logical KV pages
run prefill or decode operators
write K/V for the committed token position
sample the next token
commit sequence state
checkpoint every 64 committed generated tokens
publish an immutable event
```

A failed operator, allocation, sample, or checkpoint must not publish a success
event or advance the committed sequence state.

## Event Bus Boundary

The Event Bus attaches to Layer 21 after the state transition commits. On a
64-token boundary, publication occurs only after the ROWM-NR receipt is
committed. Events contain logical immutable data, never process-local or GPU
pointers.

Minimum event fields:

```
version
event_type
sequence_id
previous_state
new_state
committed_token_count
sampled_token_id
checkpoint_receipt_hash (optional)
transition_digest
monotonic_sequence_number
```

The transition digest covers the canonical event fields and the prior digest.
Retries reuse the same sequence number and digest, making publication
idempotent. Event delivery may be asynchronous; scheduler state mutation may
not depend on subscriber behavior.
