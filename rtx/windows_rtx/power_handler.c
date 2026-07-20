/* Zero-libc Windows power event handler
 * Manual PEB walk for user32/powrprof, no windows.h
 * Suspend -> sov_worm_checkpoint, Resume -> sov_worm_restore
 * Battery < 20% -> reduce batch via sov_janet_set
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
typedef HANDLE             HWND;
typedef HANDLE             HINSTANCE;
typedef HANDLE             HDEVNOTIFY;
typedef uint32_t           DWORD;
typedef uint64_t           ULONG_PTR;
typedef ULONG_PTR          WPARAM;
typedef int64_t            LPARAM;
typedef int32_t            LRESULT;
typedef uint32_t           UINT;
typedef uint16_t           WORD;
typedef int32_t            INT;
typedef long               LONG;
typedef int                BOOL;
typedef const char*        LPCSTR;
typedef PVOID              HMENU;
typedef PVOID              LPMSG;
typedef PVOID              LPVOID;
typedef PVOID              LPDWORD;
typedef int (*LPTHREAD_START_ROUTINE)(PVOID);
typedef ULONG_PTR          SIZE_T;

typedef struct { DWORD Data1; WORD Data2; WORD Data3; uint8_t Data4[8]; } GUID, *LPCGUID;
typedef struct { struct _LE* Flink; struct _LE* Blink; } LIST_ENTRY, *PLIST_ENTRY;
typedef struct { uint16_t Length; uint16_t MaximumLength; wchar_t* Buffer; } UNICODE_STRING;
typedef struct {
    LIST_ENTRY InLoadOrderLinks; LIST_ENTRY InMemoryOrderLinks; LIST_ENTRY InInitOrderLinks;
    PVOID DllBase; PVOID EntryPoint; ULONG SizeOfImage;
    UNICODE_STRING FullDllName; UNICODE_STRING BaseDllName;
} LDR_DATA_TABLE_ENTRY, *PLDR_DATA_TABLE_ENTRY;
typedef struct { ULONG Length; BOOL Initialized; HANDLE SsHandle;
    LIST_ENTRY InLoadOrder; LIST_ENTRY InMemoryOrder; } PEB_LDR_DATA, *PPEB_LDR_DATA;
typedef struct { uint8_t r1[2]; uint8_t BeingDebugged; uint8_t r2[1]; PVOID r3[2]; PPEB_LDR_DATA Ldr; } PEB, *PPEB;
typedef struct { WORD e_magic; WORD r[28]; LONG e_lfanew; } IMAGE_DOS_HEADER, *PIMAGE_DOS_HEADER;
typedef struct { WORD Machine; WORD NumberOfSections; DWORD r[3]; WORD SizeOfOptionalHeader; WORD Chars; } IMAGE_FILE_HEADER;
typedef struct { DWORD VirtualAddress; DWORD Size; } IMAGE_DATA_DIRECTORY;
typedef struct { WORD Magic; uint8_t r1[6]; DWORD r2[7]; ULONG_PTR r3; DWORD r4[4];
    WORD r5[6]; DWORD r6[4]; ULONG_PTR r7[4]; DWORD r8[2]; IMAGE_DATA_DIRECTORY DataDir[16]; } IMAGE_OPTIONAL_HEADER64;
typedef struct { DWORD Signature; IMAGE_FILE_HEADER FileHdr; IMAGE_OPTIONAL_HEADER64 OptHdr; } IMAGE_NT_HEADERS64, *PIMAGE_NT_HEADERS64;
typedef struct { DWORD r[4]; DWORD Name; DWORD Base; DWORD NumberOfFunctions; DWORD NumberOfNames;
    DWORD AddressOfFunctions; DWORD AddressOfNames; DWORD AddressOfNameOrdinals; } IMAGE_EXPORT_DIRECTORY, *PIMAGE_EXPORT_DIRECTORY;

typedef struct { HWND hwnd; UINT message; WPARAM wParam; LPARAM lParam; DWORD time; LONG ptx; LONG pty; } MSG;
typedef struct { UINT cbSize; UINT style; LRESULT (*lpfnWndProc)(HWND,UINT,WPARAM,LPARAM);
    INT cbClsExtra; INT cbWndExtra; HINSTANCE hInstance; HANDLE hIcon; HANDLE hCursor;
    HANDLE hBrush; LPCSTR lpszMenuName; LPCSTR lpszClassName; HANDLE hIconSm; } WNDCLASSEXA;
typedef struct { GUID PowerSetting; DWORD DataLength; uint8_t Data[1]; } POWERBROADCAST_SETTING;

#define WM_POWERBROADCAST    0x0218
#define PBT_APMSUSPEND       0x0004
#define PBT_APMRESUMESUSPEND 0x0007
#define PBT_APMPOWERSTATUSCHANGE 0x000A
#define WS_POPUP             0x80000000
#define THREAD_PRIORITY_TIME_CRITICAL 15

const GUID GUID_MONITOR_POWER_ON           = {0x02731015,0x4510,0x4526,{0x99,0xE6,0xE5,0xA1,0x7E,0xBD,0x1A,0xEA}};
const GUID GUID_LIDSWITCH_STATE_CHANGE     = {0xBA3E0F4D,0xB817,0x4094,{0xA2,0xD1,0xD5,0x63,0x79,0xE6,0xA0,0xF3}};
const GUID GUID_BATTERY_PERCENTAGE_REMAINING = {0xA7AD8041,0xB45A,0x4CAE,{0x87,0xA3,0xEE,0x1B,0x4C,0x4E,0xB3,0xD5}};
const GUID GUID_CONSOLE_DISPLAY_STATE      = {0x6FE69556,0x704A,0x47A0,{0x8F,0x24,0xC2,0x8D,0x93,0x6F,0xDA,0x47}};

typedef HDEVNOTIFY (*RegisterPowerSettingNotification_t)(HANDLE,const GUID*,DWORD);
typedef HWND (*CreateWindowExA_t)(DWORD,LPCSTR,LPCSTR,DWORD,INT,INT,INT,INT,HWND,HMENU,HINSTANCE,LPVOID);
typedef UINT (*RegisterClassExA_t)(const WNDCLASSEXA*);
typedef BOOL (*GetMessageA_t)(MSG*,HWND,UINT,UINT);
typedef LRESULT (*DispatchMessageA_t)(const MSG*);
typedef void (*PostQuitMessage_t)(INT);
typedef HANDLE (*CreateThread_t)(PVOID,SIZE_T,LPTHREAD_START_ROUTINE,PVOID,DWORD,LPDWORD);
typedef LRESULT (*DefWindowProcA_t)(HWND,UINT,WPARAM,LPARAM);

static RegisterPowerSettingNotification_t g_RegisterPwrNotif;
static CreateWindowExA_t    g_CreateWindowExA;
static RegisterClassExA_t   g_RegisterClassExA;
static GetMessageA_t        g_GetMessageA;
static DispatchMessageA_t   g_DispatchMessageA;
static PostQuitMessage_t    g_PostQuitMessage;
static CreateThread_t       g_CreateThread;
static DefWindowProcA_t     g_DefWindowProcA;

extern int  sov_worm_checkpoint(void*);
extern int  sov_worm_restore(void*);
extern void sov_janet_set(int, float);

static PVOID peb_find_module(const wchar_t* tgt) {
    PVOID peb; __asm__ volatile("mov %%gs:0x60,%0":"=r"(peb));
    PPEB_LDR_DATA ldr = ((PPEB)peb)->Ldr; if (!ldr) return 0;
    PLIST_ENTRY h = &ldr->InMemoryOrder, c = h->Flink;
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
        c=c->Flink;
    }
    return 0;
}

static PVOID pe_export(PVOID base, const char* name) {
    if (!base) return 0;
    PIMAGE_DOS_HEADER dos=(PIMAGE_DOS_HEADER)base;
    if(dos->e_magic!=0x5A4D) return 0;
    PIMAGE_NT_HEADERS64 nt=(PIMAGE_NT_HEADERS64)((uint8_t*)base+dos->e_lfanew);
    if(nt->Signature!=0x4550) return 0;
    DWORD erva=nt->OptHdr.DataDir[0].VirtualAddress; if(!erva) return 0;
    PIMAGE_EXPORT_DIRECTORY exp=(PIMAGE_EXPORT_DIRECTORY)((uint8_t*)base+erva);
    DWORD*nms=(DWORD*)((uint8_t*)base+exp->AddressOfNames);
    DWORD*fns=(DWORD*)((uint8_t*)base+exp->AddressOfFunctions);
    WORD* ords=(WORD*)((uint8_t*)base+exp->AddressOfNameOrdinals);
    int lo=0,hi=(int)exp->NumberOfNames-1;
    while(lo<=hi){
        int mid=(lo+hi)>>1; const char*mn=(const char*)((uint8_t*)base+nms[mid]);
        int cmp=0; for(int i=0;;i++){if(!mn[i]&&!name[i])break;if(mn[i]!=name[i]){cmp=(mn[i]<name[i])?-1:1;break;}}
        if(!cmp) return (PVOID)((uint8_t*)base+fns[ords[mid]]);
        else if(cmp<0) lo=mid+1; else hi=mid-1;
    }
    return 0;
}

static void resolve_power_apis(void) {
    PVOID u32 = peb_find_module(L"user32.dll");
    PVOID pwr = peb_find_module(L"powrprof.dll");
    PVOID k32 = peb_find_module(L"kernel32.dll");
    if(u32){
        g_CreateWindowExA  = (CreateWindowExA_t)pe_export(u32,"CreateWindowExA");
        g_RegisterClassExA = (RegisterClassExA_t)pe_export(u32,"RegisterClassExA");
        g_GetMessageA      = (GetMessageA_t)pe_export(u32,"GetMessageA");
        g_DispatchMessageA = (DispatchMessageA_t)pe_export(u32,"DispatchMessageA");
        g_PostQuitMessage  = (PostQuitMessage_t)pe_export(u32,"PostQuitMessage");
        g_DefWindowProcA   = (DefWindowProcA_t)pe_export(u32,"DefWindowProcA");
    }
    if(pwr) g_RegisterPwrNotif = (RegisterPowerSettingNotification_t)pe_export(pwr,"RegisterPowerSettingNotification");
    if(k32) g_CreateThread = (CreateThread_t)pe_export(k32,"CreateThread");
}

static HWND g_hwnd;

static LRESULT window_proc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    if (msg == WM_POWERBROADCAST) {
        switch ((UINT)wParam) {
            case PBT_APMSUSPEND:
                sov_worm_checkpoint(0);
                return 1;
            case PBT_APMRESUMESUSPEND:
                sov_worm_restore(0);
                return 1;
            case PBT_APMPOWERSTATUSCHANGE: {
                POWERBROADCAST_SETTING* ps = (POWERBROADCAST_SETTING*)lParam;
                if (ps && ps->DataLength >= 4) {
                    uint32_t pct = *(uint32_t*)ps->Data;
                    if (pct < 20) sov_janet_set(1, 2.0f); /* reduce batch_size to 2 */
                }
                return 1;
            }
        }
    }
    return g_DefWindowProcA ? g_DefWindowProcA(hwnd, msg, wParam, lParam) : 0;
}

static int power_thread(PVOID arg) {
    if (!g_CreateWindowExA || !g_RegisterClassExA || !g_GetMessageA) return 1;
    WNDCLASSEXA wc = {0};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = window_proc;
    wc.lpszClassName = "SovPower";
    g_RegisterClassExA(&wc);
    g_hwnd = g_CreateWindowExA(0,"SovPower","",WS_POPUP,0,0,0,0,0,0,0,0);
    if (!g_hwnd) return 2;
    if (g_RegisterPwrNotif) {
        g_RegisterPwrNotif(g_hwnd, &GUID_MONITOR_POWER_ON, 0);
        g_RegisterPwrNotif(g_hwnd, &GUID_LIDSWITCH_STATE_CHANGE, 0);
        g_RegisterPwrNotif(g_hwnd, &GUID_BATTERY_PERCENTAGE_REMAINING, 0);
        g_RegisterPwrNotif(g_hwnd, &GUID_CONSOLE_DISPLAY_STATE, 0);
    }
    MSG msg;
    while (g_GetMessageA(&msg, 0, 0, 0))
        g_DispatchMessageA(&msg);
    return 0;
}

void sov_power_handler_init(void) {
    resolve_power_apis();
    if (g_CreateThread)
        g_CreateThread(0, 0, power_thread, 0, 0, 0);
}
