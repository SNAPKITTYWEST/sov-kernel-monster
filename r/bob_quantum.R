# BOB Quantum Civilization Engine - R Bindings
# Complete interface to C ABI via .Call()
# Requires: libbobquantum.so / bobquantum.dll / libbobquantum.dylib

.onLoad <- function(libname, pkgname) {
  lib_path <- system.file("libs", paste0("bobquantum", .Platform$dynlib.ext), package = pkgname)
  if (lib_path == "") {
    lib_path <- Sys.getenv("BOB_QUANTUM_LIB", "bobquantum")
  }
  tryCatch({
    dyn.load(lib_path)
    .bob_initialized <<- TRUE
    packageStartupMessage("BOB Quantum Civilization Engine loaded from: ", lib_path)
  }, error = function(e) {
    .bob_initialized <<- FALSE
    packageStartupMessage("WARNING: Failed to load BOB library: ", e$message)
    packageStartupMessage("Set BOB_QUANTUM_LIB environment variable or install library in libs/")
  })
  invisible(NULL)
}

.onUnload <- function(libpath) {
  if (exists(".bob_initialized") && .bob_initialized) {
    tryCatch(dyn.unload(libpath), error = function(e) NULL)
    .bob_initialized <<- FALSE
  }
  invisible(NULL)
}

.bob_initialized <- FALSE

.check_init <- function() {
  if (!exists(".bob_initialized") || !.bob_initialized) {
    stop("BOB engine not initialized. Load package or call bob_init() first.")
  }
}

bob_init <- function(lib_path = NULL) {
  if (exists(".bob_initialized") && .bob_initialized) {
    return(invisible(TRUE))
  }
  if (is.null(lib_path)) {
    lib_path <- Sys.getenv("BOB_QUANTUM_LIB", "bobquantum")
  }
  dyn.load(lib_path)
  .bob_initialized <<- TRUE
  invisible(TRUE)
}

bob_version <- function() {
  .check_init()
  .Call("bob_version")
}

bob_last_error <- function() {
  .check_init()
  .Call("bob_last_error")
}

# ============================================================================
# RNG MODULE
# ============================================================================

bob.rng.create <- function(seed = NULL) {
  .check_init()
  if (is.null(seed)) {
    seed <- as.integer(runif(1, 1, .Machine$integer.max))
  } else if (!is.numeric(seed) || length(seed) != 1) {
    stop("seed must be a single integer")
  }
  seed <- as.integer(seed)
  ptr <- .Call("bob_rng_create", seed)
  if (is.null(ptr)) stop("Failed to create RNG: ", bob_last_error())
  structure(ptr, class = "bob_rng")
}

bob.rng.uniform <- function(rng) {
  .check_init()
  if (!inherits(rng, "bob_rng")) stop("rng must be a bob_rng object")
  val <- .Call("bob_rng_uniform", rng)
  if (is.null(val)) stop("RNG uniform failed: ", bob_last_error())
  val
}

bob.rng.normal <- function(rng, mean = 0, sd = 1) {
  .check_init()
  if (!inherits(rng, "bob_rng")) stop("rng must be a bob_rng object")
  if (!is.numeric(mean) || length(mean) != 1) stop("mean must be numeric scalar")
  if (!is.numeric(sd) || length(sd) != 1 || sd <= 0) stop("sd must be positive numeric scalar")
  val <- .Call("bob_rng_normal", rng, as.double(mean), as.double(sd))
  if (is.null(val)) stop("RNG normal failed: ", bob_last_error())
  val
}

bob.rng.destroy <- function(rng) {
  .check_init()
  if (!inherits(rng, "bob_rng")) stop("rng must be a bob_rng object")
  .Call("bob_rng_destroy", rng)
  invisible(NULL)
}

print.bob_rng <- function(x, ...) {
  cat("<BOB RNG pointer: ", format(x), ">\n", sep = "")
  invisible(x)
}

# ============================================================================
# LATTICE MODULE
# ============================================================================

bob.lattice.create <- function(nx, ny, nz, coupling = 1.0, seed = NULL, periodic = TRUE) {
  .check_init()
  nx <- as.integer(nx); ny <- as.integer(ny); nz <- as.integer(nz)
  if (nx <= 0 || ny <= 0 || nz <= 0) stop("Dimensions must be positive integers")
  if (nx * ny * nz > 1e7) warning("Large lattice (", nx*ny*nz, " sites) may consume significant memory")
  coupling <- as.double(coupling)
  periodic <- as.logical(periodic)
  if (is.null(seed)) {
    seed <- as.integer(runif(1, 1, .Machine$integer.max))
  } else {
    seed <- as.integer(seed)
  }
  ptr <- .Call("bob_lattice_create", nx, ny, nz, coupling, seed, periodic)
  if (is.null(ptr)) stop("Failed to create lattice: ", bob_last_error())
  structure(ptr, class = "bob_lattice", dim = c(nx, ny, nz), coupling = coupling, periodic = periodic)
}

bob.lattice.evolve <- function(lattice, dt) {
  .check_init()
  if (!inherits(lattice, "bob_lattice")) stop("lattice must be a bob_lattice object")
  dt <- as.double(dt)
  if (dt <= 0) stop("dt must be positive")
  result <- .Call("bob_lattice_evolve", lattice, dt)
  if (is.null(result)) stop("Lattice evolve failed: ", bob_last_error())
  invisible(lattice)
}

bob.lattice.energy <- function(lattice) {
  .check_init()
  if (!inherits(lattice, "bob_lattice")) stop("lattice must be a bob_lattice object")
  val <- .Call("bob_lattice_energy", lattice)
  if (is.null(val)) stop("Lattice energy failed: ", bob_last_error())
  val
}

bob.lattice.entropy <- function(lattice) {
  .check_init()
  if (!inherits(lattice, "bob_lattice")) stop("lattice must be a bob_lattice object")
  val <- .Call("bob_lattice_entropy", lattice)
  if (is.null(val)) stop("Lattice entropy failed: ", bob_last_error())
  val
}

bob.lattice.magnetization <- function(lattice) {
  .check_init()
  if (!inherits(lattice, "bob_lattice")) stop("lattice must be a bob_lattice object")
  val <- .Call("bob_lattice_magnetization", lattice)
  if (is.null(val)) stop("Lattice magnetization failed: ", bob_last_error())
  val
}

bob.lattice.correlation <- function(lattice, max_distance = NULL) {
  .check_init()
  if (!inherits(lattice, "bob_lattice")) stop("lattice must be a bob_lattice object")
  dims <- attr(lattice, "dim")
  max_dist <- if (is.null(max_distance)) min(dims) %/% 2 else as.integer(max_distance)
  val <- .Call("bob_lattice_correlation", lattice, max_dist)
  if (is.null(val)) stop("Lattice correlation failed: ", bob_last_error())
  val
}

bob.lattice.get_state <- function(lattice) {
  .check_init()
  if (!inherits(lattice, "bob_lattice")) stop("lattice must be a bob_lattice object")
  val <- .Call("bob_lattice_get_state", lattice)
  if (is.null(val)) stop("Get lattice state failed: ", bob_last_error())
  dims <- attr(lattice, "dim")
  array(val, dim = dims)
}

bob.lattice.set_state <- function(lattice, state_array) {
  .check_init()
  if (!inherits(lattice, "bob_lattice")) stop("lattice must be a bob_lattice object")
  dims <- attr(lattice, "dim")
  if (!is.array(state_array) || !all(dim(state_array) == dims)) {
    stop("state_array must be an array with dimensions ", paste(dims, collapse = "x"))
  }
  result <- .Call("bob_lattice_set_state", lattice, as.vector(state_array))
  if (is.null(result)) stop("Set lattice state failed: ", bob_last_error())
  invisible(lattice)
}

bob.lattice.destroy <- function(lattice) {
  .check_init()
  if (!inherits(lattice, "bob_lattice")) stop("lattice must be a bob_lattice object")
  .Call("bob_lattice_destroy", lattice)
  invisible(NULL)
}

print.bob_lattice <- function(x, ...) {
  dims <- attr(x, "dim")
  cat("<BOB Lattice: ", dims[1], "x", dims[2], "x", dims[3], ">", sep = "")
  cat(" coupling=", attr(x, "coupling"))
  cat(" periodic=", attr(x, "periodic"), "\n", sep = "")
  invisible(x)
}

summary.bob_lattice <- function(object, ...) {
  cat("BOB Lattice Summary\n")
  cat("===================\n")
  dims <- attr(object, "dim")
  cat("Dimensions: ", dims[1], " x ", dims[2], " x ", dims[3], " (", prod(dims), " sites)\n", sep = "")
  cat("Coupling: ", attr(object, "coupling"), "\n")
  cat("Periodic BC: ", attr(object, "periodic"), "\n")
  cat("Energy: ", bob.lattice.energy(object), "\n")
  cat("Entropy: ", bob.lattice.entropy(object), "\n")
  cat("Magnetization: ", bob.lattice.magnetization(object), "\n")
  invisible(object)
}

# ============================================================================
# QUANTUM STATE MODULE
# ============================================================================

bob.state.create <- function(num_qubits) {
  .check_init()
  num_qubits <- as.integer(num_qubits)
  if (num_qubits <= 0) stop("num_qubits must be positive")
  if (num_qubits > 20) warning("Large number of qubits (", num_qubits, ") -> state vector size ", 2^num_qubits)
  ptr <- .Call("bob_state_create", num_qubits)
  if (is.null(ptr)) stop("Failed to create quantum state: ", bob_last_error())
  structure(ptr, class = "bob_state", num_qubits = num_qubits)
}

bob.state.clone <- function(state) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  ptr <- .Call("bob_state_clone", state)
  if (is.null(ptr)) stop("Failed to clone state: ", bob_last_error())
  structure(ptr, class = "bob_state", num_qubits = attr(state, "num_qubits"))
}

bob.state.num_qubits <- function(state) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  attr(state, "num_qubits")
}

bob.state.dim <- function(state) {
  2^bob.state.num_qubits(state)
}

bob.state.get_amplitudes <- function(state) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  val <- .Call("bob_state_get_amplitudes", state)
  if (is.null(val)) stop("Get amplitudes failed: ", bob_last_error())
  val
}

bob.state.set_amplitudes <- function(state, amplitudes) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  n <- bob.state.dim(state)
  if (!is.numeric(amplitudes) && !is.complex(amplitudes)) stop("amplitudes must be numeric or complex")
  if (length(amplitudes) != n) stop("amplitudes length must be ", n)
  amps <- as.complex(amplitudes)
  norm <- sqrt(sum(Mod(amps)^2))
  if (abs(norm - 1) > 1e-10) {
    warning("Amplitudes not normalized (norm = ", norm, "), normalizing...")
    amps <- amps / norm
  }
  result <- .Call("bob_state_set_amplitudes", state, amps)
  if (is.null(result)) stop("Set amplitudes failed: ", bob_last_error())
  invisible(state)
}

bob.state.measure <- function(state, rng, collapse = TRUE) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  if (!inherits(rng, "bob_rng")) stop("rng must be a bob_rng object")
  collapse <- as.logical(collapse)
  result <- .Call("bob_state_measure", state, rng, collapse)
  if (is.null(result)) stop("Measurement failed: ", bob_last_error())
  result
}

bob.state.measure_shots <- function(state, num_shots, rng) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  if (!inherits(rng, "bob_rng")) stop("rng must be a bob_rng object")
  num_shots <- as.integer(num_shots)
  if (num_shots <= 0) stop("num_shots must be positive")
  result <- .Call("bob_state_measure_shots", state, num_shots, rng)
  if (is.null(result)) stop("Measure shots failed: ", bob_last_error())
  result
}

bob.state.probabilities <- function(state) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  amps <- bob.state.get_amplitudes(state)
  Mod(amps)^2
}

bob.state.entropy <- function(state, base = 2) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  probs <- bob.state.probabilities(state)
  probs <- probs[probs > 0]
  if (base == 2) {
    -sum(probs * log2(probs))
  } else if (base == exp(1)) {
    -sum(probs * log(probs))
  } else {
    -sum(probs * log(probs, base))
  }
}

bob.state.fidelity <- function(state1, state2) {
  .check_init()
  if (!inherits(state1, "bob_state") || !inherits(state2, "bob_state")) {
    stop("Both arguments must be bob_state objects")
  }
  if (bob.state.num_qubits(state1) != bob.state.num_qubits(state2)) {
    stop("States must have same number of qubits")
  }
  amps1 <- bob.state.get_amplitudes(state1)
  amps2 <- bob.state.get_amplitudes(state2)
  Mod(sum(Conj(amps1) * amps2))^2
}

bob.state.apply_gate <- function(state, gate_matrix, qubits) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  n <- bob.state.num_qubits(state)
  qubits <- as.integer(qubits)
  if (any(qubits < 0) || any(qubits >= n)) stop("qubits must be in 0..", n-1)
  k <- length(qubits)
  if (!is.matrix(gate_matrix) || nrow(gate_matrix) != 2^k || ncol(gate_matrix) != 2^k) {
    stop("gate_matrix must be ", 2^k, "x", 2^k)
  }
  gate <- as.complex(gate_matrix)
  result <- .Call("bob_state_apply_gate", state, gate, qubits)
  if (is.null(result)) stop("Apply gate failed: ", bob_last_error())
  invisible(state)
}

bob.state.apply_hadamard <- function(state, qubit) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  qubit <- as.integer(qubit)
  H <- matrix(c(1, 1, 1, -1), 2, 2) / sqrt(2)
  bob.state.apply_gate(state, H, qubit)
}

bob.state.apply_pauli_x <- function(state, qubit) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  qubit <- as.integer(qubit)
  X <- matrix(c(0, 1, 1, 0), 2, 2)
  bob.state.apply_gate(state, X, qubit)
}

bob.state.apply_pauli_y <- function(state, qubit) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  qubit <- as.integer(qubit)
  Y <- matrix(c(0, -1i, 1i, 0), 2, 2)
  bob.state.apply_gate(state, Y, qubit)
}

bob.state.apply_pauli_z <- function(state, qubit) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  qubit <- as.integer(qubit)
  Z <- matrix(c(1, 0, 0, -1), 2, 2)
  bob.state.apply_gate(state, Z, qubit)
}

bob.state.apply_cnot <- function(state, control, target) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  control <- as.integer(control)
  target <- as.integer(target)
  if (control == target) stop("control and target must be different")
  CNOT <- matrix(c(1,0,0,0, 0,1,0,0, 0,0,0,1, 0,0,1,0), 4, 4)
  bob.state.apply_gate(state, CNOT, c(control, target))
}

bob.state.apply_rotation <- function(state, qubit, axis, angle) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  qubit <- as.integer(qubit)
  axis <- match.arg(axis, c("x", "y", "z"))
  angle <- as.double(angle)
  if (axis == "x") {
    gate <- matrix(c(cos(angle/2), -1i*sin(angle/2), -1i*sin(angle/2), cos(angle/2)), 2, 2)
  } else if (axis == "y") {
    gate <- matrix(c(cos(angle/2), -sin(angle/2), sin(angle/2), cos(angle/2)), 2, 2)
  } else {
    gate <- matrix(c(exp(-1i*angle/2), 0, 0, exp(1i*angle/2)), 2, 2)
  }
  bob.state.apply_gate(state, gate, qubit)
}

bob.state.destroy <- function(state) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  .Call("bob_state_destroy", state)
  invisible(NULL)
}

print.bob_state <- function(x, ...) {
  n <- attr(x, "num_qubits")
  cat("<BOB Quantum State: ", n, " qubits, dim = ", 2^n, ">\n", sep = "")
  invisible(x)
}

summary.bob_state <- function(object, ...) {
  n <- attr(object, "num_qubits")
  cat("BOB Quantum State Summary\n")
  cat("=========================\n")
  cat("Qubits: ", n, "\n")
  cat("Dimension: ", 2^n, "\n")
  probs <- bob.state.probabilities(object)
  cat("Entropy (base 2): ", bob.state.entropy(object), "\n")
  cat("Max probability: ", max(probs), " (state ", which.max(probs)-1, ")\n", sep = "")
  cat("Non-zero amplitudes: ", sum(probs > 1e-15), "\n")
  invisible(object)
}

# ============================================================================
# HAMILTONIAN MODULE
# ============================================================================

bob.hamiltonian.create <- function(num_qubits) {
  .check_init()
  num_qubits <- as.integer(num_qubits)
  if (num_qubits <= 0) stop("num_qubits must be positive")
  ptr <- .Call("bob_hamiltonian_create", num_qubits)
  if (is.null(ptr)) stop("Failed to create Hamiltonian: ", bob_last_error())
  structure(ptr, class = "bob_hamiltonian", num_qubits = num_qubits, terms = list())
}

bob.hamiltonian.add_term <- function(h, matrix, coeff, qubits) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  n <- attr(h, "num_qubits")
  qubits <- as.integer(qubits)
  if (any(qubits < 0) || any(qubits >= n)) stop("qubits must be in 0..", n-1)
  k <- length(qubits)
  if (!is.matrix(matrix) || nrow(matrix) != 2^k || ncol(matrix) != 2^k) {
    stop("matrix must be ", 2^k, "x", 2^k)
  }
  coeff <- as.double(coeff)
  mat <- as.complex(matrix)
  result <- .Call("bob_hamiltonian_add_term", h, mat, coeff, qubits)
  if (is.null(result)) stop("Add term failed: ", bob_last_error())
  attr(h, "terms") <- c(attr(h, "terms"), list(list(matrix = mat, coeff = coeff, qubits = qubits)))
  invisible(h)
}

bob.hamiltonian.add_pauli_term <- function(h, pauli_string, coeff, qubits) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  pauli_map <- list(
    I = matrix(c(1,0,0,1), 2, 2),
    X = matrix(c(0,1,1,0), 2, 2),
    Y = matrix(c(0,-1i,1i,0), 2, 2),
    Z = matrix(c(1,0,0,-1), 2, 2)
  )
  pauli_string <- toupper(pauli_string)
  if (nchar(pauli_string) != length(qubits)) {
    stop("pauli_string length must match number of qubits")
  }
  mats <- strsplit(pauli_string, "")[[1]]
  for (p in mats) if (!(p %in% names(pauli_map))) stop("Invalid Pauli: ", p)
  full_mat <- pauli_map[[mats[1]]]
  if (length(mats) > 1) {
    for (i in 2:length(mats)) {
      full_mat <- kronecker(full_mat, pauli_map[[mats[i]]])
    }
  }
  bob.hamiltonian.add_term(h, full_mat, coeff, qubits)
}

bob.hamiltonian.add_ising <- function(h, J, h_field, qubits = NULL) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  n <- attr(h, "num_qubits")
  if (is.null(qubits)) qubits <- 0:(n-1)
  qubits <- as.integer(qubits)
  J <- as.double(J)
  h_field <- as.double(h_field)
  for (i in seq_along(qubits)) {
    if (i < length(qubits)) {
      bob.hamiltonian.add_pauli_term(h, "ZZ", -J, c(qubits[i], qubits[i+1]))
    }
    bob.hamiltonian.add_pauli_term(h, "Z", -h_field, qubits[i])
  }
  invisible(h)
}

bob.hamiltonian.add_heisenberg <- function(h, Jx, Jy, Jz, qubits = NULL) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  n <- attr(h, "num_qubits")
  if (is.null(qubits)) qubits <- 0:(n-1)
  qubits <- as.integer(qubits)
  Jx <- as.double(Jx); Jy <- as.double(Jy); Jz <- as.double(Jz)
  for (i in seq_along(qubits)) {
    if (i < length(qubits)) {
      bob.hamiltonian.add_pauli_term(h, "XX", -Jx, c(qubits[i], qubits[i+1]))
      bob.hamiltonian.add_pauli_term(h, "YY", -Jy, c(qubits[i], qubits[i+1]))
      bob.hamiltonian.add_pauli_term(h, "ZZ", -Jz, c(qubits[i], qubits[i+1]))
    }
  }
  invisible(h)
}

bob.hamiltonian.expectation <- function(h, state) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  if (attr(h, "num_qubits") != attr(state, "num_qubits")) {
    stop("Hamiltonian and state must have same number of qubits")
  }
  val <- .Call("bob_hamiltonian_expectation", h, state)
  if (is.null(val)) stop("Expectation failed: ", bob_last_error())
  val
}

bob.hamiltonian.variance <- function(h, state) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  exp_val <- bob.hamiltonian.expectation(h, state)
  h2 <- bob.hamiltonian.clone(h)
  bob.hamiltonian.add_term(h2, bob.hamiltonian.get_matrix(h), 1.0, 0:(attr(h, "num_qubits")-1))
  exp_val2 <- bob.hamiltonian.expectation(h2, state)
  bob.hamiltonian.destroy(h2)
  exp_val2 - exp_val^2
}

bob.hamiltonian.get_matrix <- function(h) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  val <- .Call("bob_hamiltonian_get_matrix", h)
  if (is.null(val)) stop("Get matrix failed: ", bob_last_error())
  val
}

bob.hamiltonian.eigenvalues <- function(h, k = NULL) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  n <- attr(h, "num_qubits")
  dim <- 2^n
  if (is.null(k)) k <- min(dim, 10)
  k <- as.integer(k)
  if (k <= 0 || k > dim) stop("k must be in 1..", dim)
  val <- .Call("bob_hamiltonian_eigenvalues", h, k)
  if (is.null(val)) stop("Eigenvalues failed: ", bob_last_error())
  val
}

bob.hamiltonian.ground_state <- function(h) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  n <- attr(h, "num_qubits")
  ptr <- .Call("bob_hamiltonian_ground_state", h)
  if (is.null(ptr)) stop("Ground state failed: ", bob_last_error())
  structure(ptr, class = "bob_state", num_qubits = n)
}

bob.hamiltonian.time_evolve <- function(h, state, dt) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  if (!inherits(state, "bob_state")) stop("state must be a bob_state object")
  if (attr(h, "num_qubits") != attr(state, "num_qubits")) {
    stop("Hamiltonian and state must have same number of qubits")
  }
  dt <- as.double(dt)
  result <- .Call("bob_hamiltonian_time_evolve", h, state, dt)
  if (is.null(result)) stop("Time evolution failed: ", bob_last_error())
  invisible(state)
}

bob.hamiltonian.clone <- function(h) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  ptr <- .Call("bob_hamiltonian_clone", h)
  if (is.null(ptr)) stop("Clone failed: ", bob_last_error())
  structure(ptr, class = "bob_hamiltonian", num_qubits = attr(h, "num_qubits"), terms = attr(h, "terms"))
}

bob.hamiltonian.destroy <- function(h) {
  .check_init()
  if (!inherits(h, "bob_hamiltonian")) stop("h must be a bob_hamiltonian object")
  .Call("bob_hamiltonian_destroy", h)
  invisible(NULL)
}

print.bob_hamiltonian <- function(x, ...) {
  n <- attr(x, "num_qubits")
  nterms <- length(attr(x, "terms"))
  cat("<BOB Hamiltonian: ", n, " qubits, ", nterms, " terms>\n", sep = "")
  invisible(x)
}

summary.bob_hamiltonian <- function(object, ...) {
  n <- attr(object, "num_qubits")
  terms <- attr(object, "terms")
  cat("BOB Hamiltonian Summary\n")
  cat("=======================\n")
  cat("Qubits: ", n, "\n")
  cat("Dimension: ", 2^n, "\n")
  cat("Terms: ", length(terms), "\n")
  for (i in seq_along(terms)) {
    t <- terms[[i]]
    cat("  Term ", i, ": coeff=", t$coeff, " qubits=", paste(t$qubits, collapse=","), "\n", sep="")
  }
  evals <- bob.hamiltonian.eigenvalues(object, min(5, 2^n))
  cat("Lowest eigenvalues: ", paste(round(evals, 6), collapse=", "), "\n")
  invisible(object)
}

# ============================================================================
# SIMULATION HELPERS
# ============================================================================

bob.simulate.lattice_ising <- function(nx, ny, nz, coupling = 1.0, temp = 1.0, steps = 1000, seed = NULL, periodic = TRUE) {
  .check_init()
  lattice <- bob.lattice.create(nx, ny, nz, coupling, seed, periodic)
  rng <- bob.rng.create(seed)
  energies <- numeric(steps)
  entropies <- numeric(steps)
  mags <- numeric(steps)
  for (i in seq_len(steps)) {
    bob.lattice.evolve(lattice, 1.0 / temp)
    energies[i] <- bob.lattice.energy(lattice)
    entropies[i] <- bob.lattice.entropy(lattice)
    mags[i] <- bob.lattice.magnetization(lattice)
  }
  bob.lattice.destroy(lattice)
  bob.rng.destroy(rng)
  data.frame(step = 1:steps, energy = energies, entropy = entropies, magnetization = mags)
}

bob.simulate.quantum_evolution <- function(hamiltonian, initial_state, times, rng = NULL) {
  .check_init()
  if (!inherits(hamiltonian, "bob_hamiltonian")) stop("hamiltonian must be bob_hamiltonian")
  if (!inherits(initial_state, "bob_state")) stop("initial_state must be bob_state")
  if (is.null(rng)) rng <- bob.rng.create()
  state <- bob.state.clone(initial_state)
  n_times <- length(times)
  expectations <- numeric(n_times)
  entropies <- numeric(n_times)
  fidelities <- numeric(n_times)
  for (i in seq_len(n_times)) {
    if (i > 1) {
      dt <- times[i] - times[i-1]
      bob.hamiltonian.time_evolve(hamiltonian, state, dt)
    }
    expectations[i] <- bob.hamiltonian.expectation(hamiltonian, state)
    entropies[i] <- bob.state.entropy(state)
    fidelities[i] <- bob.state.fidelity(state, initial_state)
  }
  bob.state.destroy(state)
  data.frame(time = times, expectation = expectations, entropy = entropies, fidelity = fidelities)
}

bob.simulate.measurement_statistics <- function(state, num_shots = 1000, rng = NULL) {
  .check_init()
  if (!inherits(state, "bob_state")) stop("state must be bob_state")
  if (is.null(rng)) rng <- bob.rng.create()
  results <- bob.state.measure_shots(state, num_shots, rng)
  bob.rng.destroy(rng)
  table(factor(results, levels = 0:(bob.state.dim(state)-1))) / num_shots
}

# ============================================================================
# GGPLOT2 VISUALIZATION FUNCTIONS
# ============================================================================

#' Plot entropy evolution from lattice or quantum simulation
#' @param data Data frame with columns 'step' or 'time' and 'entropy'
#' @param title Plot title
#' @param xlab X-axis label
#' @param ylab Y-axis label
#' @param color Line color
#' @param size Line size
#' @param theme_ggplot ggplot2 theme to use
#' @