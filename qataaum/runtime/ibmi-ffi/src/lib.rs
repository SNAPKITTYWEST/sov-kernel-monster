//! IBM i FFI Boundary for QATAAUM
//!
//! C-compatible interface for calling Rust quantum runtime from IBM i
//! environments (RPG, COBOL, CL, etc.)
//!
//! This provides a stable ABI for cross-language interoperability.

use shadow_rpg_q::{Executor, ExecutorConfig, Job, JobPriority, ExecutionReceipt};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uint};
use std::path::PathBuf;
use std::ptr;
use std::sync::Mutex;

/// Opaque handle to executor instance
#[repr(C)]
pub struct QATAAUMExecutor {
    _private: [u8; 0],
}

/// Opaque handle to job instance
#[repr(C)]
pub struct QATAAUMJob {
    _private: [u8; 0],
}

/// Opaque handle to receipt instance
#[repr(C)]
pub struct QATAAUMReceipt {
    _private: [u8; 0],
}

/// Job priority levels (C-compatible enum)
#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub enum QATAAUMPriority {
    Low = 0,
    Normal = 1,
    High = 2,
}

/// Error codes (C-compatible)
#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub enum QATAAUMError {
    Success = 0,
    NullPointer = 1,
    InvalidUtf8 = 2,
    ExecutorCreationFailed = 3,
    JobCreationFailed = 4,
    JobSubmissionFailed = 5,
    QueueEmpty = 6,
    ExecutionFailed = 7,
    SerializationFailed = 8,
    InternalError = 99,
}

// Global executor storage (thread-safe)
static EXECUTOR: Mutex<Option<Executor>> = Mutex::new(None);

/// Initialize the QATAAUM executor
///
/// # Parameters
/// - `journal_path`: Path to journal file (null-terminated C string)
/// - `max_queue_size`: Maximum queue size
/// - `max_concurrent_jobs`: Maximum concurrent jobs
///
/// # Returns
/// - 0 on success
/// - Error code on failure
///
/// # Safety
/// - `journal_path` must be a valid null-terminated C string
/// - Must be called before any other functions
#[no_mangle]
pub unsafe extern "C" fn qataaum_init(
    journal_path: *const c_char,
    max_queue_size: c_uint,
    max_concurrent_jobs: c_uint,
) -> c_int {
    if journal_path.is_null() {
        return QATAAUMError::NullPointer as c_int;
    }
    
    let path_cstr = match CStr::from_ptr(journal_path).to_str() {
        Ok(s) => s,
        Err(_) => return QATAAUMError::InvalidUtf8 as c_int,
    };
    
    let config = ExecutorConfig {
        max_queue_size: max_queue_size as usize,
        journal_path: PathBuf::from(path_cstr),
        max_concurrent_jobs: max_concurrent_jobs as usize,
    };
    
    match Executor::new(config) {
        Ok(executor) => {
            let mut global = EXECUTOR.lock().unwrap();
            *global = Some(executor);
            QATAAUMError::Success as c_int
        }
        Err(_) => QATAAUMError::ExecutorCreationFailed as c_int,
    }
}

/// Create a new quantum job
///
/// # Parameters
/// - `job_name`: Job name (null-terminated C string)
/// - `source_code`: Quantum source code (null-terminated C string)
/// - `source_language`: Language identifier (null-terminated C string)
/// - `target_backend`: Backend identifier (null-terminated C string)
/// - `priority`: Job priority (0=Low, 1=Normal, 2=High)
/// - `shots`: Number of shots
///
/// # Returns
/// - Pointer to job handle on success
/// - NULL on failure
///
/// # Safety
/// - All string parameters must be valid null-terminated C strings
/// - Caller must free the returned handle with `qataaum_job_free`
#[no_mangle]
pub unsafe extern "C" fn qataaum_job_create(
    job_name: *const c_char,
    source_code: *const c_char,
    source_language: *const c_char,
    target_backend: *const c_char,
    priority: c_int,
    shots: c_uint,
) -> *mut QATAAUMJob {
    if job_name.is_null() || source_code.is_null() || source_language.is_null() || target_backend.is_null() {
        return ptr::null_mut();
    }
    
    let name = match CStr::from_ptr(job_name).to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return ptr::null_mut(),
    };
    
    let code = match CStr::from_ptr(source_code).to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return ptr::null_mut(),
    };
    
    let lang = match CStr::from_ptr(source_language).to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return ptr::null_mut(),
    };
    
    let backend = match CStr::from_ptr(target_backend).to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return ptr::null_mut(),
    };
    
    let job_priority = match priority {
        0 => JobPriority::Low,
        2 => JobPriority::High,
        _ => JobPriority::Normal,
    };
    
    let job = Job::new(name, code, lang, backend)
        .with_priority(job_priority)
        .with_shots(shots);
    
    Box::into_raw(Box::new(job)) as *mut QATAAUMJob
}

/// Submit a job to the executor queue
///
/// # Parameters
/// - `job`: Job handle (will be consumed)
/// - `job_id_out`: Output buffer for job ID (36 bytes + null terminator)
///
/// # Returns
/// - 0 on success
/// - Error code on failure
///
/// # Safety
/// - `job` must be a valid job handle from `qataaum_job_create`
/// - `job_id_out` must point to a buffer of at least 37 bytes
/// - `job` handle is consumed and must not be used after this call
#[no_mangle]
pub unsafe extern "C" fn qataaum_job_submit(
    job: *mut QATAAUMJob,
    job_id_out: *mut c_char,
) -> c_int {
    if job.is_null() || job_id_out.is_null() {
        return QATAAUMError::NullPointer as c_int;
    }
    
    let job = Box::from_raw(job as *mut Job);
    let job_id = job.job_id;
    
    let global = EXECUTOR.lock().unwrap();
    let executor = match global.as_ref() {
        Some(e) => e,
        None => return QATAAUMError::ExecutorCreationFailed as c_int,
    };
    
    match executor.submit_job(*job) {
        Ok(_) => {
            let id_str = job_id.to_string();
            let id_cstr = CString::new(id_str).unwrap();
            ptr::copy_nonoverlapping(id_cstr.as_ptr(), job_id_out, id_cstr.as_bytes_with_nul().len());
            QATAAUMError::Success as c_int
        }
        Err(_) => QATAAUMError::JobSubmissionFailed as c_int,
    }
}

/// Get the next job from the queue
///
/// # Returns
/// - Pointer to job handle on success
/// - NULL if queue is empty
///
/// # Safety
/// - Caller must free the returned handle with `qataaum_job_free`
#[no_mangle]
pub unsafe extern "C" fn qataaum_job_get_next() -> *mut QATAAUMJob {
    let mut global = EXECUTOR.lock().unwrap();
    let executor = match global.as_mut() {
        Some(e) => e,
        None => return ptr::null_mut(),
    };
    
    match executor.get_next_job() {
        Ok(Some(job)) => Box::into_raw(Box::new(job)) as *mut QATAAUMJob,
        _ => ptr::null_mut(),
    }
}

/// Execute a job
///
/// # Parameters
/// - `job`: Job handle (will be consumed)
/// - `receipt_out`: Output pointer for receipt handle
///
/// # Returns
/// - 0 on success
/// - Error code on failure
///
/// # Safety
/// - `job` must be a valid job handle
/// - `receipt_out` must be a valid pointer
/// - `job` handle is consumed and must not be used after this call
/// - Caller must free the receipt with `qataaum_receipt_free`
#[no_mangle]
pub unsafe extern "C" fn qataaum_job_execute(
    job: *mut QATAAUMJob,
    receipt_out: *mut *mut QATAAUMReceipt,
) -> c_int {
    if job.is_null() || receipt_out.is_null() {
        return QATAAUMError::NullPointer as c_int;
    }
    
    let job = Box::from_raw(job as *mut Job);
    
    let global = EXECUTOR.lock().unwrap();
    let executor = match global.as_ref() {
        Some(e) => e,
        None => return QATAAUMError::ExecutorCreationFailed as c_int,
    };
    
    match executor.execute_job(*job) {
        Ok(receipt) => {
            *receipt_out = Box::into_raw(Box::new(receipt)) as *mut QATAAUMReceipt;
            QATAAUMError::Success as c_int
        }
        Err(_) => QATAAUMError::ExecutionFailed as c_int,
    }
}

/// Get receipt as JSON string
///
/// # Parameters
/// - `receipt`: Receipt handle
/// - `json_out`: Output buffer for JSON string
/// - `buffer_size`: Size of output buffer
///
/// # Returns
/// - 0 on success
/// - Error code on failure
///
/// # Safety
/// - `receipt` must be a valid receipt handle
/// - `json_out` must point to a buffer of at least `buffer_size` bytes
#[no_mangle]
pub unsafe extern "C" fn qataaum_receipt_to_json(
    receipt: *const QATAAUMReceipt,
    json_out: *mut c_char,
    buffer_size: c_uint,
) -> c_int {
    if receipt.is_null() || json_out.is_null() {
        return QATAAUMError::NullPointer as c_int;
    }
    
    let receipt = &*(receipt as *const ExecutionReceipt);
    
    match receipt.to_json() {
        Ok(json) => {
            let json_cstr = match CString::new(json) {
                Ok(s) => s,
                Err(_) => return QATAAUMError::SerializationFailed as c_int,
            };
            
            let bytes = json_cstr.as_bytes_with_nul();
            if bytes.len() > buffer_size as usize {
                return QATAAUMError::InternalError as c_int;
            }
            
            ptr::copy_nonoverlapping(json_cstr.as_ptr(), json_out, bytes.len());
            QATAAUMError::Success as c_int
        }
        Err(_) => QATAAUMError::SerializationFailed as c_int,
    }
}

/// Verify receipt seal
///
/// # Parameters
/// - `receipt`: Receipt handle
///
/// # Returns
/// - 1 if seal is valid
/// - 0 if seal is invalid or error
///
/// # Safety
/// - `receipt` must be a valid receipt handle
#[no_mangle]
pub unsafe extern "C" fn qataaum_receipt_verify(receipt: *const QATAAUMReceipt) -> c_int {
    if receipt.is_null() {
        return 0;
    }
    
    let receipt = &*(receipt as *const ExecutionReceipt);
    if receipt.verify_seal() { 1 } else { 0 }
}

/// Free a job handle
///
/// # Safety
/// - `job` must be a valid job handle or NULL
/// - Must not be called twice on the same handle
#[no_mangle]
pub unsafe extern "C" fn qataaum_job_free(job: *mut QATAAUMJob) {
    if !job.is_null() {
        drop(Box::from_raw(job as *mut Job));
    }
}

/// Free a receipt handle
///
/// # Safety
/// - `receipt` must be a valid receipt handle or NULL
/// - Must not be called twice on the same handle
#[no_mangle]
pub unsafe extern "C" fn qataaum_receipt_free(receipt: *mut QATAAUMReceipt) {
    if !receipt.is_null() {
        drop(Box::from_raw(receipt as *mut ExecutionReceipt));
    }
}

/// Get queue length
///
/// # Returns
/// - Queue length on success
/// - -1 on error
#[no_mangle]
pub unsafe extern "C" fn qataaum_queue_length() -> c_int {
    let global = EXECUTOR.lock().unwrap();
    let executor = match global.as_ref() {
        Some(e) => e,
        None => return -1,
    };
    
    match executor.queue_length() {
        Ok(len) => len as c_int,
        Err(_) => -1,
    }
}

/// Shutdown the executor
///
/// # Returns
/// - 0 on success
#[no_mangle]
pub unsafe extern "C" fn qataaum_shutdown() -> c_int {
    let mut global = EXECUTOR.lock().unwrap();
    *global = None;
    QATAAUMError::Success as c_int
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    
    #[test]
    fn test_ffi_lifecycle() {
        unsafe {
            // Initialize
            let journal_path = CString::new("/tmp/test.journal").unwrap();
            let result = qataaum_init(journal_path.as_ptr(), 100, 4);
            assert_eq!(result, QATAAUMError::Success as c_int);
            
            // Create job
            let job_name = CString::new("test_job").unwrap();
            let source = CString::new("OPENQASM 2.0; qreg q[2]; h q[0];").unwrap();
            let lang = CString::new("qasm2").unwrap();
            let backend = CString::new("simulator").unwrap();
            
            let job = qataaum_job_create(
                job_name.as_ptr(),
                source.as_ptr(),
                lang.as_ptr(),
                backend.as_ptr(),
                1,
                1024,
            );
            assert!(!job.is_null());
            
            // Submit job
            let mut job_id_buf = [0u8; 37];
            let result = qataaum_job_submit(job, job_id_buf.as_mut_ptr() as *mut c_char);
            assert_eq!(result, QATAAUMError::Success as c_int);
            
            // Get queue length
            let len = qataaum_queue_length();
            assert_eq!(len, 1);
            
            // Shutdown
            let result = qataaum_shutdown();
            assert_eq!(result, QATAAUMError::Success as c_int);
        }
    }
}

// Made with Bob
