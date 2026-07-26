#include "rowm_cuda_validation.h"
#include <stdint.h>
#include <stddef.h>

typedef struct {
    sov_rowm_commit_cuda_validation_fn    commit_fn;
    void*                                 rowm_context;
    sov_cuda_validation_evidence_t        evidence;
    sov_rowm_cuda_validation_commit_t     commit;
    int                                   authorized;
} sov_cuda_validation_state_t;

static sov_cuda_validation_state_t g_validation;

static void zero_bytes(void* dst, size_t size) {
    uint8_t* b = (uint8_t*)dst;
    size_t i;
    for (i = 0; i < size; ++i) b[i] = 0;
}

static int bytes_are_nonzero(const uint8_t* bytes, size_t size) {
    uint8_t acc = 0;
    size_t i;
    if (!bytes) return 0;
    for (i = 0; i < size; ++i) acc = (uint8_t)(acc | bytes[i]);
    return acc != 0;
}

static int bytes_equal(const uint8_t* left, const uint8_t* right, size_t size) {
    size_t i;
    if (!left || !right) return 0;
    for (i = 0; i < size; ++i)
        if (left[i] != right[i]) return 0;
    return 1;
}

static int evidence_is_valid(const sov_cuda_validation_evidence_t* ev) {
    if (!ev
            || ev->schema_version != SOV_CUDA_VALIDATION_SCHEMA_VERSION
            || ev->backend_id == 0
            || ev->driver_version == 0
            || ev->compute_capability_major == 0
            || ev->ptx_target == 0
            || ev->kernel_abi_version != SOV_CUDA_KERNEL_ABI_VERSION
            || ev->scalar_storage_bits != 16u
            || ev->accumulator_storage_bits != 32u
            || ev->kv_layout_version != SOV_CUDA_KV_LAYOUT_VERSION
            || ev->validation_result != 0
            || (ev->validation_flags & SOV_CUDA_VALIDATION_REQUIRED_FLAGS)
                != SOV_CUDA_VALIDATION_REQUIRED_FLAGS
            || ev->resolved_kernel_mask == 0
            || ev->cuda_context_generation == 0
            || !bytes_are_nonzero(ev->device_uuid, sizeof(ev->device_uuid))
            || !ev->flash_ptx.bytes || ev->flash_ptx.size == 0
            || !ev->gemm_ptx.bytes  || ev->gemm_ptx.size == 0) {
        return 0;
    }
    return 1;
}

static int commit_is_valid(const sov_rowm_cuda_validation_commit_t* c) {
    return c
        && c->version == SOV_ROWM_CUDA_COMMIT_VERSION
        && c->reserved == 0
        && c->validation_epoch != 0
        && bytes_are_nonzero(c->record_id,              sizeof(c->record_id))
        && bytes_are_nonzero(c->committed_rowm_root,    sizeof(c->committed_rowm_root))
        && bytes_are_nonzero(c->embedded_worm_receipt_hash,
                             sizeof(c->embedded_worm_receipt_hash));
}

static int evidence_equal(const sov_cuda_validation_evidence_t* l,
                          const sov_cuda_validation_evidence_t* r) {
    if (!l || !r
            || l->schema_version != r->schema_version
            || l->backend_id != r->backend_id
            || l->driver_version != r->driver_version
            || l->compute_capability_major != r->compute_capability_major
            || l->compute_capability_minor != r->compute_capability_minor
            || l->ptx_target != r->ptx_target
            || l->kernel_abi_version != r->kernel_abi_version
            || l->scalar_storage_bits != r->scalar_storage_bits
            || l->accumulator_storage_bits != r->accumulator_storage_bits
            || l->kv_layout_version != r->kv_layout_version
            || l->validation_result != r->validation_result
            || l->validation_flags != r->validation_flags
            || l->resolved_kernel_mask != r->resolved_kernel_mask
            || l->cuda_context_generation != r->cuda_context_generation
            || l->flash_ptx.size != r->flash_ptx.size
            || l->gemm_ptx.size  != r->gemm_ptx.size
            || !bytes_equal(l->device_uuid, r->device_uuid, sizeof(l->device_uuid))
            || !bytes_equal(l->flash_ptx.bytes, r->flash_ptx.bytes, l->flash_ptx.size)
            || !bytes_equal(l->gemm_ptx.bytes,  r->gemm_ptx.bytes,  l->gemm_ptx.size)) {
        return 0;
    }
    return 1;
}

int sov_cuda_validation_bind_rowm(sov_rowm_commit_cuda_validation_fn commit_fn,
                                   void* rowm_context) {
    if (!commit_fn || !rowm_context)       return SOV_CUDA_ROWM_INVALID_ARGUMENT;
    if (g_validation.authorized)           return SOV_CUDA_ROWM_BIND_CONFLICT;
    if (g_validation.commit_fn) {
        return (g_validation.commit_fn == commit_fn
                && g_validation.rowm_context == rowm_context)
            ? SOV_CUDA_ROWM_OK
            : SOV_CUDA_ROWM_BIND_CONFLICT;
    }
    g_validation.commit_fn    = commit_fn;
    g_validation.rowm_context = rowm_context;
    return SOV_CUDA_ROWM_OK;
}

int sov_cuda_validation_commit_rowm(const sov_cuda_validation_evidence_t* evidence) {
    sov_rowm_cuda_validation_commit_t commit;
    int result;

    if (!g_validation.commit_fn || !g_validation.rowm_context)
        return SOV_CUDA_ROWM_UNBOUND;
    if (!evidence_is_valid(evidence))
        return SOV_CUDA_ROWM_INVALID_ARGUMENT;

    if (g_validation.authorized) {
        if (evidence->cuda_context_generation
                != g_validation.evidence.cuda_context_generation) {
            g_validation.authorized = 0;
            zero_bytes(&g_validation.commit, sizeof(g_validation.commit));
            return SOV_CUDA_ROWM_STALE_CONTEXT;
        }
        return evidence_equal(evidence, &g_validation.evidence)
            ? SOV_CUDA_ROWM_OK
            : SOV_CUDA_ROWM_EVIDENCE_MISMATCH;
    }

    zero_bytes(&commit, sizeof(commit));
    result = g_validation.commit_fn(g_validation.rowm_context, evidence, &commit);
    if (result != 0)              return SOV_CUDA_ROWM_COMMIT_FAILED;
    if (!commit_is_valid(&commit)) return SOV_CUDA_ROWM_INVALID_PROOF;

    g_validation.evidence   = *evidence;
    g_validation.commit     = commit;
    g_validation.authorized = 1;
    return SOV_CUDA_ROWM_OK;
}

int sov_cuda_validation_require_authorized(uint64_t cuda_context_generation) {
    if (!g_validation.authorized) return SOV_CUDA_ROWM_UNAUTHORIZED;
    if (cuda_context_generation == 0
            || cuda_context_generation
                != g_validation.evidence.cuda_context_generation) {
        g_validation.authorized = 0;
        zero_bytes(&g_validation.commit, sizeof(g_validation.commit));
        return SOV_CUDA_ROWM_STALE_CONTEXT;
    }
    return SOV_CUDA_ROWM_OK;
}

int sov_cuda_validation_get_commit(sov_rowm_cuda_validation_commit_t* commit_out) {
    if (!commit_out) return SOV_CUDA_ROWM_INVALID_ARGUMENT;
    if (!g_validation.authorized) {
        zero_bytes(commit_out, sizeof(*commit_out));
        return SOV_CUDA_ROWM_UNAUTHORIZED;
    }
    *commit_out = g_validation.commit;
    return SOV_CUDA_ROWM_OK;
}

void sov_cuda_validation_clear(void) {
    zero_bytes(&g_validation, sizeof(g_validation));
}
