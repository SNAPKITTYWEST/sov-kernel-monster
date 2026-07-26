/* Zero-CRT GEMM dispatch — load gemm.ptx, launch gemm_f16_f32_accum
 * No stdlib headers. Typedefs match cuda_driver_loader.c.
 */
typedef unsigned long long uint64_t;
typedef unsigned int       uint32_t;
typedef int                int32_t;
typedef unsigned long long CUdeviceptr;
typedef struct CUmod_st*   CUmodule;
typedef struct CUfunc_st*  CUfunction;
typedef struct CUstream_st* CUstream;
typedef int                CUresult;
#define CUDA_SUCCESS 0

/* PTX blob embedded at build time via:
 *   xxd -i rtx/src/cuda/gemm.ptx > rtx/src/cuda/gemm_ptx_blob.h
 * At link time this array must be present.
 */
extern const unsigned char gemm_ptx_data[];
extern const unsigned int  gemm_ptx_size;

/* Driver function pointers (resolved in cuda_driver_loader.c) */
extern CUresult (*g_cuModuleLoadData)(CUmodule*, const void*);
extern CUresult (*g_cuModuleGetFunction)(CUfunction*, CUmodule, const char*);
extern CUresult (*g_cuLaunchKernel)(CUfunction, unsigned int, unsigned int, unsigned int,
                                     unsigned int, unsigned int, unsigned int,
                                     unsigned int, CUstream, void**, void**);
extern CUresult (*g_cuCtxSynchronize)(void);

/* Power state (written by power_handler.c, read by PTX kernel) */
extern volatile int32_t g_power_state;

/* ── module cache ── */
static CUmodule   s_module   = 0;
static CUfunction s_kernel   = 0;
static int        s_ready    = 0;

static int gemm_ensure_loaded(void) {
    if (s_ready) return 0;
    if (!g_cuModuleLoadData || !g_cuModuleGetFunction) return -1;
    CUresult r;
    r = g_cuModuleLoadData(&s_module, (const void*)gemm_ptx_data);
    if (r != CUDA_SUCCESS) return -1;
    r = g_cuModuleGetFunction(&s_kernel, s_module, "gemm_f16_f32_accum");
    if (r != CUDA_SUCCESS) return -2;
    s_ready = 1;
    return 0;
}

/* ── sov_cuda_gemm ───────────────────────────────────────────────
 * C = A * B + C  (M x K @ K x N -> M x N)
 * All device pointers.  A/B are f16, C is f32 accumulator.
 * lda = K (row-major A), ldb = N (row-major B), ldc = N (row-major C).
 * ---------------------------------------------------------------- */
int sov_cuda_gemm(CUdeviceptr A, CUdeviceptr B, CUdeviceptr C,
                  int M, int N, int K,
                  int lda, int ldb, int ldc) {
    if (gemm_ensure_loaded() != 0) return -1;
    if (!g_cuLaunchKernel) return -2;

    int pwr = (int)g_power_state;
    void* args[] = {
        &A, &B, &C,
        &M, &N, &K,
        &lda, &ldb, &ldc,
        &pwr
    };

    unsigned int gx = ((unsigned int)M + 15u) / 16u;
    unsigned int gy = ((unsigned int)N +  7u) /  8u;

    CUresult r = g_cuLaunchKernel(s_kernel,
                                   gx, gy, 1u,
                                   32u, 1u, 1u,
                                   768u,   /* smem: 512+256 bytes */
                                   0,      /* default stream */
                                   args, 0);
    return (r == CUDA_SUCCESS) ? 0 : -3;
}

/* Convenience: row-major, default leading dims */
int sov_cuda_gemm_simple(CUdeviceptr A, CUdeviceptr B, CUdeviceptr C,
                          int M, int N, int K) {
    return sov_cuda_gemm(A, B, C, M, N, K, K, N, N);
}
