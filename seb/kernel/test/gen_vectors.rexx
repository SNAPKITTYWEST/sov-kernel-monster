#!/usr/bin/rexx
/* gen_vectors.rexx - Sovereign Event Bus kernel wire format test vectors */
/* Regina REXX compatible - no external dependencies except sha256sum/hmac */
/* Writes to vectors/ subdirectory */

parse arg . /* no args expected */

call RxFuncAdd 'SysLoadFuncs', 'rexxutil', 'SysLoadFuncs'
call SysLoadFuncs

/* ============================================================
 * CONSTANTS & SEEDS
 * ============================================================ */
seed = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' /* 64 hex = 32 bytes */
seed_payload_256 = copies('deadbeef', 32)  /* 256 bytes = 512 hex chars */
seed_payload_128 = copies('cafebabe', 16)  /* 128 bytes = 256 hex chars */
segment_magic = '5345474d454e5400'         /* "SEGMENT\0" 8 bytes */
segment_version = '00000001'               /* version 1, 4 bytes LE */
segment_reserved = copies('00', 20)        /* 20 bytes reserved */
segment_event_count = '00000001'           /* 1 event, 4 bytes LE */
segment_payload_total = '00000080'         /* 128 bytes total payload, 4 bytes LE */
segment_checksum = '0000000000000000'      /* 8 bytes placeholder */

/* ============================================================
 * HELPER: little-endian hex from unsigned integer
 * ============================================================ */
le64: procedure
  parse arg val
  hex = d2x(val, 16)           /* 16 hex chars = 8 bytes */
  return substr(hex,15,2)||substr(hex,13,2)||substr(hex,11,2)||substr(hex,9,2)||
         substr(hex,7,2)||substr(hex,5,2)||substr(hex,3,2)||substr(hex,1,2)

le32: procedure
  parse arg val
  hex = d2x(val, 8)            /* 8 hex chars = 4 bytes */
  return substr(hex,7,2)||substr(hex,5,2)||substr(hex,3,2)||substr(hex,1,2)

/* ============================================================
 * HELPER: SHA-256 via external command (sha256sum)
 * Input: hex string, Output: 64-char hex string
 * ============================================================ */
sha256_hex: procedure
  parse arg hex_in
  /* write hex to temp file, hash it, read back */
  tmp_in = '/tmp/sha_in_'||random(10000,99999)||'.bin'
  tmp_out = '/tmp/sha_out_'||random(10000,99999)||'.txt'
  call charout tmp_in, x2c(hex_in)
  call charout tmp_in, ''  /* close */
  'sha256sum' tmp_in '>' tmp_out
  hash_line = linein(tmp_out)
  hash = substr(hash_line, 1, 64)
  'rm -f' tmp_in tmp_out
  return hash

/* ============================================================
 * HELPER: HMAC-SHA256 via external command (openssl)
 * Input: key_hex, data_hex -> Output: 64-char hex string (padded to 64 bytes = 128 hex)
 * ============================================================ */
hmac_sha256_hex: procedure
  parse arg key_hex, data_hex
  tmp_key = '/tmp/hmac_key_'||random(10000,99999)||'.bin'
  tmp_data = '/tmp/hmac_data_'||random(10000,99999)||'.bin'
  tmp_out = '/tmp/hmac_out_'||random(10000,99999)||'.txt'
  call charout tmp_key, x2c(key_hex)
  call charout tmp_key, ''
  call charout tmp_data, x2c(data_hex)
  call charout tmp_data, ''
  'openssl dgst -sha256 -hmac' x2c(key_hex) tmp_data '>' tmp_out
  /* openssl outputs: HMAC-SHA256(stdin)= <hex> */
  hmac_line = linein(tmp_out)
  parse var hmac_line . '=' hash
  hash = strip(hash)
  'rm -f' tmp_key tmp_data tmp_out
  return hash

/* ============================================================
 * HELPER: write binary file from hex string
 * ============================================================ */
write_bin: procedure
  parse arg filepath, hex_str
  call charout filepath, x2c(hex_str)
  call charout filepath, ''
  return

/* ============================================================
 * ENSURE vectors/ DIRECTORY EXISTS
 * ============================================================ */
'mkdir -p vectors'

/* ============================================================
 * VECTOR 1: append_valid.bin
 * Valid event, seq=1, payload=256 bytes of seed
 * ============================================================ */
/* Header fields (68 bytes) */
event_type_id_1 = le64(1)                    /* event_type_id = 1 */
timestamp_ns_1 = le64(1700000000000000000)   /* fixed timestamp */
agent_id_1 = le64(42)                        /* agent_id = 42 */
payload_size_1 = le32(256)                   /* payload_size = 256 */
partition_id_1 = le32(0)                     /* partition_id = 0 */
prev_offset_1 = le64(0)                      /* prev_offset = 0 (first) */
sequence_no_1 = le64(1)                      /* sequence_no = 1 */
reserved_1 = copies('00', 12)                /* reserved 12 bytes */

header_1 = event_type_id_1 || timestamp_ns_1 || agent_id_1 || payload_size_1 ||,
           partition_id_1 || prev_offset_1 || sequence_no_1 || reserved_1
/* header_1 length = 16+16+16+8+8+16+16+24 = 136 hex chars = 68 bytes ✓ */

payload_1 = seed_payload_256                   /* 512 hex chars = 256 bytes */

/* Footer computation */
/* prev_hash = SHA256(prev_event) but first event -> 32 zero bytes */
prev_hash_1 = copies('00', 32)

/* event_hash = SHA256(header || payload) */
event_hash_input_1 = header_1 || payload_1
event_hash_1 = sha256_hex(event_hash_input_1)  /* 64 hex chars = 32 bytes */

/* signature = HMAC-SHA256(key=seed, data=header||payload||prev_hash||event_hash) padded to 64 bytes */
sig_data_1 = header_1 || payload_1 || prev_hash_1 || event_hash_1
sig_raw_1 = hmac_sha256_hex(seed, sig_data_1)  /* 64 hex chars = 32 bytes */
signature_1 = sig_raw_1 || sig_raw_1           /* pad to 64 bytes = 128 hex chars */

footer_1 = prev_hash_1 || event_hash_1 || signature_1
/* footer_1 = 64 + 64 + 128 = 256 hex chars = 128 bytes ✓ */

event_1 = header_1 || payload_1 || footer_1
call write_bin 'vectors/append_valid.bin', event_1

/* ============================================================
 * VECTOR 2: apply_invalid_sig.bin
 * Same as vector 1 but signature = 0xFF * 64 bytes
 * ============================================================ */
signature_2 = copies('ff', 64)                 /* 64 bytes = 128 hex chars of FF */
footer_2 = prev_hash_1 || event_hash_1 || signature_2
event_2 = header_1 || payload_1 || footer_2
call write_bin 'vectors/apply_invalid_sig.bin', event_2

/* ============================================================
 * VECTOR 3: rotate_segment.bin
 * 64-byte segment header then one event with payload=128 bytes
 * ============================================================ */
/* Segment header (64 bytes) */
segment_header = segment_magic || segment_version || segment_reserved ||,
                 segment_event_count || segment_payload_total || segment_checksum
/* 16+8+40+8+8+16 = 96 hex chars = 48 bytes... wait, let's recount:
 * segment_magic: 16 hex = 8 bytes
 * segment_version: 8 hex = 4 bytes
 * segment_reserved: 40 hex = 20 bytes
 * segment_event_count: 8 hex = 4 bytes
 * segment_payload_total: 8 hex = 4 bytes
 * segment_checksum: 16 hex = 8 bytes
 * Total: 8+4+20+4+4+8 = 48 bytes. Need 64 bytes. Add 16 more reserved.
 */
segment_header = segment_magic || segment_version || segment_reserved || copies('00',16) ||,
                 segment_event_count || segment_payload_total || segment_checksum
/* Now: 8+4+20+16+4+4+8 = 64 bytes ✓ (128 hex chars) */

/* Event inside segment */
event_type_id_3 = le64(2)                    /* event_type_id = 2 (rotate) */
timestamp_ns_3 = le64(1700000000000000001)   /* timestamp +1 */
agent_id_3 = le64(42)                        /* same agent */
payload_size_3 = le32(128)                   /* payload_size = 128 */
partition_id_3 = le32(0)                     /* partition 0 */
prev_offset_3 = le64(0)                      /* prev_offset = 0 */
sequence_no_3 = le64(1)                      /* sequence = 1 */
reserved_3 = copies('00', 12)                /* reserved */

header_3 = event_type_id_3 || timestamp_ns_3 || agent_id_3 || payload_size_3 ||,
           partition_id_3 || prev_offset_3 || sequence_no_3 || reserved_3

payload_3 = seed_payload_128                   /* 256 hex chars = 128 bytes */

/* Footer for segment event */
prev_hash_3 = copies('00', 32)               /* first in segment */
event_hash_input_3 = header_3 || payload_3
event_hash_3 = sha256_hex(event_hash_input_3)
sig_data_3 = header_3 || payload_3 || prev_hash_3 || event_hash_3
sig_raw_3 = hmac_sha256_hex(seed, sig_data_3)
signature_3 = sig_raw_3 || sig_raw_3

footer_3 = prev_hash_3 || event_hash_3 || signature_3

event_3 = header_3 || payload_3 || footer_3

/* Full segment file: segment_header || event_3 */
segment_file = segment_header || event_3
call write_bin 'vectors/rotate_segment.bin', segment_file

/* ============================================================
 * VERIFICATION OUTPUT (stderr)
 * ============================================================ */
say 'Generated vectors/'
say '  append_valid.bin       ' length(x2c(event_1)) 'bytes'
say '  apply_invalid_sig.bin  ' length(x2c(event_2)) 'bytes'
say '  rotate_segment.bin     ' length(x2c(segment_file)) 'bytes'

exit 0