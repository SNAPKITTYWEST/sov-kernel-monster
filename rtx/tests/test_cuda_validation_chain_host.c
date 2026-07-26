#include <stdio.h>
#include <string.h>
#include "cuda_validation_chain.h"
#include "sov_test_stubs.h"

static const uint8_t FAKE_PTX_A[] = "// fake ptx kernel A .entry main";
static const uint8_t FAKE_PTX_B[] = "// fake ptx kernel B .entry main";

static int test_hash_deterministic(void) {
    sov_ptx_evidence_t ev1, ev2;
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_A, sizeof(FAKE_PTX_A), 1, 100, &ev1) == 0);
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_A, sizeof(FAKE_PTX_A), 1, 100, &ev2) == 0);
    SOV_ASSERT(memcmp(ev1.ptx_hash, ev2.ptx_hash, 32) == 0);
    SOV_PASS("hash_deterministic");
    return 0;
}

static int test_hash_differs_on_ptx(void) {
    sov_ptx_evidence_t ev1, ev2;
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_A, sizeof(FAKE_PTX_A), 1, 100, &ev1) == 0);
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_B, sizeof(FAKE_PTX_B), 1, 100, &ev2) == 0);
    SOV_ASSERT(memcmp(ev1.ptx_hash, ev2.ptx_hash, 32) != 0);
    SOV_PASS("hash_differs_on_ptx");
    return 0;
}

static int test_commit_basic(void) {
    sov_rowm_record_t rec;
    memset(&rec, 0, sizeof(rec));
    sov_ptx_evidence_t ev;
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_A, sizeof(FAKE_PTX_A), 1, 200, &ev) == 0);
    SOV_ASSERT(sov_rowm_commit(&rec, &ev) == 0);
    SOV_ASSERT(rec.state == SOV_ROWM_COMMITTED);
    SOV_ASSERT(rec.sequence == 1);
    SOV_PASS("commit_basic");
    return 0;
}

static int test_commit_idempotent(void) {
    sov_rowm_record_t rec;
    memset(&rec, 0, sizeof(rec));
    sov_ptx_evidence_t ev;
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_A, sizeof(FAKE_PTX_A), 1, 300, &ev) == 0);
    SOV_ASSERT(sov_rowm_commit(&rec, &ev) == 0);
    uint8_t saved_root[32];
    memcpy(saved_root, rec.rowm_root, 32);
    SOV_ASSERT(sov_rowm_commit(&rec, &ev) == 0);
    SOV_ASSERT(rec.sequence == 1);
    SOV_ASSERT(memcmp(rec.rowm_root, saved_root, 32) == 0);
    SOV_PASS("commit_idempotent");
    return 0;
}

static int test_commit_conflict(void) {
    sov_rowm_record_t rec;
    memset(&rec, 0, sizeof(rec));
    sov_ptx_evidence_t evA, evB;
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_A, sizeof(FAKE_PTX_A), 1, 400, &evA) == 0);
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_B, sizeof(FAKE_PTX_B), 1, 400, &evB) == 0);
    /* Same epoch, different PTX hash must match evidence */
    evB.device_epoch = 400;
    SOV_ASSERT(sov_rowm_commit(&rec, &evA) == 0);
    SOV_ASSERT(sov_rowm_commit(&rec, &evB) == -2);
    SOV_ASSERT(rec.state == SOV_ROWM_CONFLICT);
    SOV_PASS("commit_conflict");
    return 0;
}

static int test_authorize_and_check(void) {
    sov_rowm_record_t rec;
    memset(&rec, 0, sizeof(rec));
    sov_ptx_evidence_t ev;
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_A, sizeof(FAKE_PTX_A), 1, 500, &ev) == 0);
    SOV_ASSERT(sov_rowm_commit(&rec, &ev) == 0);

    void* handles[2] = { (void*)0x1, (void*)0x2 };
    sov_cuda_auth_t auth;
    memset(&auth, 0, sizeof(auth));
    SOV_ASSERT(sov_rowm_authorize_kernels(&rec, &auth, handles, 2) == 0);
    SOV_ASSERT(rec.state == SOV_ROWM_AUTHORIZED);
    SOV_ASSERT(sov_rowm_check_authorized(&rec, &auth) == 0);
    SOV_PASS("authorize_and_check");
    return 0;
}

static int test_authorize_without_commit_fails(void) {
    sov_rowm_record_t rec;
    memset(&rec, 0, sizeof(rec));
    void* handles[1] = { (void*)0x1 };
    sov_cuda_auth_t auth;
    memset(&auth, 0, sizeof(auth));
    SOV_ASSERT(sov_rowm_authorize_kernels(&rec, &auth, handles, 1) == -1);
    SOV_PASS("authorize_without_commit_fails");
    return 0;
}

static int test_receipt_mismatch_rejected(void) {
    sov_rowm_record_t rec;
    memset(&rec, 0, sizeof(rec));
    sov_ptx_evidence_t ev;
    SOV_ASSERT(sov_ptx_hash(FAKE_PTX_A, sizeof(FAKE_PTX_A), 1, 600, &ev) == 0);
    SOV_ASSERT(sov_rowm_commit(&rec, &ev) == 0);
    void* handles[1] = { (void*)0x1 };
    sov_cuda_auth_t auth;
    memset(&auth, 0, sizeof(auth));
    SOV_ASSERT(sov_rowm_authorize_kernels(&rec, &auth, handles, 1) == 0);
    /* Tamper receipt */
    auth.bound_worm[0] ^= 0xFF;
    SOV_ASSERT(sov_rowm_check_authorized(&rec, &auth) == -2);
    SOV_PASS("receipt_mismatch_rejected");
    return 0;
}

int main(void) {
    int fail = 0;
    fail |= test_hash_deterministic();
    fail |= test_hash_differs_on_ptx();
    fail |= test_commit_basic();
    fail |= test_commit_idempotent();
    fail |= test_commit_conflict();
    fail |= test_authorize_and_check();
    fail |= test_authorize_without_commit_fails();
    fail |= test_receipt_mismatch_rejected();
    if (!fail) printf("ALL PASS\n");
    return fail;
}
