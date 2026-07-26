/*
 * Zero-CRT diagnostic entry point.
 *
 * The CUDA driver, embedded PTX modules, and KV allocator are initialized in
 * dependency order. The scheduler is intentionally not entered until its C--
 * bridge and the WORM/Janet implementations exist in the link graph.
 */
typedef unsigned long long uint64_t;
typedef unsigned int       uint32_t;
typedef unsigned short     uint16_t;
typedef unsigned char      uint8_t;
typedef int                int32_t;
typedef unsigned long      ULONG;
typedef void*              PVOID;
typedef PVOID              HANDLE;
typedef uint32_t           DWORD;

typedef struct _SOV_LIST_ENTRY {
    struct _SOV_LIST_ENTRY* Flink;
    struct _SOV_LIST_ENTRY* Blink;
} SOV_LIST_ENTRY;

typedef struct {
    uint16_t Length;
    uint16_t MaximumLength;
    uint16_t* Buffer;
} SOV_UNICODE_STRING;

typedef struct {
    SOV_LIST_ENTRY     InLoadOrderLinks;
    SOV_LIST_ENTRY     InMemoryOrderLinks;
    SOV_LIST_ENTRY     InInitializationOrderLinks;
    PVOID              DllBase;
    PVOID              EntryPoint;
    ULONG              SizeOfImage;
    SOV_UNICODE_STRING FullDllName;
    SOV_UNICODE_STRING BaseDllName;
} SOV_LDR_DATA_TABLE_ENTRY;

typedef struct {
    ULONG          Length;
    uint32_t       Initialized;
    HANDLE         SsHandle;
    SOV_LIST_ENTRY InLoadOrderModuleList;
    SOV_LIST_ENTRY InMemoryOrderModuleList;
} SOV_PEB_LDR_DATA;

typedef struct {
    uint8_t           Reserved1[4];
    PVOID             Reserved2[2];
    SOV_PEB_LDR_DATA* Ldr;
} SOV_PEB;

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
} SOV_IMAGE_EXPORT_DIRECTORY;

typedef int    (*WriteConsoleA_t)(HANDLE, const void*, DWORD, DWORD*, void*);
typedef HANDLE (*GetStdHandle_t)(DWORD);
typedef void   (*ExitProcess_t)(DWORD);

static WriteConsoleA_t g_WriteConsoleA;
static GetStdHandle_t  g_GetStdHandle;
static ExitProcess_t   g_ExitProcess;

extern int  sov_cuda_init(void);
extern void sov_cuda_shutdown(void);
extern int  sov_cuda_kernels_init(void);
extern void sov_cuda_kernels_shutdown(void);
extern int  sov_kv_allocator_init(void);
extern void sov_kv_allocator_shutdown(void);

#define SOV_EXIT_BOOTSTRAP_API     ((DWORD)0x10u)
#define SOV_EXIT_CUDA_INIT         ((DWORD)0x20u)
#define SOV_EXIT_CUDA_KERNEL_INIT  ((DWORD)0x21u)
#define SOV_EXIT_KV_ALLOCATOR_INIT ((DWORD)0x22u)
#define SOV_EXIT_SCHEDULER_UNWIRED ((DWORD)0x30u)

static const uint16_t g_kernelbase_name[] = {
    'k','e','r','n','e','l','b','a','s','e','.','d','l','l', 0
};
static const uint16_t g_kernel32_name[] = {
    'k','e','r','n','e','l','3','2','.','d','l','l', 0
};

static PVOID peb_find(const uint16_t* target) {
    PVOID peb_address;
    SOV_PEB_LDR_DATA* loader;
    SOV_LIST_ENTRY* head;
    SOV_LIST_ENTRY* current;

    __asm__ volatile("mov %%gs:0x60,%0" : "=r"(peb_address));
    loader = ((SOV_PEB*)peb_address)->Ldr;
    if (!loader) return 0;

    head    = &loader->InMemoryOrderModuleList;
    current = head->Flink;
    while (current && current != head) {
        SOV_LDR_DATA_TABLE_ENTRY* entry =
            (SOV_LDR_DATA_TABLE_ENTRY*)((uint8_t*)current - 16u);
        uint32_t length = (uint32_t)entry->BaseDllName.Length / 2u;
        uint32_t i;
        int equal = entry->BaseDllName.Buffer != 0;

        for (i = 0; equal && i < length; ++i) {
            uint16_t actual   = entry->BaseDllName.Buffer[i];
            uint16_t expected = target[i];
            if (actual   >= 'A' && actual   <= 'Z') actual   += ('a' - 'A');
            if (expected >= 'A' && expected <= 'Z') expected += ('a' - 'A');
            if (actual != expected) equal = 0;
        }
        if (equal && target[length] == 0) return entry->DllBase;
        current = current->Flink;
    }
    return 0;
}

static int ascii_compare(const char* left, const char* right) {
    uint32_t i = 0;
    while (left[i] && right[i] && left[i] == right[i]) ++i;
    if ((uint8_t)left[i] < (uint8_t)right[i]) return -1;
    if ((uint8_t)left[i] > (uint8_t)right[i]) return  1;
    return 0;
}

static PVOID pe_export(PVOID module, const char* name) {
    uint8_t* image = (uint8_t*)module;
    int32_t pe_offset;
    uint8_t* nt;
    uint8_t* optional_header;
    uint32_t export_rva, export_size;
    SOV_IMAGE_EXPORT_DIRECTORY* exports;
    uint32_t* names;
    uint32_t* functions;
    uint16_t* ordinals;
    int32_t low, high;

    if (!image || *(uint16_t*)image != 0x5A4Du) return 0;
    pe_offset = *(int32_t*)(image + 0x3cu);
    if (pe_offset <= 0) return 0;

    nt = image + (uint32_t)pe_offset;
    if (*(uint32_t*)nt != 0x00004550u) return 0;
    optional_header = nt + 24u;
    if (*(uint16_t*)optional_header != 0x020bu) return 0;

    export_rva  = *(uint32_t*)(optional_header + 112u);
    export_size = *(uint32_t*)(optional_header + 116u);
    if (!export_rva || !export_size) return 0;

    exports   = (SOV_IMAGE_EXPORT_DIRECTORY*)(image + export_rva);
    names     = (uint32_t*)(image + exports->AddressOfNames);
    functions = (uint32_t*)(image + exports->AddressOfFunctions);
    ordinals  = (uint16_t*)(image + exports->AddressOfNameOrdinals);

    low  = 0;
    high = (int32_t)exports->NumberOfNames - 1;
    while (low <= high) {
        int32_t middle  = low + ((high - low) / 2);
        const char* cand = (const char*)(image + names[middle]);
        int cmp         = ascii_compare(cand, name);
        if (cmp == 0) {
            uint16_t ord = ordinals[middle];
            uint32_t fn_rva;
            if ((uint32_t)ord >= exports->NumberOfFunctions) return 0;
            fn_rva = functions[ord];
            if (fn_rva >= export_rva && fn_rva < export_rva + export_size)
                return 0;
            return (PVOID)(image + fn_rva);
        }
        if (cmp < 0) low  = middle + 1;
        else         high = middle - 1;
    }
    return 0;
}

static int resolve_process_apis(void) {
    PVOID module = peb_find(g_kernelbase_name);
    union { PVOID address; WriteConsoleA_t function; } wc;
    union { PVOID address; GetStdHandle_t  function; } gs;
    union { PVOID address; ExitProcess_t   function; } ep;

    if (!module) module = peb_find(g_kernel32_name);
    if (!module) return -1;

    wc.address = pe_export(module, "WriteConsoleA");
    gs.address = pe_export(module, "GetStdHandle");
    ep.address = pe_export(module, "ExitProcess");
    g_WriteConsoleA = wc.function;
    g_GetStdHandle  = gs.function;
    g_ExitProcess   = ep.function;
    return (g_WriteConsoleA && g_GetStdHandle && g_ExitProcess) ? 0 : -1;
}

static void console_write(const char* text) {
    DWORD length = 0, written = 0;
    HANDLE output;
    if (!g_WriteConsoleA || !g_GetStdHandle || !text) return;
    while (text[length]) ++length;
    output = g_GetStdHandle((DWORD)-11);
    g_WriteConsoleA(output, text, length, &written, 0);
}

static void terminate_process(DWORD exit_code) {
    if (g_ExitProcess) g_ExitProcess(exit_code);
    for (;;) __asm__ volatile("hlt");
}

void sov_main(void) {
    int status;

    if (resolve_process_apis() != 0)
        terminate_process(SOV_EXIT_BOOTSTRAP_API);

    console_write("SOV RTX DIAGNOSTIC BOOT\r\n");

    status = sov_cuda_init();
    if (status != 0) {
        console_write("CUDA INIT FAILED\r\n");
        terminate_process(SOV_EXIT_CUDA_INIT);
    }
    console_write("CUDA DRIVER OK\r\n");

    status = sov_cuda_kernels_init();
    if (status != 0) {
        console_write("CUDA KERNEL INIT FAILED\r\n");
        sov_cuda_kernels_shutdown();
        sov_cuda_shutdown();
        terminate_process(SOV_EXIT_CUDA_KERNEL_INIT);
    }
    console_write("CUDA KERNELS OK\r\n");

    status = sov_kv_allocator_init();
    if (status != 0) {
        console_write("KV ALLOCATOR INIT FAILED\r\n");
        sov_kv_allocator_shutdown();
        sov_cuda_kernels_shutdown();
        sov_cuda_shutdown();
        terminate_process(SOV_EXIT_KV_ALLOCATOR_INIT);
    }
    console_write("KV ALLOCATOR OK\r\n");

    /*
     * Fail closed. power_handler.c cannot enter the link until its WORM and
     * Janet dependencies exist, and scheduler.cmm has no C ABI bridge yet.
     */
    console_write("SCHEDULER/WORM/JANET UNWIRED - HALTING\r\n");
    sov_kv_allocator_shutdown();
    sov_cuda_kernels_shutdown();
    sov_cuda_shutdown();
    console_write("RTX SHUTDOWN OK\r\n");
    terminate_process(SOV_EXIT_SCHEDULER_UNWIRED);
}
