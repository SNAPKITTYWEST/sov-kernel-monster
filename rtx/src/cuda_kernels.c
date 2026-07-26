#include <stdint.h>
#include "cuda_validation_chain.h"

/* cuLaunchKernel signature — resolved at runtime from nvcuda.dll via cuda_driver_loader */
typedef int CUresult;
typedef struct CUstream_st* CUstream;
typedef CUresult (*cuLaunchKernel_fn)(void*, unsigned,unsigned,unsigned,
                                      unsigned,unsigned,unsigned,
                                      unsigned, CUstream, void**, void**);

static sov_rowm_record_t*  g_rowm_rec    = 0;
static sov_cuda_auth_t*    g_auth        = 0;
static cuLaunchKernel_fn   g_launch_fn   = 0;

/* Called by cuda_driver_loader after it resolves cuLaunchKernel from nvcuda.dll */
void sov_cuda_kernels_set_auth(sov_rowm_record_t* rec, sov_cuda_auth_t* auth) {
    g_rowm_rec  = rec;
    g_auth      = auth;
}

void sov_cuda_kernels_set_launch_fn(void* fn) {
    g_launch_fn = (cuLaunchKernel_fn)fn;
}

static int find_handle(const sov_cuda_auth_t* auth, void* fn) {
    for (uint32_t i = 0; i < auth->count; i++) {
        if (auth->handles[i] == fn) return (int)i;
    }
    return -1;
}

int sov_cuda_launch_kernel(void* fn,
                           unsigned gx, unsigned gy, unsigned gz,
                           unsigned bx, unsigned by, unsigned bz,
                           unsigned shared_mem, void* stream, void** args) {
    if (!g_rowm_rec || !g_auth) return -3;
    if (sov_rowm_check_authorized(g_rowm_rec, g_auth) != 0) return -3;
    if (find_handle(g_auth, fn) < 0) return -5;
    if (!g_launch_fn) return -6;

    CUresult r = g_launch_fn(fn, gx, gy, gz, bx, by, bz,
                             shared_mem, (CUstream)stream, args, 0);
    return r == 0 ? 0 : -7;
}

int sov_cuda_flash_attention(int seqs, int heads,
                             float* q, float* k, float* v, float* out,
                             int* block_table, int* seq_lens,
                             int head_dim, int block_size) {
    if (!g_rowm_rec || !g_auth) return -3;
    if (sov_rowm_check_authorized(g_rowm_rec, g_auth) != 0) return -3;
    /* Flash attention kernel handle is auth->handles[0] by convention */
    if (!g_auth->count || !g_launch_fn) return -6;

    /* Grid: ceil(seqs/32) x heads x 1 — one warp per sequence per head */
    unsigned grid_x = (unsigned)((seqs + 31) / 32);
    unsigned grid_y = (unsigned)heads;
    void* kargs[] = { &seqs, &heads, &q, &k, &v, &out,
                      &block_table, &seq_lens, &head_dim, &block_size };
    return sov_cuda_launch_kernel(g_auth->handles[0],
                                  grid_x, grid_y, 1,
                                  32, 1, 1,
                                  0, 0, kargs);
}

int sov_cuda_gemm(float* a, float* b, float* c, int m, int n, int k_dim) {
    if (!g_rowm_rec || !g_auth) return -3;
    if (sov_rowm_check_authorized(g_rowm_rec, g_auth) != 0) return -3;
    /* GEMM kernel handle is auth->handles[1] by convention */
    if (g_auth->count < 2 || !g_launch_fn) return -6;

    /* Grid: ceil(m/16) x ceil(n/16) — 16x16 tiles */
    unsigned grid_x = (unsigned)((m + 15) / 16);
    unsigned grid_y = (unsigned)((n + 15) / 16);
    void* kargs[] = { &a, &b, &c, &m, &n, &k_dim };
    return sov_cuda_launch_kernel(g_auth->handles[1],
                                  grid_x, grid_y, 1,
                                  16, 16, 1,
                                  0, 0, kargs);
}
