module BobQuantum

const LIBBOB = "libbob_quantum.so"

export BobRNG, BobLattice, BobState, BobHamiltonian,
       RNG, Lattice, State, Hamiltonian,
       evolve!, energy, entropy,
       measure, measure_shots,
       normalize!, add_term!, expectation,
       evolve_exact!, evolve_trotter!, evolve_krylov!

struct BobRNG
    handle::Ptr{Cvoid}
    function BobRNG(seed::UInt64)
        handle = ccall((:bob_rng_create, LIBBOB), Ptr{Cvoid}, (UInt64,), seed)
        obj = new(handle)
        finalizer(destroy, obj)
        return obj
    end
end

struct BobLattice
    handle::Ptr{Cvoid}
    function BobLattice(nx::Int, ny::Int, nz::Int, coupling::Float64, seed::UInt