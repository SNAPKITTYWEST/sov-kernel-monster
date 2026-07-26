#ifndef SOV_KV_ALLOCATOR_H
#define SOV_KV_ALLOCATOR_H

#include "sov_rtx.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * KV Block Allocator — zero-malloc, static free-list
 * Matches vLLM PagedAttention block_table layout exactly.
 * ============================================================ */

#define SOV_KV_MAX_BLOCKS_PER_SEQ (SOV_MAX_SEQ_LEN / SOV_KV_BLOCK_SIZE) /* 2048/16 = 128 */
#define SOV_KV_TOTAL_BLOCKS (SOV_MAX_SEQS * SOV_KV_MAX_BLOCKS_PER_SEQ) /* 256 * 128 = 32768 */

typedef struct {
    /* Block table: [seq_id * max_blocks_per_seq + block_idx] = physical_block_id (or -1) */
    int32_t block_table[SOV_MAX_SEQS * SOV_KV_MAX_BLOCKS_PER_SEQ];

    /* Free list: stack of available physical block IDs */
    int32_t free_list[SOV_KV_TOTAL_BLOCKS];
    int32_t free_top; /* index of next free slot (0 = empty) */

    /* Per-sequence allocation count */
    uint16_t seq_block_count[SOV_MAX_SEQS];

    /* GPU memory base pointer for KV cache (set at init) */
    void* gpu_kv_base; /* cuMemAlloc'd region */
    size_t gpu_kv_bytes; /* total bytes allocated */

    /* Initialization flag */
    int initialized;
} sov_kv_allocator_t;

/* Global singleton instance */
extern sov_kv_allocator_t g_kv_allocator;

/* Initialize allocator: reserve GPU memory, build free list.
 * Returns 0 on success, -1 on failure. */
int sov_kv_allocator_init(void);

/* Allocate 'num_tokens' worth of KV blocks for a sequence.
 * Returns number of blocks allocated (>= 0), or -1 on OOM. */
int sov_kv_allocate_blocks(int32_t seq_id, uint32_t num_tokens);

/* Append 'num_new_tokens' to an existing sequence.
 * Returns 0 on success, -1 on OOM. */
int sov_kv_append_tokens(int32_t seq_id, uint32_t num_new_tokens);

/* Release all blocks owned by a sequence back to free list. */
void sov_kv_free_sequence(int32_t seq_id);

/* Copy block_table to GPU (must be called before each flash_attention launch). */
int sov_kv_copy_block_table_to_device(void* d_block_table);

/* Get physical GPU address for a (seq_id, block_idx) pair. Returns 0 if not allocated. */
void* sov_kv_get_block_ptr(int32_t seq_id, uint32_t block_idx);

/* Get number of blocks currently allocated to a sequence. */
uint32_t sov_kv_get_seq_block_count(int32_t seq_id);

/* Shutdown: free GPU memory. */
void sov_kv_allocator_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif /* SOV_KV_ALLOCATOR_H */
