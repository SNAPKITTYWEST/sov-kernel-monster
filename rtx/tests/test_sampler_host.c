#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "sov_test_stubs.h"

/* Host stub: memcpy stands in for the GPU DtoH copy */
#include "sov_rtx.h"
int sov_cuda_memcpy_h2d(void* dst, const void* src, size_t sz) {
    memcpy(dst, src, sz); return 0;
}
/* Unused sov_rtx.h symbols — provide empty stubs so the TU links */
int  sov_cuda_init(void) { return 0; }
int  sov_cuda_load_ptx(const char* p, unsigned int s, void** m) { (void)p;(void)s;(void)m; return 0; }
int  sov_cuda_flash_attention(int a,int b,float*c,float*d,float*e,float*f,int*g,int*h,int i,int j)
     { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f;(void)g;(void)h;(void)i;(void)j; return 0; }
void* sov_cuda_malloc(size_t s) { (void)s; return 0; }
int  sov_scheduler_init(sov_scheduler_t* s) { (void)s; return 0; }
int  sov_scheduler_step(sov_scheduler_t* s, void* b, void* k) { (void)s;(void)b;(void)k; return 0; }
int  sov_kv_init(void* k, int a, int b, int c, int d, int e) { (void)k;(void)a;(void)b;(void)c;(void)d;(void)e; return 0; }
int  sov_kv_allocate_blocks(void* k, int a, int b, int* t) { (void)k;(void)a;(void)b;(void)t; return 0; }
int  sov_kv_append_tokens(void* k, int* t, float* kp, float* v, int l, int p)
     { (void)k;(void)t;(void)kp;(void)v;(void)l;(void)p; return 0; }
int  sov_gguf_load(const char* p, void** c) { (void)p;(void)c; return 0; }
const void* sov_gguf_get_tensor(void* c, const char* n) { (void)c;(void)n; return 0; }
int  sov_bft_vote(sov_bft_state_t* b, uint8_t v) { (void)b;(void)v; return 0; }
int  sov_bft_check_quorum(const sov_bft_state_t* b) { (void)b; return 0; }
int  sov_worm_checkpoint(void* k) { (void)k; return 0; }
int  sov_worm_restore(void* k) { (void)k; return 0; }
int  sov_set_power_state(sov_power_state_t s) { (void)s; return 0; }
sov_power_state_t sov_get_power_state(void) { return SOV_POWER_ACTIVE; }
int  sov_speculative_draft(void* b, int d, void* k) { (void)b;(void)d;(void)k; return 0; }
int  sov_speculative_verify(void* d, void* t, int l) { (void)d;(void)t;(void)l; return 0; }
float sov_janet_get(int s) { (void)s; return 0.0f; }
void  sov_janet_set(int s, float v) { (void)s;(void)v; }

#include "../src/sampler.c"

/* -----------------------------------------------------------------------
 * greedy: index of max in flat array
 * ----------------------------------------------------------------------- */
static int test_greedy(void) {
    float logits[8] = {0.1f, 0.5f, 0.9f, 0.2f, 0.3f, 0.8f, 0.4f, 0.6f};
    int tok = sov_sample_greedy(logits, 8);
    SOV_ASSERT(tok == 2);
    SOV_PASS("greedy");
    return 0;
}

/* temperature=0 greedy path through sov_sample_token */
static int test_sample_token_greedy(void) {
    float logits[4] = {0.0f, 5.0f, 1.0f, 2.0f};
    int tok = sov_sample_token(logits, 4, 0.0f, 1.0f, 0, 0);
    SOV_ASSERT(tok == 1);
    SOV_PASS("sample_token_greedy");
    return 0;
}

/* flat distribution: result must be in [0, vocab) */
static int test_flat_distribution(void) {
    static float logits[256];
    uint64_t rng = UINT64_C(0xdeadbeefcafe1234);
    int i, tok;
    for (i = 0; i < 256; i++) logits[i] = 0.0f;
    tok = sov_sample_token(logits, 256, 1.0f, 1.0f, 0, &rng);
    SOV_ASSERT(tok >= 0 && tok < 256);
    SOV_PASS("flat_distribution");
    return 0;
}

/* top_k > 64 honored — no 64 cap (Codex correction) */
static int test_topk_above_64(void) {
    static float logits[256];
    uint64_t rng = UINT64_C(0x1234567890abcdef);
    int i, tok;
    for (i = 0; i < 256; i++) logits[i] = -100.0f;
    logits[100] = 10.0f;
    for (i = 0; i < 50; i++) {
        tok = sov_sample_token(logits, 256, 1.0f, 1.0f, 128, &rng);
        SOV_ASSERT(tok == 100);
    }
    SOV_PASS("topk_above_64");
    return 0;
}

/* vocab ceiling is 131072 and over-limit is rejected */
static int test_vocab_ceiling(void) {
    float one_logit = 1.0f;
    SOV_ASSERT(SOV_SAMPLER_MAX_VOCAB == 131072);
    SOV_ASSERT(sov_sample_greedy(&one_logit, 131073) == -1);
    SOV_PASS("vocab_ceiling");
    return 0;
}

/* bad args rejected */
static int test_bad_args(void) {
    float logits[4] = {1,2,3,4};
    uint64_t rng = 1;
    SOV_ASSERT(sov_sample_greedy(NULL, 4)            == -1);
    SOV_ASSERT(sov_sample_greedy(logits, 0)           == -1);
    SOV_ASSERT(sov_sample_token(NULL, 4, 1,1,0,&rng)  == -1);
    SOV_ASSERT(sov_sample_token(logits,4,1,1,-1,&rng) == -1);
    SOV_ASSERT(sov_sample_token(logits,4,-1,1,0,&rng) == -1);
    SOV_PASS("bad_args");
    return 0;
}

int main(void) {
    int fail = 0;
    fail |= test_greedy();
    fail |= test_sample_token_greedy();
    fail |= test_flat_distribution();
    fail |= test_topk_above_64();
    fail |= test_vocab_ceiling();
    fail |= test_bad_args();
    if (!fail) printf("ALL PASS\n");
    return fail;
}
