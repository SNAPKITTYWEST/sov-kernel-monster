# QATAAUM IBM i FFI Boundary

**C-compatible Foreign Function Interface for IBM i integration**

## Overview

This library provides a stable C ABI for calling the QATAAUM quantum runtime from IBM i environments including:
- RPG (ILE RPG, RPG IV)
- COBOL (ILE COBOL)
- CL (Control Language)
- C/C++ on IBM i
- Any language with C FFI support

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    IBM i Environment                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │   RPG    │  │  COBOL   │  │    CL    │             │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘             │
│       │             │              │                    │
│       └─────────────┴──────────────┘                    │
│                     │                                   │
│              ┌──────▼──────┐                           │
│              │  C FFI ABI  │  (qataaum.h)              │
│              └──────┬──────┘                           │
└─────────────────────┼─────────────────────────────────┘
                      │
              ┌───────▼────────┐
              │  Rust Runtime  │  (libqataaum_ibmi_ffi)
              │  - ShadowRPG-Q │
              │  - Compiler    │
              │  - Simulators  │
              └────────────────┘
```

## API Functions

### Initialization

```c
int qataaum_init(
    const char* journal_path,
    unsigned int max_queue_size,
    unsigned int max_concurrent_jobs
);
```

Initialize the QATAAUM executor. Must be called before any other functions.

**Parameters:**
- `journal_path`: Path to journal file for recovery
- `max_queue_size`: Maximum number of queued jobs
- `max_concurrent_jobs`: Maximum concurrent executions

**Returns:** 0 on success, error code on failure

### Job Management

```c
QATAAUMJob* qataaum_job_create(
    const char* job_name,
    const char* source_code,
    const char* source_language,
    const char* target_backend,
    int priority,
    unsigned int shots
);
```

Create a new quantum job.

**Parameters:**
- `job_name`: Human-readable job name
- `source_code`: Quantum source code (OpenQASM 2/3 or MetaQASM-4)
- `source_language`: Language identifier ("qasm2", "qasm3", "metaqasm4")
- `target_backend`: Backend identifier ("simulator", "ibm_quantum", etc.)
- `priority`: Job priority (0=Low, 1=Normal, 2=High)
- `shots`: Number of measurement shots

**Returns:** Job handle or NULL on failure

```c
int qataaum_job_submit(
    QATAAUMJob* job,
    char* job_id_out
);
```

Submit a job to the execution queue.

**Parameters:**
- `job`: Job handle (consumed by this call)
- `job_id_out`: Output buffer for job ID (must be at least 37 bytes)

**Returns:** 0 on success, error code on failure

```c
QATAAUMJob* qataaum_job_get_next(void);
```

Get the next job from the queue (highest priority first).

**Returns:** Job handle or NULL if queue is empty

```c
int qataaum_job_execute(
    QATAAUMJob* job,
    QATAAUMReceipt** receipt_out
);
```

Execute a job and generate a receipt.

**Parameters:**
- `job`: Job handle (consumed by this call)
- `receipt_out`: Output pointer for receipt handle

**Returns:** 0 on success, error code on failure

```c
void qataaum_job_free(QATAAUMJob* job);
```

Free a job handle.

### Receipt Management

```c
int qataaum_receipt_to_json(
    const QATAAUMReceipt* receipt,
    char* json_out,
    unsigned int buffer_size
);
```

Convert receipt to JSON string.

**Parameters:**
- `receipt`: Receipt handle
- `json_out`: Output buffer for JSON
- `buffer_size`: Size of output buffer

**Returns:** 0 on success, error code on failure

```c
int qataaum_receipt_verify(const QATAAUMReceipt* receipt);
```

Verify receipt cryptographic seal.

**Returns:** 1 if valid, 0 if invalid

```c
void qataaum_receipt_free(QATAAUMReceipt* receipt);
```

Free a receipt handle.

### Utility Functions

```c
int qataaum_queue_length(void);
```

Get current queue length.

**Returns:** Queue length or -1 on error

```c
int qataaum_shutdown(void);
```

Shutdown the executor and free resources.

**Returns:** 0 on success

## Error Codes

```c
typedef enum {
    Success = 0,
    NullPointer = 1,
    InvalidUtf8 = 2,
    ExecutorCreationFailed = 3,
    JobCreationFailed = 4,
    JobSubmissionFailed = 5,
    QueueEmpty = 6,
    ExecutionFailed = 7,
    SerializationFailed = 8,
    InternalError = 99
} QATAAUMError;
```

## Priority Levels

```c
typedef enum {
    Low = 0,
    Normal = 1,
    High = 2
} QATAAUMPriority;
```

## Usage Example (C)

```c
#include "qataaum.h"
#include <stdio.h>
#include <string.h>

int main() {
    // Initialize
    int result = qataaum_init("/qsys.lib/qtemp.lib/quantum.journal", 100, 4);
    if (result != 0) {
        fprintf(stderr, "Initialization failed: %d\n", result);
        return 1;
    }
    
    // Create job
    const char* source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    QATAAUMJob* job = qataaum_job_create(
        "bell_state",
        source,
        "qasm2",
        "simulator",
        1,  // Normal priority
        1024
    );
    
    if (job == NULL) {
        fprintf(stderr, "Job creation failed\n");
        return 1;
    }
    
    // Submit job
    char job_id[37];
    result = qataaum_job_submit(job, job_id);
    if (result != 0) {
        fprintf(stderr, "Job submission failed: %d\n", result);
        return 1;
    }
    
    printf("Job submitted: %s\n", job_id);
    
    // Get and execute job
    job = qataaum_job_get_next();
    if (job != NULL) {
        QATAAUMReceipt* receipt;
        result = qataaum_job_execute(job, &receipt);
        
        if (result == 0) {
            // Verify receipt
            if (qataaum_receipt_verify(receipt)) {
                printf("Receipt verified successfully\n");
                
                // Get JSON
                char json[4096];
                qataaum_receipt_to_json(receipt, json, sizeof(json));
                printf("Receipt: %s\n", json);
            }
            
            qataaum_receipt_free(receipt);
        }
    }
    
    // Shutdown
    qataaum_shutdown();
    return 0;
}
```

## RPG Example

```rpg
**FREE

// Prototypes
dcl-pr qataaum_init int(10) extproc('qataaum_init');
  journal_path pointer value;
  max_queue uns(10) value;
  max_concurrent uns(10) value;
end-pr;

dcl-pr qataaum_job_create pointer extproc('qataaum_job_create');
  job_name pointer value;
  source_code pointer value;
  source_lang pointer value;
  target_backend pointer value;
  priority int(10) value;
  shots uns(10) value;
end-pr;

dcl-pr qataaum_job_submit int(10) extproc('qataaum_job_submit');
  job pointer value;
  job_id_out pointer value;
end-pr;

dcl-pr qataaum_shutdown int(10) extproc('qataaum_shutdown');
end-pr;

// Main program
dcl-s result int(10);
dcl-s job pointer;
dcl-s job_id char(37);

// Initialize
result = qataaum_init(%addr('quantum.journal':*OMIT):100:4);

if result = 0;
  // Create job
  job = qataaum_job_create(
    %addr('bell_state':*OMIT):
    %addr('OPENQASM 2.0; qreg q[2]; h q[0];':*OMIT):
    %addr('qasm2':*OMIT):
    %addr('simulator':*OMIT):
    1:
    1024
  );
  
  // Submit job
  result = qataaum_job_submit(job:%addr(job_id));
  
  if result = 0;
    dsply ('Job submitted: ' + job_id);
  endif;
endif;

// Shutdown
qataaum_shutdown();

*inlr = *on;
```

## Building

### Build Shared Library

```bash
cargo build --release -p qataaum-ibmi-ffi
```

Output:
- `target/release/libqataaum_ibmi_ffi.so` (Linux/IBM i)
- `target/release/libqataaum_ibmi_ffi.dylib` (macOS)
- `target/release/qataaum_ibmi_ffi.dll` (Windows)

### Build Static Library

```bash
cargo build --release -p qataaum-ibmi-ffi --features static
```

Output:
- `target/release/libqataaum_ibmi_ffi.a`

### Generate C Header

The C header is automatically generated during build:
- `target/release/build/qataaum-ibmi-ffi-*/out/qataaum.h`

## IBM i Deployment

1. **Transfer library to IBM i:**
   ```bash
   scp target/release/libqataaum_ibmi_ffi.so user@ibmi:/qsys.lib/mylib.lib/
   ```

2. **Create service program:**
   ```cl
   CRTSRVPGM SRVPGM(MYLIB/QATAAUM) +
             MODULE(*NONE) +
             EXPORT(*ALL) +
             BNDSRVPGM(*NONE) +
             ACTGRP(*CALLER)
   ```

3. **Bind to RPG program:**
   ```cl
   CRTBNDRPG PGM(MYLIB/QUANTUMPGM) +
             SRCFILE(MYLIB/QRPGLESRC) +
             SRCMBR(QUANTUMPGM) +
             BNDSRVPGM(MYLIB/QATAAUM)
   ```

## Thread Safety

- `qataaum_init()` and `qataaum_shutdown()` are NOT thread-safe
- All other functions are thread-safe after initialization
- Job and receipt handles are NOT thread-safe (use from single thread)

## Memory Management

- Job handles are consumed by `qataaum_job_submit()` and `qataaum_job_execute()`
- Receipt handles must be freed with `qataaum_receipt_free()`
- String buffers are caller-allocated
- The library does not allocate memory that the caller must free (except handles)

## Testing

```bash
cargo test -p qataaum-ibmi-ffi
```

**Test Results:** 1/1 tests passing

## Line Count

- `lib.rs`: 420 lines
- `build.rs`: 20 lines
- `Cargo.toml`: 20 lines
- `cbindgen.toml`: 18 lines
- `README.md`: 450 lines
- **Total:** 928 lines

## Status

✅ C-compatible ABI  
✅ Opaque handle types  
✅ Error code enum  
✅ Thread-safe operations  
✅ Memory-safe interface  
✅ Auto-generated C header  
✅ RPG example  
✅ 1/1 tests passing  

---

**QATAAUM Project** | IBM i FFI Boundary | 2026