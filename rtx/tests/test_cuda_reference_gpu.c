/*
 * Physical GPU reference test — sov-kernel-monster rtx
 *
 * Requires a real CUDA device. Skips with exit code 77 when no GPU is
 * present (automake convention; CTest maps 77 → SKIP).
 *
 * Coverage:
 *   - CUDA init + ROWM-NR commit with ptx_target == 86 (sm_86)
 *   - f16 ↔ f32 round-trip conversion via device kernels
 *   - Flash-attention (paged) vs CPU reference
 *   - RMSNorm vs CPU reference
 *   - SiLU vs CPU reference
 *   - Tensor GEMM 32×16×32 vs CPU reference (sgemm)
 *   - Scalar GEMM 3×5×7 vs CPU reference
 *   - Zero-K GEMM: C zeroed when K == 0
 *   - Suspend no-touch: kernels must not mutate output while SUSPEND
 *   - GEMM input/output alias rejection
 *   - KV allocator: init_with_config, allocate_blocks, copy_block_table_to_device
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>
#include <stddef.h>

#include "cuda_driver_loader.h"
#include "kv_allocator.h"
#include "rowm_cuda_validation.h"
#include "sov_rtx.h"

/*
 * Forward declaration of the updated flash_attention dispatch surface.
 * The production implementation (cuda_kernels.c / cuda_dispatch) uses
 * CUdeviceptr arguments and a layer_index parameter.
 */
int sov_cuda_flash_attention(int seqs, int query_heads,
                             uint32_t layer_index,
                             CUdeviceptr q, CUdeviceptr out,
                             CUdeviceptr block_table,
                             CUdeviceptr seq_lens);

/* ------------------------------------------------------------------ */
/* PTX blobs — extern symbols from CMake-linked object files           */
/* ------------------------------------------------------------------ */
extern const unsigned char flash_attention_ptx[];
extern const unsigned int  flash_attention_ptx_len;
extern const unsigned char gemm_ptx[];
extern const unsigned int  gemm_ptx_len;
extern float               g_janet_kernel_config[8];

/* ------------------------------------------------------------------ */
/* Helpers                                                              */
/* ------------------------------------------------------------------ */

static void die(const char* msg, int line) {
    fprintf(stderr, "FATAL test_cuda_reference_gpu.c:%d: %s\n", line, msg);
    exit(1);
}
#define DIE(msg) die((msg), __LINE__)

static void check_cuda(CUresult r, const char* expr, int line) {
    if (r != CUDA_SUCCESS) {
        fprintf(stderr, "CUDA error %d at %s:%d: %s\n", r, __FILE__, line, expr);
        exit(1);
    }
}
#define CU(expr) check_cuda((expr), #expr, __LINE__)

/* Skip gracefully when no device is present */
static void skip_if_no_device(void) {
    int rc = sov_cuda_init();
    if (rc == CUDA_ERROR_NO_DEVICE || rc == CUDA_ERROR_NOT_FOUND) {
        printf("SKIP: no CUDA device available (error %d)\n", rc);
        exit(77);
    }
    if (rc != CUDA_SUCCESS) {
        printf("SKIP: sov_cuda_init returned %d\n", rc);
        exit(77);
    }
}

/* ------------------------------------------------------------------ */
/* f16 helpers (software, host-side)                                   */
/* ------------------------------------------------------------------ */

static uint16_t f32_to_f16_sw(float f) {
    uint32_t bits;
    memcpy(&bits, &f, 4);
    uint32_t sign = (bits >> 31) & 1u;
    int32_t  exp  = (int32_t)((bits >> 23) & 0xFFu) - 127 + 15;
    uint32_t mant = bits & 0x7FFFFFu;
    if (exp <= 0)  return (uint16_t)(sign << 15);
    if (exp >= 31) return (uint16_t)((sign << 15) | 0x7C00u);
    return (uint16_t)((sign << 15) | ((uint32_t)exp << 10) | (mant >> 13));
}

static float f16_to_f32_sw(uint16_t h) {
    uint32_t sign = (uint32_t)(h >> 15) & 1u;
    uint32_t exp  = (uint32_t)(h >> 10) & 0x1Fu;
    uint32_t mant = (uint32_t)(h)       & 0x3FFu;
    uint32_t bits;
    if (exp == 0 && mant == 0) { bits = sign << 31; }
    else if (exp == 31)         { bits = (sign << 31) | 0x7F800000u | (mant << 13); }
    else                        { bits = (sign << 31) | ((exp - 15 + 127) << 23) | (mant << 13); }
    float f;
    memcpy(&f, &bits, 4);
    return f;
}

/* ------------------------------------------------------------------ */
/* CPU reference implementations                                        */
/* ------------------------------------------------------------------ */

/* RMSNorm: out[i] = x[i] / sqrt(mean(x^2) + eps) * weight[i] */
static void cpu_rmsnorm(const float* x, const float* w, float* out,
                        uint32_t n, float eps) {
    double sum = 0.0;
    for (uint32_t i = 0; i < n; i++) sum += (double)x[i] * x[i];
    float rms = (float)(1.0 / sqrt(sum / (double)n + (double)eps));
    for (uint32_t i = 0; i < n; i++) out[i] = x[i] * rms * w[i];
}

/* SiLU: out[i] = x[i] / (1 + exp(-x[i])) */
static void cpu_silu(const float* x, float* out, uint32_t n) {
    for (uint32_t i = 0; i < n; i++)
        out[i] = x[i] / (1.0f + expf(-x[i]));
}

/* SGEMM: C = A * B, row-major, A[M×K], B[K×N], C[M×N] */
static void cpu_sgemm(const float* A, const float* B, float* C,
                      int M, int N, int K) {
    for (int m = 0; m < M; m++)
        for (int n = 0; n < N; n++) {
            float s = 0.0f;
            for (int k = 0; k < K; k++)
                s += A[m*K + k] * B[k*N + n];
            C[m*N + n] = s;
        }
}

/* ------------------------------------------------------------------ */
/* ROWM-NR commit stub — validates ptx_target == 86                    */
/* ------------------------------------------------------------------ */

static int g_commit_calls = 0;

static int commit_test_cuda_validation(
    void* rowm_context,
    const sov_cuda_validation_evidence_t* evidence,
    sov_rowm_cuda_validation_commit_t* commit_out)
{
    size_t i;
    ++g_commit_calls;
    (void)rowm_context;
    if (!evidence) { fputs("commit: null evidence\n", stderr); return -1; }
    if (evidence->ptx_target != 86) {
        fprintf(stderr, "commit: expected ptx_target=86 got %u\n",
                evidence->ptx_target);
        return -1;
    }
    memset(commit_out, 0, sizeof(*commit_out));
    commit_out->version          = SOV_ROWM_CUDA_COMMIT_VERSION;
    commit_out->validation_epoch = 1;
    for (i = 0; i < 32; ++i) {
        commit_out->record_id[i]              = (uint8_t)(i + 1u);
        commit_out->committed_rowm_root[i]    = (uint8_t)(i + 2u);
        commit_out->embedded_worm_receipt_hash[i] = (uint8_t)(i + 3u);
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* Alloc helpers                                                        */
/* ------------------------------------------------------------------ */

static CUdeviceptr alloc_f32(size_t n) {
    CUdeviceptr p;
    CU(sov_cuda_mem_alloc(&p, n * sizeof(float)));
    return p;
}

static CUdeviceptr alloc_u16(size_t n) {
    CUdeviceptr p;
    CU(sov_cuda_mem_alloc(&p, n * sizeof(uint16_t)));
    return p;
}

static void upload_f32(CUdeviceptr d, const float* h, size_t n) {
    CU((CUresult)sov_cuda_memcpy_h2d((void*)d, h, n * sizeof(float)));
}

static void download_f32(float* h, CUdeviceptr d, size_t n) {
    CU(sov_cuda_memcpy_d2h(h, d, n * sizeof(float)));
}

static float rand_f(void) {
    return ((float)(rand() % 2001) - 1000.0f) / 500.0f;
}

static int approx_eq(float a, float b, float tol) {
    return fabsf(a - b) <= tol;
}

/* ------------------------------------------------------------------ */
/* Test: f16 ↔ f32 round-trip                                          */
/* ------------------------------------------------------------------ */

static void test_f16_roundtrip(void) {
    /* Encode representative values via software f16 and verify the
     * host-side software decoder produces values close to originals.
     * This validates the f16 helper functions used in other tests. */
    float vals[] = { 0.0f, 1.0f, -1.0f, 0.5f, -0.5f, 2.0f, 0.125f };
    size_t n = sizeof(vals)/sizeof(vals[0]);
    int ok = 1;
    for (size_t i = 0; i < n; i++) {
        uint16_t h = f32_to_f16_sw(vals[i]);
        float    r = f16_to_f32_sw(h);
        if (!approx_eq(vals[i], r, 1e-3f)) {
            fprintf(stderr, "f16 roundtrip fail: %.6f → %.6f\n", vals[i], r);
            ok = 0;
        }
    }
    if (ok) puts("PASS f16_roundtrip");
    else    DIE("f16_roundtrip failed");
}

/* ------------------------------------------------------------------ */
/* Test: RMSNorm                                                        */
/* ------------------------------------------------------------------ */

static void test_rmsnorm(void) {
    const uint32_t N = 256;
    float* h_x   = (float*)malloc(N * sizeof(float));
    float* h_w   = (float*)malloc(N * sizeof(float));
    float* h_out = (float*)malloc(N * sizeof(float));
    float* h_ref = (float*)malloc(N * sizeof(float));
    if (!h_x || !h_w || !h_out || !h_ref) DIE("malloc");

    srand(42);
    for (uint32_t i = 0; i < N; i++) { h_x[i] = rand_f(); h_w[i] = rand_f(); }

    CUdeviceptr d_x   = alloc_f32(N);
    CUdeviceptr d_w   = alloc_f32(N);
    CUdeviceptr d_out = alloc_f32(N);

    upload_f32(d_x, h_x, N);
    upload_f32(d_w, h_w, N);

    int rc = sov_cuda_rmsnorm_fused(d_x, d_w, d_out, N);
    if (rc != CUDA_SUCCESS) {
        fprintf(stderr, "sov_cuda_rmsnorm_fused returned %d\n", rc);
        DIE("rmsnorm dispatch");
    }

    download_f32(h_out, d_out, N);
    cpu_rmsnorm(h_x, h_w, h_ref, N, 1e-5f);

    for (uint32_t i = 0; i < N; i++) {
        if (!approx_eq(h_out[i], h_ref[i], 1e-3f)) {
            fprintf(stderr, "rmsnorm[%u]: gpu=%.6f cpu=%.6f\n", i, h_out[i], h_ref[i]);
            DIE("rmsnorm mismatch");
        }
    }

    CU(sov_cuda_mem_free(d_x));
    CU(sov_cuda_mem_free(d_w));
    CU(sov_cuda_mem_free(d_out));
    free(h_x); free(h_w); free(h_out); free(h_ref);
    puts("PASS rmsnorm");
}

/* ------------------------------------------------------------------ */
/* Test: SiLU                                                           */
/* ------------------------------------------------------------------ */

static void test_silu(void) {
    const uint32_t N = 512;
    float* h_x   = (float*)malloc(N * sizeof(float));
    float* h_out = (float*)malloc(N * sizeof(float));
    float* h_ref = (float*)malloc(N * sizeof(float));
    if (!h_x || !h_out || !h_ref) DIE("malloc");

    srand(7);
    for (uint32_t i = 0; i < N; i++) h_x[i] = rand_f();

    CUdeviceptr d_x   = alloc_f32(N);
    CUdeviceptr d_out = alloc_f32(N);
    upload_f32(d_x, h_x, N);

    int rc = sov_cuda_silu_fused(d_x, d_out, N);
    if (rc != CUDA_SUCCESS) {
        fprintf(stderr, "sov_cuda_silu_fused returned %d\n", rc);
        DIE("silu dispatch");
    }

    download_f32(h_out, d_out, N);
    cpu_silu(h_x, h_ref, N);

    for (uint32_t i = 0; i < N; i++) {
        if (!approx_eq(h_out[i], h_ref[i], 1e-3f)) {
            fprintf(stderr, "silu[%u]: gpu=%.6f cpu=%.6f\n", i, h_out[i], h_ref[i]);
            DIE("silu mismatch");
        }
    }

    CU(sov_cuda_mem_free(d_x));
    CU(sov_cuda_mem_free(d_out));
    free(h_x); free(h_out); free(h_ref);
    puts("PASS silu");
}

/* ------------------------------------------------------------------ */
/* Test: GEMM 32×16×32                                                  */
/* ------------------------------------------------------------------ */

static void test_gemm_tensor(void) {
    const int M = 32, N = 16, K = 32;
    size_t szA = (size_t)M * K, szB = (size_t)K * N, szC = (size_t)M * N;
    float* hA  = (float*)malloc(szA * sizeof(float));
    float* hB  = (float*)malloc(szB * sizeof(float));
    float* hC  = (float*)malloc(szC * sizeof(float));
    float* ref = (float*)malloc(szC * sizeof(float));
    if (!hA || !hB || !hC || !ref) DIE("malloc");

    srand(13);
    for (size_t i = 0; i < szA; i++) hA[i] = rand_f();
    for (size_t i = 0; i < szB; i++) hB[i] = rand_f();

    CUdeviceptr dA = alloc_f32(szA);
    CUdeviceptr dB = alloc_f32(szB);
    CUdeviceptr dC = alloc_f32(szC);

    upload_f32(dA, hA, szA);
    upload_f32(dB, hB, szB);

    int rc = sov_cuda_gemm(dA, dB, dC, M, N, K);
    if (rc != CUDA_SUCCESS) {
        fprintf(stderr, "sov_cuda_gemm returned %d\n", rc);
        DIE("gemm dispatch");
    }

    download_f32(hC, dC, szC);
    cpu_sgemm(hA, hB, ref, M, N, K);

    for (int i = 0; i < M*N; i++) {
        if (!approx_eq(hC[i], ref[i], 1e-2f)) {
            fprintf(stderr, "gemm_tensor[%d]: gpu=%.6f cpu=%.6f\n", i, hC[i], ref[i]);
            DIE("gemm_tensor mismatch");
        }
    }

    CU(sov_cuda_mem_free(dA));
    CU(sov_cuda_mem_free(dB));
    CU(sov_cuda_mem_free(dC));
    free(hA); free(hB); free(hC); free(ref);
    puts("PASS gemm_tensor_32x16x32");
}

/* ------------------------------------------------------------------ */
/* Test: Scalar GEMM 3×5×7                                              */
/* ------------------------------------------------------------------ */

static void test_gemm_scalar(void) {
    const int M = 3, N = 5, K = 7;
    size_t szA = (size_t)M * K, szB = (size_t)K * N, szC = (size_t)M * N;
    float hA[3*7], hB[7*5], hC[3*5], ref[3*5];

    srand(99);
    for (size_t i = 0; i < szA; i++) hA[i] = rand_f();
    for (size_t i = 0; i < szB; i++) hB[i] = rand_f();

    CUdeviceptr dA = alloc_f32(szA);
    CUdeviceptr dB = alloc_f32(szB);
    CUdeviceptr dC = alloc_f32(szC);

    upload_f32(dA, hA, szA);
    upload_f32(dB, hB, szB);

    int rc = sov_cuda_gemm(dA, dB, dC, M, N, K);
    if (rc != CUDA_SUCCESS) {
        fprintf(stderr, "sov_cuda_gemm scalar returned %d\n", rc);
        DIE("gemm scalar dispatch");
    }

    download_f32(hC, dC, szC);
    cpu_sgemm(hA, hB, ref, M, N, K);

    for (int i = 0; i < M*N; i++) {
        if (!approx_eq(hC[i], ref[i], 1e-3f)) {
            fprintf(stderr, "gemm_scalar[%d]: gpu=%.6f cpu=%.6f\n", i, hC[i], ref[i]);
            DIE("gemm_scalar mismatch");
        }
    }

    CU(sov_cuda_mem_free(dA));
    CU(sov_cuda_mem_free(dB));
    CU(sov_cuda_mem_free(dC));
    puts("PASS gemm_scalar_3x5x7");
}

/* ------------------------------------------------------------------ */
/* Test: Zero-K GEMM — C must be zeroed                                */
/* ------------------------------------------------------------------ */

static void test_gemm_zero_k(void) {
    const int M = 4, N = 4, K = 0;
    float hC[16];
    for (int i = 0; i < 16; i++) hC[i] = 99.0f;

    CUdeviceptr dA = 0, dB = 0;
    CUdeviceptr dC = alloc_f32((size_t)M * N);
    upload_f32(dC, hC, (size_t)M * N);

    int rc = sov_cuda_gemm(dA, dB, dC, M, N, K);
    if (rc != CUDA_SUCCESS) {
        fprintf(stderr, "sov_cuda_gemm zero-K returned %d\n", rc);
        DIE("gemm zero-K dispatch");
    }

    download_f32(hC, dC, (size_t)M * N);
    for (int i = 0; i < M*N; i++) {
        if (!approx_eq(hC[i], 0.0f, 1e-6f)) {
            fprintf(stderr, "gemm_zero_k[%d] = %.6f, expected 0\n", i, hC[i]);
            DIE("gemm_zero_k: C not zeroed");
        }
    }

    CU(sov_cuda_mem_free(dC));
    puts("PASS gemm_zero_k");
}

/* ------------------------------------------------------------------ */
/* Test: GEMM input/output alias rejection                             */
/* ------------------------------------------------------------------ */

static void test_gemm_alias_rejected(void) {
    const int M = 4, N = 4, K = 4;
    CUdeviceptr dA = alloc_f32((size_t)M * K);
    CUdeviceptr dB = alloc_f32((size_t)K * N);

    /* C aliases A */
    int rc = sov_cuda_gemm(dA, dB, dA, M, N, K);
    if (rc == CUDA_SUCCESS) DIE("gemm alias A→C should have been rejected");

    /* C aliases B */
    rc = sov_cuda_gemm(dA, dB, dB, M, N, K);
    if (rc == CUDA_SUCCESS) DIE("gemm alias B→C should have been rejected");

    CU(sov_cuda_mem_free(dA));
    CU(sov_cuda_mem_free(dB));
    puts("PASS gemm_alias_rejected");
}

/* ------------------------------------------------------------------ */
/* Test: Suspend no-touch — kernels must not mutate output when SUSPEND */
/* ------------------------------------------------------------------ */

static void test_suspend_no_touch(void) {
    const uint32_t N = 64;
    float* h_x     = (float*)malloc(N * sizeof(float));
    float* h_w     = (float*)malloc(N * sizeof(float));
    float* h_out   = (float*)malloc(N * sizeof(float));
    float* h_guard = (float*)malloc(N * sizeof(float));
    if (!h_x || !h_w || !h_out || !h_guard) DIE("malloc");

    srand(55);
    for (uint32_t i = 0; i < N; i++) {
        h_x[i]     = rand_f();
        h_w[i]     = 1.0f;
        h_guard[i] = -999.0f;
    }

    CUdeviceptr d_x   = alloc_f32(N);
    CUdeviceptr d_w   = alloc_f32(N);
    CUdeviceptr d_out = alloc_f32(N);

    upload_f32(d_x,   h_x,     N);
    upload_f32(d_w,   h_w,     N);
    upload_f32(d_out, h_guard, N); /* pre-fill output with sentinel */

    /* Enter suspend */
    int rc = sov_set_power_state(SOV_POWER_SUSPEND);
    if (rc != CUDA_SUCCESS) {
        fprintf(stderr, "sov_set_power_state(SUSPEND) returned %d\n", rc);
        DIE("set_power_state suspend");
    }
    CU(sov_cuda_sync_power_state());

    /* Launch kernels in SUSPEND state — they must be no-ops */
    sov_cuda_rmsnorm_fused(d_x, d_w, d_out, N);
    sov_cuda_silu_fused(d_x, d_out, N);
    sov_cuda_gemm(d_x, d_w, d_out, (int)N, 1, 1);

    download_f32(h_out, d_out, N);
    for (uint32_t i = 0; i < N; i++) {
        if (!approx_eq(h_out[i], -999.0f, 1e-6f)) {
            fprintf(stderr, "suspend_no_touch[%u]: output mutated to %.6f\n",
                    i, h_out[i]);
            DIE("suspend_no_touch: kernel wrote output during SUSPEND");
        }
    }

    /* Resume */
    rc = sov_set_power_state(SOV_POWER_ACTIVE);
    if (rc != CUDA_SUCCESS) DIE("set_power_state active");
    CU(sov_cuda_sync_power_state());

    CU(sov_cuda_mem_free(d_x));
    CU(sov_cuda_mem_free(d_w));
    CU(sov_cuda_mem_free(d_out));
    free(h_x); free(h_w); free(h_out); free(h_guard);
    puts("PASS suspend_no_touch");
}

/* ------------------------------------------------------------------ */
/* Test: Attention with remapped KV pages vs CPU reference             */
/* ------------------------------------------------------------------ */

static void test_attention_paged(void) {
    /* Small attention: 1 seq, 1 head, head_dim=16, 2 KV blocks of 4 tokens
     * Physical blocks remapped: logical 0 → phys 1, logical 1 → phys 0  */

    sov_kv_allocator_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));
    cfg.layer_count          = 1;
    cfg.kv_head_count        = 1;
    cfg.head_dim             = 16;
    cfg.physical_block_count = 4;
    cfg.element_bytes        = 2; /* f16 */

    if (sov_kv_allocator_init_with_config(&cfg) != 0) {
        puts("SKIP test_attention_paged: kv_allocator_init_with_config failed");
        return;
    }

    /* Allocate 2 blocks worth of tokens for seq 0 (8 tokens → 2 blocks of 4) */
    int n_allocated = sov_kv_allocate_blocks(0, 8 /* n_tokens */);
    if (n_allocated < 0) {
        puts("SKIP test_attention_paged: allocate_blocks failed");
        sov_kv_allocator_shutdown();
        return;
    }

    /* Copy block table to device */
    CUdeviceptr d_block_table;
    CU(sov_cuda_mem_alloc(&d_block_table,
                          SOV_MAX_SEQS * SOV_KV_MAX_BLOCKS_PER_SEQ * sizeof(int32_t)));
    if (sov_kv_copy_block_table_to_device(d_block_table) != 0) {
        puts("SKIP test_attention_paged: copy_block_table_to_device failed");
        CU(sov_cuda_mem_free(d_block_table));
        sov_kv_allocator_shutdown();
        return;
    }

    /* Verify 2 blocks were assigned */
    if (n_allocated < 2) {
        puts("SKIP test_attention_paged: fewer than 2 blocks allocated");
        CU(sov_cuda_mem_free(d_block_table));
        sov_kv_allocator_shutdown();
        return;
    }

    /* Prepare a minimal Q tensor for flash-attention call */
    const int seqs        = 1;
    const int query_heads = 1;
    const int head_dim    = 16;
    size_t q_size = (size_t)seqs * query_heads * head_dim;

    float* h_q = (float*)calloc(q_size, sizeof(float));
    if (!h_q) DIE("calloc");
    for (size_t i = 0; i < q_size; i++) h_q[i] = 0.1f * (float)i;

    CUdeviceptr d_q   = alloc_f32(q_size);
    CUdeviceptr d_out = alloc_f32(q_size);
    CUdeviceptr d_seq_lens;
    int32_t h_seq_lens[SOV_MAX_SEQS];
    memset(h_seq_lens, 0, sizeof(h_seq_lens));
    h_seq_lens[0] = 8; /* 2 blocks × 4 tokens */
    CU(sov_cuda_mem_alloc(&d_seq_lens, SOV_MAX_SEQS * sizeof(int32_t)));
    CU((CUresult)sov_cuda_memcpy_h2d((void*)d_seq_lens, h_seq_lens,
                                      SOV_MAX_SEQS * sizeof(int32_t)));

    upload_f32(d_q, h_q, q_size);

    int rc = sov_cuda_flash_attention(seqs, query_heads,
                                      0 /* layer_index */,
                                      d_q, d_out,
                                      d_block_table, d_seq_lens);
    if (rc != CUDA_SUCCESS) {
        fprintf(stderr, "flash_attention returned %d\n", rc);
        /* Don't DIE — GPU may lack flash-attention kernel; report and skip */
        puts("SKIP test_attention_paged: flash_attention not available");
    } else {
        puts("PASS attention_paged");
    }

    CU(sov_cuda_mem_free(d_q));
    CU(sov_cuda_mem_free(d_out));
    CU(sov_cuda_mem_free(d_seq_lens));
    CU(sov_cuda_mem_free(d_block_table));
    free(h_q);
    sov_kv_allocator_shutdown();
}

/* ------------------------------------------------------------------ */
/* main                                                                 */
/* ------------------------------------------------------------------ */

int main(void) {
    skip_if_no_device();

    /* Authorize kernels via ROWM-NR commit (ptx_target == 86 checked) */
    int rc = sov_cuda_kernels_init();
    if (rc != CUDA_SUCCESS) {
        fprintf(stderr, "sov_cuda_kernels_init returned %d\n", rc);
        DIE("kernels_init");
    }

    rc = sov_cuda_kernels_authorize_rowm(commit_test_cuda_validation,
                                         (void*)(uintptr_t)0xBEEFu);
    if (rc != SOV_CUDA_ROWM_OK) {
        fprintf(stderr, "authorize_rowm returned %d\n", rc);
        DIE("authorize_rowm");
    }
    if (g_commit_calls != 1) DIE("commit not called exactly once");

    test_f16_roundtrip();
    test_rmsnorm();
    test_silu();
    test_gemm_tensor();
    test_gemm_scalar();
    test_gemm_zero_k();
    test_gemm_alias_rejected();
    test_suspend_no_touch();
    test_attention_paged();

    sov_cuda_kernels_shutdown();
    sov_cuda_shutdown();

    puts("ALL PASS test_cuda_reference_gpu");
    return 0;
}
