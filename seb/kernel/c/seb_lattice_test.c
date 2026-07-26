/* seb_lattice_test.c
 * Conformance test: reads vectors.bin, verifies seb_lattice_commit.
 * Each vector record: prev[32] + payload[64] + expected[32] = 128 bytes.
 *
 * Compile: gcc -O2 -std=c11 -Wall -Wextra -o seb_lattice_test seb_lattice_test.c seb_lattice.c
 * Run:     ./seb_lattice_test vectors.bin
 * Pass:    "20/20 PASS"
 */

#include "seb_lattice.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: seb_lattice_test vectors.bin\n");
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 1; }

    uint8_t prev[32], payload[64], expected[32], got[32];
    int pass = 0, fail = 0, n = 0;

    while (fread(prev, 32, 1, f) == 1) {
        if (fread(payload, 64, 1, f) != 1) { fprintf(stderr, "truncated\n"); break; }
        if (fread(expected, 32, 1, f) != 1) { fprintf(stderr, "truncated\n"); break; }

        seb_lattice_commit(prev, payload, got);

        /* constant-time compare */
        uint8_t diff = 0;
        for (int i = 0; i < 32; i++) diff |= (got[i] ^ expected[i]);

        if (diff == 0) {
            pass++;
        } else {
            fprintf(stderr, "FAIL vector %d\n  expected: ", n);
            for (int i=0;i<32;i++) fprintf(stderr,"%02x",expected[i]);
            fprintf(stderr, "\n       got: ");
            for (int i=0;i<32;i++) fprintf(stderr,"%02x",got[i]);
            fprintf(stderr, "\n");
            fail++;
        }
        n++;
    }
    fclose(f);

    printf("%d/%d %s\n", pass, n, (fail == 0 && n > 0) ? "PASS" : "FAIL");
    return (fail == 0 && n > 0) ? 0 : 1;
}
