/* Zero-CRT entry point — no standard headers, no C runtime
 * Manual kernel32 resolution via PEB walk
 * Boot: CUDA -> Power -> Janet -> Scheduler -> loop
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
typedef uint64_t           ULONG_PTR;
typedef int                BOOL;
typedef unsigned long long SIZE_T;
typedef int (*LPTHREAD_START_ROUTINE)(PVOID);

/* PE structures (inline) */
typedef struct { struct _LE* Flink; struct _LE* Blink; } LIST_ENTRY, *PLIST_ENTRY;
typedef struct { uint16_t Length; uint16_t MaximumLength; wchar_t* Buffer; } UNICODE_STRING;
typedef struct {
    LIST_ENTRY L1, L2, L3;
    PVOID DllBase; PVOID EntryPoint; ULONG SizeOfImage;
    UNICODE_STRING FullDllName; UNICODE_STRING BaseDllName;
} LDR_DATA_TABLE_ENTRY, *PLDR_DATA_TABLE_ENTRY;
typedef struct { ULONG Length; BOOL Init; HANDLE Ss; LIST_ENTRY L1; LIST_ENTRY L2; } PEB_LDR_DATA, *PPEB_LDR_DATA;
typedef struct { uint8_t r[3]; uint8_t r2; PVOID r3[2]; PPEB_LDR_DATA Ldr; } PEB, *PPEB;
typedef struct { uint16_t e_magic; uint8_t r[58]; int32_t e_lfanew; } IMAGE_DOS_HEADER;
typedef struct { uint32_t r[4]; } IMAGE_DATA_DIRECTORY;
typedef struct { uint16_t Magic; uint8_t r1[6]; uint32_t r2[7]; uint64_t r3; uint32_t r4[4];
    uint16_t r5[6]; uint32_t r6[4]; uint64_t r7[4]; uint32_t r8[2]; IMAGE_DATA_DIRECTORY DD[16]; } IMAGE_OPTIONAL_HEADER64;
typedef struct { uint32_t Sig; uint32_t r[5]; uint16_t SzOpt; uint16_t Chars; IMAGE_OPTIONAL_HEADER64 Opt; } IMAGE_NT_HEADERS64;
typedef struct { uint32_t r[4]; uint32_t Name; uint32_t Base; uint32_t NFunc; uint32_t NNames;
    uint32_t AddrFunc; uint32_t AddrNames; uint32_t AddrOrd; } IMAGE_EXPORT_DIRECTORY;

typedef void* (*VirtualAlloc_t)(void*,SIZE_T,DWORD,DWORD);
typedef BOOL  (*WriteConsoleA_t)(HANDLE,const void*,DWORD,DWORD*,void*);
typedef HANDLE (*GetStdHandle_t)(DWORD);
typedef void  (*ExitProcess_t)(DWORD);

static VirtualAlloc_t  g_VirtualAlloc;
static WriteConsoleA_t g_WriteConsoleA;
static GetStdHandle_t  g_GetStdHandle;
static ExitProcess_t   g_ExitProcess;

/* Janet / scheduler types (mirrors sov_rtx.h) */
typedef struct { uint32_t type_tag; uint32_t length; uint32_t capacity; float data[32]; } sov_janet_array_t;
typedef struct { uint32_t state; uint32_t batch_size; sov_janet_array_t janet; } sov_scheduler_t;

extern int  sov_cuda_init(void);
extern void sov_power_handler_init(void);
extern int  sov_scheduler_init(sov_scheduler_t*);
extern int  sov_scheduler_step(sov_scheduler_t*, void*, void*);
extern int  sov_get_power_state(void);

static PVOID peb_find(const wchar_t* tgt) {
    PVOID peb; __asm__ volatile("mov %%gs:0x60,%0":"=r"(peb));
    PPEB_LDR_DATA ldr = ((PPEB)peb)->Ldr;
    LIST_ENTRY* h = &ldr->L2, *c = h->Flink;
    while (c != h) {
        PLDR_DATA_TABLE_ENTRY e = (PLDR_DATA_TABLE_ENTRY)((uint8_t*)c - 16);
        if (e->BaseDllName.Buffer) {
            int ok=1; const wchar_t* n=e->BaseDllName.Buffer;
            for (int i=0;i<e->BaseDllName.Length/2;i++){
                wchar_t a=n[i],b=tgt[i];
                if(a>='A'&&a<='Z')a+=32; if(b>='A'&&b<='Z')b+=32;
                if(a!=b){ok=0;break;}
            }
            if(ok&&tgt[e->BaseDllName.Length/2]==0) return e->DllBase;
        }
        c = c->Flink;
    }
    return 0;
}

static PVOID pe_exp(PVOID base, const char* name) {
    if (!base) return 0;
    IMAGE_DOS_HEADER* dos = (IMAGE_DOS_HEADER*)base;
    if (dos->e_magic != 0x5A4D) return 0;
    IMAGE_NT_HEADERS64* nt = (IMAGE_NT_HEADERS64*)((uint8_t*)base + dos->e_lfanew);
    if (nt->Sig != 0x4550) return 0;
    uint32_t erva = nt->Opt.DD[0].r[0]; if (!erva) return 0;
    IMAGE_EXPORT_DIRECTORY* exp = (IMAGE_EXPORT_DIRECTORY*)((uint8_t*)base + erva);
    uint32_t* nms = (uint32_t*)((uint8_t*)base + exp->AddrNames);
    uint32_t* fns = (uint32_t*)((uint8_t*)base + exp->AddrFunc);
    uint16_t* ords = (uint16_t*)((uint8_t*)base + exp->AddrOrd);
    int lo=0, hi=(int)exp->NNames-1;
    while (lo<=hi) {
        int mid=(lo+hi)>>1; const char* mn=(const char*)((uint8_t*)base+nms[mid]);
        int cmp=0; for(int i=0;;i++){if(!mn[i]&&!name[i])break;if(mn[i]!=name[i]){cmp=(mn[i]<name[i])?-1:1;break;}}
        if(!cmp) return (PVOID)((uint8_t*)base+fns[ords[mid]]);
        else if(cmp<0) lo=mid+1; else hi=mid-1;
    }
    return 0;
}

static void resolve_kernel32(void) {
    PVOID k32 = peb_find(L"kernel32.dll");
    g_VirtualAlloc  = (VirtualAlloc_t) pe_exp(k32, "VirtualAlloc");
    g_WriteConsoleA = (WriteConsoleA_t)pe_exp(k32, "WriteConsoleA");
    g_GetStdHandle  = (GetStdHandle_t) pe_exp(k32, "GetStdHandle");
    g_ExitProcess   = (ExitProcess_t)  pe_exp(k32, "ExitProcess");
}

static void console_write(const char* s, int len) {
    if (!g_WriteConsoleA || !g_GetStdHandle) return;
    HANDLE out = g_GetStdHandle((DWORD)-11); /* STD_OUTPUT_HANDLE */
    DWORD written = 0;
    g_WriteConsoleA(out, s, (DWORD)len, &written, 0);
}

static void main_loop(void) {
    sov_scheduler_t sched = {0};
    sched.state = 0;
    sched.batch_size = 8;
    sov_scheduler_init(&sched);
    while (1) {
        sov_scheduler_step(&sched, 0, 0);
        if (sov_get_power_state() == 1) break; /* SUSPEND */
    }
}

void sov_main(void) {
    resolve_kernel32();
    console_write("SOV RTX BOOT\r\n", 14);
    sov_cuda_init();
    console_write("CUDA OK\r\n", 9);
    sov_power_handler_init();
    console_write("POWER OK\r\n", 10);
    main_loop();
    console_write("HALT\r\n", 6);
    if (g_ExitProcess) g_ExitProcess(0);
    while(1) __asm__ volatile("hlt");
}
