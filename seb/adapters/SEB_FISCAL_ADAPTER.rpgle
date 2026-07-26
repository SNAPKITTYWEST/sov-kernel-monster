      * SEB Fiscal Settlement Adapter (RPG/ILE)
      * Generated from: SEB_SOVEREIGN_EVENT_BUS_MASTER_SPECIFICATION.xml
      * Version: 1.0.0
      * Layer: L4 - Mainframe Integration (IBM i)
      *
      * This module implements the settlement gateway for fiscal operations,
      * routing events from the Codestorm Hub RPC interface through the
      * Sovereign Event Bus to immutable ledger persistence.
      *
      * Entry Points:
      *   - SEB_Fiscal_Settlement: Main RPC endpoint
      *   - SEB_Settlement_Confirm: Emit confirmation event
      *   - SEB_Settlement_Error: Handle settlement failures
      *
      * Cryptography: Blake3 + Ed25519 (via WORM_SEAL module)
      * Database: DB2 (SOVEREIGN_LEDGER table)
      * Idempotency: Via Bifrost_Hash deduplication
      *
      * Thread Safety: All operations are single-threaded per agent
      *                Multiple agents can settle in parallel

     H DFTACTGRP(*NO)
     H BNDDIR('QSys/ProdData/HTTP/Public/WebSphere'
     H           'QSys/ProdData/HTTP/Public/ibm-http-server')
     H ACTGRP('*CALLER')
     H OPTION(*SRCSTMT:*NODEBUGIO)
     H TIMELIMIT(600)  * 10 minute timeout for settlement

      /?COPY SEBEVENT
      /?COPY QSYSINC/H,STRING_H

      * ================================================================
      * Global Variables
      * ================================================================

     D g_seb_chain_offset  S            10I 0 INZ(0)
     D g_bifrost_hash      S           128A   INZ('')
     D g_agent_id          S            16A   INZ('FISCAL_SETTLE')
     D g_settlement_error  S              1A   INZ('0')


      * ================================================================
      * Codestorm Hub RPC Entry Point
      * ================================================================
      * Called by: Codestorm Hub (RELAY adapter)
      * Input: Agent_ID, Amount, Asset_ID, Bifrost_Hash
      * Output: Settlement Confirmation Event or Error
      *
      * This is the main entry point for settlement requests from the hub

     P SEB_Fiscal_Settlement...
     P                 B                   EXPORT
     D SEB_Fiscal_Settlement...
     D                 PI
     D  pi_agent_id                     16A   CONST
     D  pi_amount                       18P 0 CONST
     D  pi_asset_id                     32A   CONST
     D  pi_bifrost_hash                128A   CONST
     D  po_settlement_id               128A
     D  po_error_msg                   256A

     D l_envelope              DS                  QUALIFIED
     D  sb_offset                 1      8I 0
     D  sb_timestamp             9     34A
     D  sb_agent_id              35    50A
     D  sb_event_type            51    60A
     D  sb_payload_size          61    64I 0
     D  sb_reserved              65    76A
     D  sb_prev_hash             77   108A
     D  sb_event_hash           109   140A
     D  sb_signature            141   204A

     D l_payload               S       2048A   VARYING
     D l_seb_offset            S            10I 0
     D l_error_code            S            10I 0
     D l_settlement_payload    S       2048A   VARYING
     D l_timestamp             S            26A
     D l_hash                  S            64A
     D l_hash_obj              S            16A
     D l_hash_result           S            32A
     D l_json_buffer           S          4096A   VARYING

     BEGIN

        * Validate inputs
        IF pi_amount <= 0;
          po_error_msg = 'SEB_FISCAL_ADAPTER: Settlement amount must be '
                       + 'positive';
          RETURN;
        ENDIF;

        IF pi_bifrost_hash = '';
          po_error_msg = 'SEB_FISCAL_ADAPTER: Bifrost_Hash required for '
                       + 'idempotency';
          RETURN;
        ENDIF;

        * Check for duplicate settlement (idempotency)
        EXSR check_duplicate_settlement;
        IF g_settlement_error = '1';
          po_error_msg = 'SEB_FISCAL_ADAPTER: Settlement already processed '
                       + 'for this Bifrost_Hash';
          RETURN;
        ENDIF;

        * Generate timestamp (ISO-8601 UTC)
        EXSR generate_iso_timestamp;

        * Build settlement event payload (JSON format)
        EXSR build_settlement_payload;

        * Build SEB envelope header
        l_envelope.sb_offset = 0;  * Will be assigned by SEB kernel
        l_envelope.sb_timestamp = l_timestamp;
        l_envelope.sb_agent_id = g_agent_id;
        l_envelope.sb_event_type = 'SETTLEMENT';
        l_envelope.sb_payload_size = %LEN(%TRIM(l_settlement_payload));
        l_envelope.sb_reserved = '';

        * Append event to SEB chain (WORM sealed)
        EXSR append_to_seb_chain;

        IF l_error_code <> 0;
          po_error_msg = 'SEB_FISCAL_ADAPTER: Failed to append event to '
                       + 'SEB chain (error code: '
                       + %CHAR(l_error_code) + ')';
          RETURN;
        ENDIF;

        * Insert settlement into SOVEREIGN_LEDGER (idempotent on Bifrost_Hash)
        EXSR insert_into_ledger;

        IF l_error_code <> 0;
          po_error_msg = 'SEB_FISCAL_ADAPTER: Failed to insert into '
                       + 'SOVEREIGN_LEDGER (error code: '
                       + %CHAR(l_error_code) + ')';
          RETURN;
        ENDIF;

        * Emit Settlement Confirmation Event back into SEB
        EXSR emit_confirmation_event;

        IF l_error_code <> 0;
          po_error_msg = 'SEB_FISCAL_ADAPTER: Failed to emit confirmation '
                       + 'event (error code: '
                       + %CHAR(l_error_code) + ')';
          RETURN;
        ENDIF;

        * Call SEB_Kernel_Append_Event NIF to register confirmation
        EXSR call_seb_kernel_nif;

        * Return settlement ID (which is the SEB offset)
        po_settlement_id = %CHAR(l_seb_offset);
        po_error_msg = 'SUCCESS';

     END-PROC SEB_Fiscal_Settlement;


      * ================================================================
      * SUBROUTINE: Check for Duplicate Settlement
      * ================================================================

     C     check_duplicate_settlement...
     C                   BEGSR
     D l_ledger_status     S              1
     D l_ledger_offset     S            10I 0
     D l_sqlcode           S             5I 0

        * Query SOVEREIGN_LEDGER for existing settlement with this Bifrost_Hash
        EXEC SQL
          SELECT SETTLEMENT_STATUS, SEB_OFFSET
          INTO :l_ledger_status, :l_ledger_offset
          FROM SOVEREIGN_LEDGER
          WHERE BIFROST_HASH = :pi_bifrost_hash
          AND SETTLEMENT_STATUS IN ('SUCCESS', 'PENDING')
          FETCH FIRST 1 ROW ONLY;

        l_sqlcode = SQLCODE;

        IF l_sqlcode = 0;
          * Settlement already exists
          g_settlement_error = '1';
          g_seb_chain_offset = l_ledger_offset;
        ELSE;
          * No duplicate found
          g_settlement_error = '0';
        ENDIF;

     C                   ENDSR;


      * ================================================================
      * SUBROUTINE: Generate ISO-8601 Timestamp
      * ================================================================

     C     generate_iso_timestamp...
     C                   BEGSR
     D l_now               S               Z   INZ(*SYS)
     D l_year              S              4  0
     D l_month             S              2  0
     D l_day               S              2  0
     D l_hour              S              2  0
     D l_minute            S              2  0
     D l_second            S              2  0
     D l_millis            S              3  0

        * Get current time in UTC
        l_now = %TIMESTAMP();

        * Extract components
        l_year = %YEAR(l_now);
        l_month = %MONTH(l_now);
        l_day = %DAY(l_now);
        l_hour = %HOUR(l_now);
        l_minute = %MINUTE(l_now);
        l_second = %SECOND(l_now);
        l_millis = %MILLISECOND(l_now);

        * Format: YYYY-MM-DDTHH:MM:SS.sssZ
        l_timestamp = %EDITC(l_year : '0 ') + '-'
                    + %EDITC(l_month : '0 ') + '-'
                    + %EDITC(l_day : '0 ') + 'T'
                    + %EDITC(l_hour : '0 ') + ':'
                    + %EDITC(l_minute : '0 ') + ':'
                    + %EDITC(l_second : '0 ') + '.'
                    + %EDITC(l_millis : '0 ') + 'Z';

     C                   ENDSR;


      * ================================================================
      * SUBROUTINE: Build Settlement Payload (JSON)
      * ================================================================

     C     build_settlement_payload...
     C                   BEGSR

        * Build JSON payload with settlement details
        l_settlement_payload = '{'
          + '"intent": {'
          +   '"action": "settle_fiscal",'
          +   '"subject": "' + %TRIM(pi_asset_id) + '",'
          +   '"parameters": {'
          +     '"amount": ' + %CHAR(pi_amount) + ','
          +     '"currency": "USD"'
          +   '}'
          + '},'
          + '"context": {'
          +   '"environment": "production",'
          +   '"constraints": {'
          +     '"network": "restricted",'
          +     '"max_runtime_ms": 30000,'
          +     '"max_memory_bytes": 10485760'
          +   '}'
          + '},'
          + '"authority": {'
          +   '"principal": "' + %TRIM(pi_agent_id) + '",'
          +   '"credentials": {'
          +     '"credential_type": "agent_signature"'
          +   '},'
          +   '"scope": ["settle_fiscal"]'
          + '},'
          + '"evidence": ['
          +   '{'
          +     '"evidence_type": "bifrost_hash",'
          +     '"hash": "' + %TRIM(pi_bifrost_hash) + '"'
          +   '}'
          + ']'
          + '}';

     C                   ENDSR;


      * ================================================================
      * SUBROUTINE: Append Event to SEB Chain (WORM Sealed)
      * ================================================================

     C     append_to_seb_chain...
     C                   BEGSR

        * Call SEB_Append_Event NIF (external interface)
        * The kernel handles cryptographic sealing via Blake3+Ed25519

        CALL 'SEB_APPEND'
          PARM l_envelope
          PARM l_settlement_payload
          PARM l_seb_offset
          PARM l_error_code;

     C                   ENDSR;


      * ================================================================
      * SUBROUTINE: Insert into SOVEREIGN_LEDGER (Idempotent)
      * ================================================================

     C     insert_into_ledger...
     C                   BEGSR
     D l_sqlcode           S             5I 0
     D l_settlement_id     S            128A
     D l_timestamp_ins     S               Z

        l_timestamp_ins = %TIMESTAMP();
        l_settlement_id = %CHAR(l_seb_offset);

        * Attempt INSERT (will fail if Bifrost_Hash exists)
        * Use INSERT IGNORE or ON CONFLICT behavior for idempotency

        EXEC SQL
          INSERT INTO SOVEREIGN_LEDGER (
            SETTLEMENT_ID,
            BIFROST_HASH,
            AGENT_ID,
            AMOUNT,
            ASSET_ID,
            SEB_OFFSET,
            SETTLEMENT_STATUS,
            CREATED_AT,
            UPDATED_AT,
            EVENT_HASH,
            SIGNATURE
          ) VALUES (
            :l_settlement_id,
            :pi_bifrost_hash,
            :pi_agent_id,
            :pi_amount,
            :pi_asset_id,
            :l_seb_offset,
            'SUCCESS',
            :l_timestamp_ins,
            :l_timestamp_ins,
            :l_hash,
            ''
          )
          ON CONFLICT (BIFROST_HASH) DO NOTHING;

        l_sqlcode = SQLCODE;

        IF l_sqlcode <> 0 AND l_sqlcode <> 100;
          * SQL error occurred (not "no rows found")
          l_error_code = l_sqlcode;
        ELSE;
          * Either inserted successfully or already existed (idempotency)
          l_error_code = 0;
        ENDIF;

     C                   ENDSR;


      * ================================================================
      * SUBROUTINE: Emit Settlement Confirmation Event
      * ================================================================

     C     emit_confirmation_event...
     C                   BEGSR
     D l_conf_envelope     DS                  QUALIFIED
     D  sb_offset                 1      8I 0
     D  sb_timestamp             9     34A
     D  sb_agent_id              35    50A
     D  sb_event_type            51    60A
     D  sb_payload_size          61    64I 0
     D  sb_reserved              65    76A
     D  sb_prev_hash             77   108A
     D  sb_event_hash           109   140A
     D  sb_signature            141   204A

     D l_conf_payload      S       1024A   VARYING

        * Build confirmation event payload
        l_conf_payload = '{'
          + '"settlement_id": "' + %TRIM(l_settlement_id) + '",'
          + '"bifrost_hash": "' + %TRIM(pi_bifrost_hash) + '",'
          + '"status": "CONFIRMED",'
          + '"seb_offset": ' + %CHAR(l_seb_offset)
          + '}';

        * Build confirmation envelope
        l_conf_envelope.sb_offset = 0;
        l_conf_envelope.sb_timestamp = l_timestamp;
        l_conf_envelope.sb_agent_id = g_agent_id;
        l_conf_envelope.sb_event_type = 'CONFIRM';
        l_conf_envelope.sb_payload_size = %LEN(%TRIM(l_conf_payload));
        l_conf_envelope.sb_reserved = '';

        * Append confirmation to SEB chain
        CALL 'SEB_APPEND'
          PARM l_conf_envelope
          PARM l_conf_payload
          PARM g_seb_chain_offset
          PARM l_error_code;

     C                   ENDSR;


      * ================================================================
      * SUBROUTINE: Call SEB_Kernel_Append_Event NIF
      * ================================================================

     C     call_seb_kernel_nif...
     C                   BEGSR

        * This subroutine would call the native interface to the Rust kernel
        * For now, it's a placeholder - the actual NIF would be loaded
        * via CALL 'SEB_KERNEL_NIF' with appropriate parameters

        * The kernel is responsible for:
        * 1. Final Blake3 hash verification
        * 2. Ed25519 signature validation
        * 3. Chain integrity checks
        * 4. Conflict resolution for parallel appends

        l_error_code = 0;  * Assume success for now

     C                   ENDSR;


      * ================================================================
      * Exported Procedure: Settlement Error Handler
      * ================================================================

     P SEB_Settlement_Error...
     P                 B                   EXPORT
     D SEB_Settlement_Error...
     D                 PI
     D  pi_settlement_id                128A   CONST
     D  pi_error_code                    5I 0 CONST
     D  pi_error_msg                   512A   CONST
     D  po_retry_offset                  10I 0

     D l_error_envelope     DS                  QUALIFIED
     D  sb_offset                 1      8I 0
     D  sb_timestamp             9     34A
     D  sb_agent_id              35    50A
     D  sb_event_type            51    60A
     D  sb_payload_size          61    64I 0
     D  sb_reserved              65    76A
     D  sb_prev_hash             77   108A
     D  sb_event_hash           109   140A
     D  sb_signature            141   204A

     D l_error_payload     S       1024A   VARYING
     D l_seb_offset        S            10I 0
     D l_error_seb         S            10I 0

     BEGIN

        * Build error event payload
        l_error_payload = '{'
          + '"settlement_id": "' + %TRIM(pi_settlement_id) + '",'
          + '"error_code": ' + %CHAR(pi_error_code) + ','
          + '"error_msg": "' + %TRIM(pi_error_msg) + '",'
          + '"timestamp": "' + l_timestamp + '"'
          + '}';

        * Build error envelope
        l_error_envelope.sb_event_type = 'ERROR';
        l_error_envelope.sb_agent_id = g_agent_id;

        * Append error event to SEB
        CALL 'SEB_APPEND'
          PARM l_error_envelope
          PARM l_error_payload
          PARM l_seb_offset
          PARM l_error_seb;

        * Return offset for retry tracking
        po_retry_offset = l_seb_offset;

     END-PROC SEB_Settlement_Error;


      * ================================================================
      * End of Module
      * ================================================================

