#include "sov_rtx.h"
#include "cuda_driver_loader.h"
#include "rowm_cuda_validation.h"

#if defined(_MSC_VER)
#include <intrin.h>
#endif

/*
 * Zero-CRT CUDA driver loader for 64-bit Windows.
 *
 * nvcuda.dll is loaded through ntdll!LdrLoadDll when it is not already in
 * the PEB module list. CUDA entry points are then resolved directly from the
 * image export table, so neither the CUDA SDK nor an import library is needed.
 */

typedef void*   PVOID;
typedef int32_t NTSTATUS;

#if defined(_MSC_VER)
#define SOV_WINAPI __stdcall
#elif defined(__GNUC__) && defined(__i386__)
#define SOV_WINAPI __attribute__((stdcall))
#else
#define SOV_WINAPI
#endif

typedef struct sov_list_entry {
    struct sov_list_entry* Flink;
    struct sov_list_entry* Blink;
} LIST_ENTRY;

typedef struct {
    uint16_t Length;
    uint16_t MaximumLength;
    wchar_t* Buffer;
} UNICODE_STRING;

typedef struct {
    uint32_t   Length;
    uint8_t    Initialized;
    uint8_t    Reserved1[3];
    PVOID      SsHandle;
    LIST_ENTRY InLoadOrderModuleList;
    LIST_ENTRY InMemoryOrderModuleList;
    LIST_ENTRY InInitializationOrderModuleList;
} PEB_LDR_DATA;

typedef struct {
    LIST_ENTRY     InLoadOrderLinks;
    LIST_ENTRY     InMemoryOrderLinks;
    LIST_ENTRY     InInitializationOrderLinks;
    PVOID          DllBase;
    PVOID          EntryPoint;
    uint32_t       SizeOfImage;
    uint32_t       Reserved;
    UNICODE_STRING FullDllName;
    UNICODE_STRING BaseDllName;
} LDR_DATA_TABLE_ENTRY;

typedef struct {
    uint8_t       Reserved1[2];
    uint8_t       BeingDebugged;
    uint8_t       Reserved2;
    PVOID         Reserved3[2];
    PEB_LDR_DATA* Ldr;
} PEB;

typedef struct {
    uint16_t e_magic;
    uint16_t e_cblp;
    uint16_t e_cp;
    uint16_t e_crlc;
    uint16_t e_cparhdr;
    uint16_t e_minalloc;
    uint16_t e_maxalloc;
    uint16_t e_ss;
    uint16_t e_sp;
    uint16_t e_csum;
    uint16_t e_ip;
    uint16_t e_cs;
    uint16_t e_lfarlc;
    uint16_t e_ovno;
    uint16_t e_res[4];
    uint16_t e_oemid;
    uint16_t e_oeminfo;
    uint16_t e_res2[10];
    int32_t  e_lfanew;
} IMAGE_DOS_HEADER;

typedef struct {
    uint32_t VirtualAddress;
    uint32_t Size;
} IMAGE_DATA_DIRECTORY;

typedef struct {
    uint16_t Machine;
    uint16_t NumberOfSections;
    uint32_t TimeDateStamp;
    uint32_t PointerToSymbolTable;
    uint32_t NumberOfSymbols;
    uint16_t SizeOfOptionalHeader;
    uint16_t Characteristics;
} IMAGE_FILE_HEADER;

typedef struct {
    uint16_t Magic;
    uint8_t  MajorLinkerVersion;
    uint8_t  MinorLinkerVersion;
    uint32_t SizeOfCode;
    uint32_t SizeOfInitializedData;
    uint32_t SizeOfUninitializedData;
    uint32_t AddressOfEntryPoint;
    uint32_t BaseOfCode;
    uint64_t ImageBase;
    uint32_t SectionAlignment;
    uint32_t FileAlignment;
    uint16_t MajorOperatingSystemVersion;
    uint16_t MinorOperatingSystemVersion;
    uint16_t MajorImageVersion;
    uint16_t MinorImageVersion;
    uint16_t MajorSubsystemVersion;
    uint16_t MinorSubsystemVersion;
    uint32_t Win32VersionValue;
    uint32_t SizeOfImage;
    uint32_t SizeOfHeaders;
    uint32_t CheckSum;
    uint16_t Subsystem;
    uint16_t DllCharacteristics;
    uint64_t SizeOfStackReserve;
    uint64_t SizeOfStackCommit;
    uint64_t SizeOfHeapReserve;
    uint64_t SizeOfHeapCommit;
    uint32_t LoaderFlags;
    uint32_t NumberOfRvaAndSizes;
    IMAGE_DATA_DIRECTORY DataDirectory[16];
} IMAGE_OPTIONAL_HEADER64;

typedef struct {
    uint32_t              Signature;
    IMAGE_FILE_HEADER     FileHeader;
    IMAGE_OPTIONAL_HEADER64 OptionalHeader;
} IMAGE_NT_HEADERS64;

typedef struct {
    uint32_t Characteristics;
    uint32_t TimeDateStamp;
    uint16_t MajorVersion;
    uint16_t MinorVersion;
    uint32_t Name;
    uint32_t Base;
    uint32_t NumberOfFunctions;
    uint32_t NumberOfNames;
    uint32_t AddressOfFunctions;
    uint32_t AddressOfNames;
    uint32_t AddressOfNameOrdinals;
} IMAGE_EXPORT_DIRECTORY;

typedef NTSTATUS (SOV_WINAPI *LdrLoadDll_t)(
    wchar_t*, uint32_t*, UNICODE_STRING*, PVOID*);

typedef struct { uint8_t bytes[16]; } CUuuid;

typedef CUresult (SOV_WINAPI *cuInit_t)(unsigned int);
typedef CUresult (SOV_WINAPI *cuDriverGetVersion_t)(int*);
typedef CUresult (SOV_WINAPI *cuDeviceGet_t)(CUdevice*, int);
typedef CUresult (SOV_WINAPI *cuDeviceGetCount_t)(int*);
typedef CUresult (SOV_WINAPI *cuDeviceGetName_t)(char*, int, CUdevice);
typedef CUresult (SOV_WINAPI *cuDeviceGetAttribute_t)(int*, CUdevice_attribute, CUdevice);
typedef CUresult (SOV_WINAPI *cuDeviceGetUuid_t)(CUuuid*, CUdevice);
typedef CUresult (SOV_WINAPI *cuCtxCreate_v2_t)(CUcontext*, unsigned int, CUdevice);
typedef CUresult (SOV_WINAPI *cuCtxDestroy_v2_t)(CUcontext);
typedef CUresult (SOV_WINAPI *cuCtxSetCurrent_t)(CUcontext);
typedef CUresult (SOV_WINAPI *cuModuleLoadData_t)(CUmodule*, const void*);
typedef CUresult (SOV_WINAPI *cuModuleGetFunction_t)(CUfunction*, CUmodule, const char*);
typedef CUresult (SOV_WINAPI *cuModuleGetGlobal_v2_t)(CUdeviceptr*, size_t*, CUmodule, const char*);
typedef CUresult (SOV_WINAPI *cuModuleUnload_t)(CUmodule);
typedef CUresult (SOV_WINAPI *cuLaunchKernel_t)(
    CUfunction,
    unsigned int, unsigned int, unsigned int,
    unsigned int, unsigned int, unsigned int,
    unsigned int, CUstream, void**, void**);
typedef CUresult (SOV_WINAPI *cuMemAlloc_v2_t)(CUdeviceptr*, size_t);
typedef CUresult (SOV_WINAPI *cuMemFree_v2_t)(CUdeviceptr);
typedef CUresult (SOV_WINAPI *cuMemcpyHtoD_v2_t)(CUdeviceptr, const void*, size_t);
typedef CUresult (SOV_WINAPI *cuMemcpyDtoH_v2_t)(void*, CUdeviceptr, size_t);

static cuInit_t               g_cuInit;
static cuDriverGetVersion_t   g_cuDriverGetVersion;
static cuDeviceGet_t          g_cuDeviceGet;
static cuDeviceGetCount_t     g_cuDeviceGetCount;
static cuDeviceGetName_t      g_cuDeviceGetName;
static cuDeviceGetAttribute_t g_cuDeviceGetAttribute;
static cuDeviceGetUuid_t      g_cuDeviceGetUuid;
static cuCtxCreate_v2_t       g_cuCtxCreate_v2;
static cuCtxDestroy_v2_t      g_cuCtxDestroy_v2;
static cuCtxSetCurrent_t      g_cuCtxSetCurrent;
static cuModuleLoadData_t     g_cuModuleLoadData;
static cuModuleGetFunction_t  g_cuModuleGetFunction;
static cuModuleGetGlobal_v2_t g_cuModuleGetGlobal_v2;
static cuModuleUnload_t       g_cuModuleUnload;
static cuLaunchKernel_t       g_cuLaunchKernel;
static cuMemAlloc_v2_t        g_cuMemAlloc_v2;
static cuMemFree_v2_t         g_cuMemFree_v2;
static cuMemcpyHtoD_v2_t      g_cuMemcpyHtoD_v2;
static cuMemcpyDtoH_v2_t      g_cuMemcpyDtoH_v2;

static CUcontext      g_cuda_context;
static CUdevice       g_cuda_device;
static uint32_t       g_cuda_device_ordinal;
static CUdeviceptr    g_power_state_device;
static volatile int32_t g_power_state_host;
static int            g_cuda_initialized;
static uint64_t       g_cuda_context_generation;

float g_janet_kernel_config[8] = {
    1.0f, 0.5f, 0.25f, 0.125f, 8.0f, 16.0f, 32.0f, 64.0f
};

static void power_state_store(int32_t state) {
#if defined(_MSC_VER)
    (void)_InterlockedExchange((volatile long*)&g_power_state_host, (long)state);
#else
    __atomic_store_n(&g_power_state_host, state, __ATOMIC_RELEASE);
#endif
}

static int32_t power_state_load(void) {
#if defined(_MSC_VER)
    return (int32_t)_InterlockedCompareExchange(
        (volatile long*)&g_power_state_host, 0, 0);
#else
    return __atomic_load_n(&g_power_state_host, __ATOMIC_ACQUIRE);
#endif
}

static PVOID peb_get(void) {
#if defined(_MSC_VER)
    return (PVOID)__readgsqword(0x60);
#elif defined(__x86_64__)
    PVOID peb;
    __asm__ volatile ("mov %%gs:0x60, %0" : "=r"(peb));
    return peb;
#else
#error "The sovereign CUDA loader supports only 64-bit Windows"
#endif
}

static wchar_t ascii_lower_w(wchar_t value) {
    if (value >= L'A' && value <= L'Z') return (wchar_t)(value + (L'a' - L'A'));
    return value;
}

static PVOID find_module(const wchar_t* target) {
    PEB* peb = (PEB*)peb_get();
    LIST_ENTRY* head;
    LIST_ENTRY* current;

    if (!peb || !peb->Ldr || !target) return 0;

    head    = &peb->Ldr->InMemoryOrderModuleList;
    current = head->Flink;
    while (current && current != head) {
        LDR_DATA_TABLE_ENTRY* entry =
            (LDR_DATA_TABLE_ENTRY*)((uint8_t*)current -
                offsetof(LDR_DATA_TABLE_ENTRY, InMemoryOrderLinks));
        if (entry->BaseDllName.Buffer && entry->BaseDllName.Length) {
            size_t length = (size_t)entry->BaseDllName.Length / sizeof(wchar_t);
            size_t i;
            int matches = 1;
            for (i = 0; i < length; ++i) {
                if (!target[i] ||
                    ascii_lower_w(entry->BaseDllName.Buffer[i]) !=
                        ascii_lower_w(target[i])) {
                    matches = 0;
                    break;
                }
            }
            if (matches && target[length] == L'\0') return entry->DllBase;
        }
        current = current->Flink;
    }
    return 0;
}

static int ascii_compare(const char* left, const char* right) {
    size_t i = 0;
    while (left[i] && right[i] && left[i] == right[i]) ++i;
    return (int)(uint8_t)left[i] - (int)(uint8_t)right[i];
}

static PVOID get_export(PVOID base, const char* name) {
    IMAGE_DOS_HEADER*     dos;
    IMAGE_NT_HEADERS64*   nt;
    IMAGE_DATA_DIRECTORY* export_data;
    IMAGE_EXPORT_DIRECTORY* exports;
    uint32_t* names;
    uint32_t* functions;
    uint16_t* ordinals;
    int low, high;

    if (!base || !name) return 0;

    dos = (IMAGE_DOS_HEADER*)base;
    if (dos->e_magic != 0x5a4d || dos->e_lfanew <= 0) return 0;

    nt = (IMAGE_NT_HEADERS64*)((uint8_t*)base + dos->e_lfanew);
    if (nt->Signature != 0x00004550 ||
        nt->OptionalHeader.Magic != 0x020b ||
        nt->OptionalHeader.NumberOfRvaAndSizes == 0) return 0;

    export_data = &nt->OptionalHeader.DataDirectory[0];
    if (!export_data->VirtualAddress || !export_data->Size) return 0;

    exports   = (IMAGE_EXPORT_DIRECTORY*)((uint8_t*)base + export_data->VirtualAddress);
    names     = (uint32_t*)((uint8_t*)base + exports->AddressOfNames);
    functions = (uint32_t*)((uint8_t*)base + exports->AddressOfFunctions);
    ordinals  = (uint16_t*)((uint8_t*)base + exports->AddressOfNameOrdinals);

    low  = 0;
    high = (int)exports->NumberOfNames - 1;
    while (low <= high) {
        int middle       = low + ((high - low) / 2);
        const char* cand = (const char*)((uint8_t*)base + names[middle]);
        int cmp          = ascii_compare(cand, name);
        if (cmp == 0) {
            uint16_t ordinal   = ordinals[middle];
            uint32_t fn_rva;
            if ((uint32_t)ordinal >= exports->NumberOfFunctions) return 0;
            fn_rva = functions[ordinal];
            if (fn_rva >= export_data->VirtualAddress &&
                fn_rva <  export_data->VirtualAddress + export_data->Size) return 0;
            return (PVOID)((uint8_t*)base + fn_rva);
        }
        if (cmp < 0) low  = middle + 1;
        else         high = middle - 1;
    }
    return 0;
}

static PVOID load_nvcuda(void) {
    static wchar_t dll_name_buffer[] = L"nvcuda.dll";
    PVOID nvcuda = find_module(dll_name_buffer);
    PVOID ntdll;
    LdrLoadDll_t load_dll;
    UNICODE_STRING dll_name;

    if (nvcuda) return nvcuda;

    ntdll    = find_module(L"ntdll.dll");
    load_dll = (LdrLoadDll_t)get_export(ntdll, "LdrLoadDll");
    if (!load_dll) return 0;

    dll_name.Length        = (uint16_t)(10u * sizeof(wchar_t));
    dll_name.MaximumLength = (uint16_t)(11u * sizeof(wchar_t));
    dll_name.Buffer        = dll_name_buffer;
    if (load_dll(0, 0, &dll_name, &nvcuda) < 0) return 0;
    return nvcuda;
}

#define RESOLVE_CUDA(base, symbol) \
    g_##symbol = (symbol##_t)get_export((base), #symbol)

static int resolve_cuda(void) {
    PVOID nvcuda = load_nvcuda();
    if (!nvcuda) return -1;

    RESOLVE_CUDA(nvcuda, cuInit);
    RESOLVE_CUDA(nvcuda, cuDriverGetVersion);
    RESOLVE_CUDA(nvcuda, cuDeviceGet);
    RESOLVE_CUDA(nvcuda, cuDeviceGetCount);
    RESOLVE_CUDA(nvcuda, cuDeviceGetName);
    RESOLVE_CUDA(nvcuda, cuDeviceGetAttribute);
    g_cuDeviceGetUuid = (cuDeviceGetUuid_t)get_export(nvcuda, "cuDeviceGetUuid_v2");
    if (!g_cuDeviceGetUuid)
        g_cuDeviceGetUuid = (cuDeviceGetUuid_t)get_export(nvcuda, "cuDeviceGetUuid");
    RESOLVE_CUDA(nvcuda, cuCtxCreate_v2);
    RESOLVE_CUDA(nvcuda, cuCtxDestroy_v2);
    RESOLVE_CUDA(nvcuda, cuCtxSetCurrent);
    RESOLVE_CUDA(nvcuda, cuModuleLoadData);
    RESOLVE_CUDA(nvcuda, cuModuleGetFunction);
    RESOLVE_CUDA(nvcuda, cuModuleGetGlobal_v2);
    RESOLVE_CUDA(nvcuda, cuModuleUnload);
    RESOLVE_CUDA(nvcuda, cuLaunchKernel);
    RESOLVE_CUDA(nvcuda, cuMemAlloc_v2);
    RESOLVE_CUDA(nvcuda, cuMemFree_v2);
    RESOLVE_CUDA(nvcuda, cuMemcpyHtoD_v2);
    RESOLVE_CUDA(nvcuda, cuMemcpyDtoH_v2);

    return (g_cuInit && g_cuDriverGetVersion &&
            g_cuDeviceGet && g_cuDeviceGetCount &&
            g_cuDeviceGetName && g_cuDeviceGetAttribute &&
            g_cuDeviceGetUuid &&
            g_cuCtxCreate_v2 && g_cuCtxDestroy_v2 && g_cuCtxSetCurrent &&
            g_cuModuleLoadData && g_cuModuleGetFunction &&
            g_cuModuleGetGlobal_v2 && g_cuModuleUnload &&
            g_cuLaunchKernel && g_cuMemAlloc_v2 && g_cuMemFree_v2 &&
            g_cuMemcpyHtoD_v2 && g_cuMemcpyDtoH_v2)
        ? 1 : 0;
}

static CUresult make_cuda_context_current(void) {
    if (!g_cuda_initialized || !g_cuda_context || !g_cuCtxSetCurrent)
        return CUDA_ERROR_NOT_INITIALIZED;
    return g_cuCtxSetCurrent(g_cuda_context);
}

#define REQUIRE_CURRENT_CONTEXT()                           \
    do {                                                    \
        CUresult _ctx_result = make_cuda_context_current(); \
        if (_ctx_result != CUDA_SUCCESS) return _ctx_result; \
    } while (0)

int sov_cuda_init(void) {
    CUdevice  device;
    CUcontext context;
    CUresult  result;
    int       device_count;
    int       resolve_result;

    if (g_cuda_initialized) return CUDA_SUCCESS;

    resolve_result = resolve_cuda();
    if (resolve_result < 0)  return CUDA_ERROR_NOT_FOUND;
    if (resolve_result == 0) return CUDA_ERROR_UNKNOWN;

    result = g_cuInit(0);
    if (result != CUDA_SUCCESS) return result;

    device_count = 0;
    result = g_cuDeviceGetCount(&device_count);
    if (result != CUDA_SUCCESS) return result;
    if (device_count <= 0) return CUDA_ERROR_NO_DEVICE;

    device = 0;
    result = g_cuDeviceGet(&device, 0);
    if (result != CUDA_SUCCESS) return result;

    context = 0;
    result = g_cuCtxCreate_v2(&context, 0, device);
    if (result != CUDA_SUCCESS) return result;

    g_cuda_context       = context;
    g_cuda_device        = device;
    g_cuda_device_ordinal = 0;
    power_state_store(0);
    g_power_state_device = 0;
    ++g_cuda_context_generation;
    if (g_cuda_context_generation == 0u) ++g_cuda_context_generation;
    g_cuda_initialized = 1;
    return CUDA_SUCCESS;
}

void sov_cuda_shutdown(void) {
    CUcontext context;
    if (!g_cuda_initialized) { sov_cuda_validation_clear(); return; }

    context = g_cuda_context;
    if (context && g_cuCtxSetCurrent) (void)g_cuCtxSetCurrent(context);
    g_power_state_device = 0;
    g_cuda_context       = 0;
    g_cuda_device        = 0;
    g_cuda_device_ordinal = 0;
    if (context && g_cuCtxDestroy_v2) (void)g_cuCtxDestroy_v2(context);
    g_cuda_initialized = 0;
    sov_cuda_validation_clear();
}

int sov_cuda_is_initialized(void) { return g_cuda_initialized; }

uint64_t sov_cuda_context_generation(void) { return g_cuda_context_generation; }

CUresult sov_cuda_get_runtime_identity(sov_cuda_runtime_identity_t* identity_out) {
    CUuuid   uuid;
    CUresult result;
    int      driver_version;
    int      major, minor;
    size_t   index;

    if (!identity_out) return CUDA_ERROR_INVALID_VALUE;
    for (index = 0; index < sizeof(*identity_out); ++index)
        ((uint8_t*)identity_out)[index] = 0;

    if (!g_cuda_initialized || !g_cuDriverGetVersion ||
        !g_cuDeviceGetName || !g_cuDeviceGetAttribute || !g_cuDeviceGetUuid)
        return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();

    driver_version = 0;
    result = g_cuDriverGetVersion(&driver_version);
    if (result != CUDA_SUCCESS || driver_version <= 0)
        return result != CUDA_SUCCESS ? result : CUDA_ERROR_UNKNOWN;

    result = g_cuDeviceGetName(identity_out->device_name,
                               (int)sizeof(identity_out->device_name),
                               g_cuda_device);
    if (result != CUDA_SUCCESS) return result;
    identity_out->device_name[sizeof(identity_out->device_name) - 1u] = '\0';

    major = 0;
    result = g_cuDeviceGetAttribute(&major, (CUdevice_attribute)75, g_cuda_device);
    if (result != CUDA_SUCCESS || major <= 0)
        return result != CUDA_SUCCESS ? result : CUDA_ERROR_UNKNOWN;

    minor = 0;
    result = g_cuDeviceGetAttribute(&minor, (CUdevice_attribute)76, g_cuda_device);
    if (result != CUDA_SUCCESS || minor < 0)
        return result != CUDA_SUCCESS ? result : CUDA_ERROR_UNKNOWN;

    result = g_cuDeviceGetUuid(&uuid, g_cuda_device);
    if (result != CUDA_SUCCESS) return result;

    identity_out->driver_version             = (uint32_t)driver_version;
    identity_out->device_ordinal             = g_cuda_device_ordinal;
    identity_out->compute_capability_major   = (uint32_t)major;
    identity_out->compute_capability_minor   = (uint32_t)minor;
    for (index = 0; index < sizeof(identity_out->device_uuid); ++index)
        identity_out->device_uuid[index] = uuid.bytes[index];
    identity_out->context_generation = g_cuda_context_generation;
    return CUDA_SUCCESS;
}

CUresult sov_cuda_module_load_data(CUmodule* module, const void* image) {
    if (!module || !image) return CUDA_ERROR_INVALID_VALUE;
    *module = 0;
    if (!g_cuda_initialized || !g_cuModuleLoadData) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuModuleLoadData(module, image);
}

CUresult sov_cuda_module_get_function(CUfunction* function, CUmodule module,
                                      const char* name) {
    if (!function || !module || !name || !name[0]) return CUDA_ERROR_INVALID_VALUE;
    *function = 0;
    if (!g_cuda_initialized || !g_cuModuleGetFunction) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuModuleGetFunction(function, module, name);
}

CUresult sov_cuda_module_get_global(CUdeviceptr* device_ptr, size_t* bytes,
                                    CUmodule module, const char* name) {
    if (!device_ptr || !module || !name || !name[0]) return CUDA_ERROR_INVALID_VALUE;
    *device_ptr = 0;
    if (bytes) *bytes = 0;
    if (!g_cuda_initialized || !g_cuModuleGetGlobal_v2) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuModuleGetGlobal_v2(device_ptr, bytes, module, name);
}

CUresult sov_cuda_module_unload(CUmodule module) {
    if (!module) return CUDA_SUCCESS;
    if (!g_cuda_initialized || !g_cuModuleUnload) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuModuleUnload(module);
}

CUresult sov_cuda_launch_kernel(CUfunction function,
                                unsigned int grid_x, unsigned int grid_y,
                                unsigned int grid_z,
                                unsigned int block_x, unsigned int block_y,
                                unsigned int block_z,
                                unsigned int shared_mem_bytes,
                                CUstream stream,
                                void** kernel_params,
                                void** extra) {
    if (!function || !grid_x || !grid_y || !grid_z ||
        !block_x  || !block_y || !block_z) return CUDA_ERROR_INVALID_VALUE;
    if (!g_cuda_initialized || !g_cuLaunchKernel) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuLaunchKernel(function,
                            grid_x, grid_y, grid_z,
                            block_x, block_y, block_z,
                            shared_mem_bytes, stream,
                            kernel_params, extra);
}

CUresult sov_cuda_mem_alloc(CUdeviceptr* device_ptr, size_t bytes) {
    if (!device_ptr || !bytes) return CUDA_ERROR_INVALID_VALUE;
    *device_ptr = 0;
    if (!g_cuda_initialized || !g_cuMemAlloc_v2) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuMemAlloc_v2(device_ptr, bytes);
}

CUresult sov_cuda_mem_free(CUdeviceptr device_ptr) {
    if (!device_ptr) return CUDA_SUCCESS;
    if (!g_cuda_initialized || !g_cuMemFree_v2) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuMemFree_v2(device_ptr);
}

int sov_cuda_memcpy_h2d(void* device_dst, const void* host_src, size_t bytes) {
    if (!bytes) return CUDA_SUCCESS;
    if (!device_dst || !host_src) return CUDA_ERROR_INVALID_VALUE;
    if (!g_cuda_initialized || !g_cuMemcpyHtoD_v2) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuMemcpyHtoD_v2((CUdeviceptr)(uintptr_t)device_dst, host_src, bytes);
}

CUresult sov_cuda_memcpy_d2h(void* host_dst, CUdeviceptr device_src, size_t bytes) {
    if (!bytes) return CUDA_SUCCESS;
    if (!host_dst || !device_src) return CUDA_ERROR_INVALID_VALUE;
    if (!g_cuda_initialized || !g_cuMemcpyDtoH_v2) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    return g_cuMemcpyDtoH_v2(host_dst, device_src, bytes);
}

CUresult sov_cuda_register_power_state_device(CUdeviceptr device_ptr) {
    g_power_state_device = device_ptr;
    if (!device_ptr) return CUDA_SUCCESS;
    return sov_cuda_sync_power_state();
}

CUresult sov_cuda_sync_power_state(void) {
    int32_t state;
    if (!g_power_state_device) return CUDA_SUCCESS;
    if (!g_cuda_initialized || !g_cuMemcpyHtoD_v2) return CUDA_ERROR_NOT_INITIALIZED;
    REQUIRE_CURRENT_CONTEXT();
    state = power_state_load();
    return g_cuMemcpyHtoD_v2(g_power_state_device, &state, sizeof(state));
}

int sov_cuda_load_ptx(const char* ptx_data, unsigned int ptx_size, void** module_out) {
    CUmodule module;
    CUresult result;
    unsigned int i;
    if (!module_out) return CUDA_ERROR_INVALID_VALUE;
    *module_out = 0;
    if (!ptx_data || !ptx_size || ptx_data[ptx_size - 1u] != '\0')
        return CUDA_ERROR_INVALID_VALUE;
    for (i = 0; i + 1u < ptx_size; ++i)
        if (ptx_data[i] == '\0') return CUDA_ERROR_INVALID_VALUE;
    result = sov_cuda_module_load_data(&module, ptx_data);
    if (result == CUDA_SUCCESS) *module_out = (void*)module;
    return result;
}

void* sov_cuda_malloc(size_t bytes) {
    CUdeviceptr device_ptr;
    if (sov_cuda_mem_alloc(&device_ptr, bytes) != CUDA_SUCCESS) return 0;
    return (void*)(uintptr_t)device_ptr;
}

int sov_set_power_state(sov_power_state_t state) {
    if ((unsigned int)state > (unsigned int)SOV_POWER_LOW_BATTERY)
        return CUDA_ERROR_INVALID_VALUE;
    power_state_store((int32_t)state);
    return CUDA_SUCCESS;
}

sov_power_state_t sov_get_power_state(void) {
    return (sov_power_state_t)power_state_load();
}
