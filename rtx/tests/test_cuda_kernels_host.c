#include <stdio.h>
#include <string.h>
#include "cuda_validation_chain.h"
#include "sov_test_stubs.h"

static const uint8_t FAKE_PTX[] = "// ptx stub .entry flash_attn .entry gemm";

static void setup_authorized(sov_rowm_record_t* rec, sov_cuda_auth_t* auth,
                              void** handles, uint32_t count) {
    memset(rec, 0, sizeof(*rec));
    memset(auth, 0, sizeof(*auth));
    sov_ptx_evidence_t ev;
    sov_ptx_hash(FAKE_PTX, sizeof(FAKE_PTX), 2, 999, &ev);
    sov_rowm_commit(rec, &ev);
    sov_rowm_authorize_kernels(rec, auth, handles, count);
    sov_cuda_kernels_set_auth(rec, auth);
}

static int test_flash_attn_authorized(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[2] = { (void*)0xA1, (void*)0xA2 };
    setup_authorized(&rec, &auth, handles, 2);

    SOV_ASSERT(sov_cuda_flash_attention(1, 8, 0, 0, 0, 0, 0, 0, 64, 16) == 0);
    SOV_PASS("flash_attn_authorized");
    return 0;
}

static int test_flash_attn_no_auth(void) {
    sov_cuda_kernels_set_auth(0, 0);
    SOV_ASSERT(sov_cuda_flash_attention(1, 8, 0, 0, 0, 0, 0, 0, 64, 16) == -3);
    SOV_PASS("flash_attn_no_auth");
    return 0;
}

static int test_gemm_authorized(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[1] = { (void*)0xB1 };
    setup_authorized(&rec, &auth, handles, 1);

    SOV_ASSERT(sov_cuda_gemm(0, 0, 0, 4, 4, 4) == 0);
    SOV_PASS("gemm_authorized");
    return 0;
}

static int test_gemm_no_auth(void) {
    sov_cuda_kernels_set_auth(0, 0);
    SOV_ASSERT(sov_cuda_gemm(0, 0, 0, 4, 4, 4) == -3);
    SOV_PASS("gemm_no_auth");
    return 0;
}

static int test_launch_bound_handle(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[2] = { (void*)0xC1, (void*)0xC2 };
    setup_authorized(&rec, &auth, handles, 2);

    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xC1, 1,1,1, 32,1,1, 0, 0, 0) == 0);
    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xC2, 1,1,1, 32,1,1, 0, 0, 0) == 0);
    SOV_PASS("launch_bound_handle");
    return 0;
}

static int test_launch_unbound_handle_rejected(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[1] = { (void*)0xD1 };
    setup_authorized(&rec, &auth, handles, 1);

    /* 0xD2 was never committed as a bound handle */
    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xD2, 1,1,1, 32,1,1, 0, 0, 0) == -5);
    SOV_PASS("launch_unbound_handle_rejected");
    return 0;
}

static int test_launch_no_auth(void) {
    sov_cuda_kernels_set_auth(0, 0);
    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xE1, 1,1,1, 32,1,1, 0, 0, 0) == -3);
    SOV_PASS("launch_no_auth");
    return 0;
}

static int test_tampered_worm_blocks_launch(void) {
    sov_rowm_record_t rec;
    sov_cuda_auth_t   auth;
    void* handles[1] = { (void*)0xF1 };
    setup_authorized(&rec, &auth, handles, 1);

    /* Simulate receipt tamper after authorization */
    rec.worm_receipt[0] ^= 0xFF;

    SOV_ASSERT(sov_cuda_launch_kernel((void*)0xF1, 1,1,1, 32,1,1, 0, 0, 0) == -3);
    SOV_PASS("tampered_worm_blocks_launch");
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
    if (!fail) printf("ALL PASS\n");
    return fail;
}
