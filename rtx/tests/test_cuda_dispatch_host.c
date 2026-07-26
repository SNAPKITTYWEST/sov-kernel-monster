/*
 * Host-only test for cuda_kernels.c dispatch surface.
 * Stubs every CUDA driver call; validates init/shutdown/auth/launch paths.
 */
#include "cuda_driver_loader.h"
#include "kv_allocator.h"
#include "rowm_cuda_validation.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PTR_VALUE(type, value) ((type)(uintptr_t)(value))

static void check_failed(const char* expression, const char* file, int line) {
    fprintf(stderr, "CHECK failed: %s (%s:%d)\n", expression, file, line);
    exit(1);
}
#define CHECK(expression) \
    ((expression) ? (void)0 : check_failed(#expression, __FILE__, __LINE__))

const unsigned char flash_attention_ptx[] = {'.', 'v', 0};
const unsigned int  flash_attention_ptx_len = 3;
const unsigned char gemm_ptx[] = {'.', 'g', 0};
const unsigned int  gemm_ptx_len = 3;
float g_janet_kernel_config[8] = {
    1.0f, 0.5f, 0.25f, 0.125f, 8.0f, 16.0f, 32.0f, 64.0f
};

int sov_cuda_flash_attention(int seqs, int query_heads,
                             uint32_t layer_index,
                             CUdeviceptr q, CUdeviceptr out,
                             CUdeviceptr block_table,
                             CUdeviceptr seq_lens);

static CUmodule   g_fake_module  = PTR_VALUE(CUmodule,   0x1000);
static CUfunction g_fake_flash   = PTR_VALUE(CUfunction, 0x2000);
static CUfunction g_fake_rmsnorm = PTR_VALUE(CUfunction, 0x3000);
static CUfunction g_fake_silu    = PTR_VALUE(CUfunction, 0x4000);
static CUdeviceptr g_fake_power  = UINT64_C(0x5000);
static CUdeviceptr g_fake_config = UINT64_C(0x6000);

static int g_driver_initialized;
static int g_driver_init_calls;
static int g_module_load_calls;
static int g_module_unload_calls;
static int g_lookup_calls;
static int g_fail_lookup_call;
static int g_register_calls;
static CUdeviceptr g_registered_power;
static int g_power_sync_calls;
static int g_config_copy_calls;
static int g_gemm_init_calls;
static int g_gemm_init_result;
static int g_gemm_shutdown_calls;
static int g_expected_launch;
static int g_launch_calls;
static int g_rowm_commit_calls;

static int g_allocator_ready;
static sov_kv_allocator_config_t g_allocator_config;
static CUdeviceptr g_allocator_k;
static CUdeviceptr g_allocator_v;
static size_t g_token_stride;
static size_t g_page_stride;
static size_t g_layer_stride;
static size_t g_plane_stride;

static void reset_allocator_contract(void) {
    g_allocator_ready = 1;
    g_allocator_config.physical_block_count = 3;
    g_allocator_config.layer_count          = 2;
    g_allocator_config.kv_head_count        = 2;
    g_allocator_config.head_dim             = 64;
    g_allocator_config.element_bytes        = 2;
    g_allocator_k    = UINT64_C(0x20000);
    g_token_stride   = 256;
    g_page_stride    = 4096;
    g_layer_stride   = 12288;
    g_plane_stride   = 24576;
    g_allocator_v    = g_allocator_k + (CUdeviceptr)g_plane_stride;
}

int sov_kv_get_config(sov_kv_allocator_config_t* out) {
    if (!g_allocator_ready || !out) return -1;
    *out = g_allocator_config;
    return 0;
}
CUdeviceptr sov_kv_get_k_base(void)        { return g_allocator_k; }
CUdeviceptr sov_kv_get_v_base(void)        { return g_allocator_v; }
size_t sov_kv_get_token_stride(void)       { return g_token_stride; }
size_t sov_kv_get_page_stride(void)        { return g_page_stride; }
size_t sov_kv_get_layer_stride(void)       { return g_layer_stride; }
size_t sov_kv_get_plane_stride(void)       { return g_plane_stride; }

int sov_cuda_init(void) { ++g_driver_init_calls; g_driver_initialized = 1; return CUDA_SUCCESS; }
int sov_cuda_is_initialized(void)          { return g_driver_initialized; }
uint64_t sov_cuda_context_generation(void) { return g_driver_initialized ? UINT64_C(1) : UINT64_C(0); }

CUresult sov_cuda_get_runtime_identity(sov_cuda_runtime_identity_t* id) {
    size_t i;
    CHECK(id != 0);
    memset(id, 0, sizeof(*id));
    id->driver_version             = 12080;
    id->compute_capability_major   = 8;
    id->compute_capability_minor   = 9;
    id->context_generation         = sov_cuda_context_generation();
    for (i = 0; i < sizeof(id->device_uuid); ++i)
        id->device_uuid[i] = (uint8_t)(i + 1u);
    return CUDA_SUCCESS;
}

CUresult sov_cuda_module_load_data(CUmodule* module, const void* image) {
    CHECK(module != 0);
    CHECK(image == flash_attention_ptx);
    ++g_module_load_calls;
    *module = g_fake_module;
    return CUDA_SUCCESS;
}

CUresult sov_cuda_module_get_function(CUfunction* function, CUmodule module,
                                      const char* name) {
    ++g_lookup_calls;
    CHECK(function != 0);
    CHECK(module == g_fake_module);
    if (g_lookup_calls == g_fail_lookup_call) return CUDA_ERROR_NOT_FOUND;
    if (strcmp(name, "flash_attention_paged") == 0) *function = g_fake_flash;
    else if (strcmp(name, "rmsnorm_fused")    == 0) *function = g_fake_rmsnorm;
    else if (strcmp(name, "silu_fused")       == 0) *function = g_fake_silu;
    else CHECK(!"unexpected kernel lookup");
    return CUDA_SUCCESS;
}

CUresult sov_cuda_module_get_global(CUdeviceptr* device_ptr, size_t* bytes,
                                    CUmodule module, const char* name) {
    CHECK(device_ptr != 0); CHECK(bytes != 0); CHECK(module == g_fake_module);
    if (strcmp(name, "power_state") == 0) {
        *device_ptr = g_fake_power; *bytes = sizeof(int32_t);
    } else if (strcmp(name, "janet_kernel_config") == 0) {
        *device_ptr = g_fake_config; *bytes = 256;
    } else CHECK(!"unexpected module-global lookup");
    return CUDA_SUCCESS;
}

CUresult sov_cuda_module_unload(CUmodule module) {
    CHECK(module == g_fake_module);
    ++g_module_unload_calls;
    return CUDA_SUCCESS;
}

int sov_cuda_memcpy_h2d(void* device_dst, const void* host_src, size_t bytes) {
    CHECK((CUdeviceptr)(uintptr_t)device_dst == g_fake_config);
    CHECK(host_src == g_janet_kernel_config);
    CHECK(bytes == sizeof(g_janet_kernel_config));
    ++g_config_copy_calls;
    return CUDA_SUCCESS;
}

CUresult sov_cuda_register_power_state_device(CUdeviceptr device_ptr) {
    ++g_register_calls;
    g_registered_power = device_ptr;
    return CUDA_SUCCESS;
}

CUresult sov_cuda_sync_power_state(void) {
    CHECK(g_registered_power == g_fake_power);
    ++g_power_sync_calls;
    return CUDA_SUCCESS;
}

CUresult sov_cuda_launch_kernel(CUfunction function,
                                unsigned int grid_x, unsigned int grid_y,
                                unsigned int grid_z,
                                unsigned int block_x, unsigned int block_y,
                                unsigned int block_z,
                                unsigned int shared_mem_bytes,
                                CUstream stream,
                                void** kernel_params,
                                void** extra) {
    ++g_launch_calls;
    CHECK(grid_z == 1); CHECK(block_z == 1);
    CHECK(shared_mem_bytes == 0); CHECK(stream == 0);
    CHECK(kernel_params != 0); CHECK(extra == 0);

    if (g_expected_launch == 1) {
        CHECK(function == g_fake_flash);
        CHECK(grid_x == 2 && grid_y == 4);
        CHECK(block_x == 1 && block_y == 1);
        CHECK(*(CUdeviceptr*)kernel_params[0] == UINT64_C(0x10000));
        CHECK(*(CUdeviceptr*)kernel_params[1] == g_allocator_k);
        CHECK(*(CUdeviceptr*)kernel_params[2] == g_allocator_v);
        CHECK(*(CUdeviceptr*)kernel_params[3] == UINT64_C(0x40000));
        CHECK(*(CUdeviceptr*)kernel_params[4] == UINT64_C(0x50000));
        CHECK(*(CUdeviceptr*)kernel_params[5] == UINT64_C(0x60000));
        CHECK(*(uint64_t*)kernel_params[6] == 256);
        CHECK(*(uint64_t*)kernel_params[7] == 4096);
        CHECK(*(uint64_t*)kernel_params[8] == 12288);
        CHECK(*(uint32_t*)kernel_params[9]  == 1);
        CHECK(*(uint32_t*)kernel_params[10] == 4);
        CHECK(*(uint32_t*)kernel_params[11] == 2);
        CHECK(*(uint32_t*)kernel_params[12] == 64);
        CHECK(*(uint32_t*)kernel_params[13] == 3);
        CHECK(*(uint32_t*)kernel_params[14] == SOV_KV_MAX_BLOCKS_PER_SEQ);
    } else if (g_expected_launch == 2) {
        CHECK(function == g_fake_rmsnorm);
        CHECK(grid_x == 1 && grid_y == 1);
        CHECK(block_x == 1 && block_y == 1);
        CHECK(*(CUdeviceptr*)kernel_params[0] == UINT64_C(0x70000));
        CHECK(*(CUdeviceptr*)kernel_params[1] == UINT64_C(0x80000));
        CHECK(*(CUdeviceptr*)kernel_params[2] == UINT64_C(0x90000));
        CHECK(*(uint32_t*)kernel_params[3] == 129);
    } else if (g_expected_launch == 3) {
        CHECK(function == g_fake_silu);
        CHECK(grid_x == 2 && grid_y == 1);
        CHECK(block_x == 128 && block_y == 1);
        CHECK(*(CUdeviceptr*)kernel_params[0] == UINT64_C(0xa0000));
        CHECK(*(CUdeviceptr*)kernel_params[1] == UINT64_C(0xb0000));
        CHECK(*(uint32_t*)kernel_params[2] == 129);
    } else CHECK(!"unexpected launch");
    return CUDA_SUCCESS;
}

int sov_cuda_gemm_init(void) { ++g_gemm_init_calls; return g_gemm_init_result; }
void sov_cuda_gemm_shutdown(void) { ++g_gemm_shutdown_calls; }

static int commit_cuda_validation(
    void* rowm_context,
    const sov_cuda_validation_evidence_t* evidence,
    sov_rowm_cuda_validation_commit_t* commit_out) {
    size_t index;
    ++g_rowm_commit_calls;
    CHECK(rowm_context == (void*)(uintptr_t)0xcafeu);
    CHECK(evidence != 0);
    CHECK(evidence->ptx_target == 89);
    CHECK(evidence->flash_ptx.bytes == flash_attention_ptx);
    CHECK(evidence->flash_ptx.size == 2);
    CHECK(evidence->gemm_ptx.bytes == gemm_ptx);
    CHECK(evidence->gemm_ptx.size == 2);
    CHECK(evidence->resolved_kernel_mask == SOV_CUDA_REQUIRED_KERNEL_MASK);
    memset(commit_out, 0, sizeof(*commit_out));
    commit_out->version          = SOV_ROWM_CUDA_COMMIT_VERSION;
    commit_out->validation_epoch = 1;
    for (index = 0; index < 32; ++index) {
        commit_out->record_id[index]              = (uint8_t)(index + 1u);
        commit_out->committed_rowm_root[index]    = (uint8_t)(index + 2u);
        commit_out->embedded_worm_receipt_hash[index] = (uint8_t)(index + 3u);
    }
    return 0;
}

static int call_attention(int seqs, int query_heads, uint32_t layer,
                          CUdeviceptr q, CUdeviceptr out,
                          CUdeviceptr table, CUdeviceptr lens) {
    return sov_cuda_flash_attention(seqs, query_heads, layer, q, out, table, lens);
}

static void test_lookup_failure_cleanup(void) {
    g_fail_lookup_call = 2;
    CHECK(sov_cuda_kernels_init() == CUDA_ERROR_NOT_FOUND);
    CHECK(g_driver_init_calls  == 1);
    CHECK(g_module_load_calls  == 1);
    CHECK(g_module_unload_calls == 1);
    CHECK(g_registered_power   == 0);
    CHECK(g_gemm_init_calls    == 0);
    CHECK(g_gemm_shutdown_calls == 1);
    g_fail_lookup_call = 0;
}

static void test_gemm_failure_cleanup(void) {
    g_gemm_init_result = -33;
    CHECK(sov_cuda_kernels_init() == -33);
    CHECK(g_module_load_calls   == 2);
    CHECK(g_module_unload_calls == 2);
    CHECK(g_registered_power    == 0);
    CHECK(g_gemm_init_calls     == 1);
    CHECK(g_gemm_shutdown_calls == 2);
    g_gemm_init_result = 0;
}

static void test_dispatch_and_shutdown(void) {
    reset_allocator_contract();
    CHECK(sov_cuda_kernels_init() == CUDA_SUCCESS);
    CHECK(sov_cuda_kernels_init() == CUDA_SUCCESS);
    CHECK(g_module_load_calls   == 3);
    CHECK(g_config_copy_calls   == 2);
    CHECK(g_registered_power    == g_fake_power);
    CHECK(g_gemm_init_calls     == 3);

    g_expected_launch = 1;
    CHECK(call_attention(2, 4, 1,
                         UINT64_C(0x10000), UINT64_C(0x40000),
                         UINT64_C(0x50000), UINT64_C(0x60000))
          == SOV_CUDA_ROWM_UNAUTHORIZED);
    CHECK(g_launch_calls == 0);

    CHECK(sov_cuda_kernels_authorize_rowm(
              commit_cuda_validation, (void*)(uintptr_t)0xcafeu)
          == SOV_CUDA_ROWM_OK);
    CHECK(g_rowm_commit_calls == 1);

    g_expected_launch = 1;
    CHECK(call_attention(2, 4, 1,
                         UINT64_C(0x10000), UINT64_C(0x40000),
                         UINT64_C(0x50000), UINT64_C(0x60000))
          == CUDA_SUCCESS);

    g_expected_launch = 2;
    CHECK(sov_cuda_rmsnorm_fused(
              UINT64_C(0x70000), UINT64_C(0x80000),
              UINT64_C(0x90000), 129) == CUDA_SUCCESS);

    g_expected_launch = 3;
    CHECK(sov_cuda_silu_fused(
              UINT64_C(0xa0000), UINT64_C(0xb0000), 129) == CUDA_SUCCESS);

    sov_cuda_kernels_shutdown();
    CHECK(g_registered_power    == 0);
    CHECK(g_module_unload_calls == 3);
    CHECK(g_gemm_shutdown_calls == 3);
    CHECK(g_power_sync_calls    == 3);
    CHECK(g_launch_calls        == 3);
    CHECK(sov_cuda_validation_require_authorized(1) == SOV_CUDA_ROWM_UNAUTHORIZED);
}

int main(void) {
    reset_allocator_contract();
    test_lookup_failure_cleanup();
    test_gemm_failure_cleanup();
    test_dispatch_and_shutdown();
    puts("cuda kernel dispatch host tests passed");
    return 0;
}
