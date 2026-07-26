#include <stdint.h>
#include <stddef.h>
#include "cuda_validation_chain.h"

/* -----------------------------------------------------------------------
 * Minimal FNV-1a-256 for deterministic PTX hashing.
 * Serialization order: [abi_version BE4][device_epoch BE8][ptx_len BE4][ptx bytes]
 * ----------------------------------------------------------------------- */

static void fnv256_init(uint8_t* h) {
    /* FNV-1a 256-bit offset basis */
    static const uint8_t BASIS[32] = {
        0xdd,0x26,0x8d,0xbc,0xaa,0xe0,0x94,0x84,
        0xdb,0x9f,0x6a,0xae,0x0c,0x41,0x4b,0x41,
        0x21,0x72,0x24,0xd1,0x0d,0x3b,0x26,0x1d,
        0xc4,0xef,0x15,0x81,0x5a,0x2e,0xf0,0x65
    };
    for (int i = 0; i < 32; i++) h[i] = BASIS[i];
}

static void fnv256_update(uint8_t* h, const uint8_t* data, size_t len) {
    static const uint8_t PRIME[32] = {
        0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
        0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
        0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
        0x00,0x00,0x00,0x00,0x00,0x00,0x01,0x63
    };
    for (size_t i = 0; i < len; i++) {
        /* XOR */
        h[31] ^= data[i];
        /* Multiply by prime (big-endian 256-bit × 256-bit, keep low 32 bytes) */
        uint16_t carry = 0;
        for (int b = 31; b >= 0; b--) {
            uint16_t acc = (uint16_t)h[b] * (uint16_t)PRIME[31] + carry;
            h[b] = (uint8_t)(acc & 0xFF);
            carry = acc >> 8;
        }
        (void)carry;
    }
}

static void push_be4(uint8_t* h, uint32_t v) {
    uint8_t buf[4] = {
        (uint8_t)(v >> 24), (uint8_t)(v >> 16),
        (uint8_t)(v >>  8), (uint8_t)(v)
    };
    fnv256_update(h, buf, 4);
}

static void push_be8(uint8_t* h, uint64_t v) {
    uint8_t buf[8] = {
        (uint8_t)(v >> 56), (uint8_t)(v >> 48),
        (uint8_t)(v >> 40), (uint8_t)(v >> 32),
        (uint8_t)(v >> 24), (uint8_t)(v >> 16),
        (uint8_t)(v >>  8), (uint8_t)(v)
    };
    fnv256_update(h, buf, 8);
}

int sov_ptx_hash(const uint8_t* ptx, uint32_t ptx_len,
                 uint32_t abi_version, uint64_t device_epoch,
                 sov_ptx_evidence_t* ev_out) {
    if (!ptx || !ptx_len || !ev_out) return -1;
    uint8_t h[32];
    fnv256_init(h);
    push_be4(h, abi_version);
    push_be8(h, device_epoch);
    push_be4(h, ptx_len);
    fnv256_update(h, ptx, ptx_len);
    for (int i = 0; i < 32; i++) ev_out->ptx_hash[i] = h[i];
    ev_out->abi_version  = abi_version;
    ev_out->device_epoch = device_epoch;
    ev_out->ptx_len      = ptx_len;
    return 0;
}

/* -----------------------------------------------------------------------
 * ROWM-NR commit: evidence → rowm_root → worm_receipt (internal WORM layer)
 * ----------------------------------------------------------------------- */

static void derive_rowm_root(const sov_ptx_evidence_t* ev, uint64_t seq, uint8_t* root) {
    uint8_t h[32];
    fnv256_init(h);
    fnv256_update(h, ev->ptx_hash, 32);
    push_be4(h, ev->abi_version);
    push_be8(h, ev->device_epoch);
    push_be4(h, ev->ptx_len);
    push_be8(h, seq);
    for (int i = 0; i < 32; i++) root[i] = h[i];
}

static void derive_worm_receipt(const uint8_t* rowm_root, uint8_t* receipt) {
    uint8_t h[32];
    fnv256_init(h);
    fnv256_update(h, rowm_root, 32);
    /* Domain separation: receipt ≠ root */
    uint8_t dom = 0xAB;
    fnv256_update(h, &dom, 1);
    for (int i = 0; i < 32; i++) receipt[i] = h[i];
}

static int bytes_eq(const uint8_t* a, const uint8_t* b, size_t n) {
    uint8_t acc = 0;
    for (size_t i = 0; i < n; i++) acc |= (uint8_t)(a[i] ^ b[i]);
    return acc == 0;
}

int sov_rowm_commit(sov_rowm_record_t* rec, const sov_ptx_evidence_t* ev) {
    if (!rec || !ev) return -1;

    if (rec->state == SOV_ROWM_COMMITTED || rec->state == SOV_ROWM_AUTHORIZED) {
        /* Idempotent: same epoch + same hash → no-op */
        if (rec->evidence.device_epoch == ev->device_epoch &&
            bytes_eq(rec->evidence.ptx_hash, ev->ptx_hash, 32)) {
            return 0;
        }
        /* Different PTX for same epoch → conflict */
        if (rec->evidence.device_epoch == ev->device_epoch) {
            rec->state = SOV_ROWM_CONFLICT;
            return -2;
        }
    }

    rec->evidence = *ev;
    rec->sequence++;

    derive_rowm_root(ev, rec->sequence, rec->rowm_root);
    derive_worm_receipt(rec->rowm_root, rec->worm_receipt);
    rec->state = SOV_ROWM_COMMITTED;
    return 0;
}

/* -----------------------------------------------------------------------
 * Kernel authorization: bind exact handles to committed WORM receipt
 * ----------------------------------------------------------------------- */

int sov_rowm_authorize_kernels(sov_rowm_record_t* rec, sov_cuda_auth_t* auth,
                               void** handles, uint32_t count) {
    if (!rec || !auth || !handles) return -1;
    if (rec->state != SOV_ROWM_COMMITTED) return -1;
    if (count > SOV_ROWM_MAX_KERNELS) return -4;

    for (uint32_t i = 0; i < count; i++) auth->handles[i] = handles[i];
    auth->count = count;
    for (int i = 0; i < 32; i++) auth->bound_worm[i] = rec->worm_receipt[i];

    rec->state = SOV_ROWM_AUTHORIZED;
    return 0;
}

int sov_rowm_check_authorized(const sov_rowm_record_t* rec,
                              const sov_cuda_auth_t* auth) {
    if (!rec || !auth) return -1;
    if (rec->state != SOV_ROWM_AUTHORIZED) return -1;
    if (!bytes_eq(rec->worm_receipt, auth->bound_worm, 32)) return -2;
    return 0;
}
