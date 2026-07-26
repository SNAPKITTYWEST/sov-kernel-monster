#include "kv_allocator.h"
#include "cuda_driver_loader.h"
#include "sov_rtx.h"

#include <stdint.h>
#include <stddef.h>

/*
 * KV block allocator — static free-list, separate K/V planes.
 *
 * Physical layout per plane (bytes):
 *   [layer][physical_block][token_in_block][kv_head][head_dim × element_bytes]
 *
 * Strides:
 *   token_stride = kv_heads * head_dim * element_bytes
 *   page_stride  = SOV_KV_BLOCK_SIZE * token_stride
 *   layer_stride = physical_blocks * page_stride
 *   plane_stride = layers * layer_stride
 */

/* Capacity */
#define SOV_KV_FREE_STACK_SIZE SOV_KV_TOTAL_BLOCKS

typedef struct {
    /* GPU allocation */
    CUdeviceptr         device_base;   /* K plane base; V = device_base + plane_stride */
    size_t              alloc_bytes;

    /* Configuration */
    sov_kv_allocator_config_t config;

    /* Strides (bytes) */
    size_t token_stride;
    size_t page_stride;
    size_t layer_stride;
    size_t plane_stride;

    /* Free list — stack of available physical block IDs */
    int32_t free_stack[SOV_KV_FREE_STACK_SIZE];
    int     free_top;   /* index of next free slot; -1 = empty */

    /* Per-sequence block tables: block_table[seq][logical_block] = physical */
    int32_t block_table[SOV_MAX_SEQS][SOV_KV_MAX_BLOCKS_PER_SEQ];
    int     seq_block_count[SOV_MAX_SEQS]; /* number of allocated blocks */

    int initialized;
} sov_kv_allocator_t;

/* Exported for test_cuda_reference_gpu.c */
sov_kv_allocator_t g_kv_allocator;

/* -----------------------------------------------------------------------
 * Internal helpers
 * ----------------------------------------------------------------------- */

static void zero_bytes(void* dst, size_t size) {
    uint8_t* b = (uint8_t*)dst;
    size_t i;
    for (i = 0; i < size; ++i) b[i] = 0;
}

static int checked_mul_size(size_t a, size_t b, size_t* out) {
    if (a != 0 && b > (size_t)-1 / a) return -1;
    *out = a * b;
    return 0;
}

/* -----------------------------------------------------------------------
 * sov_kv_allocator_init_with_config — real init used by both production
 * and test paths.
 * ----------------------------------------------------------------------- */
int sov_kv_allocator_init_with_config(const sov_kv_allocator_config_t* cfg) {
    size_t token_stride, page_stride, layer_stride, plane_stride, alloc_bytes;
    CUdeviceptr device_base;
    CUresult result;
    int i;

    if (!cfg
            || cfg->layer_count == 0
            || cfg->kv_head_count == 0
            || cfg->head_dim == 0
            || cfg->physical_block_count == 0
            || cfg->physical_block_count > SOV_KV_TOTAL_BLOCKS
            || cfg->element_bytes == 0
            || cfg->element_bytes > 4) {
        return -1;
    }

    /* Compute strides */
    if (checked_mul_size(cfg->kv_head_count, cfg->head_dim, &token_stride) != 0
            || checked_mul_size(token_stride, cfg->element_bytes, &token_stride) != 0
            || checked_mul_size(SOV_KV_BLOCK_SIZE, token_stride, &page_stride) != 0
            || checked_mul_size(cfg->physical_block_count, page_stride, &layer_stride) != 0
            || checked_mul_size(cfg->layer_count, layer_stride, &plane_stride) != 0
            || checked_mul_size(2, plane_stride, &alloc_bytes) != 0) {
        return -1;
    }

    /* Allocate GPU memory */
    result = sov_cuda_mem_alloc(&device_base, alloc_bytes);
    if (result != CUDA_SUCCESS) return -1;

    zero_bytes(&g_kv_allocator, sizeof(g_kv_allocator));
    g_kv_allocator.device_base   = device_base;
    g_kv_allocator.alloc_bytes   = alloc_bytes;
    g_kv_allocator.config        = *cfg;
    g_kv_allocator.token_stride  = token_stride;
    g_kv_allocator.page_stride   = page_stride;
    g_kv_allocator.layer_stride  = layer_stride;
    g_kv_allocator.plane_stride  = plane_stride;

    /* Initialize free list: push blocks in reverse order so block 0 is
     * allocated first, making tests deterministic. */
    g_kv_allocator.free_top = (int)cfg->physical_block_count - 1;
    for (i = 0; i < (int)cfg->physical_block_count; ++i)
        g_kv_allocator.free_stack[i] = (int32_t)((int)cfg->physical_block_count - 1 - i);

    /* Initialize block tables to -1 (no block) */
    for (i = 0; i < SOV_MAX_SEQS; ++i) {
        int j;
        g_kv_allocator.seq_block_count[i] = 0;
        for (j = 0; j < SOV_KV_MAX_BLOCKS_PER_SEQ; ++j)
            g_kv_allocator.block_table[i][j] = -1;
    }

    g_kv_allocator.initialized = 1;
    return 0;
}

int sov_kv_allocator_init(void) {
    /* Default configuration matching flash_attention.ptx expectations */
    sov_kv_allocator_config_t cfg;
    cfg.layer_count          = 32;
    cfg.kv_head_count        = 8;
    cfg.head_dim             = 128;
    cfg.physical_block_count = SOV_KV_TOTAL_BLOCKS;
    cfg.element_bytes        = 2; /* f16 */
    return sov_kv_allocator_init_with_config(&cfg);
}

void sov_kv_allocator_shutdown(void) {
    if (!g_kv_allocator.initialized) return;
    if (g_kv_allocator.device_base)
        (void)sov_cuda_mem_free(g_kv_allocator.device_base);
    zero_bytes(&g_kv_allocator, sizeof(g_kv_allocator));
}

/* -----------------------------------------------------------------------
 * Config and stride accessors
 * ----------------------------------------------------------------------- */

int sov_kv_get_config(sov_kv_allocator_config_t* cfg) {
    if (!g_kv_allocator.initialized || !cfg) return -1;
    *cfg = g_kv_allocator.config;
    return 0;
}

size_t      sov_kv_get_token_stride(void) { return g_kv_allocator.token_stride; }
size_t      sov_kv_get_page_stride(void)  { return g_kv_allocator.page_stride; }
size_t      sov_kv_get_layer_stride(void) { return g_kv_allocator.layer_stride; }
size_t      sov_kv_get_plane_stride(void) { return g_kv_allocator.plane_stride; }
CUdeviceptr sov_kv_get_k_base(void)       { return g_kv_allocator.device_base; }
CUdeviceptr sov_kv_get_v_base(void) {
    if (!g_kv_allocator.initialized) return 0;
    return g_kv_allocator.device_base + (CUdeviceptr)g_kv_allocator.plane_stride;
}

/* -----------------------------------------------------------------------
 * Block allocation
 * ----------------------------------------------------------------------- */

int sov_kv_allocate_blocks(int seq_id, int n_tokens) {
    int n_blocks_needed;
    int already;
    int i;

    if (!g_kv_allocator.initialized
            || seq_id < 0 || seq_id >= SOV_MAX_SEQS
            || n_tokens <= 0) return -1;

    n_blocks_needed = (n_tokens + SOV_KV_BLOCK_SIZE - 1) / SOV_KV_BLOCK_SIZE;
    already = g_kv_allocator.seq_block_count[seq_id];

    if (already + n_blocks_needed > SOV_KV_MAX_BLOCKS_PER_SEQ) return -1;
    if (g_kv_allocator.free_top + 1 < n_blocks_needed) return -1;

    for (i = 0; i < n_blocks_needed; ++i) {
        int32_t phys = g_kv_allocator.free_stack[g_kv_allocator.free_top--];
        g_kv_allocator.block_table[seq_id][already + i] = phys;
    }
    g_kv_allocator.seq_block_count[seq_id] += n_blocks_needed;
    return n_blocks_needed;
}

int sov_kv_free_sequence(int seq_id) {
    int i;
    if (!g_kv_allocator.initialized
            || seq_id < 0 || seq_id >= SOV_MAX_SEQS) return -1;
    for (i = 0; i < g_kv_allocator.seq_block_count[seq_id]; ++i) {
        int32_t phys = g_kv_allocator.block_table[seq_id][i];
        if (phys >= 0) {
            g_kv_allocator.free_stack[++g_kv_allocator.free_top] = phys;
            g_kv_allocator.block_table[seq_id][i] = -1;
        }
    }
    g_kv_allocator.seq_block_count[seq_id] = 0;
    return 0;
}

/* Copy block table for seq 0 to GPU (used by GPU tests) */
int sov_kv_copy_block_table_to_device(CUdeviceptr d_table) {
    if (!g_kv_allocator.initialized || !d_table) return -1;
    return sov_cuda_memcpy_h2d(
        (void*)(uintptr_t)d_table,
        g_kv_allocator.block_table[0],
        (size_t)SOV_KV_TOTAL_BLOCKS * sizeof(int32_t));
}

/* -----------------------------------------------------------------------
 * Legacy sov_rtx.h surface
 * ----------------------------------------------------------------------- */

int sov_kv_init(void* kv_store, int n_layers, int n_kv_heads, int head_dim,
                int block_size, int max_blocks) {
    sov_kv_allocator_config_t cfg;
    (void)kv_store; (void)block_size; (void)max_blocks;
    cfg.layer_count          = (uint32_t)n_layers;
    cfg.kv_head_count        = (uint32_t)n_kv_heads;
    cfg.head_dim             = (uint32_t)head_dim;
    cfg.physical_block_count = SOV_KV_TOTAL_BLOCKS;
    cfg.element_bytes        = 2;
    return sov_kv_allocator_init_with_config(&cfg);
}

int sov_kv_allocate_blocks_legacy(void* kv_store, int seq_id, int n_blocks,
                                  int* block_table) {
    int result, i;
    (void)kv_store;
    result = sov_kv_allocate_blocks(seq_id, n_blocks * SOV_KV_BLOCK_SIZE);
    if (result < 0) return result;
    if (block_table) {
        for (i = 0; i < result; ++i)
            block_table[i] = g_kv_allocator.block_table[seq_id][i];
    }
    return result;
}

int sov_kv_append_tokens(void* kv_store, int* block_table, float* k, float* v,
                         int layer, int token_pos) {
    /* Stub — actual K/V writes happen via GEMM + attention kernels */
    (void)kv_store; (void)block_table; (void)k; (void)v;
    (void)layer; (void)token_pos;
    return 0;
}
