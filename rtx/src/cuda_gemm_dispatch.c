#include "cuda_driver_loader.h"
#include "rowm_cuda_validation.h"

extern const unsigned char gemm_ptx[];
extern const unsigned int  gemm_ptx_len;

enum {
    SOV_GEMM_ERR_INVALID_ARGUMENT = -1,
    SOV_GEMM_ERR_MODULE_LOAD      = -2,
    SOV_GEMM_ERR_TENSOR_LOOKUP    = -3,
    SOV_GEMM_ERR_SCALAR_LOOKUP    = -4,
    SOV_GEMM_ERR_LAUNCH           = -5,
    SOV_GEMM_ERR_GRID_TOO_LARGE   = -6
};

static CUmodule  g_gemm_module;
static CUfunction g_gemm_tensor_kernel;
static CUfunction g_gemm_scalar_kernel;
static uint64_t  g_gemm_context_generation;

static int checked_mul_u64(uint64_t left, uint64_t right, uint64_t* product) {
    if (!product) return -1;
    if (left != 0 && right > UINT64_MAX / left) return -1;
    *product = left * right;
    return 0;
}

#define UINT64_MAX ((uint64_t)0xFFFFFFFFFFFFFFFFu)

static int matrix_end(CUdeviceptr base, uint64_t rows, uint64_t cols,
                      uint64_t ld, CUdeviceptr* end) {
    uint64_t last_row, elements, bytes;
    if (!base || !rows || !cols || !end) return -1;
    if (checked_mul_u64(rows - 1u, ld, &last_row) != 0
            || last_row > UINT64_MAX - cols) return -1;
    elements = last_row + cols;
    if (checked_mul_u64(elements, 2u, &bytes) != 0
            || base > UINT64_MAX - bytes) return -1;
    *end = base + bytes;
    return 0;
}

static int ranges_overlap(CUdeviceptr lb, CUdeviceptr le,
                          CUdeviceptr rb, CUdeviceptr re) {
    return lb < re && rb < le;
}

int sov_cuda_gemm_init(void) {
    CUresult result;
    uint64_t ctx_gen;

    if (gemm_ptx_len == 0u || gemm_ptx[gemm_ptx_len - 1u] != 0u)
        return SOV_GEMM_ERR_MODULE_LOAD;
    if (!sov_cuda_is_initialized() && sov_cuda_init() != 0)
        return SOV_GEMM_ERR_MODULE_LOAD;

    ctx_gen = sov_cuda_context_generation();
    if (ctx_gen == 0u) return SOV_GEMM_ERR_MODULE_LOAD;

    if (g_gemm_tensor_kernel && g_gemm_scalar_kernel
            && g_gemm_context_generation == ctx_gen) return 0;

    if (g_gemm_context_generation != ctx_gen) {
        g_gemm_module          = 0;
        g_gemm_tensor_kernel   = 0;
        g_gemm_scalar_kernel   = 0;
        g_gemm_context_generation = 0;
    }

    result = sov_cuda_module_load_data(&g_gemm_module, (const void*)gemm_ptx);
    if (result != CUDA_SUCCESS) { g_gemm_module = 0; return SOV_GEMM_ERR_MODULE_LOAD; }

    result = sov_cuda_module_get_function(&g_gemm_tensor_kernel, g_gemm_module,
                                          "gemm_f16_f32_accum");
    if (result != CUDA_SUCCESS) {
        sov_cuda_module_unload(g_gemm_module);
        g_gemm_module = 0; g_gemm_tensor_kernel = 0;
        return SOV_GEMM_ERR_TENSOR_LOOKUP;
    }

    result = sov_cuda_module_get_function(&g_gemm_scalar_kernel, g_gemm_module,
                                          "gemm_f16_f32_accum_scalar");
    if (result != CUDA_SUCCESS) {
        sov_cuda_module_unload(g_gemm_module);
        g_gemm_module = 0; g_gemm_tensor_kernel = 0; g_gemm_scalar_kernel = 0;
        return SOV_GEMM_ERR_SCALAR_LOOKUP;
    }

    g_gemm_context_generation = ctx_gen;
    return 0;
}

int sov_cuda_gemm_ex(CUdeviceptr A, CUdeviceptr B, CUdeviceptr C,
                     int M, int N, int K,
                     int lda, int ldb, int ldc) {
    CUfunction kernel;
    CUresult result;
    unsigned int grid_x, grid_y, block_x, block_y;
    int power_state, use_tensor, prepare;
    CUdeviceptr a_end, b_end, c_end;
    void* args[10];

    if (!A || !B || !C
            || M < 0 || N < 0 || K < 0
            || lda < K || ldb < N || ldc < N
            || lda < 0 || ldb < 0 || ldc < 0)
        return SOV_GEMM_ERR_INVALID_ARGUMENT;

    if (M == 0 || N == 0) return 0;

    if (matrix_end(C, (uint64_t)M, (uint64_t)N, (uint64_t)ldc, &c_end) != 0)
        return SOV_GEMM_ERR_INVALID_ARGUMENT;

    if (K > 0) {
        if (matrix_end(A, (uint64_t)M, (uint64_t)K, (uint64_t)lda, &a_end) != 0
                || matrix_end(B, (uint64_t)K, (uint64_t)N, (uint64_t)ldb, &b_end) != 0
                || ranges_overlap(A, a_end, C, c_end)
                || ranges_overlap(B, b_end, C, c_end))
            return SOV_GEMM_ERR_INVALID_ARGUMENT;
    }

    use_tensor = (M & 15) == 0 && (N & 7) == 0 && (K & 15) == 0;
    if (use_tensor) {
        grid_x  = (unsigned int)M / 16u;
        grid_y  = (unsigned int)N / 8u;
        block_x = 32u; block_y = 1u;
    } else {
        grid_x  = ((unsigned int)N + 15u) / 16u;
        grid_y  = ((unsigned int)M + 15u) / 16u;
        block_x = 16u; block_y = 16u;
    }
    if (grid_y > 65535u) return SOV_GEMM_ERR_GRID_TOO_LARGE;

    prepare = sov_cuda_gemm_init();
    if (prepare != 0) return prepare;

    prepare = sov_cuda_validation_require_authorized(sov_cuda_context_generation());
    if (prepare != SOV_CUDA_ROWM_OK) return prepare;

    kernel      = use_tensor ? g_gemm_tensor_kernel : g_gemm_scalar_kernel;
    power_state = 0; /* sov_get_power_state() wired by caller after link */

    args[0] = &A;  args[1] = &B;  args[2] = &C;
    args[3] = &M;  args[4] = &N;  args[5] = &K;
    args[6] = &lda; args[7] = &ldb; args[8] = &ldc;
    args[9] = &power_state;

    result = sov_cuda_launch_kernel(kernel,
                                    grid_x, grid_y, 1u,
                                    block_x, block_y, 1u,
                                    0u, (CUstream)0, args, 0);
    return result == CUDA_SUCCESS ? 0 : SOV_GEMM_ERR_LAUNCH;
}

int sov_cuda_gemm(CUdeviceptr A, CUdeviceptr B, CUdeviceptr C,
                  int M, int N, int K) {
    return sov_cuda_gemm_ex(A, B, C, M, N, K, K, N, N);
}

void sov_cuda_gemm_shutdown(void) {
    if (g_gemm_module
            && sov_cuda_is_initialized()
            && g_gemm_context_generation == sov_cuda_context_generation())
        sov_cuda_module_unload(g_gemm_module);
    g_gemm_module          = 0;
    g_gemm_tensor_kernel   = 0;
    g_gemm_scalar_kernel   = 0;
    g_gemm_context_generation = 0;
}
