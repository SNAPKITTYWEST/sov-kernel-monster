// seb_lattice.c
// SEB Lattice Circuit — Ahmad Ali Parr, SnapKitty Collective 2026
//
// R = GF(2^8)[x]/(x^32 + 1), irreducible poly x^8+x^4+x^3+x+1 (0x11B)
// commitment[k] = XOR_{i=0..31} K0[i]*prev[(k-i)&31]
//               ^ XOR_{i=0..31} K1[i]*b[(k-i)&31]
//               ^ XOR_{i=0..31} K2[i]*c[(k-i)&31]
// K0=1, K1=x, K2=x^2 => K0 is identity => tip injective
// Constant-time: no data-dependent branches

#include "seb_lattice.h"
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
static int lattice_read_at(int fd, void *buf, size_t n, long long off) {
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    OVERLAPPED ov = {0};
    ov.Offset     = (DWORD)(off & 0xFFFFFFFF);
    ov.OffsetHigh = (DWORD)((off >> 32) & 0xFFFFFFFF);
    DWORD got = 0;
    return ReadFile(h, buf, (DWORD)n, &got, &ov) ? (int)got : -1;
}
static int lattice_write_at(int fd, const void *buf, size_t n, long long off) {
    HANDLE h = (HANDLE)_get_osfhandle(fd);
    OVERLAPPED ov = {0};
    ov.Offset     = (DWORD)(off & 0xFFFFFFFF);
    ov.OffsetHigh = (DWORD)((off >> 32) & 0xFFFFFFFF);
    DWORD wrote = 0;
    return WriteFile(h, buf, (DWORD)n, &wrote, &ov) ? (int)wrote : -1;
}
static int lattice_fsync(int fd) {
    return FlushFileBuffers((HANDLE)_get_osfhandle(fd)) ? 0 : -1;
}
static long long lattice_filesize(int fd) {
    LARGE_INTEGER sz = {0};
    return GetFileSizeEx((HANDLE)_get_osfhandle(fd), &sz) ? sz.QuadPart : -1;
}
#else
#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
static int lattice_read_at(int fd, void *buf, size_t n, long long off) {
    return (int)pread(fd, buf, n, (off_t)off);
}
static int lattice_write_at(int fd, const void *buf, size_t n, long long off) {
    return (int)pwrite(fd, buf, n, (off_t)off);
}
static int lattice_fsync(int fd) { return fdatasync(fd); }
static long long lattice_filesize(int fd) {
    off_t r = lseek(fd, 0, SEEK_END);
    return (r == (off_t)-1) ? -1 : (long long)r;
}
#endif

/* GF(256) multiply, AES poly 0x11B, constant-time */
static uint8_t gf256_mul(uint8_t x, uint8_t y) {
    uint8_t z = 0;
    for (int i = 0; i < 8; i++) {
        if (y & 1) z ^= x;
        uint8_t hi = x & 0x80;
        x = (uint8_t)(x << 1);
        if (hi) x ^= 0x1B;
        y >>= 1;
    }
    return z;
}

/* Cyclic convolution in GF(256)[x]/(x^32+1) */
static void cyclic_convolve(const uint8_t a[32], const uint8_t b[32], uint8_t c[32]) {
    for (int k = 0; k < 32; k++) {
        uint8_t s = 0;
        for (int i = 0; i < 32; i++)
            s ^= gf256_mul(a[i], b[(k - i) & 31]);
        c[k] = s;
    }
}

/* K0=1 (identity), K1=x, K2=x^2 — frozen at genesis */
static const uint8_t K0[32] = { 1 };
static const uint8_t K1[32] = { 0, 1 };
static const uint8_t K2[32] = { 0, 0, 1 };

void seb_lattice_commit(const uint8_t prev[32],
                        const uint8_t payload[64],
                        uint8_t next[32])
{
    uint8_t t0[32], t1[32], t2[32];
    cyclic_convolve(K0, prev,         t0);
    cyclic_convolve(K1, payload,      t1);
    cyclic_convolve(K2, payload + 32, t2);
    for (int i = 0; i < 32; i++)
        next[i] = t0[i] ^ t1[i] ^ t2[i];
}

int seb_lattice_append(int fd, const uint8_t payload[64], uint8_t record[96])
{
    uint8_t tip[32] = {0};
    long long sz = lattice_filesize(fd);
    if (sz < 0) return -1;
    if (sz > 0 && lattice_read_at(fd, tip, 32, sz - 32) != 32) return -1;
    seb_lattice_commit(tip, payload, record + 64);
    memcpy(record, payload, 64);
    if (lattice_write_at(fd, record, 96, sz) != 96) return -1;
    return lattice_fsync(fd);
}

int seb_lattice_tip(int fd, uint8_t tip[32])
{
    long long sz = lattice_filesize(fd);
    if (sz < 0) return -1;
    if (sz == 0) { memset(tip, 0, 32); return 0; }
    return (lattice_read_at(fd, tip, 32, sz - 32) == 32) ? 0 : -1;
}

int seb_lattice_verify(int fd, seb_off_t start_offset, size_t count)
{
    uint8_t expected[32] = {0};
    uint8_t record[96];
    long long pos = (long long)start_offset;
    while (count > 0) {
        int r = lattice_read_at(fd, record, 96, pos);
        if (r == 0) break;
        if (r != 96) return -1;
        uint8_t computed[32];
        seb_lattice_commit(expected, record, computed);
        uint8_t diff = 0;
        for (int i = 0; i < 32; i++) diff |= computed[i] ^ record[64 + i];
        if (diff) return 0;
        memcpy(expected, computed, 32);
        pos += 96;
        count--;
    }
    return 1;
}
