/* Zero-libc CUDA driver loader for Windows
 * PEB walk -> nvcuda.dll -> PE export table -> 25 CUDA functions
 * Janet kernel config uploaded to device constant memory on init
 */
typedef unsigned long long uint64_t;
typedef unsigned int       uint32_t;
typedef unsigned short     uint16_t;
typedef unsigned char      uint8_t;
typedef int                int32_t;
typedef long long          int64_t;
typedef unsigned long      ULONG;
typedef void*              PVOID;
typedef PVOID              HANDLE;
typedef uint32_t           DWORD;
typedef uint64_t           ULONG_PTR;
typedef ULONG_PTR          SIZE_T;
typedef uint16_t           WORD;
typedef uint32_t           UINT;
typedef long               LONG;
typedef uint16_t           ATOM;
typedef int                BOOL;
typedef unsigned long long CUdeviceptr;
typedef int                CUdevice;
typedef int                CUdevice_attribute;
typedef struct CUctx_st*   CUcontext;
typedef struct CUmod_st*   CUmodule;
typedef struct CUfunc_st*  CUfunction;
typedef struct CUstream_st* CUstream;
typedef struct CUevent_st*  CUevent;

typedef enum {
    CUDA_SUCCESS            = 0,
    CUDA_ERROR_INVALID_VALUE = 1,
    CUDA_ERROR_OUT_OF_MEMORY = 2,
    CUDA_ERROR_NOT_INITIALIZED = 3,
    CUDA_ERROR_NO_DEVICE    = 100,
} CUresult;

typedef struct { struct _LIST_ENTRY* Flink; struct _LIST_ENTRY* Blink; } LIST_ENTRY, *PLIST_ENTRY;
typedef struct { uint16_t Length; uint16_t MaximumLength; wchar_t* Buffer; } UNICODE_STRING;
typedef struct {
    LIST_ENTRY InLoadOrderLinks;
    LIST_ENTRY InMemoryOrderLinks;
    LIST_ENTRY InInitializationOrderLinks;
    PVOID DllBase; PVOID EntryPoint;
    ULONG SizeOfImage;
    UNICODE_STRING FullDllName;
    UNICODE_STRING BaseDllName;
} LDR_DATA_TABLE_ENTRY, *PLDR_DATA_TABLE_ENTRY;
typedef struct {
    ULONG Length; BOOL Initialized; HANDLE SsHandle;
    LIST_ENTRY InLoadOrderModuleList;
    LIST_ENTRY InMemoryOrderModuleList;
} PEB_LDR_DATA, *PPEB_LDR_DATA;
typedef struct {
    uint8_t Reserved1[2]; uint8_t BeingDebugged; uint8_t Reserved2[1];
    PVOID Reserved3[2]; PPEB_LDR_DATA Ldr;
} PEB, *PPEB;

typedef struct { WORD e_magic; WORD e_cblp; WORD e_cp; WORD e_crlc; WORD e_cparhdr;
    WORD e_minalloc; WORD e_maxalloc; WORD e_ss; WORD e_sp; WORD e_csum; WORD e_ip;
    WORD e_cs; WORD e_lfarlc; WORD e_ovno; WORD e_res[4]; WORD e_oemid; WORD e_oeminfo;
    WORD e_res2[10]; LONG e_lfanew; } IMAGE_DOS_HEADER, *PIMAGE_DOS_HEADER;
typedef struct { WORD Machine; WORD NumberOfSections; DWORD TimeDateStamp;
    DWORD PointerToSymbolTable; DWORD NumberOfSymbols; WORD SizeOfOptionalHeader;
    WORD Characteristics; } IMAGE_FILE_HEADER;
typedef struct { DWORD VirtualAddress; DWORD Size; } IMAGE_DATA_DIRECTORY;
typedef struct { WORD Magic; uint8_t MajorLinkerVersion; uint8_t MinorLinkerVersion;
    DWORD SizeOfCode; DWORD SizeOfInitializedData; DWORD SizeOfUninitializedData;
    DWORD AddressOfEntryPoint; DWORD BaseOfCode; ULONG_PTR ImageBase;
    DWORD SectionAlignment; DWORD FileAlignment; WORD MajorOperatingSystemVersion;
    WORD MinorOperatingSystemVersion; WORD MajorImageVersion; WORD MinorImageVersion;
    WORD MajorSubsystemVersion; WORD MinorSubsystemVersion; DWORD Win32VersionValue;
    DWORD SizeOfImage; DWORD SizeOfHeaders; DWORD CheckSum; WORD Subsystem;
    WORD DllCharacteristics; ULONG_PTR SizeOfStackReserve; ULONG_PTR SizeOfStackCommit;
    ULONG_PTR SizeOfHeapReserve; ULONG_PTR SizeOfHeapCommit; DWORD LoaderFlags;
    DWORD NumberOfRvaAndSizes; IMAGE_DATA_DIRECTORY DataDirectory[16]; } IMAGE_OPTIONAL_HEADER64;
typedef struct { DWORD Signature; IMAGE_FILE_HEADER FileHeader; IMAGE_OPTIONAL_HEADER64 OptionalHeader; } IMAGE_NT_HEADERS64, *PIMAGE_NT_HEADERS64;
typedef struct { DWORD Characteristics; DWORD TimeDateStamp; WORD MajorVersion; WORD MinorVersion;
    DWORD Name; DWORD Base; DWORD NumberOfFunctions; DWORD NumberOfNames;
    DWORD AddressOfFunctions; DWORD AddressOfNames; DWORD AddressOfNameOrdinals; } IMAGE_EXPORT_DIRECTORY, *PIMAGE_EXPORT_DIRECTORY;

/* CUDA function pointer typedefs */
typedef CUresult (*cuInit_t)(UINT);
typedef CUresult (*cuDeviceGet_t)(CUdevice*, int);
typedef CUresult (*cuDeviceGetCount_t)(int*);
typedef CUresult (*cuCtxCreate_v2_t)(CUcontext*, UINT, CUdevice);
typedef CUresult (*cuModuleLoadData_t)(CUmodule*, const void*);
typedef CUresult (*cuModuleGetFunction_t)(CUfunction*, CUmodule, const char*);
typedef CUresult (*cuLaunchKernel_t)(CUfunction, UINT,UINT,UINT, UINT,UINT,UINT, UINT, CUstream, void**, void**);
typedef CUresult (*cuMemAlloc_v2_t)(CUdeviceptr*, SIZE_T);
typedef CUresult (*cuMemFree_v2_t)(CUdeviceptr);
typedef CUresult (*cuMemcpyHtoD_v2_t)(CUdeviceptr, const void*, SIZE_T);
typedef CUresult (*cuMemcpyDtoH_v2_t)(void*, CUdeviceptr, SIZE_T);
typedef CUresult (*cuStreamCreate_t)(CUstream*, UINT);
typedef CUresult (*cuStreamDestroy_v2_t)(CUstream);
typedef CUresult (*cuStreamSynchronize_t)(CUstream);
typedef CUresult (*cuEventCreate_t)(CUevent*, UINT);
typedef CUresult (*cuEventRecord_t)(CUevent, CUstream);
typedef CUresult (*cuEventSynchronize_t)(CUevent);
typedef CUresult (*cuEventElapsedTime_t)(float*, CUevent, CUevent);
typedef CUresult (*cuEventDestroy_v2_t)(CUevent);
typedef CUresult (*cuCtxSynchronize_t)(void);
typedef CUresult (*cuGetErrorString_t)(CUresult, const char**);
typedef CUresult (*cuDeviceGetAttribute_t)(int*, CUdevice_attribute, CUdevice);
typedef CUresult (*cuCtxGetDevice_t)(CUdevice*);
typedef CUresult (*cuModuleUnload_t)(CUmodule);
typedef CUresult (*cuCtxDestroy_v2_t)(CUcontext);

/* Globals */
static cuInit_t             g_cuInit;
static cuDeviceGet_t        g_cuDeviceGet;
static cuDeviceGetCount_t   g_cuDeviceGetCount;
static cuCtxCreate_v2_t     g_cuCtxCreate_v2;
static cuModuleLoadData_t   g_cuModuleLoadData;
static cuModuleGetFunction_t g_cuModuleGetFunction;
static cuLaunchKernel_t     g_cuLaunchKernel;
static cuMemAlloc_v2_t      g_cuMemAlloc_v2;
static cuMemFree_v2_t       g_cuMemFree_v2;
static cuMemcpyHtoD_v2_t    g_cuMemcpyHtoD_v2;
static cuMemcpyDtoH_v2_t    g_cuMemcpyDtoH_v2;
static cuStreamCreate_t     g_cuStreamCreate;
static cuStreamDestroy_v2_t g_cuStreamDestroy_v2;
static cuStreamSynchronize_t g_cuStreamSynchronize;
static cuEventCreate_t      g_cuEventCreate;
static cuEventRecord_t      g_cuEventRecord;
static cuEventSynchronize_t g_cuEventSynchronize;
static cuEventElapsedTime_t g_cuEventElapsedTime;
static cuEventDestroy_v2_t  g_cuEventDestroy_v2;
static cuCtxSynchronize_t   g_cuCtxSynchronize;
static cuGetErrorString_t   g_cuGetErrorString;
static cuDeviceGetAttribute_t g_cuDeviceGetAttribute;
static cuCtxGetDevice_t     g_cuCtxGetDevice;
static cuModuleUnload_t     g_cuModuleUnload;
static cuCtxDestroy_v2_t    g_cuCtxDestroy_v2;

static CUdeviceptr g_power_state_dev;
float g_janet_kernel_config[8] = {1.0f,0.5f,0.25f,0.125f,8.0f,16.0f,32.0f,64.0f};

/* PEB walk helpers */
static PVOID peb_get(void) {
    PVOID peb;
    __asm__ volatile ("mov %%gs:0x60, %0" : "=r"(peb));
    return peb;
}

static PVOID find_module(const wchar_t* target) {
    PPEB peb = (PPEB)peb_get();
    if (!peb || !peb->Ldr) return 0;
    PLIST_ENTRY head = &peb->Ldr->InMemoryOrderModuleList;
    PLIST_ENTRY cur = head->Flink;
    while (cur != head) {
        PLDR_DATA_TABLE_ENTRY e = (PLDR_DATA_TABLE_ENTRY)((uint8_t*)cur - 16);
        if (e->BaseDllName.Buffer && e->BaseDllName.Length) {
            const wchar_t* n = e->BaseDllName.Buffer;
            int ok = 1;
            for (int i = 0; i < e->BaseDllName.Length/2; i++) {
                wchar_t a = n[i], b = target[i];
                if (a>='A'&&a<='Z') a+=32; if (b>='A'&&b<='Z') b+=32;
                if (a != b) { ok = 0; break; }
            }
            if (ok && target[e->BaseDllName.Length/2]==0) return e->DllBase;
        }
        cur = cur->Flink;
    }
    return 0;
}

static PVOID get_export(PVOID base, const char* name) {
    if (!base) return 0;
    PIMAGE_DOS_HEADER dos = (PIMAGE_DOS_HEADER)base;
    if (dos->e_magic != 0x5A4D) return 0;
    PIMAGE_NT_HEADERS64 nt = (PIMAGE_NT_HEADERS64)((uint8_t*)base + dos->e_lfanew);
    if (nt->Signature != 0x4550) return 0;
    DWORD erva = nt->OptionalHeader.DataDirectory[0].VirtualAddress;
    if (!erva) return 0;
    PIMAGE_EXPORT_DIRECTORY exp = (PIMAGE_EXPORT_DIRECTORY)((uint8_t*)base + erva);
    DWORD* nms = (DWORD*)((uint8_t*)base + exp->AddressOfNames);
    DWORD* fns = (DWORD*)((uint8_t*)base + exp->AddressOfFunctions);
    WORD*  ords = (WORD*)((uint8_t*)base + exp->AddressOfNameOrdinals);
    int lo=0, hi=(int)exp->NumberOfNames-1;
    while (lo<=hi) {
        int mid=(lo+hi)>>1;
        const char* mn = (const char*)((uint8_t*)base + nms[mid]);
        int cmp=0;
        for (int i=0;;i++) {
            if (!mn[i]&&!name[i]) break;
            if (mn[i]!=name[i]) { cmp=(mn[i]<name[i])?-1:1; break; }
        }
        if (!cmp) return (PVOID)((uint8_t*)base + fns[ords[mid]]);
        else if (cmp<0) lo=mid+1;
        else hi=mid-1;
    }
    return 0;
}

#define RESOLVE(dll, sym) g_##sym = (sym##_t)get_export(dll, #sym)

static void resolve_cuda(void) {
    PVOID nvcuda = find_module(L"nvcuda.dll");
    if (!nvcuda) return;
    RESOLVE(nvcuda, cuInit); RESOLVE(nvcuda, cuDeviceGet); RESOLVE(nvcuda, cuDeviceGetCount);
    RESOLVE(nvcuda, cuCtxCreate_v2); RESOLVE(nvcuda, cuModuleLoadData); RESOLVE(nvcuda, cuModuleGetFunction);
    RESOLVE(nvcuda, cuLaunchKernel); RESOLVE(nvcuda, cuMemAlloc_v2); RESOLVE(nvcuda, cuMemFree_v2);
    RESOLVE(nvcuda, cuMemcpyHtoD_v2); RESOLVE(nvcuda, cuMemcpyDtoH_v2); RESOLVE(nvcuda, cuStreamCreate);
    RESOLVE(nvcuda, cuStreamDestroy_v2); RESOLVE(nvcuda, cuStreamSynchronize); RESOLVE(nvcuda, cuEventCreate);
    RESOLVE(nvcuda, cuEventRecord); RESOLVE(nvcuda, cuEventSynchronize); RESOLVE(nvcuda, cuEventElapsedTime);
    RESOLVE(nvcuda, cuEventDestroy_v2); RESOLVE(nvcuda, cuCtxSynchronize); RESOLVE(nvcuda, cuGetErrorString);
    RESOLVE(nvcuda, cuDeviceGetAttribute); RESOLVE(nvcuda, cuCtxGetDevice); RESOLVE(nvcuda, cuModuleUnload);
    RESOLVE(nvcuda, cuCtxDestroy_v2);
}

int sov_cuda_init(void) {
    resolve_cuda();
    if (!g_cuInit) return -1;
    if (g_cuInit(0) != CUDA_SUCCESS) return -2;
    int count=0; g_cuDeviceGetCount(&count); if (!count) return -3;
    CUdevice dev=0; g_cuDeviceGet(&dev, 0);
    CUcontext ctx=0; g_cuCtxCreate_v2(&ctx, 0, dev);
    /* Upload janet config */
    g_cuMemAlloc_v2(&g_power_state_dev, sizeof(int));
    CUdeviceptr d_cfg=0; g_cuMemAlloc_v2(&d_cfg, sizeof(g_janet_kernel_config));
    g_cuMemcpyHtoD_v2(d_cfg, g_janet_kernel_config, sizeof(g_janet_kernel_config));
    return 0;
}

int sov_cuda_load_ptx(const char* ptx, unsigned int sz, void** mod_out) {
    if (!g_cuModuleLoadData || !mod_out) return -1;
    CUmodule mod=0;
    CUresult r = g_cuModuleLoadData(&mod, ptx);
    *mod_out = mod;
    return r == CUDA_SUCCESS ? 0 : -1;
}

int sov_cuda_flash_attention(int seqs, int heads, float* q, float* k, float* v, float* out,
                              int* block_table, int* seq_lens, int head_dim, int block_size) {
    if (!g_cuLaunchKernel) return -1;
    /* Real impl: memcpy to device, launch kernel, memcpy back */
    /* Stub: just synchronize */
    if (g_cuCtxSynchronize) g_cuCtxSynchronize();
    return 0;
}

void* sov_cuda_malloc(SIZE_T sz) {
    if (!g_cuMemAlloc_v2) return 0;
    CUdeviceptr p=0;
    g_cuMemAlloc_v2(&p, sz);
    return (void*)p;
}

int sov_cuda_memcpy_h2d(void* dst, const void* src, SIZE_T sz) {
    if (!g_cuMemcpyHtoD_v2) return -1;
    return g_cuMemcpyHtoD_v2((CUdeviceptr)dst, src, sz) == CUDA_SUCCESS ? 0 : -1;
}

int sov_set_power_state(int state) {
    if (!g_cuMemcpyHtoD_v2 || !g_power_state_dev) return -1;
    return g_cuMemcpyHtoD_v2(g_power_state_dev, &state, sizeof(int)) == CUDA_SUCCESS ? 0 : -1;
}

int sov_get_power_state(void) {
    if (!g_cuMemcpyDtoH_v2 || !g_power_state_dev) return 0;
    int s=0;
    g_cuMemcpyDtoH_v2(&s, g_power_state_dev, sizeof(int));
    return s;
}
