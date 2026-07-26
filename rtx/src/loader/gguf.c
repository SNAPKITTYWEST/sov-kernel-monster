/* GGUF v3 parser — zero libc
 * Windows: CreateFileA/MapViewOfFile  Linux: open/mmap
 * No malloc — VirtualAlloc / mmap anonymous for metadata
 *
 * v2: adds SOV_GGUF_ERR_DESTINATION_SIZE, SOV_GGUF_ERR_UNSUPPORTED_ENDIAN,
 *     SOV_GGUF_MAX_TENSORS, SOV_GGUF_MAX_METADATA, big-endian header detection,
 *     destination_capacity guard on sov_gguf_upload_to_gpu, 64-byte name limit.
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

#define GGUF_MAGIC   0x46554747u  /* "GGUF" little-endian */
#define GGUF_VERSION 3u

/* Capacity limits — reject implausibly large counts before allocating */
#define SOV_GGUF_MAX_TENSORS   4096u
#define SOV_GGUF_MAX_METADATA  65536u
#define SOV_GGUF_MAX_NAME_LEN  64u

typedef enum {
    SOV_GGUF_OK                     =  0,
    SOV_GGUF_ERR_IO                 = -1,
    SOV_GGUF_ERR_MAP                = -2,
    SOV_GGUF_ERR_BAD_MAGIC          = -3,
    SOV_GGUF_ERR_BAD_VERSION        = -4,
    SOV_GGUF_ERR_ALLOC              = -5,
    SOV_GGUF_ERR_NOT_FOUND          = -6,
    SOV_GGUF_ERR_NAME_TOO_LONG      = -7,
    SOV_GGUF_ERR_DESTINATION_SIZE   = -8,
    SOV_GGUF_ERR_UNSUPPORTED_ENDIAN = -9,
} sov_gguf_result_t;

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
} sov_gguf_tensor_view_t;

typedef struct {
    char     key[256];
    uint32_t value_type;
} sov_gguf_metadata_t;

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
    uint32_t metadata_count;
    sov_gguf_tensor_view_t* tensors;
} sov_gguf_context_t;

/* Caller-supplied host→device copy function */
typedef int (*sov_gguf_h2d_fn)(void* dst, const void* src, size_t sz);

/* ------------------------------------------------------------------ */
/* Internal helpers                                                     */
/* ------------------------------------------------------------------ */

static int map_file(sov_gguf_context_t* ctx, const char* path) {
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

static void unmap_file(sov_gguf_context_t* ctx) {
#ifdef _WIN32
    if (ctx->base) UnmapViewOfFile(ctx->base);
    if (ctx->mh)   CloseHandle(ctx->mh);
    if (ctx->fh && ctx->fh != INVALID_HANDLE_VALUE) CloseHandle(ctx->fh);
#else
    if (ctx->base && ctx->base != MAP_FAILED) munmap(ctx->base, ctx->file_size);
    if (ctx->fd >= 0) close(ctx->fd);
#endif
}

static uint32_t bswap32(uint32_t v) {
    return ((v & 0xFFu) << 24) | ((v & 0xFF00u) << 8)
         | ((v >> 8) & 0xFF00u) | ((v >> 24) & 0xFFu);
}

/* Skip GGUF KV value of given type; return advanced pointer */
static const char* skip_kv_value(const char* p, uint32_t type) {
    switch (type) {
        case 0: case 1: return p + 1;   /* uint8/int8 */
        case 2: case 3: return p + 2;   /* uint16/int16 */
        case 4: case 5: return p + 4;   /* uint32/int32/float32 */
        case 6:         return p + 1;   /* bool */
        case 7: { uint64_t n; n=*(const uint64_t*)p; return p + 8 + n; } /* string */
        case 8:         return p + 8;   /* uint64/int64/float64 */
        case 9: {       /* array */
            uint32_t et=*(const uint32_t*)p; p+=4;
            uint64_t n=*(const uint64_t*)p;  p+=8;
            for (uint64_t i=0;i<n;i++) p = skip_kv_value(p, et);
            return p;
        }
        default: return p + 8;
    }
}

/* ------------------------------------------------------------------ */
/* Public API                                                           */
/* ------------------------------------------------------------------ */

int sov_gguf_load(const char* path, void** out) {
    sov_gguf_context_t* ctx;
    const uint8_t* b;
    uint64_t n_tensors, n_kv;
    const char* p;
    size_t i;

    ctx = (sov_gguf_context_t*)SOV_ALLOC(sizeof(sov_gguf_context_t));
    if (!ctx) return SOV_GGUF_ERR_ALLOC;
    for (i=0;i<sizeof(*ctx);i++) ((uint8_t*)ctx)[i]=0;
#ifndef _WIN32
    ctx->fd = -1;
#endif

    if (map_file(ctx, path) != 0) { SOV_FREE(ctx, sizeof(*ctx)); return SOV_GGUF_ERR_IO; }

    b = (const uint8_t*)ctx->base;
    if (ctx->file_size < 24) goto fail_magic;

    /* Magic check */
    if (*(const uint32_t*)(b+0) != GGUF_MAGIC) goto fail_magic;

    /* Version check — also detect big-endian files */
    {
        uint32_t ver = *(const uint32_t*)(b+4);
        if (ver != GGUF_VERSION) {
            if (bswap32(ver) == GGUF_VERSION) {
                unmap_file(ctx);
                SOV_FREE(ctx, sizeof(*ctx));
                return SOV_GGUF_ERR_UNSUPPORTED_ENDIAN;
            }
            goto fail_magic;
        }
    }

    n_tensors = *(const uint64_t*)(b+8);
    n_kv      = *(const uint64_t*)(b+16);

    /* Sanity-cap counts before any allocation */
    if (n_tensors > SOV_GGUF_MAX_TENSORS || n_kv > SOV_GGUF_MAX_METADATA) goto fail_magic;

    ctx->tensor_count   = (uint32_t)n_tensors;
    ctx->metadata_count = (uint32_t)n_kv;

    p = (const char*)(b + 24);

    /* Skip KV section */
    for (uint64_t ki=0;ki<n_kv;ki++) {
        uint64_t klen = *(const uint64_t*)p; p += 8 + klen; /* key */
        uint32_t vtype = *(const uint32_t*)p; p += 4;
        p = skip_kv_value(p, vtype);
    }

    /* Allocate and parse tensor info */
    if (n_tensors > 0) {
        size_t tsize = n_tensors * sizeof(sov_gguf_tensor_view_t);
        ctx->tensors = (sov_gguf_tensor_view_t*)SOV_ALLOC(tsize);
        if (!ctx->tensors) goto fail_alloc;
        for (i=0;i<tsize;i++) ((uint8_t*)ctx->tensors)[i]=0;
    }

    for (uint64_t ti=0;ti<n_tensors;ti++) {
        uint64_t nlen = *(const uint64_t*)p; p += 8;

        /* Reject names over 64 bytes */
        if (nlen > SOV_GGUF_MAX_NAME_LEN) {
            if (ctx->tensors) SOV_FREE(ctx->tensors,
                                       ctx->tensor_count * sizeof(sov_gguf_tensor_view_t));
            unmap_file(ctx);
            SOV_FREE(ctx, sizeof(*ctx));
            return SOV_GGUF_ERR_NAME_TOO_LONG;
        }

        size_t copy = (nlen < 255) ? (size_t)nlen : 255;
        for (size_t j=0;j<copy;j++) ctx->tensors[ti].name[j] = p[j];
        ctx->tensors[ti].name[copy] = 0;
        p += nlen;

        ctx->tensors[ti].n_dims = *(const uint32_t*)p; p += 4;
        for (uint32_t d=0;d<ctx->tensors[ti].n_dims && d<4;d++) {
            ctx->tensors[ti].dims[d] = *(const uint64_t*)p; p += 8;
        }
        ctx->tensors[ti].type   = *(const uint32_t*)p; p += 4;
        ctx->tensors[ti].offset = *(const uint64_t*)p; p += 8;
    }

    /* Align tensor data to 32 bytes */
    {
        size_t hdr_off = (size_t)(p - (const char*)b);
        ctx->tensor_data_offset = (hdr_off + 31) & ~(size_t)31;
    }
    *out = ctx;
    return SOV_GGUF_OK;

fail_magic:
    unmap_file(ctx);
    SOV_FREE(ctx, sizeof(*ctx));
    return SOV_GGUF_ERR_BAD_MAGIC;

fail_alloc:
    unmap_file(ctx);
    SOV_FREE(ctx, sizeof(*ctx));
    return SOV_GGUF_ERR_ALLOC;
}

const void* sov_gguf_get_tensor(void* vctx, const char* name) {
    sov_gguf_context_t* ctx = (sov_gguf_context_t*)vctx;
    if (!ctx || !name) return 0;
    for (uint32_t i=0;i<ctx->tensor_count;i++) {
        const char* a = ctx->tensors[i].name, *nb = name;
        while (*a && *nb && *a == *nb) { a++; nb++; }
        if (!*a && !*nb) {
            return (const uint8_t*)ctx->base
                   + ctx->tensor_data_offset
                   + ctx->tensors[i].offset;
        }
    }
    return 0;
}

/* Upload tensor to GPU via caller-supplied upload fn.
 * Returns SOV_GGUF_ERR_DESTINATION_SIZE if byte_size > destination_capacity.
 * Returns SOV_GGUF_ERR_NOT_FOUND if no tensor with that name exists.
 * Returns h2d return value on success (0 = ok).
 */
int sov_gguf_upload_to_gpu(const sov_gguf_context_t* ctx,
                           const char* name,
                           sov_gguf_h2d_fn h2d,
                           void* gpu_dst,
                           size_t destination_capacity) {
    if (!ctx || !name) return SOV_GGUF_ERR_NOT_FOUND;
    for (uint32_t i=0;i<ctx->tensor_count;i++) {
        const char* a = ctx->tensors[i].name, *nb = name;
        while (*a && *nb && *a == *nb) { a++; nb++; }
        if (!*a && !*nb) {
            const void* src = (const uint8_t*)ctx->base
                              + ctx->tensor_data_offset
                              + ctx->tensors[i].offset;
            /* Compute byte size from element count × element width */
            size_t n = 1;
            for (uint32_t d=0;d<ctx->tensors[i].n_dims;d++)
                n *= (size_t)ctx->tensors[i].dims[d];
            size_t elem;
            switch (ctx->tensors[i].type) {
                case 0:  elem = 4; break;  /* F32  */
                case 1:  elem = 2; break;  /* F16  */
                case 32: elem = 2; break;  /* BF16 */
                case 2:  elem = 1; break;  /* Q4_0 */
                case 8:  elem = 1; break;  /* Q8_0 */
                case 12: elem = 1; break;  /* Q4_K */
                default: elem = 1; break;
            }
            size_t byte_size = n * elem;
            if (byte_size > destination_capacity)
                return SOV_GGUF_ERR_DESTINATION_SIZE;
            return h2d(gpu_dst, src, byte_size);
        }
    }
    return SOV_GGUF_ERR_NOT_FOUND;
}

void sov_gguf_free(void* vctx) {
    sov_gguf_context_t* ctx = (sov_gguf_context_t*)vctx;
    if (!ctx) return;
    if (ctx->tensors)
        SOV_FREE(ctx->tensors,
                 ctx->tensor_count * sizeof(sov_gguf_tensor_view_t));
    unmap_file(ctx);
    SOV_FREE(ctx, sizeof(*ctx));
}
