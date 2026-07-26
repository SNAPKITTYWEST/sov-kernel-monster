/* sampler.c — zero-libc top-p nucleus sampler with temperature
 * No malloc, no qsort, no stdlib. xorshift64* RNG.
 */
typedef unsigned long long uint64_t;
typedef unsigned int       uint32_t;
typedef int                int32_t;
typedef unsigned long long CUdeviceptr;
typedef int                CUresult;
#define CUDA_SUCCESS 0

extern CUresult (*g_cuMemcpyDtoH_v2)(void*, CUdeviceptr, unsigned long long);

/* ── intrinsic expf (no libm) ───────────────────────────────────
 * exp(x) = 2^(x * log2e) via hardware ex2.approx equivalent
 * We use the compiler's built-in when available; on MSVC/clang
 * this will lower to the FPU instruction.
 */
static float sov_expf(float x) {
    /* Clamp to avoid overflow */
    if (x > 88.0f) return 3.402823466e+38f;
    if (x < -88.0f) return 0.0f;
    /* Use __builtin_expf if available, otherwise polynomial */
#if defined(__GNUC__) || defined(__clang__)
    return __builtin_expf(x);
#else
    /* Horner's method: e^x ~ 1 + x + x^2/2 + x^3/6 + x^4/24 + x^5/120 */
    float t = 1.0f + x * (1.0f + x * (0.5f + x * (0.16666667f + x * (0.041666668f + x * 0.008333334f))));
    return t;
#endif
}

/* ── candidate type ─────────────────────────────────────────── */
#define SOV_MAX_TOPK 64

typedef struct {
    float   prob;
    int32_t index;
} sov_cand_t;

/* ── partial top-k selection via insertion sort ─────────────── */
static int sov_partial_topk(const float* logits, int vocab_size,
                             int topk, sov_cand_t* out) {
    int n = (vocab_size < topk) ? vocab_size : topk;

    for (int i = 0; i < n; ++i) {
        out[i].prob  = logits[i];
        out[i].index = i;
    }
    /* insertion sort: descending by logit */
    for (int i = 1; i < n; ++i) {
        sov_cand_t tmp = out[i];
        int j = i - 1;
        while (j >= 0 && out[j].prob < tmp.prob) {
            out[j + 1] = out[j];
            --j;
        }
        out[j + 1] = tmp;
    }
    /* scan remaining elements */
    for (int i = n; i < vocab_size; ++i) {
        float v = logits[i];
        if (v <= out[n - 1].prob) continue;
        sov_cand_t tmp = { v, i };
        int j = n - 2;
        while (j >= 0 && out[j].prob < tmp.prob) {
            out[j + 1] = out[j];
            --j;
        }
        out[j + 1] = tmp;
    }
    return n;
}

/* ── top-p (nucleus) filter ─────────────────────────────────── */
static int sov_top_p_filter(sov_cand_t* cands, int n, float top_p) {
    if (top_p >= 1.0f || n <= 1) return n;

    /* softmax over top-k logits */
    float max_l = cands[0].prob;
    float sum   = 0.0f;
    for (int i = 0; i < n; ++i) {
        float p = sov_expf(cands[i].prob - max_l);
        cands[i].prob = p;
        sum += p;
    }
    for (int i = 0; i < n; ++i) cands[i].prob /= sum;

    /* nucleus truncation */
    float cumsum = 0.0f;
    int keep = n;
    for (int i = 0; i < n; ++i) {
        cumsum += cands[i].prob;
        if (cumsum >= top_p) { keep = i + 1; break; }
    }
    return keep;
}

/* ── categorical sample from (already normalised) cands ─────── */
static int sov_sample_categorical(sov_cand_t* cands, int n,
                                   uint64_t* rng) {
    /* xorshift64* */
    uint64_t x = *rng;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    *rng = x;
    float u = (float)((x * 0x2545F4914F6CDD1Dull) >> 32) / 4294967296.0f;

    float cumsum = 0.0f;
    for (int i = 0; i < n; ++i) {
        cumsum += cands[i].prob;
        if (u < cumsum) return cands[i].index;
    }
    return cands[n - 1].index;
}

/* ── sov_sample_token ───────────────────────────────────────────
 * d_logits: device pointer to vocab_size float32 logits
 * Returns sampled token id, or negative on error.
 * ---------------------------------------------------------------- */
int sov_sample_token(CUdeviceptr d_logits, int vocab_size,
                     float temperature, float top_p, int top_k,
                     uint64_t* rng_state) {
    static float    h_logits[128000];
    static sov_cand_t cands[SOV_MAX_TOPK];

    if (vocab_size <= 0 || vocab_size > 128000) return -1;
    if (!g_cuMemcpyDtoH_v2) return -2;

    CUresult err = g_cuMemcpyDtoH_v2(h_logits, d_logits,
                                      (unsigned long long)(vocab_size * (int)sizeof(float)));
    if (err != CUDA_SUCCESS) return -3;

    /* greedy fast-path */
    if (temperature == 0.0f) {
        float best = h_logits[0]; int best_i = 0;
        for (int i = 1; i < vocab_size; ++i) {
            if (h_logits[i] > best) { best = h_logits[i]; best_i = i; }
        }
        return best_i;
    }

    /* temperature scaling */
    if (temperature != 1.0f && temperature > 0.0f) {
        float inv_t = 1.0f / temperature;
        for (int i = 0; i < vocab_size; ++i) h_logits[i] *= inv_t;
    }

    int eff_topk = top_k;
    if (eff_topk <= 0 || eff_topk > vocab_size) eff_topk = vocab_size;
    if (eff_topk > SOV_MAX_TOPK) eff_topk = SOV_MAX_TOPK;

    int n = sov_partial_topk(h_logits, vocab_size, eff_topk, cands);

    /* if top_p < 1 we need probabilities for nucleus filter */
    if (top_p < 1.0f) {
        n = sov_top_p_filter(cands, n, top_p);
    } else {
        /* just softmax for sampling */
        float max_l = cands[0].prob, sum = 0.0f;
        for (int i = 0; i < n; ++i) {
            float p = sov_expf(cands[i].prob - max_l);
            cands[i].prob = p; sum += p;
        }
        for (int i = 0; i < n; ++i) cands[i].prob /= sum;
    }

    return sov_sample_categorical(cands, n, rng_state);
}

/* ── sov_sample_greedy ──────────────────────────────────────────── */
int sov_sample_greedy(CUdeviceptr d_logits, int vocab_size) {
    static float h_logits[128000];
    if (vocab_size <= 0 || vocab_size > 128000) return -1;
    if (!g_cuMemcpyDtoH_v2) return -2;
    CUresult err = g_cuMemcpyDtoH_v2(h_logits, d_logits,
                                      (unsigned long long)(vocab_size * (int)sizeof(float)));
    if (err != CUDA_SUCCESS) return -3;
    float best = h_logits[0]; int best_i = 0;
    for (int i = 1; i < vocab_size; ++i) {
        if (h_logits[i] > best) { best = h_logits[i]; best_i = i; }
    }
    return best_i;
}
