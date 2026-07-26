/* SEB PL/I Declaration Module */
/* Generated from: SEB_SOVEREIGN_EVENT_BUS_MASTER_SPECIFICATION.xml */
/* Version: 1.0.0 */
/* Layer: L4 - Mainframe Integration (z/OS) */
/*  */
/* This module provides PL/I declarations and entry points for SEB */
/* integration on IBM z/OS systems. It implements the cryptographic */
/* envelope structure and coordination with the Sovereign Event Bus kernel. */
/*  */
/* Entry Points: */
/*   - SEB_APPEND_EVENT: Append event to SEB chain (WORM sealed) */
/*   - SEB_COMMIT_OFFSET: Commit offset marker for idempotency */
/*   - SEB_VERIFY_CHAIN: Verify chain integrity from offset N to M */
/*   - SEB_READ_EVENT: Read event by offset */
/*  */
/* Thread Safety: All entry points are reentrant and thread-safe */
/*  Coordinates with SOVEREIGN_LEDGER via DB2 or IMS */

 DECLARE VERSION CHAR (16) INIT ('1.0.0');
 DECLARE BUILD_DATE CHAR (26) INIT ('2026-07-25T00:00:00.000Z');

 /* ================================================================ */
 /* EVENT ENVELOPE DECLARATION (196 bytes total) */
 /* ================================================================ */
 /*  */
 /* This structure matches the SEBEVENT copybook on IBM i */
 /* and maintains binary compatibility with Rust kernel */

 DECLARE 1 SEB_EVENT_ENVELOPE,
      2 ENVELOPE_HEADER,
         3 OFFSET                   FIXED BIN (63) UNSIGNED,
         3 TIMESTAMP                CHAR (26),    /* ISO-8601 UTC */
         3 AGENT_ID                 CHAR (16),
         3 EVENT_TYPE               CHAR (10),
         3 PAYLOAD_SIZE             FIXED BIN (31) UNSIGNED,
         3 RESERVED                 CHAR (12),
      2 ENVELOPE_FOOTER,
         3 PREV_HASH                CHAR (64),    /* Blake3 hex */
         3 EVENT_HASH               CHAR (64),    /* Blake3 hex */
         3 SIGNATURE                CHAR (128);   /* Ed25519 hex */

 /* Envelope size constant */
 DECLARE SEB_ENVELOPE_SIZE FIXED DEC (4,0) INIT (196);


 /* ================================================================ */
 /* EVENT PAYLOAD STRUCTURE (variable-length JSON) */
 /* ================================================================ */

 DECLARE 1 SEB_EVENT_PAYLOAD,
      2 INTENT,
         3 ACTION                   CHAR (32),
         3 SUBJECT                  CHAR (128),
         3 PARAMETERS               CHAR (2048),  /* JSON string */
      2 CONTEXT,
         3 ENVIRONMENT              CHAR (16),
         3 CONSTRAINTS,
            4 NETWORK               CHAR (16),
            4 MAX_RUNTIME_MS        FIXED DEC (10,0),
            4 MAX_MEMORY_BYTES      FIXED DEC (10,0),
            4 FILESYSTEM            CHAR (16),
         3 METADATA                 CHAR (512),   /* JSON string */
      2 AUTHORITY,
         3 PRINCIPAL                CHAR (64),
         3 CREDENTIALS,
            4 CREDENTIAL_TYPE       CHAR (32),
            4 VALUE                 CHAR (128),
         3 SCOPE                    CHAR (256),   /* JSON array */
      2 EVIDENCE                    CHAR (1024); /* JSON array */


 /* ================================================================ */
 /* CRYPTOGRAPHIC STRUCTURES */
 /* ================================================================ */

 DECLARE 1 SEB_BLAKE3_HASH,
      2 HEX_DIGEST                  CHAR (64),
      2 BINARY_VALUE                CHAR (32);

 DECLARE 1 SEB_ED25519_SIGNATURE,
      2 HEX_SIGNATURE               CHAR (128),
      2 BINARY_VALUE                CHAR (64),
      2 PUBLIC_KEY_HEX              CHAR (64),
      2 PUBLIC_KEY_BINARY           CHAR (32);

 DECLARE 1 SEB_SEAL,
      2 HASH                        CHAR (64),
      2 SIGNATURE                   CHAR (128),
      2 PUBLIC_KEY                  CHAR (64),
      2 TIMESTAMP                   CHAR (26),
      2 ALGORITHM                   CHAR (16);


 /* ================================================================ */
 /* RESULT TYPES */
 /* ================================================================ */

 DECLARE 1 SEB_APPEND_RESULT,
      2 STATUS                      FIXED DEC (5,0),
      2 OFFSET                      FIXED BIN (63) UNSIGNED,
      2 ERROR_CODE                  FIXED DEC (5,0),
      2 ERROR_MESSAGE               CHAR (256);

 DECLARE 1 SEB_VERIFY_RESULT,
      2 STATUS                      FIXED DEC (5,0),
      2 CHAIN_VALID                 CHAR (1),
      2 FIRST_VALID_OFFSET          FIXED BIN (63) UNSIGNED,
      2 FIRST_INVALID_OFFSET        FIXED BIN (63) UNSIGNED,
      2 ERROR_CODE                  FIXED DEC (5,0),
      2 ERROR_MESSAGE               CHAR (256);

 DECLARE 1 SEB_READ_RESULT,
      2 STATUS                      FIXED DEC (5,0),
      2 ENVELOPE                    CHAR (196),
      2 PAYLOAD                     CHAR (32767) VARYING,
      2 ERROR_CODE                  FIXED DEC (5,0),
      2 ERROR_MESSAGE               CHAR (256);

 DECLARE 1 SEB_COMMIT_RESULT,
      2 STATUS                      FIXED DEC (5,0),
      2 COMMITTED                   CHAR (1),
      2 EXISTING_OFFSET             FIXED BIN (63) UNSIGNED,
      2 ERROR_CODE                  FIXED DEC (5,0),
      2 ERROR_MESSAGE               CHAR (256);


 /* ================================================================ */
 /* ERROR CODES */
 /* ================================================================ */

 DECLARE SEB_SUCCESS                FIXED DEC (5,0) INIT (0);
 DECLARE SEB_ERR_INVALID_OFFSET     FIXED DEC (5,0) INIT (1);
 DECLARE SEB_ERR_INVALID_SIZE       FIXED DEC (5,0) INIT (2);
 DECLARE SEB_ERR_HASH_MISMATCH      FIXED DEC (5,0) INIT (3);
 DECLARE SEB_ERR_SIG_INVALID        FIXED DEC (5,0) INIT (4);
 DECLARE SEB_ERR_FILE_READ          FIXED DEC (5,0) INIT (5);
 DECLARE SEB_ERR_FILE_WRITE         FIXED DEC (5,0) INIT (6);
 DECLARE SEB_ERR_CHAIN_BROKEN       FIXED DEC (5,0) INIT (7);
 DECLARE SEB_ERR_PAYLOAD_CORRUPT    FIXED DEC (5,0) INIT (8);
 DECLARE SEB_ERR_DB_ERROR           FIXED DEC (5,0) INIT (9);
 DECLARE SEB_ERR_DUPLICATE_HASH     FIXED DEC (5,0) INIT (10);


 /* ================================================================ */
 /* ENTRY POINT: SEB_APPEND_EVENT */
 /* ================================================================ */
 /*  */
 /* Appends an event to the SEB chain with cryptographic sealing. */
 /*  */
 /* Input: */
 /*   envelope: SEB_EVENT_ENVELOPE structure */
 /*   payload:  variable-length JSON payload */
 /*  */
 /* Output: */
 /*   result: SEB_APPEND_RESULT structure */
 /*           - STATUS: 0 = success, non-zero = error */
 /*           - OFFSET: chain offset of new event (for idempotency) */
 /*           - ERROR_CODE: detailed error code */
 /*           - ERROR_MESSAGE: human-readable error message */
 /*  */
 /* Guarantees: */
 /*   1. Deterministic: same inputs produce same hash/offset */
 /*   2. Immutable: once appended, event cannot be modified */
 /*   3. Idempotent: Bifrost_Hash deduplication prevents duplicates */
 /*   4. Verifiable: cryptographic seal can be validated independently */
 /*  */
 /* Thread Safety: Reentrant, thread-safe via SEB kernel synchronization */

 DECLARE SEB_APPEND_EVENT ENTRY (
    BYVAL FIXED BIN (63),           /* envelope offset (unused, computed) */
    BYVAL FIXED BIN (31),           /* payload size */
    BYREF CHAR (32767),             /* payload data */
    BYVAL CHAR (128),               /* bifrost_hash for dedup */
    BYVAL CHAR (64),                /* prev_hash for chain */
    BYVAL CHAR (16),                /* agent_id */
    BYVAL CHAR (10),                /* event_type */
    BYREF CHAR (196)                /* result envelope (output) */
    ) RETURNS (FIXED DEC (5,0));    /* error code */


 /* ================================================================ */
 /* ENTRY POINT: SEB_COMMIT_OFFSET */
 /* ================================================================ */
 /*  */
 /* Commits an offset to the ledger with idempotency key. */
 /* Used by SOVEREIGN_LEDGER to track settlement confirmations. */
 /*  */
 /* Input: */
 /*   bifrost_hash: immutable identifier for transaction */
 /*   offset: SEB chain offset to commit */
 /*  */
 /* Output: */
 /*   result: SEB_COMMIT_RESULT structure */
 /*           - COMMITTED: '1' if new, '0' if already existed */
 /*           - EXISTING_OFFSET: offset of duplicate (if any) */
 /*  */
 /* Guarantees: */
 /*   1. First-write-wins: first offset wins, subsequent calls return it */
 /*   2. No duplicates: Bifrost_Hash acts as immutable idempotency key */
 /*   3. Atomic: commit is all-or-nothing */
 /*  */
 /* Used by: SOVEREIGN_LEDGER, settlement confirmation flow */

 DECLARE SEB_COMMIT_OFFSET ENTRY (
    BYVAL CHAR (128),               /* bifrost_hash */
    BYVAL FIXED BIN (63),           /* offset */
    BYREF CHAR (1),                 /* committed flag (output) */
    BYREF FIXED BIN (63)            /* existing_offset (output) */
    ) RETURNS (FIXED DEC (5,0));    /* error code */


 /* ================================================================ */
 /* ENTRY POINT: SEB_VERIFY_CHAIN */
 /* ================================================================ */
 /*  */
 /* Verifies chain integrity from start offset to end offset. */
 /* Checks all cryptographic seals and hash chain continuity. */
 /*  */
 /* Input: */
 /*   start_offset: first offset to verify (inclusive) */
 /*   end_offset:   last offset to verify (inclusive) */
 /*  */
 /* Output: */
 /*   result: SEB_VERIFY_RESULT structure */
 /*           - CHAIN_VALID: '1' if entire chain is valid */
 /*           - FIRST_INVALID_OFFSET: offset of first break (if any) */
 /*  */
 /* Guarantees: */
 /*   1. Deterministic: same offsets always produce same result */
 /*   2. Complete: validates all cryptographic properties */
 /*   3. Efficient: early exit on first detected break */
 /*  */
 /* Chaos Testing: Detects corruption from kill -9 during writes */

 DECLARE SEB_VERIFY_CHAIN ENTRY (
    BYVAL FIXED BIN (63),           /* start_offset */
    BYVAL FIXED BIN (63),           /* end_offset */
    BYREF CHAR (1),                 /* chain_valid (output) */
    BYREF FIXED DEC (5,0)           /* first_invalid_offset (output) */
    ) RETURNS (FIXED DEC (5,0));    /* error code */


 /* ================================================================ */
 /* ENTRY POINT: SEB_READ_EVENT */
 /* ================================================================ */
 /*  */
 /* Reads an event from the SEB chain by offset. */
 /*  */
 /* Input: */
 /*   offset: SEB chain offset to read */
 /*  */
 /* Output: */
 /*   result: SEB_READ_RESULT structure */
 /*           - ENVELOPE: cryptographic envelope header + footer */
 /*           - PAYLOAD: variable-length JSON payload */
 /*           - ERROR_CODE: detailed error code */
 /*  */
 /* Guarantees: */
 /*   1. Read-only: no modification to the chain */
 /*   2. Verifiable: can validate seal immediately after read */
 /*   3. Atomic: read completes without interference */

 DECLARE SEB_READ_EVENT ENTRY (
    BYVAL FIXED BIN (63),           /* offset */
    BYREF CHAR (196),               /* envelope (output) */
    BYREF CHAR (32767),             /* payload (output, varying) */
    BYREF FIXED DEC (10,0)          /* payload_length (output) */
    ) RETURNS (FIXED DEC (5,0));    /* error code */


 /* ================================================================ */
 /* INTERNAL PROCEDURES */
 /* ================================================================ */
 /*  */
 /* These procedures are called internally by the entry points */
 /* They should not be called directly by external code */

 DECLARE SEB_COMPUTE_BLAKE3 ENTRY (
    BYVAL FIXED BIN (31),           /* data_length */
    BYREF CHAR (32767),             /* data */
    BYREF CHAR (64)                 /* hash_hex (output) */
    ) RETURNS (FIXED DEC (5,0));    /* error code */

 DECLARE SEB_VERIFY_ED25519 ENTRY (
    BYVAL CHAR (64),                /* message_hash_hex */
    BYVAL CHAR (128),               /* signature_hex */
    BYVAL CHAR (64),                /* public_key_hex */
    BYREF CHAR (1)                  /* valid_flag (output) */
    ) RETURNS (FIXED DEC (5,0));    /* error code */

 DECLARE SEB_SIGN_ED25519 ENTRY (
    BYVAL CHAR (64),                /* message_hash_hex */
    BYVAL CHAR (64),                /* secret_key_hex */
    BYREF CHAR (128)                /* signature_hex (output) */
    ) RETURNS (FIXED DEC (5,0));    /* error code */


 /* ================================================================ */
 /* STORAGE ALLOCATION */
 /* ================================================================ */

 DECLARE SEB_CHAIN_FILE CHAR (60) INIT ('SEB_CHAIN_LOG');
 DECLARE SEB_PAYLOAD_DIR CHAR (60) INIT ('SEB_PAYLOADS');
 DECLARE SEB_LEDGER_TABLE CHAR (30) INIT ('SOVEREIGN_LEDGER');
 DECLARE SEB_OFFSET_TABLE CHAR (30) INIT ('SEB_OFFSET_COMMITS');

 /* File descriptors */
 DECLARE SEB_CHAIN_FD FIXED DEC (5,0);
 DECLARE SEB_PAYLOAD_FD FIXED DEC (5,0);

 /* Database cursors */
 DECLARE SEB_DB_CURSOR_LEDGER CHAR (30) INIT ('CUR_LEDGER');
 DECLARE SEB_DB_CURSOR_OFFSET CHAR (30) INIT ('CUR_OFFSET');


 /* ================================================================ */
 /* CONSTANTS */
 /* ================================================================ */

 DECLARE SEB_MAX_OFFSET FIXED BIN (63) INIT (9223372036854775807); /* 2^63-1 */
 DECLARE SEB_MAX_PAYLOAD FIXED BIN (31) INIT (2147483647);          /* 2^31-1 */
 DECLARE SEB_HASH_LENGTH FIXED DEC (3,0) INIT (64);                 /* Blake3 hex */
 DECLARE SEB_SIG_LENGTH FIXED DEC (3,0) INIT (128);                 /* Ed25519 hex */
 DECLARE SEB_PUBKEY_LENGTH FIXED DEC (3,0) INIT (64);               /* Ed25519 pubkey hex */

 DECLARE SEB_TIMESTAMP_FORMAT CHAR (24) INIT ('YYYY-MM-DDTHH:MM:SS.sssZ');

 /* Event type constants */
 DECLARE SEB_EVENT_SETTLEMENT CHAR (10) INIT ('SETTLEMENT');
 DECLARE SEB_EVENT_CONFIRM CHAR (10) INIT ('CONFIRM');
 DECLARE SEB_EVENT_ERROR CHAR (10) INIT ('ERROR');
 DECLARE SEB_EVENT_VERIFY CHAR (10) INIT ('VERIFY');

 /* ================================================================ */
 /* GLOBAL STATE (thread-local) */
 /* ================================================================ */

 DECLARE SEB_CURRENT_OFFSET FIXED BIN (63) STATIC INIT (0);
 DECLARE SEB_LAST_HASH CHAR (64) STATIC INIT ('');
 DECLARE SEB_AGENT_ID CHAR (16) STATIC INIT ('SEB_KERNEL');
 DECLARE SEB_ERROR_CONTEXT CHAR (256) STATIC INIT ('');

 /* ================================================================ */
 /* INITIALIZATION PROCEDURE */
 /* ================================================================ */

 DECLARE SEB_INITIALIZE ENTRY () RETURNS (FIXED DEC (5,0));

 /* Called at module startup to: */
 /* 1. Open chain log file */
 /* 2. Connect to DB2/IMS ledger */
 /* 3. Verify no corruption from prior crash */
 /* 4. Load current chain offset */

 /* ================================================================ */
 /* SHUTDOWN PROCEDURE */
 /* ================================================================ */

 DECLARE SEB_SHUTDOWN ENTRY () RETURNS (FIXED DEC (5,0));

 /* Called at module shutdown to: */
 /* 1. Close chain log file */
 /* 2. Disconnect from database */
 /* 3. Flush all pending writes */
 /* 4. Save final chain state */

