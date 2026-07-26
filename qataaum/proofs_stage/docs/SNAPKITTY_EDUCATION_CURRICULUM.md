# SnapKitty Education Curriculum

Source-grounded curriculum draft for SnapKitty Algebra, SnapKitty Science, and SnapKitty Quantum.

This curriculum is derived from visible local repositories and public reference signals. It is not a claim that every upstream fork is fully present locally.

## Source Map

| Source | Local path | Curriculum use |
|---|---|---|
| Fibonacci Contraction | `C:/Users/jessi/Desktop/fibonacci-contraction` | Phinary arithmetic, Fibonacci sequences, contraction vs expansion, Lean/APL formalization |
| Sovereign Calculus | `C:/Users/jessi/Desktop/sovereign-calculus` | Domain algebra, transition algebra, omega isolation, proof traps, formal systems |
| SNAPKITTY-PROOFS | `C:/Users/jessi/Desktop/SNAPKITTY-PROOFS` | Lean/Prolog/Haskell proof stack, policy algebra, no-cloning, quantum monad, thermal window |
| the-49th-call | `C:/Users/jessi/Desktop/the-49th-call` | Symmetry, reverse transforms, constraint logic, SUBLEQ, cross-script encoding, OISC thesis |
| Multiplicity fork signal | `C:/Users/jessi/Desktop/agentic-arena/worm/meta-repos/MultiplicityTheory-multiplicity` | Fork/restoration metadata only; use for PIRTM gap analysis, not full lesson source |
| Agentic Arena fork injector | `C:/Users/jessi/Desktop/agentic-arena/runtime/worm-fork-inject.mjs` | Documents `MultiplicityTheory/multiplicity`, PIRTM entry path, and gap taxonomy |

## Source Limits

- Exact local repo named `f1` was not found.
- `F1` is treated as a likely shorthand for `fibonacci-contraction` until clarified.
- Exact local repo named `uor` was not found.
- `UOR` is not used as a source label in the curriculum until the repo is identified.
- `MultiplicityTheory-multiplicity` local mirror contains only `Project.lisp` and `graveyard.forth`; it does not contain the full upstream Lean source.

## Program Model

The SnapKitty education system has three tracks:

1. SnapKitty Algebra
2. SnapKitty Science
3. SnapKitty Quantum

Each track has three levels:

1. Foundations
2. Research Lab
3. Proof Studio

Every module should produce one of:

- a notebook
- a proof file
- a simulation
- a sealed audit note
- a short research memo

## Track 1: SnapKitty Algebra

Purpose: teach symbolic mathematics, domain algebra, and proof-aware computation using SnapKitty's own formal artifacts.

### A1. Pattern, Sequence, and Recursion

Source:

- `fibonacci-contraction/README.md`
- `fibonacci-contraction/lean/FibCore/PhinaryContraction.lean`
- `fibonacci-contraction/apl/phinary.apl`

Concepts:

- Fibonacci recurrence
- golden ratio
- ratio convergence
- recursion
- open conjectures
- difference between theorem, axiom, and visualization

Student outcomes:

- compute Fibonacci sequences
- explain why `F(n+1)/F(n)` approaches phi
- distinguish contraction from expansion
- identify an open problem without pretending it is solved

Activities:

- implement Fibonacci in Python or APL
- graph ratio convergence
- compare `phi` and `1 / phi` as growth/contraction factors
- write a one-page note: "What makes a mathematical claim verified?"

Assessment:

- notebook with sequence table and convergence chart
- short proof sketch of `phi^2 = phi + 1`

### A2. Phinary Arithmetic

Source:

- `fibonacci-contraction/docs/index.html`
- `fibonacci-contraction/fcc-phi-2026.ipynb`
- `fibonacci-contraction/lean/FibCore/PhinaryContraction.lean`

Concepts:

- base-phi numeration
- Zeckendorf-style representation
- irrational bases
- carry rules
- visual math vs formal math

Student outcomes:

- explain why phinary arithmetic does not behave like base 10
- build a simple phinary encoder for small integers
- describe why a visualization is not a proof

Activities:

- convert small integers into Fibonacci basis
- build a phinary spiral visual
- annotate which claims are proven, conjectural, or illustrative

Assessment:

- phinary worksheet
- code artifact
- claim classification table

### A3. Sovereign Domain Algebra

Source:

- `sovereign-calculus/README.md`
- `sovereign-calculus/lean/SovereignCore/DomainAlgebra.lean`

Concepts:

- domain labels
- partitions
- boundary conditions
- zero state
- seal validity vs boundary validity
- trust-order mistakes

Student outcomes:

- define a domain partition
- model allowed and disallowed transitions
- explain why order of verification matters

Activities:

- create a small domain graph
- mark valid vs invalid cross-domain edges
- repair a "seal implies boundary" reasoning error

Assessment:

- domain model diagram
- corrected inference rule

### A4. Transition Algebra and Morphisms

Source:

- `sovereign-calculus/lean/PIRTM/TransitionAlgebra.lean`
- `sovereign-calculus/lean/SovereignCore/SovereignMorphism.lean`
- `sovereign-calculus/apl/MOC_TO_BANACH.apl`

Concepts:

- morphisms
- composition order
- transition monoids
- omega isolation
- null transitions
- MOC to Banach mapping

Student outcomes:

- explain left-to-right vs right-to-left composition
- identify inverted composition bugs
- model a transition that collapses to a null state

Activities:

- compose three symbolic morphisms
- test how reversing composition changes output
- write a "transition audit" of a toy system

Assessment:

- morphism composition exercise
- null-transition proof sketch

### A5. Multiplicity and PIRTM Gap Lab

Source:

- `agentic-arena/worm/meta-repos/MultiplicityTheory-multiplicity/Project.lisp`
- `agentic-arena/worm/meta-repos/MultiplicityTheory-multiplicity/graveyard.forth`
- `agentic-arena/runtime/worm-fork-inject.mjs`
- public GitHub signal for `MultiplicityTheory`

Concepts:

- PIRTM as prime-indexed recursive tensor mathematics
- admits/placeholders as proof gaps
- stability contradiction: `alpha >= 1` vs `q < 1`
- morphism registry gaps
- fork/research provenance

Student outcomes:

- read a restoration manifest
- separate "repo signal" from "source proof"
- classify proof gaps by severity

Activities:

- parse `Project.lisp`
- convert gap list into a research backlog
- write a restoration plan without claiming the missing upstream code is present

Assessment:

- gap taxonomy memo
- source-limit statement

## Track 2: SnapKitty Science

Purpose: teach systems thinking, simulation, thermodynamics, computation, and experimental reasoning using SnapKitty engines.

### S1. Systems, State, and Feedback

Source:

- `SNAPKITTY-PROOFS/haskell/README.md`
- `SNAPKITTY-PROOFS/haskell/thermal.hs`

Concepts:

- state variables
- feedback loops
- friction
- thermal windows
- invariants

Student outcomes:

- model a feedback loop
- explain why smart constructors enforce valid states
- distinguish runtime checks from compiler-enforced invariants

Activities:

- simulate friction changing over time
- compute thermal windows for sample inputs
- graph cool/warm/hot modes

Assessment:

- simulation notebook
- invariant explanation

### S2. Evidence, Observation, and Attestation

Source:

- `SNAPKITTY-PROOFS/prolog/README.md`
- `SNAPKITTY-PROOFS/prolog/shrew_observer.pl`

Concepts:

- observation
- evidence levels
- source present vs binary present vs execution proven
- read-only witnesses

Student outcomes:

- design an evidence ladder
- explain why "file exists" is weaker than "execution proven"
- build a simple attestation checklist

Activities:

- inspect a repo and classify evidence
- write a Prolog-style fact table
- produce a SHREW-style attestation report

Assessment:

- evidence matrix
- attestation report

### S3. Constraint Logic as Scientific Method

Source:

- `the-49th-call/ere.pl`
- `the-49th-call/README.md`
- `SNAPKITTY-PROOFS/prolog/edaulc_verify.pl`

Concepts:

- constraint systems
- multiple passes
- hypothesis testing
- reversal and symmetry as transformations
- false positives

Student outcomes:

- express a hypothesis as a predicate
- run multiple independent checks
- explain why agreement across passes is stronger than one-pass validation

Activities:

- define a toy `valid_trigram`
- add forward and reverse validation passes
- build an EDAULC-style five-pass linter for a small text

Assessment:

- Prolog exercise
- pass/fail trace

### S4. Computational Physics of Proof

Source:

- `SNAPKITTY-PROOFS/haskell/thermal.hs`
- `SNAPKITTY-PROOFS/haskell/quantum_monad.hs`
- `SNAPKITTY-PROOFS/haskell/no_cloning.hs`

Concepts:

- signal windows
- superposition as a weighted list of branches
- collapse as measurement
- resource linearity
- no-cloning as an information safety rule

Student outcomes:

- simulate branching and collapse
- explain no-cloning in computational terms
- compare classical reusable values with linear single-use values

Activities:

- implement weighted branch selection
- destroy invalid branches
- trace a value through a linear pipeline

Assessment:

- branch/collapse simulation
- no-cloning explanation

### S5. Research Ethics and Source Boundaries

Source:

- `SNAPKITTY-PROOFS/LICENSE`
- `SNAPKITTY-PROOFS/README.md`
- `agentic-arena/runtime/worm-fork-inject.mjs`

Concepts:

- provenance
- license boundaries
- fork signals
- proof of authorship
- traps vs teaching examples

Student outcomes:

- cite local source paths
- avoid claiming hidden/private internals
- distinguish authorized curriculum from unauthorized reuse

Activities:

- write a provenance block
- label source-derived vs inferred material
- create a "do not overclaim" checklist

Assessment:

- provenance appendix
- ethics memo

## Track 3: SnapKitty Quantum

Purpose: teach quantum-inspired computation, formal resource control, and proof systems without overclaiming physical quantum hardware.

### Q1. Quantum-Inspired State

Source:

- `SNAPKITTY-PROOFS/haskell/quantum_monad.hs`
- `SNAPKITTY-PROOFS/prolog/quantum_monad.pl`

Concepts:

- amplitude
- branch
- weighted superposition
- normalization
- measurement/collapse

Student outcomes:

- represent a superposition as weighted branches
- normalize weights
- collapse to the dominant branch

Activities:

- implement `QuantumAmplitude`
- implement `prune` and `renormalize`
- compare random collapse and max-weight collapse

Assessment:

- code exercise
- branch trace table

### Q2. Watchtowers and Search Modes

Source:

- `SNAPKITTY-PROOFS/prolog/quantum_monad.pl`
- `the-49th-call/src/lib.rs`

Concepts:

- search spaces
- grid values
- collapsed vs uncertain values
- multi-pass agreement
- threshold certification

Student outcomes:

- model uncertain values
- build a simple grid with candidates
- certify a value when all passes agree

Activities:

- create a 3x3 candidate grid
- run four validation passes
- collapse cells when agreement is reached

Assessment:

- grid lab
- certification trace

### Q3. No-Cloning and Linear Types

Source:

- `SNAPKITTY-PROOFS/haskell/no_cloning.hs`
- `SNAPKITTY-PROOFS/haskell/README.md`

Concepts:

- single-use resources
- GADT constructors
- linear arrows
- observation consumes state

Student outcomes:

- explain no-cloning as a type-system discipline
- trace why a superposed value cannot be observed twice
- model destructive validation

Activities:

- annotate linear pipeline steps
- identify cloning bugs in pseudocode
- write a non-code proof narrative

Assessment:

- no-cloning worksheet
- corrected pseudocode

### Q4. Mirror Systems and Symmetry

Source:

- `the-49th-call/README.md`
- `the-49th-call/substrate/substrate.apl`
- `the-49th-call/substrate/soul_spec.hs`
- `the-49th-call/substrate/comefrom.i`

Concepts:

- reverse as transformation
- mirror identity
- `reverse(reverse(x)) = x`
- reading direction
- COMEFROM as inverted control flow

Student outcomes:

- prove double reverse identity for lists
- compare the same idea in APL, Haskell, Prolog, and assembly
- explain how notation changes reasoning

Activities:

- implement reverse in two languages
- write a mirror identity proof
- map SUBLEQ A/B/C to a decision threshold

Assessment:

- multi-language comparison
- symmetry proof sketch

### Q5. Quantum Research Studio

Source:

- all proof-stack sources above

Concepts:

- research notebook discipline
- conjecture vs theorem
- compiler proof vs runtime evidence
- visual proof vs formal proof

Student outcomes:

- design a small research question
- choose the right proof language
- produce a sealed learning artifact

Capstone options:

- build a phinary visualizer and formal claim table
- build a Prolog five-pass validator
- build a Haskell no-cloning demo
- build a Lean theorem glossary for domain algebra
- build a curriculum map from one repo into lessons

Assessment:

- capstone artifact
- provenance block
- limitations section

## Curriculum Ladder

### Beginner

- Fibonacci sequence
- functions and recursion
- graphs and convergence
- predicates and facts
- evidence levels

### Intermediate

- irrational bases
- domain partitions
- transition systems
- Prolog constraints
- weighted superposition
- Haskell types

### Advanced

- Lean theorem reading
- morphism composition
- contraction proofs
- no-cloning via LinearTypes
- PIRTM gap analysis
- multi-pass certification

## SnapKitty Course Names

1. SnapKitty Algebra 101: Recursion, Phi, and Pattern
2. SnapKitty Algebra 201: Phinary Arithmetic and Domain Algebra
3. SnapKitty Algebra 301: Morphisms, Transitions, and Proof Traps
4. SnapKitty Science 101: Systems, Signals, and Feedback
5. SnapKitty Science 201: Evidence, Attestation, and Constraint Logic
6. SnapKitty Science 301: Computational Proof Laboratories
7. SnapKitty Quantum 101: Branches, Weights, and Collapse
8. SnapKitty Quantum 201: Watchtowers, Search, and Certification
9. SnapKitty Quantum 301: No-Cloning, Linear Types, and Research Proofs

## Claude/Engine Handoff

Use this curriculum as the education layer for the repos.

Needed next:

1. Identify the exact `F1` repo if it is not `fibonacci-contraction`.
2. Identify the exact `UOR` repo before adding it as a source.
3. Clone or fetch full upstream `MultiplicityTheory/multiplicity` if deeper PIRTM lesson extraction is needed.
4. Convert each module into:
   - `lesson.md`
   - `notebook.ipynb`
   - `proof.lean` or `exercise.pl` or `exercise.hs`
   - `assessment.md`
5. Build a SnapKitty Academy route that reads this curriculum and links to proof artifacts.

## Seal

AN = education intent extracted

KI = grounded in visible local repo source and public repo signal

ME = source limits preserved
