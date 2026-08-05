# Verified Physics

Machine-verified numerical kernels for physical simulations.

## Black Hole Mechanics

Schwarzschild and Kerr black hole thermodynamics verified with Lean 4 + Fortran + Coq.
Every numerical result is within 1 ULP of the exact formula.

```bash
cd bh-mechanics && make test
# 14/14 tests pass, all ULP-verified
```

### What is verified

| Formula | Verification |
|---------|-------------|
| κ = 1/(4M) (Schwarzschild surface gravity) | Fortran + runtime check |
| S = 4πM² (Hawking entropy) | Fortran + runtime check |
| First law: dM = (κ/2π)dS | Fortran |
| Kerr κ, S, Ω exact formulas | Fortran + runtime check |
| LQG correction S = A/4 + α ln A + β | Fortran + runtime check |
| String correction S = A/4 + γ√A | Fortran + runtime check |

### Connection to the Constraint DSL

The entropy bound H ≤ 0.20 nats in the HyperKitty Constraint DSL is an
information-theoretic threshold. The K3 surface (Hodge entropy = 0.831 nats)
violates it. Black hole entropy is a physical analogue of the same principle:
entropy bounds determine what states are thermodynamically admissible.

The BH mechanics kernel applies the same verification methodology to physical
systems: formal specification → numerical implementation → proof that
implementation matches specification within machine precision.

See: [hyperkitty-constraint-dsl](https://github.com/SNAPKITTYWEST/hyperkitty-constraint-dsl)
