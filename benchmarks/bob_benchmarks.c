/// BOB Quantum Civilization Engine - Benchmarks
/// Latency tests for each language binding call overhead
/// Measures FFI marshalling, memory allocation, and quantum ops performance

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <math.h>
#include "../include/bob_quantum.h"

#define BENCHMARK_ITERATIONS 10000
#define BENCHMARK_WARMUP 100

typedef struct {
    const char *name;
    uint64_t total_ns;
    uint64_t min_ns;
    uint64_t max_ns;
    uint64_t count;
} Benchmark_Result;

/// =========================================================================
/// Timing Utilities
/// =========================================================================

static uint64_t time_now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000UL + (uint64_t)ts.tv_nsec;
}

static void print_result(const Benchmark_Result *result) {
    if (result->count == 0) return;

    double avg_us = (double)result->total_ns / result->count / 1000.0;
    double min_us = (double)result->min_ns / 1000.0;
    double max_us = (double)result->max_ns / 1000.0;

    printf("%-40s | Avg: %8.3f μs | Min: %8.3f μs | Max: %8.3f μs\n",
           result->name, avg_us, min_us, max_us);
}

/// =========================================================================
/// RNG Benchmarks
/// =========================================================================

void benchmark_rng_creation(void) {
    printf("\n=== RNG Creation Overhead ===\n");

    Benchmark_Result result = {.name = "rng_create", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_rng_handle_t *rng = NULL;
        bob_rng_create(&rng);
        bob_rng_destroy(rng);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        bob_rng_handle_t *rng = NULL;
        bob_rng_create(&rng);
        bob_rng_destroy(rng);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
}

void benchmark_rng_uniform(void) {
    printf("\n=== RNG Uniform Generation ===\n");

    bob_rng_handle_t *rng = NULL;
    bob_rng_create(&rng);
    bob_rng_seed(rng, 12345);

    Benchmark_Result result = {.name = "rng_uniform", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        double val;
        bob_rng_uniform(rng, &val);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        double val;
        bob_rng_uniform(rng, &val);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_rng_destroy(rng);
}

void benchmark_rng_normal(void) {
    printf("\n=== RNG Normal Distribution ===\n");

    bob_rng_handle_t *rng = NULL;
    bob_rng_create(&rng);
    bob_rng_seed(rng, 12345);

    Benchmark_Result result = {.name = "rng_normal", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        double val;
        bob_rng_normal(rng, &val);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        double val;
        bob_rng_normal(rng, &val);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_rng_destroy(rng);
}

void benchmark_rng_integer(void) {
    printf("\n=== RNG Integer Generation ===\n");

    bob_rng_handle_t *rng = NULL;
    bob_rng_create(&rng);
    bob_rng_seed(rng, 12345);

    Benchmark_Result result = {.name = "rng_integer", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        int64_t val;
        bob_rng_integer(rng, 0, 100, &val);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        int64_t val;
        bob_rng_integer(rng, 0, 100, &val);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_rng_destroy(rng);
}

/// =========================================================================
/// Lattice Benchmarks
/// =========================================================================

void benchmark_lattice_creation(void) {
    printf("\n=== Lattice Creation (4x4x4) ===\n");

    Benchmark_Result result = {.name = "lattice_create", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_lattice_handle_t *lat = NULL;
        bob_lattice_create(4, 4, 4, 1.0, 12345, &lat);
        bob_lattice_destroy(lat);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS / 100; i++) {
        uint64_t start = time_now_ns();

        bob_lattice_handle_t *lat = NULL;
        bob_lattice_create(4, 4, 4, 1.0, 12345, &lat);
        bob_lattice_destroy(lat);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
}

void benchmark_lattice_evolve(void) {
    printf("\n=== Lattice Evolution (1 MC step) ===\n");

    bob_lattice_handle_t *lat = NULL;
    bob_lattice_create(4, 4, 4, 1.0, 12345, &lat);

    Benchmark_Result result = {.name = "lattice_evolve", .min_ns = UINT64_MAX};
    double energy;

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_lattice_evolve(lat, 1, &energy);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        bob_lattice_evolve(lat, 1, &energy);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_lattice_destroy(lat);
}

void benchmark_lattice_energy(void) {
    printf("\n=== Lattice Energy Computation ===\n");

    bob_lattice_handle_t *lat = NULL;
    bob_lattice_create(4, 4, 4, 1.0, 12345, &lat);

    Benchmark_Result result = {.name = "lattice_energy", .min_ns = UINT64_MAX};
    double energy;

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_lattice_energy(lat, &energy);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        bob_lattice_energy(lat, &energy);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_lattice_destroy(lat);
}

void benchmark_lattice_entropy(void) {
    printf("\n=== Lattice Entropy Computation ===\n");

    bob_lattice_handle_t *lat = NULL;
    bob_lattice_create(4, 4, 4, 1.0, 12345, &lat);

    Benchmark_Result result = {.name = "lattice_entropy", .min_ns = UINT64_MAX};
    double entropy;

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_lattice_entropy(lat, &entropy);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        bob_lattice_entropy(lat, &entropy);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_lattice_destroy(lat);
}

/// =========================================================================
/// State Benchmarks
/// =========================================================================

void benchmark_state_creation(void) {
    printf("\n=== Quantum State Creation (4 qubits) ===\n");

    Benchmark_Result result = {.name = "state_create", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_state_handle_t *state = NULL;
        bob_state_create(4, 0, &state);
        bob_state_destroy(state);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS / 100; i++) {
        uint64_t start = time_now_ns();

        bob_state_handle_t *state = NULL;
        bob_state_create(4, 0, &state);
        bob_state_destroy(state);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
}

void benchmark_state_measure(void) {
    printf("\n=== Quantum State Measurement ===\n");

    bob_state_handle_t *state = NULL;
    bob_state_create(4, 0, &state);

    Benchmark_Result result = {.name = "state_measure", .min_ns = UINT64_MAX};
    int outcome;
    double prob;

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_state_measure(state, 0, &outcome, &prob);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        bob_state_measure(state, 0, &outcome, &prob);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_state_destroy(state);
}

void benchmark_state_apply_gate(void) {
    printf("\n=== Quantum Gate Application ===\n");

    bob_state_handle_t *state = NULL;
    bob_state_create(4, 0, &state);

    Benchmark_Result result = {.name = "state_apply_gate", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_state_apply_gate(state, 0, 0, NULL, 0);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        bob_state_apply_gate(state, 0, 0, NULL, 0);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_state_destroy(state);
}

/// =========================================================================
/// Hamiltonian Benchmarks
/// =========================================================================

void benchmark_hamiltonian_creation(void) {
    printf("\n=== Hamiltonian Creation (4 qubits) ===\n");

    Benchmark_Result result = {.name = "hamiltonian_create", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_hamiltonian_handle_t *ham = NULL;
        bob_hamiltonian_create(4, 0, &ham);
        bob_hamiltonian_destroy(ham);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS / 100; i++) {
        uint64_t start = time_now_ns();

        bob_hamiltonian_handle_t *ham = NULL;
        bob_hamiltonian_create(4, 0, &ham);
        bob_hamiltonian_destroy(ham);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
}

void benchmark_hamiltonian_add_term(void) {
    printf("\n=== Hamiltonian Add Term ===\n");

    bob_hamiltonian_handle_t *ham = NULL;
    bob_hamiltonian_create(4, 0, &ham);

    int qubits[] = {0};
    Benchmark_Result result = {.name = "hamiltonian_add_term", .min_ns = UINT64_MAX};

    // Warmup
    for (int i = 0; i < BENCHMARK_WARMUP; i++) {
        bob_hamiltonian_add_term(ham, 1.0, 0.0, qubits, 1);
    }

    // Benchmark
    for (int i = 0; i < BENCHMARK_ITERATIONS; i++) {
        uint64_t start = time_now_ns();

        bob_hamiltonian_add_term(ham, 1.0, 0.0, qubits, 1);

        uint64_t elapsed = time_now_ns() - start;
        result.total_ns += elapsed;
        result.min_ns = elapsed < result.min_ns ? elapsed : result.min_ns;
        result.max_ns = elapsed > result.max_ns ? elapsed : result.max_ns;
        result.count++;
    }

    print_result(&result);
    bob_hamiltonian_destroy(ham);
}

/// =========================================================================
/// Main Benchmark Suite
/// =========================================================================

int main(void) {
    printf("\n");
    printf("╔════════════════════════════════════════════════════════════════╗\n");
    printf("║ BOB Quantum Civilization Engine - Performance Benchmarks       ║\n");
    printf("║ Language FFI Binding Latency Analysis                         ║\n");
    printf("╚════════════════════════════════════════════════════════════════╝\n");

    // RNG benchmarks
    printf("\n>>> RNG Subsystem <<<\n");
    benchmark_rng_creation();
    benchmark_rng_uniform();
    benchmark_rng_normal();
    benchmark_rng_integer();

    // Lattice benchmarks
    printf("\n>>> Lattice Subsystem <<<\n");
    benchmark_lattice_creation();
    benchmark_lattice_evolve();
    benchmark_lattice_energy();
    benchmark_lattice_entropy();

    // State benchmarks
    printf("\n>>> Quantum State Subsystem <<<\n");
    benchmark_state_creation();
    benchmark_state_measure();
    benchmark_state_apply_gate();

    // Hamiltonian benchmarks
    printf("\n>>> Hamiltonian Subsystem <<<\n");
    benchmark_hamiltonian_creation();
    benchmark_hamiltonian_add_term();

    printf("\n=== Benchmark Complete ===\n\n");

    return 0;
}
