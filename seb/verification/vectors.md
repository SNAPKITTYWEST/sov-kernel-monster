# SEB Lattice Circuit — Conformance Test Vectors

Circuit: GF(2^8)[x]/(x^32+1), K0=1, K1=x, K2=x^2, 0x11B
Record size: 96 bytes | Payload: 64 | Commitment: 32
Simplified form: `next[k] = prev[k] ^ payload[(k-1)&31] ^ payload[32+((k-2)&31)]`
Vectors: 20

Every implementation (C, Ada, Lean) MUST produce identical `next_commitment` for each vector.

## Format

- `prev_commitment` 32 bytes hex — input tip
- `payload` 64 bytes hex — input payload
- `next_commitment` 32 bytes hex — expected output

## Vectors

| id | prev (first 8 bytes) | payload (first 8 bytes) | expected (first 8 bytes) |
|----|--------------------|------------------------|--------------------------|
| 00 | `0000000000000000…` | `0001020304050607…` | `213f212321272123…` |
| 01 | `213f212321272123…` | `ffffffffffffffff…` | `213f212321272123…` |
| 02 | `213f212321272123…` | `aa55aa55aa55aa55…` | `dec0dedcded8dedc…` |
| 03 | `dec0dedcded8dedc…` | `e1c2fffade596ef7…` | `8c55fde1dbfc59eb…` |
| 04 | `8c55fde1dbfc59eb…` | `2e349d641df8832b…` | `f101e7482285bc90…` |
| 05 | `f101e7482285bc90…` | `d66fab0fea0c5aac…` | `05605e8c86605ac6…` |
| 06 | `05605e8c86605ac6…` | `5a5b58595e5f5c5d…` | `245f7fafa7477be5…` |
| 07 | `245f7fafa7477be5…` | `a5a4a7a6a1a0a3a2…` | `05605e8c86605ac6…` |
| 08 | `05605e8c86605ac6…` | `0000000000000000…` | `fa9fa173799fa539…` |
| 09 | `fa9fa173799fa539…` | `ffffffffffffffff…` | `05605e8c86605ac6…` |
| 10 | `05605e8c86605ac6…` | `36ce94bff914b671…` | `b005a6d6ad26b764…` |
| 11 | `b005a6d6ad26b764…` | `21aef37bf4ee4959…` | `1c9c298b25a9adc3…` |
| 12 | `1c9c298b25a9adc3…` | `b57d7fca1df58e60…` | `d343e189907e45b8…` |
| 13 | `d343e189907e45b8…` | `8cff07c77e6bdbdb…` | `7b8a927150c75008…` |
| 14 | `7b8a927150c75008…` | `1f348a2dd6128081…` | `1b57b9cff73c949a…` |
| 15 | `1b57b9cff73c949a…` | `0001020304050607…` | `3a6898ecd61bb5b9…` |
| 16 | `3a6898ecd61bb5b9…` | `4041424344454647…` | `1b57b9cff73c949a…` |
| 17 | `1b57b9cff73c949a…` | `8081828384858687…` | `3a6898ecd61bb5b9…` |
| 18 | `3a6898ecd61bb5b9…` | `c0c1c2c3c4c5c6c7…` | `1b57b9cff73c949a…` |
| 19 | `1b57b9cff73c949a…` | `fec577d6349e7a8c…` | `e764827d56de3e7e…` |

## Verification commands

```bash
# C
gcc -O2 -std=c11 -Wall -o seb_lattice_test seb_lattice_test.c seb_lattice.c && ./seb_lattice_test vectors.bin

# Ada
gnatmake -O2 seb_lattice_test.adb && ./seb_lattice_test vectors.bin

# Lean
lake build SEB.Lattice && ./SEB_Lattice_Test vectors.bin
```

## Binary hash of vectors.bin

`SHA-256: 569a59dba1c73b53f2c53cd56143bc3e336133322059427c69d4eba22782d290`