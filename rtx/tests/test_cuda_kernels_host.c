#include <stdio.h>
#include <string.h>
#include "cuda_validation_chain.h"
#include "sov_test_stubs.h"

static const uint8_t FAKE_PTX[] = "// ptx stub .entry flash_attn .entry gemm";

/* Mock cuLaunchKernel: always succeeds — proves the dispatch path is reached */
static int mock_launch_calls = 0;
static int mock_cuLaunchKernel(void* fn,
                               unsigned gx, unsigned gy, unsigned gz,
                               unsigned bx, unsigned by, unsigned bz,
                               unsigned sm, void* stream, void** args, void* extra) {
    (void)fn; (void)gx; (void)gy; (void)gz;
    (void)bx; (void)by; (void)bz;
    (void)sm; (void)stream; (void)args; (void)extra;
    mock_launch_calls++;
    return 0; /* CUDA_SUCCESS */
}

static void setup_authorized(sov_rowm_record_t* rec, sov_cuda_auth_t* auth,
                              void** handles, uint32_t count) {
    memset(rec, 0, sizeof(*rec));
    memset(auth, 0, sizeof(*auth));
    sov_ptx_evidence_t ev;
    sov_ptx_hash(FAKE_PTX, sizeof(FAKE_PTX), 2, 999, &ev);
    sov_rowm_commit(rec, &ev);
    sov_rowm_authorize_kernels(rec, auth, handles, count);
    sov_cuda_kernels_set_auth(rec, auth);
    sov_cuda_kernels_set_launch_fn((void*)mock_cuLaunchKernel);
}

static int test_flash_attn_authorized(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    /* handles[0] = flash_attn, handles[1] = gemm */
    void* handles[2] = { (void*)0xA1, (void*)0xA2 };
    setup_authorized(&rec, &auth, handles, 2);
    mock_launch_calls = 0;

    SOV_ASSERT(sov_cuda_flash_attention(1, 8, 0, 0, 0, 0, 0, 0, 64, 16) == 0);
    SOV_ASSERT(mock_launch_calls == 1);
    SOV_PASS("flash_attn_authorized");
    return 0;
}

static int test_flash_attn_no_auth(void) {
    sov_cuda_kernels_set_auth(0, 0);
    sov_cuda_kernels_set_launch_fn(0);
    SOV_ASSERT(sov_cuda_flash_attention(1, 8, 0, 0, 0, 0, 0, 0, 64, 16) == -3);
    SOV_PASS("flash_attn_no_auth");
    return 0;
}

static int test_gemm_authorized(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[2] = { (void*)0xB0, (void*)0xB1 };
    setup_authorized(&rec, &auth, handles, 2);
    mock_launch_calls = 0;

    SOV_ASSERT(sov_cuda_gemm(0, 0, 0, 4, 4, 4) == 0);
    SOV_ASSERT(mock_launch_calls == 1);
    SOV_PASS("gemm_authorized");
    return 0;
}

static int test_gemm_no_auth(void) {
    sov_cuda_kernels_set_auth(0, 0);
    sov_cuda_kernels_set_launch_fn(0);
    SOV_ASSERT(sov_cuda_gemm(0, 0, 0, 4, 4, 4) == -3);
    SOV_PASS("gemm_no_auth");
    return 0;
}

static int test_launch_bound_handle(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[2] = { (void*)0xC1, (void*)0xC2 };
    setup_authorized(&rec, &auth, handles, 2);
    mock_launch_calls = 0;

    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xC1, 1,1,1, 32,1,1, 0, 0, 0) == 0);
    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xC2, 1,1,1, 32,1,1, 0, 0, 0) == 0);
    SOV_ASSERT(mock_launch_calls == 2);
    SOV_PASS("launch_bound_handle");
    return 0;
}

static int test_launch_unbound_handle_rejected(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[1] = { (void*)0xD1 };
    setup_authorized(&rec, &auth, handles, 1);
    mock_launch_calls = 0;

    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xD2, 1,1,1, 32,1,1, 0, 0, 0) == -5);
    SOV_ASSERT(mock_launch_calls == 0);
    SOV_PASS("launch_unbound_handle_rejected");
    return 0;
}

static int test_launch_no_auth(void) {
    sov_cuda_kernels_set_auth(0, 0);
    sov_cuda_kernels_set_launch_fn(0);
    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xE1, 1,1,1, 32,1,1, 0, 0, 0) == -3);
    SOV_PASS("launch_no_auth");
    return 0;
}

static int test_tampered_worm_blocks_launch(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[1] = { (void*)0xF1 };
    setup_authorized(&rec, &auth, handles, 1);
    mock_launch_calls = 0;

    rec.worm_receipt[0] ^= 0xFF;

    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xF1, 1,1,1, 32,1,1, 0, 0, 0) == -3);
    SOV_ASSERT(mock_launch_calls == 0);
    SOV_PASS("tampered_worm_blocks_launch");
    return 0;
}

static int test_launch_fn_absent_returns_minus6(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[1] = { (void*)0x91 };
    memset(&rec, 0, sizeof(rec));
    memset(&auth, 0, sizeof(auth));
    sov_ptx_evidence_t ev;
    sov_ptx_hash(FAKE_PTX, sizeof(FAKE_PTX), 2, 888, &ev);
    sov_rowm_commit(&rec, &ev);
    sov_rowm_authorize_kernels(&rec, &auth, handles, 1);
    sov_cuda_kernels_set_auth(&rec, &auth);
    sov_cuda_kernels_set_launch_fn(0); /* no driver loaded */

    SOV_ASSERT(sov_cuda_launch_kernel((void*)0x91, 1,1,1, 1,1,1, 0, 0, 0) == -6);
    SOV_PASS("launch_fn_absent_returns_minus6");
    return 0;
}

int main(void) {
    int fail = 0;
    fail |= test_flash_attn_authorized();
    fail |= test_flash_attn_no_auth();
    fail |= test_gemm_authorized();
    fail |= test_gemm_no_auth();
    fail |= test_launch_bound_handle();
    fail |= test_launch_unbound_handle_rejected();
    fail |= test_launch_no_auth();
    fail |= test_tampered_worm_blocks_launch();
    fail |= test_launch_fn_absent_returns_minus6();
    if (!fail) printf("ALL PASS\n");
    return fail;
}
