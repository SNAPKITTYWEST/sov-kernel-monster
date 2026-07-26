#include <stdint.h>
#include "sov_rtx.h"

/* Arena covers full vocab so top_k=0 (full-vocab nucleus) is always valid.
 * 131072 covers Llama-3 128256-token vocabularies.                          */
#define SOV_SAMPLER_MAX_VOCAB    131072
/* Threshold below which partial insertion-sort is faster than heapsort.     */
#define SOV_SAMPLER_PARTIAL_TOPK 64

typedef struct {
    float   probability;
    int32_t index;
} sov_token_candidate_t;

typedef union {
    float    value;
    uint32_t bits;
} sov_float_bits_t;

static float                 g_sampler_logits[SOV_SAMPLER_MAX_VOCAB];
static uint16_t              g_sampler_logits_f16[SOV_SAMPLER_MAX_VOCAB];
static sov_token_candidate_t g_sampler_arena[SOV_SAMPLER_MAX_VOCAB];

/* -----------------------------------------------------------------------
 * Scalar helpers
 * ----------------------------------------------------------------------- */

static int sov_float_is_finite(float value) {
    sov_float_bits_t repr;
    repr.value = value;
    return (repr.bits & UINT32_C(0x7f800000)) != UINT32_C(0x7f800000);
}

static float sov_f16_to_f32(uint16_t value) {
    const uint32_t sign     = ((uint32_t)value & UINT32_C(0x8000)) << 16;
    uint32_t exponent       = ((uint32_t)value >> 10) & UINT32_C(0x1f);
    uint32_t mantissa       = (uint32_t)value & UINT32_C(0x03ff);
    sov_float_bits_t result;

    if (exponent == 0) {
        if (mantissa == 0) { result.bits = sign; return result.value; }
        exponent = 113;
        while ((mantissa & UINT32_C(0x0400)) == 0) { mantissa <<= 1; --exponent; }
        mantissa &= UINT32_C(0x03ff);
        result.bits = sign | (exponent << 23) | (mantissa << 13);
        return result.value;
    }
    if (exponent == 31) {
        result.bits = sign | UINT32_C(0x7f800000) | (mantissa << 13);
        return result.value;
    }
    result.bits = sign | ((exponent + 112) << 23) | (mantissa << 13);
    return result.value;
}

/*
 * Approximate exp(x) for x <= 0 only (stable softmax range).
 * Inputs below -80 are below f32 sampling resolution.
 * Degree-6 polynomial after range reduction to [0, ln(2)).
 */
static float sov_exp_nonpositive(float x) {
    const float inv_ln2 = 1.4426950408889634f;
    const float ln2     = 0.6931471805599453f;
    int exponent;
    float scaled, remainder, remainder2, polynomial;
    sov_float_bits_t two_to_exponent;

    if (x >= 0.0f)   return 1.0f;
    if (x <= -80.0f) return 0.0f;

    scaled   = x * inv_ln2;
    exponent = (int)scaled;
    if ((float)exponent > scaled) --exponent;

    remainder  = x - (float)exponent * ln2;
    remainder2 = remainder * remainder;
    polynomial =
        1.0f + remainder +
        remainder2 * (0.5f +
        remainder  * (0.1666666716f +
        remainder  * (0.0416666679f +
        remainder  * (0.0083333338f +
        remainder  * 0.0013888889f))));

    two_to_exponent.bits = (uint32_t)(exponent + 127) << 23;
    return polynomial * two_to_exponent.value;
}

static int sov_validate_logits(const float* logits, int vocab_size) {
    int i;
    for (i = 0; i < vocab_size; ++i)
        if (!sov_float_is_finite(logits[i])) return -1;
    return 0;
}

/* -----------------------------------------------------------------------
 * Candidate sort — insertion sort for n ≤ PARTIAL_TOPK, heapsort for larger
 * ----------------------------------------------------------------------- */

static int sov_candidate_greater(const sov_token_candidate_t* a,
                                  const sov_token_candidate_t* b) {
    if (a->probability > b->probability) return 1;
    if (a->probability < b->probability) return 0;
    return a->index < b->index; /* tie-break: lower index first */
}

static void sov_swap_candidates(sov_token_candidate_t* a,
                                 sov_token_candidate_t* b) {
    sov_token_candidate_t tmp = *a; *a = *b; *b = tmp;
}

static void sov_heap_sift_down(sov_token_candidate_t* c, int count, int root) {
    for (;;) {
        int left = root * 2 + 1, greater;
        if (left >= count) return;
        greater = left;
        if (left + 1 < count && sov_candidate_greater(&c[left+1], &c[left]))
            greater = left + 1;
        if (!sov_candidate_greater(&c[greater], &c[root])) return;
        sov_swap_candidates(&c[root], &c[greater]);
        root = greater;
    }
}

/* Descending heapsort — result is sorted highest→lowest probability */
static void sov_heapsort_candidates(sov_token_candidate_t* c, int count) {
    int i;
    for (i = count / 2; i > 0; --i)
        sov_heap_sift_down(c, count, i - 1);
    for (i = count; i > 1; --i) {
        sov_swap_candidates(&c[0], &c[i - 1]);
        sov_heap_sift_down(c, i - 1, 0);
    }
    /* heap produces ascending order; reverse to descending */
    for (i = 0; i < count / 2; ++i)
        sov_swap_candidates(&c[i], &c[count - 1 - i]);
}

/* Partial insertion-sort top-k — O(n·k), fast for small k */
static int sov_partial_topk(const float* logits, int vocab_size, int topk,
                             sov_token_candidate_t* out) {
    int n = vocab_size < topk ? vocab_size : topk;
    int i, j;

    for (i = 0; i < n; ++i) { out[i].probability = logits[i]; out[i].index = i; }
    for (i = 1; i < n; ++i) {
        sov_token_candidate_t cand = out[i];
        j = i - 1;
        while (j >= 0 && out[j].probability < cand.probability) { out[j+1]=out[j]; --j; }
        out[j+1] = cand;
    }
    for (i = n; i < vocab_size; ++i) {
        float logit = logits[i];
        sov_token_candidate_t cand;
        if (logit <= out[n-1].probability) continue;
        cand.probability = logit; cand.index = i;
        j = n - 2;
        while (j >= 0 && out[j].probability < cand.probability) { out[j+1]=out[j]; --j; }
        out[j+1] = cand;
    }
    return n;
}

/* Route to fast path for small k, heapsort for large k */
static int sov_prepare_candidates(const float* logits, int vocab_size, int top_k) {
    int effective = (top_k == 0 || top_k > vocab_size) ? vocab_size : top_k;
    int i;

    if (effective <= SOV_SAMPLER_PARTIAL_TOPK)
        return sov_partial_topk(logits, vocab_size, effective, g_sampler_arena);

    for (i = 0; i < vocab_size; ++i) {
        g_sampler_arena[i].probability = logits[i];
        g_sampler_arena[i].index = i;
    }
    sov_heapsort_candidates(g_sampler_arena, vocab_size);
    return effective;
}

static int sov_softmax_and_top_p(sov_token_candidate_t* candidates, int count,
                                  float temperature, float top_p) {
    const float max_logit = candidates[0].probability;
    float sum = 0.0f, cumulative = 0.0f;
    int keep = count, i;

    for (i = 0; i < count; ++i) {
        float w = sov_exp_nonpositive(
            (candidates[i].probability - max_logit) / temperature);
        candidates[i].probability = w;
        sum += w;
    }
    if (!(sum > 0.0f) || !sov_float_is_finite(sum)) return -1;
    for (i = 0; i < count; ++i) {
        candidates[i].probability /= sum;
        cumulative += candidates[i].probability;
        if (cumulative >= top_p) { keep = i + 1; break; }
    }
    return keep;
}

static int sov_sample_categorical(const sov_token_candidate_t* candidates,
                                   int count, uint64_t* rng_state) {
    uint64_t x = *rng_state;
    float retained = 0.0f, threshold, cumulative = 0.0f;
    int i;

    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    *rng_state = x;
    x *= UINT64_C(0x2545f4914f6cdd1d);

    for (i = 0; i < count; ++i) retained += candidates[i].probability;
    threshold = (float)(x >> 40) * (1.0f / 16777216.0f) * retained;
    for (i = 0; i < count; ++i) {
        cumulative += candidates[i].probability;
        if (threshold < cumulative) return candidates[i].index;
    }
    return candidates[count - 1].index;
}

static int sov_validate_sampling_request(const void* d_logits, int vocab_size,
                                          float temperature, float top_p,
                                          int top_k, const uint64_t* rng_state) {
    if (!d_logits || vocab_size <= 0 || vocab_size > SOV_SAMPLER_MAX_VOCAB) return -1;
    if (!sov_float_is_finite(temperature) || temperature < 0.0f)            return -1;
    if (!sov_float_is_finite(top_p) || top_p <= 0.0f || top_p > 1.0f)      return -1;
    if (top_k < 0)                                                           return -1;
    if (temperature > 0.0f && (!rng_state || *rng_state == UINT64_C(0)))    return -1;
    return 0;
}

static int sov_argmax_loaded(int vocab_size) {
    float max = g_sampler_logits[0];
    int idx = 0, i;
    for (i = 1; i < vocab_size; ++i)
        if (g_sampler_logits[i] > max) { max = g_sampler_logits[i]; idx = i; }
    return idx;
}

static int sov_sample_loaded(int vocab_size, float temperature, float top_p,
                              int top_k, uint64_t* rng_state) {
    int count;
    if (sov_validate_logits(g_sampler_logits, vocab_size) != 0) return -3;
    if (temperature == 0.0f) return sov_argmax_loaded(vocab_size);
    count = sov_prepare_candidates(g_sampler_logits, vocab_size, top_k);
    count = sov_softmax_and_top_p(g_sampler_arena, count, temperature, top_p);
    if (count <= 0) return -3;
    return sov_sample_categorical(g_sampler_arena, count, rng_state);
}

/* -----------------------------------------------------------------------
 * Public API — f32 and f16 entry points
 * ----------------------------------------------------------------------- */

int sov_sample_token(void* d_logits, int vocab_size,
                     float temperature, float top_p, int top_k,
                     uint64_t* rng_state) {
    if (sov_validate_sampling_request(d_logits, vocab_size, temperature,
                                      top_p, top_k, rng_state) != 0) return -1;
    if (sov_cuda_memcpy_h2d(g_sampler_logits, d_logits,
                             (size_t)vocab_size * sizeof(float)) != 0) return -2;
    return sov_sample_loaded(vocab_size, temperature, top_p, top_k, rng_state);
}

int sov_sample_token_f16(void* d_logits, int vocab_size,
                          float temperature, float top_p, int top_k,
                          uint64_t* rng_state) {
    int i;
    if (sov_validate_sampling_request(d_logits, vocab_size, temperature,
                                      top_p, top_k, rng_state) != 0) return -1;
    if (sov_cuda_memcpy_h2d(g_sampler_logits_f16, d_logits,
                             (size_t)vocab_size * sizeof(uint16_t)) != 0) return -2;
    for (i = 0; i < vocab_size; ++i)
        g_sampler_logits[i] = sov_f16_to_f32(g_sampler_logits_f16[i]);
    return sov_sample_loaded(vocab_size, temperature, top_p, top_k, rng_state);
}

int sov_sample_greedy(void* d_logits, int vocab_size) {
    if (!d_logits || vocab_size <= 0 || vocab_size > SOV_SAMPLER_MAX_VOCAB) return -1;
    if (sov_cuda_memcpy_h2d(g_sampler_logits, d_logits,
                             (size_t)vocab_size * sizeof(float)) != 0) return -2;
    if (sov_validate_logits(g_sampler_logits, vocab_size) != 0) return -3;
    return sov_argmax_loaded(vocab_size);
}

int sov_sample_greedy_f16(void* d_logits, int vocab_size) {
    int i;
    if (!d_logits || vocab_size <= 0 || vocab_size > SOV_SAMPLER_MAX_VOCAB) return -1;
    if (sov_cuda_memcpy_h2d(g_sampler_logits_f16, d_logits,
                             (size_t)vocab_size * sizeof(uint16_t)) != 0) return -2;
    for (i = 0; i < vocab_size; ++i)
        g_sampler_logits[i] = sov_f16_to_f32(g_sampler_logits_f16[i]);
    if (sov_validate_logits(g_sampler_logits, vocab_size) != 0) return -3;
    return sov_argmax_loaded(vocab_size);
}
