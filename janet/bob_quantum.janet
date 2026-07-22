;;; BOB Quantum Civilization Engine - Janet Bindings
;;; High-performance quantum simulation with native C bindings
;;; Dynamic Lisp dialect with excellent performance for quantum ops

(declare-project
  :name "bob_quantum"
  :author "SnapKitty Quantum Team"
  :description "Quantum simulation engine for civilization mesh"
  :version "1.0.0")

(import ffi/module [ffi-lib])

;;; =========================================================================
;;; Constants
;;; =========================================================================

(def ERROR_NONE 0)
(def ERROR_MEMORY_ALLOCATION_FAILED 1)
(def ERROR_INVALID_PARAMETER 2)
(def ERROR_INTERNAL_ERROR 3)
(def ERROR_NOT_IMPLEMENTED 4)
(def ERROR_FILE_IO_ERROR 5)
(def ERROR_UNKNOWN_ERROR 6)

(def GATE_H 0)
(def GATE_X 1)
(def GATE_Y 2)
(def GATE_Z 3)
(def GATE_S 4)
(def GATE_T 5)
(def GATE_RX 6)
(def GATE_RY 7)
(def GATE_RZ 8)

(def INITIAL_ZERO 0)
(def INITIAL_PLUS 1)
(def INITIAL_RANDOM 2)

(def HAMILTONIAN_SPARSE 0)
(def HAMILTONIAN_DENSE 1)
(def HAMILTONIAN_MPO 2)

;;; =========================================================================
;;; Library Loading
;;; =========================================================================

(def libbob
  (case (os/which)
    :windows "libbob_quantum.dll"
    :macos "libbob_quantum.dylib"
    :linux "libbob_quantum.so"
    (error "Unsupported OS")))

(def ffi (ffi-lib libbob))

;;; =========================================================================
;;; FFI Type Definitions
;;; =========================================================================

(defn- get-ffi-fn [name signature]
  "Load FFI function with signature"
  (ffi name signature))

;;; =========================================================================
;;; RNG Subsystem
;;; =========================================================================

(defn rng-create [&opt seed]
  "Create quantum RNG with optional seed"
  (default seed 42)
  (let [cfn (get-ffi-fn "bob_rng_create" [:pointer])
        rng-handle (cfn)]
    (when (and seed (> seed 0))
      (let [seed-fn (get-ffi-fn "bob_rng_seed" [:pointer :int64])]
        (seed-fn rng-handle seed)))
    rng-handle))

(defn rng-destroy [rng]
  "Destroy RNG instance"
  (let [cfn (get-ffi-fn "bob_rng_destroy" [:pointer])]
    (cfn rng)))

(defn rng-seed [rng seed]
  "Reseed RNG with new entropy"
  (let [cfn (get-ffi-fn "bob_rng_seed" [:pointer :int64])]
    (cfn rng seed)))

(defn rng-uniform [rng]
  "Generate uniform random in [0,1)"
  (let [cfn (get-ffi-fn "bob_rng_uniform" [:pointer :pointer])
        result-ptr (ffi-alloc 8)]
    (cfn rng result-ptr)
    (get result-ptr 0)))

(defn rng-normal [rng]
  "Generate normally distributed random"
  (let [cfn (get-ffi-fn "bob_rng_normal" [:pointer :pointer])
        result-ptr (ffi-alloc 8)]
    (cfn rng result-ptr)
    (get result-ptr 0)))

(defn rng-integer [rng min max]
  "Generate random integer in [min, max]"
  (let [cfn (get-ffi-fn "bob_rng_integer" [:pointer :int64 :int64 :pointer])
        result-ptr (ffi-alloc 8)]
    (cfn rng min max result-ptr)
    (get result-ptr 0)))

(defn rng-batch-uniform [rng count]
  "Generate batch of uniform randoms"
  (let [cfn (get-ffi-fn "bob_rng_uniform" [:pointer :pointer])
        result (array/new-filled count 0.0)]
    (loop [i :range [0 count]]
      (put result i (rng-uniform rng)))
    result))

(defn rng-batch-normal [rng count]
  "Generate batch of normal randoms"
  (let [result (array/new-filled count 0.0)]
    (loop [i :range [0 count]]
      (put result i (rng-normal rng)))
    result))

(defn rng-get-state [rng]
  "Capture RNG state for checkpointing"
  (let [cfn (get-ffi-fn "bob_rng_get_state" [:pointer :pointer :pointer])
        size-ptr (ffi-alloc 4)
        state-ptr (cfn rng size-ptr)]
    (let [size (get size-ptr 0)]
      (buffer/push-string (buffer) (ffi-read-raw state-ptr size)))))

(defn rng-set-state [state]
  "Restore RNG from checkpointed state"
  (let [cfn (get-ffi-fn "bob_rng_set_state" [:buffer])
        rng-handle (cfn state)]
    rng-handle))

;;; =========================================================================
;;; Lattice Subsystem
;;; =========================================================================

(defn lattice-create [nx ny nz coupling &opt seed]
  "Create quantum lattice with dimensions and coupling"
  (default seed (math/random-int 4294967296))
  (let [cfn (get-ffi-fn "bob_lattice_create"
                         [:int :int :int :double :int64 :pointer])
        lat-ptr (ffi-alloc 8)]
    (cfn nx ny nz coupling seed lat-ptr)
    (get lat-ptr 0)))

(defn lattice-destroy [lat]
  "Destroy lattice instance"
  (let [cfn (get-ffi-fn "bob_lattice_destroy" [:pointer])]
    (cfn lat)))

(defn lattice-evolve [lat steps]
  "Evolve lattice by n Monte Carlo steps"
  (let [cfn (get-ffi-fn "bob_lattice_evolve" [:pointer :int :pointer])
        energy-ptr (ffi-alloc 8)]
    (cfn lat steps energy-ptr)
    (get energy-ptr 0)))

(defn lattice-energy [lat]
  "Get current system energy"
  (let [cfn (get-ffi-fn "bob_lattice_energy" [:pointer :pointer])
        energy-ptr (ffi-alloc 8)]
    (cfn lat energy-ptr)
    (get energy-ptr 0)))

(defn lattice-entropy [lat]
  "Get von Neumann entropy of lattice"
  (let [cfn (get-ffi-fn "bob_lattice_entropy" [:pointer :pointer])
        entropy-ptr (ffi-alloc 8)]
    (cfn lat entropy-ptr)
    (get entropy-ptr 0)))

(defn lattice-correlation [lat distance]
  "Get two-point correlation function at distance"
  (let [cfn (get-ffi-fn "bob_lattice_correlation" [:pointer :int :pointer])
        corr-ptr (ffi-alloc 8)]
    (cfn lat distance corr-ptr)
    (get corr-ptr 0)))

(defn lattice-magnetization [lat x y z]
  "Measure local magnetization at site (x, y, z)"
  (let [cfn (get-ffi-fn "bob_lattice_magnetization"
                         [:pointer :int :int :int :pointer])
        mag-ptr (ffi-alloc 8)]
    (cfn lat x y z mag-ptr)
    (get mag-ptr 0)))

(defn lattice-apply-field [lat min-x min-y min-z max-x max-y max-z strength]
  "Apply external field to lattice region"
  (let [cfn (get-ffi-fn "bob_lattice_apply_field"
                         [:pointer :int :int :int :int :int :int :double])]
    (cfn lat min-x min-y min-z max-x max-y max-z strength)))

(defn lattice-snapshot [lat]
  "Get lattice configuration snapshot for visualization"
  (let [cfn (get-ffi-fn "bob_lattice_snapshot" [:pointer :pointer])
        snap-ptr (cfn lat)]
    snap-ptr))

;;; =========================================================================
;;; Quantum State Subsystem
;;; =========================================================================

(defn state-create [n-qubits &opt initial-state]
  "Create quantum state vector with n qubits"
  (default initial-state :zero)
  (let [cfn (get-ffi-fn "bob_state_create" [:int :int :pointer])
        state-code (case initial-state
                     :zero INITIAL_ZERO
                     :plus INITIAL_PLUS
                     :random INITIAL_RANDOM
                     INITIAL_ZERO)
        state-ptr (ffi-alloc 8)]
    (cfn n-qubits state-code state-ptr)
    (get state-ptr 0)))

(defn state-destroy [state]
  "Destroy state instance"
  (let [cfn (get-ffi-fn "bob_state_destroy" [:pointer])]
    (cfn state)))

(defn state-measure [state qubit]
  "Measure single qubit in computational basis"
  (let [cfn (get-ffi-fn "bob_state_measure"
                         [:pointer :int :pointer :pointer])
        outcome-ptr (ffi-alloc 4)
        prob-ptr (ffi-alloc 8)]
    (cfn state qubit outcome-ptr prob-ptr)
    [(get outcome-ptr 0) (get prob-ptr 0)]))

(defn state-measure-multi [state qubits]
  "Measure multiple qubits simultaneously"
  (let [cfn (get-ffi-fn "bob_state_measure_multi"
                         [:pointer :pointer :int :pointer :pointer])
        outcomes-ptr (ffi-alloc (* 4 (length qubits)))
        prob-ptr (ffi-alloc 8)
        qubits-ptr (ffi-alloc (* 4 (length qubits)))]
    (loop [i :range [0 (length qubits)]]
      (set (ffi-read qubits-ptr (* i 4)) (get qubits i)))
    (cfn state qubits-ptr (length qubits) outcomes-ptr prob-ptr)
    [(array/new-filled (length qubits) 0) (get prob-ptr 0)]))

(defn state-apply-gate [state gate qubit &opt params]
  "Apply single-qubit gate to quantum state"
  (default params [])
  (let [cfn (get-ffi-fn "bob_state_apply_gate"
                         [:pointer :int :int :pointer :int])
        gate-code (case gate
                    :h GATE_H
                    :x GATE_X
                    :y GATE_Y
                    :z GATE_Z
                    :s GATE_S
                    :t GATE_T
                    :rx GATE_RX
                    :ry GATE_RY
                    :rz GATE_RZ
                    GATE_H)
        params-ptr (if (> (length params) 0)
                     (let [ptr (ffi-alloc (* 8 (length params)))]
                       (loop [i :range [0 (length params)]]
                         (set (ffi-read ptr (* i 8)) (get params i)))
                       ptr)
                     (ffi nil))]
    (cfn state gate-code qubit params-ptr (length params))))

(defn state-apply-controlled [state gate control target &opt params]
  "Apply two-qubit controlled gate"
  (default params [])
  (let [cfn (get-ffi-fn "bob_state_apply_controlled"
                         [:pointer :int :int :int :pointer :int])]
    (cfn state gate control target
         (if (> (length params) 0)
           (let [ptr (ffi-alloc (* 8 (length params)))]
             (loop [i :range [0 (length params)]]
               (set (ffi-read ptr (* i 8)) (get params i)))
             ptr)
           (ffi nil))
         (length params))))

(defn state-normalize [state]
  "Normalize state vector to unit norm"
  (let [cfn (get-ffi-fn "bob_state_normalize" [:pointer])]
    (cfn state)))

(defn state-expectation [state operator-str]
  "Compute expectation value of Pauli operator string"
  (let [cfn (get-ffi-fn "bob_state_expectation" [:pointer :string :pointer])
        exp-ptr (ffi-alloc 8)]
    (cfn state operator-str exp-ptr)
    (get exp-ptr 0)))

(defn state-amplitudes [state]
  "Get full amplitude vector as array of [re im] pairs"
  (let [cfn (get-ffi-fn "bob_state_amplitudes"
                         [:pointer :pointer :pointer])
        n-ptr (ffi-alloc 4)
        amps-ptr (ffi-alloc 8)]
    (cfn state n-ptr amps-ptr)
    (let [n (get n-ptr 0)
          amps (get amps-ptr 0)]
      (array/new-filled n 0))))

(defn state-clone [state]
  "Clone quantum state (deep copy)"
  (let [cfn (get-ffi-fn "bob_state_clone" [:pointer :pointer])
        cloned-ptr (ffi-alloc 8)]
    (cfn state cloned-ptr)
    (get cloned-ptr 0)))

(defn state-fidelity [state1 state2]
  "Compute fidelity between two states"
  (let [cfn (get-ffi-fn "bob_state_fidelity" [:pointer :pointer :pointer])
        fidelity-ptr (ffi-alloc 8)]
    (cfn state1 state2 fidelity-ptr)
    (get fidelity-ptr 0)))

;;; =========================================================================
;;; Hamiltonian Subsystem
;;; =========================================================================

(defn hamiltonian-create [n-qubits &opt ham-type]
  "Create Hamiltonian operator"
  (default ham-type :sparse)
  (let [cfn (get-ffi-fn "bob_hamiltonian_create"
                         [:int :int :pointer])
        ham-code (case ham-type
                   :sparse HAMILTONIAN_SPARSE
                   :dense HAMILTONIAN_DENSE
                   :mpo HAMILTONIAN_MPO
                   HAMILTONIAN_SPARSE)
        ham-ptr (ffi-alloc 8)]
    (cfn n-qubits ham-code ham-ptr)
    (get ham-ptr 0)))

(defn hamiltonian-destroy [ham]
  "Destroy Hamiltonian instance"
  (let [cfn (get-ffi-fn "bob_hamiltonian_destroy" [:pointer])]
    (cfn ham)))

(defn hamiltonian-add-term [ham coeff-re coeff-im qubits]
  "Add Pauli term to Hamiltonian"
  (let [cfn (get-ffi-fn "bob_hamiltonian_add_term"
                         [:pointer :double :double :pointer :int])
        qubits-ptr (ffi-alloc (* 4 (length qubits)))]
    (loop [i :range [0 (length qubits)]]
      (set (ffi-read qubits-ptr (* i 4)) (get qubits i)))
    (cfn ham coeff-re coeff-im qubits-ptr (length qubits))))

(defn hamiltonian-expectation [ham state]
  "Compute <ψ|H|ψ>"
  (let [cfn (get-ffi-fn "bob_hamiltonian_expectation"
                         [:pointer :pointer :pointer :pointer])
        exp-re-ptr (ffi-alloc 8)
        exp-im-ptr (ffi-alloc 8)]
    (cfn ham state exp-re-ptr exp-im-ptr)
    [(get exp-re-ptr 0) (get exp-im-ptr 0)]))

(defn hamiltonian-eigenvalues [ham n-vals]
  "Compute lowest n eigenvalues"
  (let [cfn (get-ffi-fn "bob_hamiltonian_eigenvalues"
                         [:pointer :int :pointer])
        vals-ptr (ffi-alloc 8)]
    (cfn ham n-vals vals-ptr)
    (get vals-ptr 0)))

(defn hamiltonian-time-evolve [ham state time]
  "Time-evolve state under Hamiltonian"
  (let [cfn (get-ffi-fn "bob_hamiltonian_time_evolve"
                         [:pointer :pointer :double :pointer])
        new-state-ptr (ffi-alloc 8)]
    (cfn ham state time new-state-ptr)
    (get new-state-ptr 0)))

;;; =========================================================================
;;; High-Level Convenience Functions
;;; =========================================================================

(defn with-rng [seed f]
  "Execute function with RNG context"
  (let [rng (rng-create seed)]
    (try
      (f rng)
      (finally
        (rng-destroy rng)))))

(defn with-state [n-qubits f]
  "Execute function with quantum state context"
  (let [state (state-create n-qubits)]
    (try
      (f state)
      (finally
        (state-destroy state)))))

(defn with-lattice [nx ny nz coupling f]
  "Execute function with lattice context"
  (let [lat (lattice-create nx ny nz coupling)]
    (try
      (f lat)
      (finally
        (lattice-destroy lat)))))

(defn with-hamiltonian [n-qubits f]
  "Execute function with Hamiltonian context"
  (let [ham (hamiltonian-create n-qubits)]
    (try
      (f ham)
      (finally
        (hamiltonian-destroy ham)))))

;;; =========================================================================
;;; Example Usage
;;; =========================================================================

(defn example-simple-rng []
  "Example: Simple RNG usage with context"
  (with-rng 12345
    (fn [rng]
      (pp (rng-uniform rng))
      (pp (rng-normal rng))
      (pp (rng-integer rng 0 100)))))

(defn example-quantum-circuit []
  "Example: Build and measure quantum circuit"
  (with-state 2
    (fn [state]
      (state-apply-gate state :h 0)
      (let [[outcome prob] (state-measure state 0)]
        (print (string "Measurement: " outcome " with prob " prob))))))

(defn example-lattice-evolution []
  "Example: Evolve quantum lattice over time"
  (with-lattice 4 4 4 1.0
    (fn [lat]
      (loop [i :range [0 10]]
        (let [energy (lattice-energy lat)
              entropy (lattice-entropy lat)]
          (lattice-evolve lat 1)
          (printf "Step %d: E=%f S=%f\n" i energy entropy))))))

(defn example-vqe-ansatz []
  "Example: Variational Quantum Eigensolver setup"
  (with-hamiltonian 2
    (fn [ham]
      (with-state 2
        (fn [state]
          (state-apply-gate state :ry 0 [1.5])
          (state-apply-gate state :rz 0 [0.7])
          (let [[exp-re exp-im] (hamiltonian-expectation ham state)]
            (printf "Expectation: %f + %fi\n" exp-re exp-im)))))))
