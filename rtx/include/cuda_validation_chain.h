#pragma once
#include <stdint.h>
#include <stddef.h>

#define SOV_ROWM_HASH_LEN    32
#define SOV_ROWM_MAX_KERNELS 5

typedef enum {
    SOV_ROWM_IDLE       = 0,
    SOV_ROWM_COMMITTED  = 1,
    SOV_ROWM_AUTHORIZED = 2,
    SOV_ROWM_CONFLICT   = 3
} sov_rowm_state_t;

typedef struct {
    uint8_t  ptx_hash[SOV_ROWM_HASH_LEN];
    uint32_t abi_version;
    uint64_t device_epoch;
    uint32_t ptx_len;
} sov_ptx_evidence_t;

typedef struct {
    sov_ptx_evidence_t evidence;
    uint64_t           sequence;
    uint8_t            rowm_root[SOV_ROWM_HASH_LEN];
    uint8_t            worm_receipt[SOV_ROWM_HASH_LEN];
    sov_rowm_state_t   state;
} sov_rowm_record_t;

typedef struct {
    void*    handles[SOV_ROWM_MAX_KERNELS];
    uint32_t count;
    uint8_t  bound_worm[SOV_ROWM_HASH_LEN];
} sov_cuda_auth_t;

/* Hash PTX bytes into evidence.
 * Serialization: [abi_version BE4][device_epoch BE8][ptx_len BE4][ptx_len bytes]
 * No pointers, no padding, no raw struct image.
 */
int sov_ptx_hash(const uint8_t* ptx, uint32_t ptx_len,
                 uint32_t abi_version, uint64_t device_epoch,
                 sov_ptx_evidence_t* ev_out);

/* Commit PTX evidence through ROWM-NR.
 * Returns  0  : committed, worm_receipt is durable.
 * Returns -1  : null input.
 * Returns -2  : same epoch, different PTX — conflict, state set to CONFLICT.
 * Idempotent  : same epoch + same ptx_hash → returns 0, sequence/receipt unchanged.
 */
int sov_rowm_commit(sov_rowm_record_t* rec, const sov_ptx_evidence_t* ev);

/* Bind exactly `count` kernel handles to the committed WORM receipt.
 * Returns  0  : authorized.
 * Returns -1  : rec not in COMMITTED state (must commit first).
 * Returns -4  : count exceeds SOV_ROWM_MAX_KERNELS.
 */
int sov_rowm_authorize_kernels(sov_rowm_record_t* rec, sov_cuda_auth_t* auth,
                               void** handles, uint32_t count);

/* Check auth is still bound to rec's current WORM receipt.
 * Returns  0  : valid.
 * Returns -1  : rec not AUTHORIZED.
 * Returns -2  : WORM receipt mismatch — stale or tampered.
 */
int sov_rowm_check_authorized(const sov_rowm_record_t* rec,
                              const sov_cuda_auth_t* auth);

/* Kernel wrappers — implemented in cuda_kernels.c */
void sov_cuda_kernels_set_auth(sov_rowm_record_t* rec, sov_cuda_auth_t* auth);
/* Must be called after cuLaunchKernel is resolved from nvcuda.dll */
void sov_cuda_kernels_set_launch_fn(void* fn);

int sov_cuda_flash_attention(int seqs, int heads,
                             float* q, float* k, float* v, float* out,
                             int* block_table, int* seq_lens,
                             int head_dim, int block_size);

int sov_cuda_gemm(float* a, float* b, float* c, int m, int n, int k_dim);

/* Gate: fn must be one of auth->handles; returns -3 if not authorized, -5 if fn not bound. */
int sov_cuda_launch_kernel(void* fn,
                           unsigned gx, unsigned gy, unsigned gz,
                           unsigned bx, unsigned by, unsigned bz,
                           unsigned shared_mem, void* stream, void** args);
