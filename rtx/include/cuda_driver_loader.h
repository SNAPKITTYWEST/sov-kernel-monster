#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint64_t  CUdeviceptr;
typedef int32_t   CUdevice;
typedef int32_t   CUdevice_attribute;
typedef int32_t   CUresult;
typedef struct CUctx_st*    CUcontext;
typedef struct CUmod_st*    CUmodule;
typedef struct CUfunc_st*   CUfunction;
typedef struct CUstream_st* CUstream;
typedef struct CUevent_st*  CUevent;

enum {
    CUDA_SUCCESS               = 0,
    CUDA_ERROR_INVALID_VALUE   = 1,
    CUDA_ERROR_OUT_OF_MEMORY   = 2,
    CUDA_ERROR_NOT_INITIALIZED = 3,
    CUDA_ERROR_DEINITIALIZED   = 4,
    CUDA_ERROR_NO_DEVICE       = 100,
    CUDA_ERROR_INVALID_DEVICE  = 101,
    CUDA_ERROR_INVALID_IMAGE   = 200,
    CUDA_ERROR_INVALID_CONTEXT = 201,
    CUDA_ERROR_NOT_FOUND       = 500,
    CUDA_ERROR_UNKNOWN         = 999
};

/* Driver and primary-context lifetime */
int  sov_cuda_init(void);
void sov_cuda_shutdown(void);
int  sov_cuda_is_initialized(void);

/* Runtime identity — used by the ROWM-NR authorization path */
typedef struct {
    uint32_t driver_version;
    uint32_t compute_capability_major;
    uint32_t compute_capability_minor;
    uint64_t context_generation;
    uint8_t  device_uuid[16];
} sov_cuda_runtime_identity_t;

uint64_t sov_cuda_context_generation(void);
CUresult sov_cuda_get_runtime_identity(sov_cuda_runtime_identity_t* out);

#define SOV_CUDA_BACKEND_SOV_RTX    1u
#define SOV_CUDA_REQUIRED_KERNEL_MASK \
    ((uint64_t)0x07u)   /* flash_attention_paged | rmsnorm_fused | silu_fused */

/* Checked access to the dynamically resolved CUDA Driver API */
CUresult sov_cuda_module_load_data(CUmodule* module, const void* image);
CUresult sov_cuda_module_get_function(CUfunction* function, CUmodule module,
                                      const char* name);
CUresult sov_cuda_module_get_global(CUdeviceptr* device_ptr, size_t* bytes,
                                    CUmodule module, const char* name);
CUresult sov_cuda_module_unload(CUmodule module);
CUresult sov_cuda_launch_kernel(CUfunction function,
                                unsigned int grid_x,
                                unsigned int grid_y,
                                unsigned int grid_z,
                                unsigned int block_x,
                                unsigned int block_y,
                                unsigned int block_z,
                                unsigned int shared_mem_bytes,
                                CUstream stream,
                                void** kernel_params,
                                void** extra);
CUresult sov_cuda_mem_alloc(CUdeviceptr* device_ptr, size_t bytes);
CUresult sov_cuda_mem_free(CUdeviceptr device_ptr);
int      sov_cuda_memcpy_h2d(void* device_dst, const void* host_src, size_t bytes);
CUresult sov_cuda_memcpy_d2h(void* host_dst, CUdeviceptr device_src, size_t bytes);

/* Power state device symbol binding */
CUresult sov_cuda_register_power_state_device(CUdeviceptr device_ptr);
CUresult sov_cuda_sync_power_state(void);

/* PTX module dispatch */
int  sov_cuda_kernels_init(void);
void sov_cuda_kernels_shutdown(void);
int  sov_cuda_rmsnorm_fused(CUdeviceptr x, CUdeviceptr weight,
                            CUdeviceptr out, uint32_t element_count);
int  sov_cuda_silu_fused(CUdeviceptr x, CUdeviceptr out,
                         uint32_t element_count);

/* GEMM dispatch */
int  sov_cuda_gemm_init(void);
void sov_cuda_gemm_shutdown(void);
int  sov_cuda_gemm(CUdeviceptr A, CUdeviceptr B, CUdeviceptr C,
                   int M, int N, int K);
int  sov_cuda_gemm_ex(CUdeviceptr A, CUdeviceptr B, CUdeviceptr C,
                      int M, int N, int K,
                      int lda, int ldb, int ldc);

/* ROWM-NR kernel authorization */
struct sov_rowm_cuda_validation_commit_t;
typedef int (*sov_rowm_commit_cuda_validation_fn)(
    void* rowm_context,
    const void* evidence,
    struct sov_rowm_cuda_validation_commit_t* commit_out);

int sov_cuda_kernels_authorize_rowm(
    sov_rowm_commit_cuda_validation_fn commit_fn,
    void* rowm_context);

/* Compatibility entry points retained for the existing RTX public API */
int   sov_cuda_load_ptx(const char* ptx_data, unsigned int ptx_size,
                        void** module_out);
void* sov_cuda_malloc(size_t bytes);

#ifdef __cplusplus
}
#endif
