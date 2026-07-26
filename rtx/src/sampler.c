#include <stdint.h>
#include "sov_rtx.h"

/* Codex correction: 131072 covers 128256-token vocabularies (Llama-3 etc.) */
#define SOV_SAMPLER_MAX_VOCAB 131072
/* top_k arena — sized to full vocab for top_k=0 path */
#define SOV_SAMPLER_ARENA_SIZE SOV_SAMPLER_MAX_VOCAB

typedef struct {
    float   probability;
    int32_t index;
} sov_token_candidate_t;

typedef union {
    float    value;
    uint32_t bits;
} sov_float_bits_t;

static float                 g_sampler_logits[SOV_SAMPLER_MAX_VOCAB];
static sov_token_candidate_t g_sampler_arena[SOV_SAMPLER_ARENA_SIZE];

static int sov_float_is_finite(float value) {
    sov_float_bits_t repr;
    repr.value = value;
    return (repr.bits & UINT32_C(0x7f800000)) != UINT32_C(0x7f800000);
}

/*
 * Approximate exp(x) for x <= 0 only (stable softmax range).
 * Inputs below -80 are below f32 sampling resolution — return 0.
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

/*
 * Partial top-k selection via insertion sort on the first `topk` entries,
 * then a single-pass maintain-heap scan for the remainder.
 * When topk == vocab_size the full sorted list is returned.
 */
static int sov_partial_topk(
    const float* logits, int vocab_size, int topk,
    sov_token_candidate_t* out)
{
    int n = vocab_size < topk ? vocab_size : topk;
    int i, j;

    for (i = 0; i < n; ++i) {
        out[i].probability = logits[i];
        out[i].index = i;
    }
    for (i = 1; i < n; ++i) {
        sov_token_candidate_t cand = out[i];
        j = i - 1;
        while (j >= 0 && out[j].probability < cand.probability) {
            out[j + 1] = out[j];
            --j;
        }
        out[j + 1] = cand;
    }
    for (i = n; i < vocab_size; ++i) {
        float logit = logits[i];
        sov_token_candidate_t cand;
        if (logit <= out[n - 1].probability) continue;
        cand.probability = logit;
        cand.index = i;
        j = n - 2;
        while (j >= 0 && out[j].probability < cand.probability) {
            out[j + 1] = out[j];
            --j;
        }
        out[j + 1] = cand;
    }
    return n;
}

static int sov_softmax_and_top_p(
    sov_token_candidate_t* candidates, int count,
    float temperature, float top_p)
{
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

static int sov_sample_categorical(
    const sov_token_candidate_t* candidates, int count,
    uint64_t* rng_state)
{
    uint64_t x = *rng_state;
    float retained_mass = 0.0f, threshold, cumulative = 0.0f;
    int i;

    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    *rng_state = x;
    x *= UINT64_C(0x2545f4914f6cdd1d);

    for (i = 0; i < count; ++i) retained_mass += candidates[i].probability;
    threshold = (float)(x >> 40) * (1.0f / 16777216.0f) * retained_mass;

    for (i = 0; i < count; ++i) {
        cumulative += candidates[i].probability;
        if (threshold < cumulative) return candidates[i].index;
    }
    return candidates[count - 1].index;
}

/*
 * sov_sample_token — top-k / top-p / temperature sampling from GPU logits.
 *
 * d_logits   : GPU-side f32 logit buffer (cuMemcpyDtoH'd via sov_cuda_memcpy_d2h)
 * vocab_size : number of logit entries
 * temperature: > 0 for stochastic, == 0 for greedy
 * top_p      : nucleus threshold (0,1]
 * top_k      : 0 = full vocab; > 0 = at most top_k candidates before top_p
 *              Codex correction: explicit top_k is honored without a 64 cap
 * rng_state  : must be non-null and non-zero when temperature > 0
 *
 * Returns token index >= 0, or negative error code.
 */
int sov_sample_token(
    void*    d_logits,
    int      vocab_size,
    float    temperature,
    float    top_p,
    int      top_k,
    uint64_t* rng_state)
{
    int effective_topk, candidate_count;

    if (!d_logits || vocab_size <= 0 || vocab_size > SOV_SAMPLER_MAX_VOCAB) return -1;
    if (!sov_float_is_finite(temperature) || temperature < 0.0f)            return -1;
    if (!sov_float_is_finite(top_p) || top_p <= 0.0f || top_p > 1.0f)      return -1;
    if (top_k < 0)                                                           return -1;
    if (temperature > 0.0f && (!rng_state || *rng_state == UINT64_C(0)))    return -1;

    if (sov_cuda_memcpy_h2d(g_sampler_logits, d_logits,
                            (size_t)vocab_size * sizeof(float)) != 0)       return -2;
    if (sov_validate_logits(g_sampler_logits, vocab_size) != 0)             return -3;

    if (temperature == 0.0f) {
        float max_logit = g_sampler_logits[0];
        int max_index = 0, i;
        for (i = 1; i < vocab_size; ++i)
            if (g_sampler_logits[i] > max_logit) { max_logit = g_sampler_logits[i]; max_index = i; }
        return max_index;
    }

    /* top_k=0 → full vocab; otherwise honor the explicit value, no hard cap */
    effective_topk = (top_k == 0 || top_k > vocab_size) ? vocab_size : top_k;

    candidate_count = sov_partial_topk(
        g_sampler_logits, vocab_size, effective_topk, g_sampler_arena);
    candidate_count = sov_softmax_and_top_p(
        g_sampler_arena, candidate_count, temperature, top_p);
    if (candidate_count <= 0) return -3;

    return sov_sample_categorical(g_sampler_arena, candidate_count, rng_state);
}

int sov_sample_greedy(void* d_logits, int vocab_size) {
    float max_logit;
    int max_index = 0, i;

    if (!d_logits || vocab_size <= 0 || vocab_size > SOV_SAMPLER_MAX_VOCAB) return -1;
    if (sov_cuda_memcpy_h2d(g_sampler_logits, d_logits,
                            (size_t)vocab_size * sizeof(float)) != 0)       return -2;
    if (sov_validate_logits(g_sampler_logits, vocab_size) != 0)             return -3;

    max_logit = g_sampler_logits[0];
    for (i = 1; i < vocab_size; ++i)
        if (g_sampler_logits[i] > max_logit) { max_logit = g_sampler_logits[i]; max_index = i; }
    return max_index;
}
