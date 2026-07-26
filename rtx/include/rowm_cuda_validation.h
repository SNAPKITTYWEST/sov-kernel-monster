#pragma once
#include "sov_rtx.h"
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SOV_CUDA_VALIDATION_SCHEMA_VERSION 1u
#define SOV_CUDA_KERNEL_ABI_VERSION        1u
#define SOV_CUDA_KV_LAYOUT_VERSION         1u
#define SOV_ROWM_CUDA_COMMIT_VERSION       1u

enum {
    SOV_CUDA_VALIDATION_JIT_ACCEPTED      = 1u << 0,
    SOV_CUDA_VALIDATION_SYMBOLS_RESOLVED  = 1u << 1,
    SOV_CUDA_VALIDATION_POWER_BOUND       = 1u << 2,
    SOV_CUDA_VALIDATION_JANET_CONFIGURED  = 1u << 3,
    SOV_CUDA_VALIDATION_TENSOR_GEMM_READY = 1u << 4,
    SOV_CUDA_VALIDATION_SCALAR_GEMM_READY = 1u << 5,
    SOV_CUDA_VALIDATION_KV_LAYOUT_CHECKED = 1u << 6,
    SOV_CUDA_VALIDATION_KNOWN_ANSWER_TEST = 1u << 7
};

#define SOV_CUDA_VALIDATION_REQUIRED_FLAGS              \
    (SOV_CUDA_VALIDATION_JIT_ACCEPTED                   \
     | SOV_CUDA_VALIDATION_SYMBOLS_RESOLVED             \
     | SOV_CUDA_VALIDATION_POWER_BOUND                  \
     | SOV_CUDA_VALIDATION_JANET_CONFIGURED             \
     | SOV_CUDA_VALIDATION_TENSOR_GEMM_READY            \
     | SOV_CUDA_VALIDATION_SCALAR_GEMM_READY            \
     | SOV_CUDA_VALIDATION_KV_LAYOUT_CHECKED)

enum {
    SOV_CUDA_ROWM_OK                = 0,
    SOV_CUDA_ROWM_INVALID_ARGUMENT  = -1001,
    SOV_CUDA_ROWM_UNBOUND           = -1002,
    SOV_CUDA_ROWM_BIND_CONFLICT     = -1003,
    SOV_CUDA_ROWM_COMMIT_FAILED     = -1004,
    SOV_CUDA_ROWM_INVALID_PROOF     = -1005,
    SOV_CUDA_ROWM_UNAUTHORIZED      = -1006,
    SOV_CUDA_ROWM_STALE_CONTEXT     = -1007,
    SOV_CUDA_ROWM_EVIDENCE_MISMATCH = -1008
};

typedef struct {
    const uint8_t* bytes;
    size_t         size;
} sov_cuda_validation_bytes_t;

typedef struct {
    uint32_t schema_version;
    uint32_t backend_id;
    uint32_t driver_version;
    uint32_t compute_capability_major;
    uint32_t compute_capability_minor;
    uint32_t ptx_target;
    uint32_t kernel_abi_version;
    uint32_t scalar_storage_bits;
    uint32_t accumulator_storage_bits;
    uint32_t kv_layout_version;
    uint32_t validation_result;
    uint32_t validation_flags;
    uint64_t resolved_kernel_mask;
    uint64_t cuda_context_generation;
    uint8_t  device_uuid[16];
    sov_cuda_validation_bytes_t flash_ptx;
    sov_cuda_validation_bytes_t gemm_ptx;
} sov_cuda_validation_evidence_t;

typedef struct {
    uint32_t version;
    uint32_t reserved;
    uint64_t validation_epoch;
    uint8_t  record_id[32];
    uint8_t  committed_rowm_root[32];
    uint8_t  embedded_worm_receipt_hash[32];
} sov_rowm_cuda_validation_commit_t;

typedef int (*sov_rowm_commit_cuda_validation_fn)(
    void* rowm_context,
    const sov_cuda_validation_evidence_t* evidence,
    sov_rowm_cuda_validation_commit_t* commit_out);

int  sov_cuda_validation_bind_rowm(
    sov_rowm_commit_cuda_validation_fn commit_fn,
    void* rowm_context);
int  sov_cuda_validation_commit_rowm(
    const sov_cuda_validation_evidence_t* evidence);
int  sov_cuda_validation_require_authorized(uint64_t cuda_context_generation);
int  sov_cuda_validation_get_commit(sov_rowm_cuda_validation_commit_t* commit_out);
void sov_cuda_validation_clear(void);

#ifdef __cplusplus
}
#endif
