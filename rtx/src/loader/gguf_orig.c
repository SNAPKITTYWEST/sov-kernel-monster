/* GGUF v3 parser — zero libc
 * Windows: CreateFileA/MapViewOfFile  Linux: open/mmap
 * No malloc — VirtualAlloc / mmap anonymous for metadata
 */
#include <stdint.h>
#include <stddef.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  define SOV_ALLOC(sz)     VirtualAlloc(NULL,(sz),MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE)
#  define SOV_FREE(p,sz)    VirtualFree((p),0,MEM_RELEASE)
#else
#  include <sys/mman.h>
#  include <fcntl.h>
#  include <unistd.h>
#  include <sys/stat.h>
#  define SOV_ALLOC(sz)     mmap(NULL,(sz),PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0)
#  define SOV_FREE(p,sz)    munmap((p),(sz))
#endif

#define GGUF_MAGIC   0x46554747u  /* "GGUF" */
#define GGUF_VERSION 3u

typedef enum {
    GGUF_TYPE_F32  = 0,
    GGUF_TYPE_F16  = 1,
    GGUF_TYPE_Q4_0 = 2,
    GGUF_TYPE_Q8_0 = 8,
    GGUF_TYPE_Q4_K = 12,
    GGUF_TYPE_BF16 = 32,
} gguf_type_t;

typedef struct {
    char     name[256];
    uint32_t n_dims;
    uint64_t dims[4];
    uint32_t type;
    uint64_t offset;  /* from tensor data block */
} gguf_tensor_info_t;

typedef struct {
#ifdef _WIN32
    HANDLE   fh, mh;
#else
    int      fd;
#endif
    void*    base;
    size_t   file_size;
    uint64_t tensor_data_offset;
    uint32_t tensor_count;
    gguf_tensor_info_t* tensors;
} gguf_context_t;

static int map_file(gguf_context_t* ctx, const char* path) {
#ifdef _WIN32
    ctx->fh = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                          OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (ctx->fh == INVALID_HANDLE_VALUE) return -1;
    LARGE_INTEGER sz; GetFileSizeEx(ctx->fh, &sz); ctx->file_size = (size_t)sz.QuadPart;
    ctx->mh = CreateFileMappingA(ctx->fh, NULL, PAGE_READONLY, 0, 0, NULL);
    if (!ctx->mh) { CloseHandle(ctx->fh); return -2; }
    ctx->base = MapViewOfFile(ctx->mh, FILE_MAP_READ, 0, 0, 0);
    if (!ctx->base) { CloseHandle(ctx->mh); CloseHandle(ctx->fh); return -3; }
#else
    ctx->fd = open(path, O_RDONLY);
    if (ctx->fd < 0) return -1;
    struct stat st; fstat(ctx->fd, &st); ctx->file_size = st.st_size;
    ctx->base = mmap(NULL, ctx->file_size, PROT_READ, MAP_PRIVATE, ctx->fd, 0);
    if (ctx->base == MAP_FAILED) { close(ctx->fd); return -2; }
#endif
    return 0;
}

static void unmap_file(gguf_context_t* ctx) {
#ifdef _WIN32
    if (ctx->base) UnmapViewOfFile(ctx->base);
    if (ctx->mh)   CloseHandle(ctx->mh);
    if (ctx->fh && ctx->fh != INVALID_HANDLE_VALUE) CloseHandle(ctx->fh);
#else
    if (ctx->base && ctx->base != MAP_FAILED) munmap(ctx->base, ctx->file_size);
    if (ctx->fd >= 0) close(ctx->fd);
#endif
}

/* Skip GGUF KV value of given type; return advanced pointer */
static const char* skip_kv_value(const char* p, uint32_t type) {
    switch (type) {
        case 0: case 1: return p + 1;   /* uint8/int8 */
        case 2: case 3: return p + 2;   /* uint16/int16 */
        case 4: case 5: return p + 4;   /* uint32/int32/float32 */
        case 6:         return p + 1;   /* bool */
        case 7: { uint64_t n=*(uint64_t*)p; return p + 8 + n; } /* string */
        case 8:         return p + 8;   /* uint64/int64/float64 */
        case 9: {       /* array */
            uint32_t et=*(uint32_t*)p; p+=4;
            uint64_t n=*(uint64_t*)p;  p+=8;
            for (uint64_t i=0;i<n;i++) p = skip_kv_value(p, et);
            return p;
        }
        default: return p + 8;
    }
}

int gguf_load(const char* path, gguf_context_t** out) {
    gguf_context_t* ctx = (gguf_context_t*)SOV_ALLOC(sizeof(gguf_context_t));
    if (!ctx) return -1;
    /* zero-init */
    for (size_t i=0;i<sizeof(*ctx);i++) ((uint8_t*)ctx)[i]=0;

    if (map_file(ctx, path) != 0) { SOV_FREE(ctx, sizeof(*ctx)); return -2; }

    const uint8_t* b = (const uint8_t*)ctx->base;
    if (ctx->file_size < 24) goto fail;
    if (*(uint32_t*)(b+0) != GGUF_MAGIC)   goto fail;
    if (*(uint32_t*)(b+4) != GGUF_VERSION) goto fail;

    uint64_t n_tensors = *(uint64_t*)(b+8);
    uint64_t n_kv      = *(uint64_t*)(b+16);
    ctx->tensor_count  = (uint32_t)n_tensors;

    const char* p = (const char*)(b + 24);
    /* skip KV section */
    for (uint64_t i=0;i<n_kv;i++) {
        uint64_t klen = *(uint64_t*)p; p += 8 + klen; /* key */
        uint32_t vtype = *(uint32_t*)p; p += 4;
        p = skip_kv_value(p, vtype);
    }

    /* parse tensor info */
    size_t tsize = n_tensors * sizeof(gguf_tensor_info_t);
    ctx->tensors = (gguf_tensor_info_t*)SOV_ALLOC(tsize);
    if (!ctx->tensors) goto fail;
    for (size_t i=0;i<tsize;i++) ((uint8_t*)ctx->tensors)[i]=0;

    for (uint64_t i=0;i<n_tensors;i++) {
        uint64_t nlen = *(uint64_t*)p; p += 8;
        size_t copy = nlen < 255 ? nlen : 255;
        for (size_t j=0;j<copy;j++) ctx->tensors[i].name[j] = p[j];
        ctx->tensors[i].name[copy] = 0;
        p += nlen;
        ctx->tensors[i].n_dims = *(uint32_t*)p; p += 4;
        for (uint32_t d=0;d<ctx->tensors[i].n_dims;d++) {
            ctx->tensors[i].dims[d] = *(uint64_t*)p; p += 8;
        }
        ctx->tensors[i].type   = *(uint32_t*)p; p += 4;
        ctx->tensors[i].offset = *(uint64_t*)p; p += 8;
    }
    /* align tensor data to 32 bytes */
    size_t hdr_off = (size_t)(p - (const char*)b);
    ctx->tensor_data_offset = (hdr_off + 31) & ~31ULL;
    *out = ctx;
    return 0;

fail:
    unmap_file(ctx);
    if (ctx->tensors) SOV_FREE(ctx->tensors, ctx->tensor_count * sizeof(gguf_tensor_info_t));
    SOV_FREE(ctx, sizeof(*ctx));
    return -3;
}

const void* gguf_get_tensor(gguf_context_t* ctx, const char* name) {
    for (uint32_t i=0;i<ctx->tensor_count;i++) {
        const char* a = ctx->tensors[i].name, *b = name;
        while (*a && *b && *a == *b) { a++; b++; }
        if (!*a && !*b) {
            return (const uint8_t*)ctx->base + ctx->tensor_data_offset + ctx->tensors[i].offset;
        }
    }
    return 0;
}

/* Upload tensor to GPU via caller-supplied upload fn */
int gguf_upload_to_gpu(gguf_context_t* ctx, const char* name,
                       int (*h2d)(void* dst, const void* src, size_t sz),
                       void* gpu_dst) {
    for (uint32_t i=0;i<ctx->tensor_count;i++) {
        const char* a = ctx->tensors[i].name, *b = name;
        while (*a && *b && *a == *b) { a++; b++; }
        if (!*a && !*b) {
            const void* src = (const uint8_t*)ctx->base + ctx->tensor_data_offset + ctx->tensors[i].offset;
            /* compute byte size */
            size_t n = 1;
            for (uint32_t d=0;d<ctx->tensors[i].n_dims;d++) n *= (size_t)ctx->tensors[i].dims[d];
            size_t elem;
            switch (ctx->tensors[i].type) {
                case 0:  elem = 4; break;  /* F32 */
                case 1:  elem = 2; break;  /* F16 */
                case 32: elem = 2; break;  /* BF16 */
                case 2:  elem = 1; break;  /* Q4_0 ~0.5 byte/elem, approx 1 */
                case 8:  elem = 1; break;  /* Q8_0 */
                case 12: elem = 1; break;  /* Q4_K */
                default: elem = 1; break;
            }
            return h2d(gpu_dst, src, n * elem);
        }
    }
    return -1;
}

void gguf_free(gguf_context_t* ctx) {
    if (!ctx) return;
    if (ctx->tensors) SOV_FREE(ctx->tensors, ctx->tensor_count * sizeof(gguf_tensor_info_t));
    unmap_file(ctx);
    SOV_FREE(ctx, sizeof(*ctx));
}
