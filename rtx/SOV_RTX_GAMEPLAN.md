# SOV-RTX: Complete the 40% — Agent Research & Build Prompt

## Context

Repository: github.com/SNAPKITTYWEST/sov-kernel-monster  
Target: `rtx/` directory — sovereign GPU runtime, zero-libc, zero-CRT  
Language: C (zero-libc), PTX assembly (sm_89), C-- (GHC backend), Fortran 2018  

## What Already Exists (60%)

```
rtx/src/cuda/flash_attention.ptx   — PagedAttention + online softmax + tensor core WMMA
                                     rmsnorm_fused, silu_fused — all real PTX sm_89
rtx/windows_rtx/cuda_driver_loader.c — PEB walk, 25 CUDA functions, zero headers
rtx/windows_rtx/main.c             — zero-CRT entry, PEB→kernel32, boots full stack
rtx/windows_rtx/power_handler.c    — suspend/resume/battery power events
rtx/src/c--/scheduler.cmm          — continuous batching FSM: IDLE/PREFILL/GENERATE/SWAP/CHECKPOINT/RESUME
rtx/src/fortran/transformer_kernel.f90 — rope_fused, gqa_attention_paged, kv stubs
rtx/src/loader/gguf.c              — GGUF v3 parser, zero libc, VirtualAlloc/mmap
rtx/include/sov_rtx.h              — SOV_MAX_SEQS=256, SOV_MAX_HEADS=128, KV_BLOCK_SIZE=16
```

## The Missing 40% — Exactly Four Components

---

### MISSING 1: `gemm.ptx` — Matrix Multiply (sm_89 tensor cores)

**Why it's the hardest missing piece:**  
Every linear layer in a transformer is a GEMM: Q/K/V projection, output projection,
FFN gate/up/down. Without GEMM, you cannot do any forward pass. The scheduler.cmm
already calls `sov_cuda_flash_attention` — but before that you need:
  `x_proj = Linear(x)` — that's GEMM.

**What to build:**  
PTX kernel using `mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32` (tensor core WMMA).
This is the same instruction family already in flash_attention.ptx.

**Shortcut:**  
Use the CUTLASS PTX templates as reference — they're Apache 2.0.
Specifically CUTLASS `include/cutlass/arch/mma_sm89.h` shows the exact PTX idiom.
No need to copy CUTLASS — just use it as a reference for the instruction pattern.

**Signature to implement:**
```c
// gemm.ptx: C = A × B + C (M×K @ K×N → M×N)
// grid = (M/16, N/8, 1)   block = (32, 1, 1)  — one warp per output tile
// Uses mma.sync.aligned.m16n8k16 (Ampere/Ada tensor core)
// Inputs: f16 (quantized weights from GGUF), f32 accumulator
```

**Files to create:**
- `rtx/src/cuda/gemm.ptx` — the kernel
- `rtx/src/cuda/gemm_dispatch.c` — C dispatch: picks tile size, launches grid

---

### MISSING 2: `kv_allocator.c` — Block Allocator

**Why it's needed:**  
`sov_rtx.h` declares `SOV_MAX_SEQS=256`, `KV_BLOCK_SIZE=16` but there's no
implementation of the free-list that manages which KV blocks are allocated to
which sequences. `kv_allocate_blocks` and `kv_append_tokens` in transformer_kernel.f90
are stubs. The scheduler calls them but they do nothing.

**What to build:**  
A zero-malloc block allocator using a static free-list array.
VirtualAlloc one large region upfront (GPU side: cuMemAlloc via driver API).

**Data structure:**
```c
// Static: SOV_MAX_SEQS * max_blocks_per_seq block table
// Free list: stack of available block IDs (int32 array, top pointer)
// GPU-side: copy block_table to device before every flash_attention launch
```

**Shortcut:**  
vLLM's PagedAttention paper (Kwon et al. 2023) describes the block table layout exactly.
The block_table in flash_attention.ptx already matches it: `block_table[seq_id * max_blocks + b]`.
Build the CPU-side allocator, GPU side just reads block_table.

**Files to create:**
- `rtx/src/kv_allocator.c` — free-list + block_table management
- `rtx/src/kv_allocator.h` — types + API

---

### MISSING 3: `sampler.c` — Token Sampling

**Why it's needed:**  
After the forward pass produces logits (vocab_size floats), you need to:
1. Apply temperature scaling
2. Run top-p (nucleus) or top-k filtering
3. Sample from the resulting distribution
4. Return the next token ID

The scheduler.cmm increments `tokens_generated` and checks for EOS — but there's
no implementation of what produces the next token from logits.

**What to build:**  
A CPU-side sampler that receives logits from GPU memory.
No GPU kernel needed — sampling is memory-bandwidth bound not compute bound
at batch_size=1, and pulling 32K floats (Llama vocab) from GPU is fast enough.

**Shortcut:**  
llama.cpp's `sampling.cpp` is MIT licensed. The core top-p algorithm is 40 lines.
Use it as direct reference. Zero-libc version: replace stdlib qsort with a simple
partial sort (only need top-k candidates, not full sort).

**Files to create:**
- `rtx/src/sampler.c` — temperature, top-p, top-k, greedy (zero-libc)
- Declare `sov_sample_token` in `sov_rtx.h`

---

### MISSING 4: Wiring — `cuda_driver_loader.c` → actual kernel launches

**Why it's needed:**  
`cuda_driver_loader.c` resolves 25 CUDA driver API functions from nvcuda.dll
via PEB walk. But the actual launch code — loading the PTX module, getting
function handles, setting up launch parameters for `flash_attention_paged`
and the new `gemm` kernel — is missing. There's no `cuModuleLoadData`,
`cuModuleGetFunction`, `cuLaunchKernel` wiring.

**What to build:**  
A `cuda_kernels.c` that:
1. Calls `cuModuleLoadData(ptx_blob)` to load `flash_attention.ptx` and `gemm.ptx`
2. Calls `cuModuleGetFunction` to get handles for all 5 kernels
3. Implements `sov_cuda_flash_attention()` and `sov_cuda_gemm()` as thin wrappers
   that set up `CUlaunchKernel` calls with correct grid/block dims

**Shortcut:**  
The PTX blobs can be embedded as C char arrays (xxd -i flash_attention.ptx).
No file I/O needed — zero-libc compatible.

**Files to create:**
- `rtx/src/cuda_kernels.c` — module load + function dispatch

---

## Build Order (strict)

```
1. kv_allocator.c           ← no dependencies, unblocks everything
2. gemm.ptx + gemm_dispatch  ← depends on kv_allocator for buffer management
3. cuda_kernels.c            ← depends on both PTX files existing
4. sampler.c                 ← independent, but final step in the inference loop
```

---

## Shortcuts and Reference Materials

| Gap | Best Reference | License | Effort |
|-----|---------------|---------|--------|
| GEMM PTX (tensor cores) | CUTLASS sm89 mma patterns | Apache 2.0 | ~200 lines PTX |
| KV block allocator | vLLM PagedAttention paper + llama.cpp kv_cache.cpp | Apache 2.0 | ~150 lines C |
| Sampler | llama.cpp sampling.cpp | MIT | ~100 lines C |
| CUDA driver wiring | CUDA driver API docs + cuModuleLoadData examples | Public | ~200 lines C |

---

## Invariants to Preserve

The following invariants already exist in the codebase — do NOT break them:

1. **Zero-libc**: No `#include <stdlib.h>`, `<stdio.h>`, `<string.h>`.
   Use `VirtualAlloc`/`mmap` for memory. Manual memcpy loops or PTX `ld/st`.

2. **Zero-CRT**: `main.c` has no C runtime. Entry point is `sov_main()`.
   No `malloc`. No global constructors.

3. **WORM every 64 tokens**: `scheduler.cmm` calls `sov_worm_checkpoint(kv_ptr)`
   every 64 tokens. This must remain. New code must not bypass this.

4. **Power checkpoint semantics**: Any GPU kernel must check `power_state` global
   before heavy compute. `flash_attention.ptx` already does this. `gemm.ptx` must too.

5. **Janet config array**: `scheduler_janet_array[32]` at fixed address.
   Slots 0-7 are scheduler config. Slots 8-31 are WORM receipt.
   New code uses `janet_get/janet_set` from scheduler.cmm — never raw array access.

6. **GGUF v3 layout**: `gguf.c` reads weights. The GEMM kernel receives
   weight pointers from GGUF tensor data directly. No copy/convert step.

7. **sm_89 target**: All PTX must be `.target sm_89`. No sm_80, no sm_90.

---

## Exact PTX Instruction for GEMM

The tensor core instruction already used in `flash_attention.ptx` for the
warp-reduce is `shfl.sync.bfly`. The GEMM needs:

```ptx
// Load f16 tiles from A and B into registers
// A tile: 8x16 f16 = 4 x .b32 registers (each .b32 holds 2 f16)
// B tile: 16x8 f16 = 4 x .b32 registers
// C/D accumulator: 4 x .f32 registers

mma.sync.aligned.m16n8k16.row.col.f32.f16.f16.f32
    {%f0, %f1, %f2, %f3},    // D (f32 accumulator out)
    {%a0, %a1, %a2, %a3},    // A matrix (f16, 4 registers = 8 f16 values)
    {%b0, %b1},              // B matrix (f16, 2 registers = 4 f16 values)
    {%f0, %f1, %f2, %f3};   // C (f32 accumulator in)
```

This computes a 16×8×16 output tile in one instruction.
Tile the full GEMM by iterating K dimension in chunks of 16.

---

## Agent Research Tasks

For each agent you spawn, give it this context and one specific task:

**Agent A — GEMM PTX researcher:**
"Research CUTLASS sm89 PTX mma.sync patterns for f16 matrix multiply.
Find the exact register layout for m16n8k16, ldmatrix instruction for
loading f16 tiles from shared memory, and the loop structure for tiling
a full GEMM. Output: annotated PTX pseudocode with exact register names."

**Agent B — KV allocator researcher:**
"Research vLLM PagedAttention block table format and llama.cpp kv_cache
allocation. Specifically: how does the block_table[seq_id * max_blocks + b]
map to physical GPU memory addresses? What is the free-list data structure?
Output: C struct definitions and allocate/free pseudocode, zero-malloc."

**Agent C — CUDA driver loader researcher:**
"Research cuModuleLoadData, cuModuleGetFunction, cuLaunchKernel from the
CUDA driver API (not CUDA runtime). How do you load a PTX string at runtime?
How do you pass pointer parameters to a kernel via cuKernelParamsSetAttribute?
Output: complete working example in C, no CUDA headers (use typedefs only)."

**Agent D — Zero-libc sampler researcher:**
"Research top-p nucleus sampling algorithm. Implement it in C with no stdlib:
no qsort, no malloc. Given float* logits of size vocab_size, apply temperature,
partial sort top-k candidates, compute cumulative probabilities, return sampled
token index. Output: complete C function, zero external dependencies."

---

## Final Integration Point

When all four components exist, the full inference loop in `scheduler.cmm` becomes:

```
IDLE → PREFILL:
  kv_allocator_alloc(seq_id, num_tokens)     ← kv_allocator.c
  gemm(embedding_weights, token_ids, x)      ← gemm.ptx via cuda_kernels.c

GENERATE (per token):
  gemm(q_proj, x, q)                         ← gemm.ptx
  gemm(k_proj, x, k)                         ← gemm.ptx
  gemm(v_proj, x, v)                         ← gemm.ptx
  kv_append_tokens(seq_id, k, v)             ← kv_allocator.c
  flash_attention_paged(q, block_table, out) ← flash_attention.ptx (EXISTS)
  rmsnorm_fused(out, w, out)                 ← EXISTS
  gemm(o_proj, out, x)                       ← gemm.ptx
  silu_fused + gemm(gate_proj + up_proj)     ← gemm.ptx
  gemm(down_proj, x, x)                      ← gemm.ptx
  rmsnorm_fused(x, w, x)                     ← EXISTS
  gemm(lm_head, x, logits)                   ← gemm.ptx
  token = sampler(logits, temperature, top_p) ← sampler.c
  if token == EOS or len >= max: → IDLE
  else: repeat GENERATE
  every 64 tokens: worm_checkpoint()         ← EXISTS
```

That loop is the complete sovereign LLM inference engine.
Everything except the four missing pieces already exists in the repository.
```
