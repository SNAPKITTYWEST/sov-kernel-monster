#include <stdint.h>
#include "cuda_validation_chain.h"

static sov_rowm_record_t* g_rowm_rec = 0;
static sov_cuda_auth_t*   g_auth     = 0;

void sov_cuda_kernels_set_auth(sov_rowm_record_t* rec, sov_cuda_auth_t* auth) {
    g_rowm_rec = rec;
    g_auth     = auth;
}

/* Returns the function pointer slot index in auth->handles, or -1 if not found. */
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

    /* Real dispatch: cuLaunchKernel(fn, gx,gy,gz, bx,by,bz, shared_mem, stream, args, 0) */
    /* Suppressed here — caller resolves CU symbols separately */
    (void)gx; (void)gy; (void)gz;
    (void)bx; (void)by; (void)bz;
    (void)shared_mem; (void)stream; (void)args;
    return 0;
}

int sov_cuda_flash_attention(int seqs, int heads,
                             float* q, float* k, float* v, float* out,
                             int* block_table, int* seq_lens,
                             int head_dim, int block_size) {
    if (!g_rowm_rec || !g_auth) return -3;
    if (sov_rowm_check_authorized(g_rowm_rec, g_auth) != 0) return -3;

    (void)seqs; (void)heads; (void)q; (void)k; (void)v; (void)out;
    (void)block_table; (void)seq_lens; (void)head_dim; (void)block_size;
    return 0;
}

int sov_cuda_gemm(float* a, float* b, float* c, int m, int n, int k_dim) {
    if (!g_rowm_rec || !g_auth) return -3;
    if (sov_rowm_check_authorized(g_rowm_rec, g_auth) != 0) return -3;

    (void)a; (void)b; (void)c; (void)m; (void)n; (void)k_dim;
    return 0;
}
