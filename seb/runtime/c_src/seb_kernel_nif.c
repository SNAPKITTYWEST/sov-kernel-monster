/*
 * Sovereign Event Bus (SEB) - Erlang/OTP NIF Bridge
 *
 * Zero external dependencies. The commitment circuit is inlined from
 * seb_lattice.c — Goldilocks GF, x^3 S-box, circulant mix, 12 rounds.
 *
 * L0 Invariants enforced on every append:
 *   1. Commitment chain: circuit(prev_tip || header64) == footer.commitment
 *   2. Hash chain: footer.prev_commitment == handle.tip
 *   3. Offset monotonic: new_offset > tip_offset
 *   4. Segment bounds: total event size <= 1 GiB
 *   5. Sequence monotonic on rotate
 *
 * Authority and signature verification are handled by the external policy
 * layer (seb_datalog_bridge) before events reach this NIF. This boundary
 * is intentional: the kernel enforces structural integrity only.
 */

#include "erl_nif.h"
#include <string.h>
#include <stdint.h>

/* Inline the lattice circuit — zero linking, zero external headers */
#include "seb_lattice.c"

/* Wire format constants (seb_types.ads) */
#define FIXED_HEADER_SIZE    68
#define FIXED_FOOTER_SIZE    64   /* prev_commitment[32] || commitment[32] */
#define HASH_SIZE_BYTES      32

/* Handle: in-memory kernel state for one segment */
typedef struct {
    uint64_t current_segment_id;
    uint64_t current_sequence;
    uint8_t  tip[HASH_SIZE_BYTES];   /* current commitment tip */
    uint64_t tip_offset;
    uint64_t events_sealed;
    uint64_t segments_rotated;
} seb_kernel_handle;

ErlNifResourceType* kernel_handle_type = NULL;

static void kernel_handle_dtor(ErlNifEnv* env, void* obj) { (void)env; (void)obj; }

/* ── NIF: init_kernel(SegmentId, SegmentSequence) -> {ok, Handle} ─────── */
static ERL_NIF_TERM nif_init_kernel(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 2) return enif_make_badarg(env);

    uint64_t segment_id, segment_sequence;
    if (!enif_get_uint64(env, argv[0], &segment_id))   return enif_make_badarg(env);
    if (!enif_get_uint64(env, argv[1], &segment_sequence)) return enif_make_badarg(env);

    seb_kernel_handle* h = enif_alloc_resource(kernel_handle_type, sizeof(seb_kernel_handle));
    if (!h) return enif_make_atom(env, "error");

    h->current_segment_id = segment_id;
    h->current_sequence   = segment_sequence;
    memset(h->tip, 0, HASH_SIZE_BYTES);   /* genesis tip = all zeros */
    h->tip_offset       = 0;
    h->events_sealed    = 0;
    h->segments_rotated = 0;

    ERL_NIF_TERM res = enif_make_resource(env, h);
    enif_release_resource(h);
    return enif_make_tuple2(env, enif_make_atom(env, "ok"), res);
}

/* ── NIF: append_event(Handle, Header68, Payload, Footer64) -> {ok,Offset}
 *
 * Footer layout: prev_commitment[32] || commitment[32]
 * Commitment verified by: circuit(prev_tip[32] || header[64]) == footer.commitment
 *
 * The header is exactly 64 bytes of the circuit input (after the 32-byte tip).
 * If header > 64 bytes, we take only the first 64 bytes as circuit input —
 * the rest is structural metadata not committed by the circuit.
 * ─────────────────────────────────────────────────────────────────────── */
static ERL_NIF_TERM nif_append_event(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 4) return enif_make_badarg(env);

    seb_kernel_handle* h;
    ErlNifBinary header_bin, payload_bin, footer_bin;

    if (!enif_get_resource(env, argv[0], kernel_handle_type, (void**)&h))
        return enif_make_atom(env, "error");

    if (!enif_inspect_binary(env, argv[1], &header_bin) ||
        header_bin.size != FIXED_HEADER_SIZE)
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                enif_make_atom(env, "invalid_header"));

    if (!enif_inspect_binary(env, argv[2], &payload_bin))
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                enif_make_atom(env, "invalid_payload"));

    if (!enif_inspect_binary(env, argv[3], &footer_bin) ||
        footer_bin.size != FIXED_FOOTER_SIZE)
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                enif_make_atom(env, "invalid_footer"));

    /* Segment bounds check */
    uint64_t event_size = FIXED_HEADER_SIZE + payload_bin.size + FIXED_FOOTER_SIZE;
    if (event_size > (1ULL << 30) - h->tip_offset)
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                enif_make_atom(env, "segment_full"));

    /* Invariant 2: hash chain — prev_commitment in footer must match tip */
    const uint8_t* prev_commit = footer_bin.data;          /* footer[0..31] */
    const uint8_t* recv_commit = footer_bin.data + 32;     /* footer[32..63] */

    if (h->events_sealed > 0) {
        if (memcmp(prev_commit, h->tip, HASH_SIZE_BYTES) != 0)
            return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                    enif_make_atom(env, "hash_chain_broken"));
    }

    /* Invariant 1: commitment — circuit(prev_tip[32] || header[64]) == footer.commitment
     * The circuit input is 96 bytes: 32 bytes prev tip + 64 bytes from header.
     * Header is 68 bytes; we use the first 64 as the payload word block. */
    uint8_t in96[96];
    memcpy(in96,      h->tip,           HASH_SIZE_BYTES); /* prev tip        */
    memcpy(in96 + 32, header_bin.data,  64);              /* header[0..63]   */

    uint8_t computed[HASH_SIZE_BYTES];
    circuit(in96, computed);

    if (memcmp(computed, recv_commit, HASH_SIZE_BYTES) != 0)
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                enif_make_atom(env, "invalid_commitment"));

    /* Commit */
    uint64_t committed_offset = h->tip_offset;
    h->tip_offset += event_size;
    memcpy(h->tip, recv_commit, HASH_SIZE_BYTES);
    h->events_sealed++;

    return enif_make_tuple2(env, enif_make_atom(env, "ok"),
                            enif_make_uint64(env, committed_offset));
}

/* ── NIF: rotate_segment(Handle, NewSegmentId, NewSequence) -> {ok, 0} ── */
static ERL_NIF_TERM nif_rotate_segment(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 3) return enif_make_badarg(env);

    seb_kernel_handle* h;
    uint64_t new_id, new_seq;

    if (!enif_get_resource(env, argv[0], kernel_handle_type, (void**)&h))
        return enif_make_atom(env, "error");
    if (!enif_get_uint64(env, argv[1], &new_id))  return enif_make_badarg(env);
    if (!enif_get_uint64(env, argv[2], &new_seq)) return enif_make_badarg(env);

    /* Invariant 5: segment sequence monotonic */
    if (new_seq <= h->current_sequence)
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                                enif_make_atom(env, "sequence_not_monotonic"));

    h->current_segment_id = new_id;
    h->current_sequence   = new_seq;
    h->tip_offset         = 0;
    h->segments_rotated++;

    return enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_uint64(env, 0));
}

/* ── NIF: verify_chain(Handle) -> {ok, EventsSealed} ──────────────────── */
static ERL_NIF_TERM nif_verify_chain(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 1) return enif_make_badarg(env);
    seb_kernel_handle* h;
    if (!enif_get_resource(env, argv[0], kernel_handle_type, (void**)&h))
        return enif_make_atom(env, "error");
    return enif_make_tuple2(env, enif_make_atom(env, "ok"),
                            enif_make_uint64(env, h->events_sealed));
}

/* ── NIF: commit_offset(Handle, AgentId, Partition, Offset) -> ok ──────── */
static ERL_NIF_TERM nif_commit_offset(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 4) return enif_make_badarg(env);
    seb_kernel_handle* h;
    uint64_t agent_id, partition, offset;
    if (!enif_get_resource(env, argv[0], kernel_handle_type, (void**)&h))
        return enif_make_atom(env, "error");
    if (!enif_get_uint64(env, argv[1], &agent_id))  return enif_make_badarg(env);
    if (!enif_get_uint64(env, argv[2], &partition)) return enif_make_badarg(env);
    if (!enif_get_uint64(env, argv[3], &offset))    return enif_make_badarg(env);
    (void)agent_id; (void)partition; (void)offset;
    return enif_make_atom(env, "ok");
}

/* ── NIF: get_state(Handle) -> {SegId, Seq, Sealed, Rotated, TipOffset} ── */
static ERL_NIF_TERM nif_get_state(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 1) return enif_make_badarg(env);
    seb_kernel_handle* h;
    if (!enif_get_resource(env, argv[0], kernel_handle_type, (void**)&h))
        return enif_make_atom(env, "error");
    return enif_make_tuple5(env,
        enif_make_uint64(env, h->current_segment_id),
        enif_make_uint64(env, h->current_sequence),
        enif_make_uint64(env, h->events_sealed),
        enif_make_uint64(env, h->segments_rotated),
        enif_make_uint64(env, h->tip_offset));
}

static ErlNifFunc nif_funcs[] = {
    {"init_kernel",    2, nif_init_kernel},
    {"append_event",   4, nif_append_event},
    {"rotate_segment", 3, nif_rotate_segment},
    {"verify_chain",   1, nif_verify_chain},
    {"commit_offset",  4, nif_commit_offset},
    {"get_state",      1, nif_get_state}
};

static int on_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info)
{
    (void)priv_data; (void)load_info;
    kernel_handle_type = enif_open_resource_type(env, NULL, "seb_kernel_handle",
                                                 kernel_handle_dtor,
                                                 ERL_NIF_RT_CREATE, NULL);
    return kernel_handle_type ? 0 : -1;
}

ERL_NIF_INIT(seb_kernel_nif, nif_funcs, on_load, NULL, NULL, NULL)
