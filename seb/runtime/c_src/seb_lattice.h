// seb_lattice.h
// SEB Lattice Circuit — single header, C99, zero dependencies
//
// Circuit: R = GF(2^8)[x]/(x^32 + 1), AES irreducible 0x11B
// Commitment = K0*prev XOR K1*payload[0:32] XOR K2*payload[32:64]
// K0=1 (invertible) => tip injectivity trivially holds
// 96 bytes in -> 32 bytes out, no branches on secret data

#ifndef SEB_LATTICE_H
#define SEB_LATTICE_H

#include <stdint.h>
#include <stddef.h>

#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
typedef long long seb_off_t;
#else
#include <unistd.h>
#include <fcntl.h>
typedef off_t seb_off_t;
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define SEB_PAYLOAD_SIZE    64
#define SEB_COMMITMENT_SIZE 32
#define SEB_RECORD_SIZE     96

/* Circuit: commitment = K0*prev XOR K1*payload[0:32] XOR K2*payload[32:64] */
void seb_lattice_commit(const uint8_t prev[32],
                        const uint8_t payload[64],
                        uint8_t next[32]);

/* Append: read tip, commit, write 96-byte record, fsync */
int seb_lattice_append(int fd, const uint8_t payload[64], uint8_t record[96]);

/* Tip: last 32 bytes of file (genesis zeros if empty) */
int seb_lattice_tip(int fd, uint8_t tip[32]);

/* Verify: re-evaluate chain from start_offset, count records */
int seb_lattice_verify(int fd, seb_off_t start_offset, size_t count);

#ifdef __cplusplus
}
#endif
#endif
