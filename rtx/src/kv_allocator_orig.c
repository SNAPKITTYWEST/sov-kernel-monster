#include "kv_allocator.h"
#include "cuda_driver_loader.h" /* for cuMemAlloc, cuMemFree, cuMemcpyHtoD */

/* --------------------------------------------------------------
 * Global singleton
 * -------------------------------------------------------------- */
sov_kv_allocator_t g_kv_allocator = {0};

/* --------------------------------------------------------------
 * Helpers: manual memory ops (zero-libc)
 * -------------------------------------------------------------- */
static void sov_memset(void* dst, int val, size_t n) {
    unsigned char* p = (unsigned char*)dst;
    unsigned char v = (unsigned char)val;
    while (n--) *p++ = v;
}
static void sov_memcpy(void* dst, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dst;
    const unsigned char* s = (const unsigned char*)src;
    while (n--) *d++ = *s++;
}

/* --------------------------------------------------------------
 * Initialize: allocate one giant GPU buffer for all KV blocks,
 * build free list [0, 1, 2, ..., TOTAL_BLOCKS-1]
 * -------------------------------------------------------------- */
int sov_kv_allocator_init(void) {
    if (g_kv_allocator.initialized) return 0;

    /* Calculate total KV cache size:
     * 2 buffers (K + V) * SOV_MAX_HEADS * KV_BLOCK_SIZE * head_dim * sizeof(half)
     * head_dim = 128 (Llama-3 8B: 4096/32) — hardcoded per sov_rtx.h constants
     */
    const size_t head_dim = 128;
    const size_t bytes_per_block = 2 * SOV_MAX_HEADS * SOV_KV_BLOCK_SIZE * head_dim * sizeof(uint16_t);
    const size_t total_bytes = bytes_per_block * SOV_KV_TOTAL_BLOCKS;

    /* Allocate GPU memory via driver API (cuMemAlloc) */
    CUresult err = g_cuMemAlloc_v2((CUdeviceptr*)&g_kv_allocator.gpu_kv_base, total_bytes);
    if (err != CUDA_SUCCESS) return -1;

    g_kv_allocator.gpu_kv_bytes = total_bytes;

    /* Initialize block_table to -1 (unallocated) */
    const int32_t total_slots = SOV_MAX_SEQS * SOV_KV_MAX_BLOCKS_PER_SEQ;
    for (int32_t i = 0; i < total_slots; ++i) {
        g_kv_allocator.block_table[i] = -1;
    }

    /* Build free list: push all physical block IDs onto stack */
    g_kv_allocator.free_top = 0;
    for (int32_t i = 0; i < SOV_KV_TOTAL_BLOCKS; ++i) {
        g_kv_allocator.free_list[g_kv_allocator.free_top++] = i;
    }

    /* Zero per-sequence block counts */
    for (int i = 0; i < SOV_MAX_SEQS; ++i) {
        g_kv_allocator.seq_block_count[i] = 0;
    }

    g_kv_allocator.initialized = 1;
    return 0;
}

/* --------------------------------------------------------------
 * Pop a free block ID from the stack. Returns -1 if empty.
 * -------------------------------------------------------------- */
static int32_t pop_free_block(void) {
    if (g_kv_allocator.free_top == 0) return -1;
    return g_kv_allocator.free_list[--g_kv_allocator.free_top];
}

/* --------------------------------------------------------------
 * Push a block ID back onto the free stack.
 * -------------------------------------------------------------- */
static void push_free_block(int32_t block_id) {
    if (g_kv_allocator.free_top < SOV_KV_TOTAL_BLOCKS) {
        g_kv_allocator.free_list[g_kv_allocator.free_top++] = block_id;
    }
}

/* --------------------------------------------------------------
 * Compute number of blocks needed for 'num_tokens' (ceiling division).
 * -------------------------------------------------------------- */
static uint32_t tokens_to_blocks(uint32_t num_tokens) {
    return (num_tokens + SOV_KV_BLOCK_SIZE - 1) / SOV_KV_BLOCK_SIZE;
}

/* --------------------------------------------------------------
 * Allocate blocks for a new sequence.
 * -------------------------------------------------------------- */
int sov_kv_allocate_blocks(int32_t seq_id, uint32_t num_tokens) {
    if (!g_kv_allocator.initialized) return -1;
    if (seq_id < 0 || seq_id >= SOV_MAX_SEQS) return -1;
    if (g_kv_allocator.seq_block_count[seq_id] != 0) return -1; /* already allocated */

    uint32_t needed = tokens_to_blocks(num_tokens);
    uint32_t max_allowed = SOV_KV_MAX_BLOCKS_PER_SEQ;
    if (needed > max_allowed) needed = max_allowed;

    int32_t* seq_table = &g_kv_allocator.block_table[seq_id * SOV_KV_MAX_BLOCKS_PER_SEQ];

    for (uint32_t i = 0; i < needed; ++i) {
        int32_t blk = pop_free_block();
        if (blk < 0) {
            /* OOM: rollback allocations for this sequence */
            for (uint32_t j = 0; j < i; ++j) {
                push_free_block(seq_table[j]);
                seq_table[j] = -1;
            }
            return -1;
        }
        seq_table[i] = blk;
    }

    g_kv_allocator.seq_block_count[seq_id] = (uint16_t)needed;
    return (int)needed;
}

/* --------------------------------------------------------------
 * Append tokens: allocate additional blocks if needed.
 * -------------------------------------------------------------- */
int sov_kv_append_tokens(int32_t seq_id, uint32_t num_new_tokens) {
    if (!g_kv_allocator.initialized) return -1;
    if (seq_id < 0 || seq_id >= SOV_MAX_SEQS) return -1;

    uint32_t current_blocks = g_kv_allocator.seq_block_count[seq_id];
    if (current_blocks == 0) return -1; /* sequence not allocated */

    uint32_t current_tokens = current_blocks * SOV_KV_BLOCK_SIZE;
    uint32_t new_total_tokens = current_tokens + num_new_tokens;
    uint32_t new_total_blocks = tokens_to_blocks(new_total_tokens);
    uint32_t max_allowed = SOV_KV_MAX_BLOCKS_PER_SEQ;
    if (new_total_blocks > max_allowed) new_total_blocks = max_allowed;

    uint32_t blocks_to_add = new_total_blocks - current_blocks;
    if (blocks_to_add == 0) return 0;

    int32_t* seq_table = &g_kv_allocator.block_table[seq_id * SOV_KV_MAX_BLOCKS_PER_SEQ];

    for (uint32_t i = 0; i < blocks_to_add; ++i) {
        int32_t blk = pop_free_block();
        if (blk < 0) {
            /* OOM: rollback */
            for (uint32_t j = 0; j < i; ++j) {
                push_free_block(seq_table[current_blocks + j]);
                seq_table[current_blocks + j] = -1;
            }
            return -1;
        }
        seq_table[current_blocks + i] = blk;
    }

    g_kv_allocator.seq_block_count[seq_id] = (uint16_t)new_total_blocks;
    return 0;
}

/* --------------------------------------------------------------
 * Free all blocks for a sequence.
 * -------------------------------------------------------------- */
void sov_kv_free_sequence(int32_t seq_id) {
    if (!g_kv_allocator.initialized) return;
    if (seq_id < 0 || seq_id >= SOV_MAX_SEQS) return;

    uint32_t count = g_kv_allocator.seq_block_count[seq_id];
    if (count == 0) return;

    int32_t* seq_table = &g_kv_allocator.block_table[seq_id * SOV_KV_MAX_BLOCKS_PER_SEQ];

    for (uint32_t i = 0; i < count; ++i) {
        int32_t blk = seq_table[i];
        if (blk >= 0) {
            push_free_block(blk);
            seq_table[i] = -1;
        }
    }

    g_kv_allocator.seq_block_count[seq_id] = 0;
}

/* --------------------------------------------------------------
 * Copy block_table (host) -> device memory for flash_attention kernel.
 * Caller must have allocated d_block_table of size
 * SOV_MAX_SEQS * SOV_KV_MAX_BLOCKS_PER_SEQ * sizeof(int32_t).
 * -------------------------------------------------------------- */
int sov_kv_copy_block_table_to_device(void* d_block_table) {
    if (!g_kv_allocator.initialized) return -1;
    const size_t bytes = SOV_MAX_SEQS * SOV_KV_MAX_BLOCKS_PER_SEQ * sizeof(int32_t);
    CUresult err = g_cuMemcpyHtoD_v2((CUdeviceptr)d_block_table,
                                      g_kv_allocator.block_table,
                                      bytes);
    return (err == CUDA_SUCCESS) ? 0 : -1;
}

/* --------------------------------------------------------------
 * Get GPU pointer for a specific block.
 * Each block contains [K_buffer, V_buffer] contiguous.
 * K_buffer: SOV_MAX_HEADS * KV_BLOCK_SIZE * head_dim * half
 * V_buffer: same size immediately after.
 * -------------------------------------------------------------- */
void* sov_kv_get_block_ptr(int32_t seq_id, uint32_t block_idx) {
    if (!g_kv_allocator.initialized) return 0;
    if (seq_id < 0 || seq_id >= SOV_MAX_SEQS) return 0;
    if (block_idx >= SOV_KV_MAX_BLOCKS_PER_SEQ) return 0;

    int32_t phys_blk = g_kv_allocator.block_table[seq_id * SOV_KV_MAX_BLOCKS_PER_SEQ + block_idx];
    if (phys_blk < 0) return 0;

    const size_t head_dim = 128;
    const size_t bytes_per_block = 2 * SOV_MAX_HEADS * SOV_KV_BLOCK_SIZE * head_dim * sizeof(uint16_t);
    char* base = (char*)g_kv_allocator.gpu_kv_base;
    return base + (size_t)phys_blk * bytes_per_block;
}

/* -------------------------------------------------------------- */
uint32_t sov_kv_get_seq_block_count(int32_t seq_id) {
    if (!g_kv_allocator.initialized) return 0;
    if (seq_id < 0 || seq_id >= SOV_MAX_SEQS) return 0;
    return g_kv_allocator.seq_block_count[seq_id];
}

/* -------------------------------------------------------------- */
void sov_kv_allocator_shutdown(void) {
    if (!g_kv_allocator.initialized) return;
    if (g_kv_allocator.gpu_kv_base) {
        g_cuMemFree_v2((CUdeviceptr)g_kv_allocator.gpu_kv_base);
        g_kv_allocator.gpu_kv_base = 0;
    }
    g_kv_allocator.initialized = 0;
}
