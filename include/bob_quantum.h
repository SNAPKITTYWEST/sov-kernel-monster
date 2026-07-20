#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle typedefs
typedef struct bob_rng_handle bob_rng_handle_t;
typedef struct bob_lattice_handle bob_lattice_handle_t;
typedef struct bob_state_handle bob_state_handle_t;
typedef struct bob_hamiltonian_handle bob_hamiltonian_handle_t;

// Error code enum
typedef enum {
    BOB_ERROR_NONE = 0,
    BOB_ERROR_MEMORY_ALLOCATION_FAILED,
    BOB_ERROR_INVALID_PARAMETER,
    BOB_ERROR_INTERNAL_ERROR,
    BOB_ERROR_NOT_IMPLEMENTED,
    BOB_ERROR_FILE_IO_ERROR,
    BOB_ERROR_UNKNOWN_ERROR
} bob_error_t;

// RNG functions
bob_error_t bob_rng_create(bob_rng_handle_t **rng);
bob_error_t bob_rng_destroy(bob_rng_handle_t *rng);
bob_error_t bob_rng_seed(bob_rng_handle_t *rng, uint64_t seed);
bob_error_t bob_rng_uniform(bob_rng_handle_t *rng, double *value);
bob_error_t bob_rng_normal(bob_rng_handle_t *rng, double *value);
bob_error_t bob_rng_integer(bob_rng_handle_t *rng, int3