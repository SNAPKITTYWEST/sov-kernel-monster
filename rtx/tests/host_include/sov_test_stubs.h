#pragma once
/* Host test stubs — no CUDA driver needed */
#include <stdio.h>
#include <string.h>

#define SOV_ASSERT(cond) do { \
    if (!(cond)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        return 1; \
    } \
} while(0)

#define SOV_PASS(name) printf("PASS %s\n", (name))
