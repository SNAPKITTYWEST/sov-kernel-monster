#pragma once
#include <stdint.h>
#include <stddef.h>

#define SOV_MAX_SEQS     256
#define SOV_MAX_HEADS    128
#define SOV_KV_BLOCK_SIZE 16
#define SOV_JANET_SLOTS   32

typedef enum {
    SOV_POWER_ACTIVE      = 0,
    SOV_POWER_SUSPEND     = 1,
    SOV_POWER_RESUME      = 2,
    SOV_POWER_LOW_BATTERY = 3
} sov_power_state_t;

typedef enum {
    SOV_SCHED_IDLE       = 0,
    SOV_SCHED_PREFILL    = 1,
    SOV_SCHED_GENERATE   = 2,
    SOV_SCHED_SWAP       = 3,
    SOV_SCHED_CHECKPOINT = 4,
    SOV_SCHED_RESUME     = 5
} sov_sched_state_t;

typedef struct {
    uint32_t type_tag;
    uint32_t length;
    uint32_t capacity;
    float    data[SOV_JANET_SLOTS];
} sov_janet_array_t;

typedef struct {
    uint32_t block_id;
    uint32_t seq_id;
    uint32_t layer;
    uint32_t token_offset;
    float*   k_data;
    float*   v_data;
} sov_kv_block_t;

typedef struct {
    sov_sched_state_t state;
    uint32_t          batch_size;
    sov_janet_array_t janet;
} sov_scheduler_t;

typedef struct {
    uint8_t  votes[5];
    uint32_t quorum;
    uint32_t height;
} sov_bft_state_t;

typedef struct {
    uint8_t blake3[32];
    uint8_t ed25519[64];
} sov_worm_receipt_t;

/* CUDA */
int   sov_cuda_init(void);
int   sov_cuda_load_ptx(const char* ptx_data, unsigned int ptx_size, void** module_out);
int   sov_cuda_flash_attention(int seqs, int heads, float* q, float* k, float* v,
                               float* out, int* block_table, int* seq_lens,
                               int head_dim, int block_size);
void* sov_cuda_malloc(size_t size);
int   sov_cuda_memcpy_h2d(void* dst, const void* src, size_t size);

/* Scheduler */
int sov_scheduler_init(sov_scheduler_t* sched);
int sov_scheduler_step(sov_scheduler_t* sched, void* batch_ptr, void* kv_ptr);

/* KV Cache */
int sov_kv_init(void* kv_store, int n_layers, int n_kv_heads, int head_dim, int block_size, int max_blocks);
int sov_kv_allocate_blocks(void* kv_store, int seq_id, int n_blocks, int* block_table);
int sov_kv_append_tokens(void* kv_store, int* block_table, float* k, float* v, int layer, int token_pos);

/* GGUF */
int         sov_gguf_load(const char* path, void** ctx_out);
const void* sov_gguf_get_tensor(void* ctx, const char* name);

/* BFT */
int sov_bft_vote(sov_bft_state_t* bft, uint8_t vote);
int sov_bft_check_quorum(const sov_bft_state_t* bft);

/* WORM */
int sov_worm_checkpoint(void* kv_ptr);
int sov_worm_restore(void* kv_ptr);

/* Power */
int               sov_set_power_state(sov_power_state_t state);
sov_power_state_t sov_get_power_state(void);

/* Speculative */
int sov_speculative_draft(void* batch_ptr, int draft_len, void* kv_ptr);
int sov_speculative_verify(void* draft_logits, void* target_logits, int len);

/* Janet */
float sov_janet_get(int slot);
void  sov_janet_set(int slot, float val);
