#pragma once
#include <stddef.h>
#include <stdint.h>
#include "cuda_driver_loader.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Static capacity constants — must match the values used by flash_attention.ptx */
#define SOV_KV_TOTAL_BLOCKS       4096
#define SOV_KV_MAX_BLOCKS_PER_SEQ  256

typedef struct {
    uint32_t layer_count;
    uint32_t kv_head_count;
    uint32_t head_dim;
    uint32_t physical_block_count;
    uint32_t element_bytes;   /* 2 for f16 */
} sov_kv_allocator_config_t;

/* Lifecycle */
int  sov_kv_allocator_init(void);
void sov_kv_allocator_shutdown(void);

/* Configuration query — fills *cfg, returns 0 on success */
int sov_kv_get_config(sov_kv_allocator_config_t* cfg);

/* Typed stride accessors — all return byte counts */
size_t sov_kv_get_token_stride(void);
size_t sov_kv_get_page_stride(void);
size_t sov_kv_get_layer_stride(void);
size_t sov_kv_get_plane_stride(void);

/* GPU base pointers (0 when not initialized) */
CUdeviceptr sov_kv_get_k_base(void);
CUdeviceptr sov_kv_get_v_base(void);

/* Block table management — block_table[seq][logical_block] = physical_block */
int sov_kv_allocate_blocks(int seq_id, int n_blocks, int32_t* block_table_row);
int sov_kv_free_sequence(int seq_id);

/* Legacy sov_rtx.h surface */
int sov_kv_init(void* kv_store, int n_layers, int n_kv_heads, int head_dim,
                int block_size, int max_blocks);
int sov_kv_allocate_blocks_legacy(void* kv_store, int seq_id, int n_blocks,
                                  int* block_table);
int sov_kv_append_tokens(void* kv_store, int* block_table, float* k, float* v,
                         int layer, int token_pos);

#ifdef __cplusplus
}
#endif
