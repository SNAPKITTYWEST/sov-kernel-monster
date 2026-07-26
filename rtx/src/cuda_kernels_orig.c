/* cuda_kernels.c — load PTX modules, wire all kernel dispatch
 * Zero-CRT, zero-libc. Typedefs from cuda_driver_loader.c.
 */
typedef unsigned long long uint64_t;
typedef unsigned int       uint32_t;
typedef int                int32_t;
typedef unsigned long long CUdeviceptr;
typedef struct CUmod_st*   CUmodule;
typedef struct CUfunc_st*  CUfunction;
typedef struct CUstream_st* CUstream;
typedef int                CUresult;
typedef unsigned long long SIZE_T;
#define CUDA_SUCCESS 0

/* Driver function pointers (resolved by cuda_driver_loader.c) */
extern CUresult (*g_cuModuleLoadData)(CUmodule*, const void*);
extern CUresult (*g_cuModuleGetFunction)(CUfunction*, CUmodule, const char*);
extern CUresult (*g_cuLaunchKernel)(CUfunction, unsigned int, unsigned int, unsigned int,
                                     unsigned int, unsigned int, unsigned int,
                                     unsigned int, CUstream, void**, void**);
extern CUresult (*g_cuMemAlloc_v2)(CUdeviceptr*, SIZE_T);
extern CUresult (*g_cuMemcpyHtoD_v2)(CUdeviceptr, const void*, SIZE_T);
extern CUresult (*g_cuModuleUnload)(CUmodule);

/* Embedded PTX blobs (xxd -i at build time) */
extern const unsigned char flash_attention_ptx_data[];
extern const unsigned int  flash_attention_ptx_size;
extern const unsigned char gemm_ptx_data[];
extern const unsigned int  gemm_ptx_size;

/* ── module / function handles ─────────────────────────────────── */
static CUmodule   s_fa_module    = 0;
static CUmodule   s_gemm_module  = 0;

static CUfunction s_fa_paged     = 0;   /* flash_attention_paged   */
static CUfunction s_rmsnorm      = 0;   /* rmsnorm_fused           */
static CUfunction s_silu         = 0;   /* silu_fused              */
static CUfunction s_gemm         = 0;   /* gemm_f16_f32_accum      */

/* block_table device buffer (allocated once) */
static CUdeviceptr s_d_block_table = 0;
#define SOV_MAX_SEQS 256
#define SOV_KV_MAX_BLOCKS_PER_SEQ 128

/* ── sov_cuda_kernels_init ──────────────────────────────────────── */
int sov_cuda_kernels_init(void) {
    if (!g_cuModuleLoadData || !g_cuModuleGetFunction) return -1;
    CUresult r;

    r = g_cuModuleLoadData(&s_fa_module, (const void*)flash_attention_ptx_data);
    if (r != CUDA_SUCCESS) return -1;

    r = g_cuModuleGetFunction(&s_fa_paged, s_fa_module, "flash_attention_paged");
    if (r != CUDA_SUCCESS) return -2;

    r = g_cuModuleGetFunction(&s_rmsnorm, s_fa_module, "rmsnorm_fused");
    if (r != CUDA_SUCCESS) return -3;

    r = g_cuModuleGetFunction(&s_silu, s_fa_module, "silu_fused");
    if (r != CUDA_SUCCESS) return -4;

    r = g_cuModuleLoadData(&s_gemm_module, (const void*)gemm_ptx_data);
    if (r != CUDA_SUCCESS) return -5;

    r = g_cuModuleGetFunction(&s_gemm, s_gemm_module, "gemm_f16_f32_accum");
    if (r != CUDA_SUCCESS) return -6;

    /* Allocate persistent device block_table buffer */
    SIZE_T bt_bytes = SOV_MAX_SEQS * SOV_KV_MAX_BLOCKS_PER_SEQ * sizeof(int32_t);
    r = g_cuMemAlloc_v2(&s_d_block_table, bt_bytes);
    if (r != CUDA_SUCCESS) return -7;

    return 0;
}

/* ── sov_cuda_flash_attention ───────────────────────────────────── */
int sov_cuda_flash_attention(int seqs, int heads,
                              float* q, float* k, float* v, float* out,
                              int* h_block_table, int* seq_lens,
                              int head_dim, int block_size) {
    if (!s_fa_paged || !g_cuLaunchKernel) return -1;

    /* Upload block_table to device */
    SIZE_T bt_bytes = (SIZE_T)(seqs * block_size) * sizeof(int32_t);
    g_cuMemcpyHtoD_v2(s_d_block_table, h_block_table, bt_bytes);

    void* args[] = {
        &q, &k, &v, &out,
        &s_d_block_table,
        &seq_lens,
        (void*)&head_dim,
        (void*)&block_size
    };

    /* grid = (n_seqs, n_heads, 1)   block = (128, 1, 1) */
    CUresult r = g_cuLaunchKernel(s_fa_paged,
                                   (unsigned int)seqs,
                                   (unsigned int)heads,
                                   1u,
                                   128u, 1u, 1u,
                                   (unsigned int)(head_dim * 4 + 16), /* smem: Q tile */
                                   0, args, 0);
    return (r == CUDA_SUCCESS) ? 0 : -2;
}

/* ── sov_cuda_rmsnorm_fused ─────────────────────────────────────── */
int sov_cuda_rmsnorm_fused(CUdeviceptr x, CUdeviceptr w, int n) {
    if (!s_rmsnorm || !g_cuLaunchKernel) return -1;
    void* args[] = { &x, &w, &x, (void*)&n };
    unsigned int grid = ((unsigned int)n + 127u) / 128u;
    CUresult r = g_cuLaunchKernel(s_rmsnorm,
                                   grid, 1u, 1u,
                                   128u, 1u, 1u,
                                   0u, 0, args, 0);
    return (r == CUDA_SUCCESS) ? 0 : -2;
}

/* ── sov_cuda_silu_fused ────────────────────────────────────────── */
int sov_cuda_silu_fused(CUdeviceptr x, CUdeviceptr out, int n) {
    if (!s_silu || !g_cuLaunchKernel) return -1;
    void* args[] = { &x, &out, (void*)&n };
    unsigned int grid = ((unsigned int)n + 127u) / 128u;
    CUresult r = g_cuLaunchKernel(s_silu,
                                   grid, 1u, 1u,
                                   128u, 1u, 1u,
                                   0u, 0, args, 0);
    return (r == CUDA_SUCCESS) ? 0 : -2;
}

/* ── sov_cuda_gemm (thin wrapper -> gemm_dispatch.c) ────────────── */
int sov_cuda_gemm_simple(CUdeviceptr A, CUdeviceptr B, CUdeviceptr C,
                          int M, int N, int K);

int sov_cuda_gemm(CUdeviceptr A, CUdeviceptr B, CUdeviceptr C,
                  int M, int N, int K) {
    return sov_cuda_gemm_simple(A, B, C, M, N, K);
}

/* ── shutdown ───────────────────────────────────────────────────── */
void sov_cuda_kernels_shutdown(void) {
    if (g_cuModuleUnload) {
        if (s_fa_module)   g_cuModuleUnload(s_fa_module);
        if (s_gemm_module) g_cuModuleUnload(s_gemm_module);
    }
    s_fa_module = s_gemm_module = 0;
    s_fa_paged = s_rmsnorm = s_silu = s_gemm = 0;
}
