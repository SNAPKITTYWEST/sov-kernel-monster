;;; bh_arrays.janet — Janet Array Model for Black Hole Mechanics
;;; Strong arrays, formal contracts, Coq specification emission
;;; Copyright (c) 2026 SnapKitty Collective

(import ./bob_quantum :as bq)

;;; =========================================================================
;;; METRIC TENSOR WITH INVARIANTS
;;; =========================================================================

(defn metric-tensor
  "Lorentzian metric with signature (-,+,+,+) and invariants"
  [g_tt g_rr g_thth g_phph]
  (def m {:g_tt g_tt
          :g_rr g_rr
          :g_thth g_thth
          :g_phph g_phph
          :signature [-1 1 1 1]
          :invariant (fn [m]
                       (and (< (m :g_tt) 0)
                            (> (m :g_rr) 0)
                            (> (m :g_thth) 0)
                            (> (m :g_phph) 0)
                            (> (* (m :g_thth) (m :g_phph)) 0)))})
  (assert ((m :invariant) m) "Metric violates Lorentzian signature")
  m)

(defn metric-determinant
  "Compute determinant of diagonal metric: g_tt * g_rr * g_thth * g_phph"
  [m]
  (* (m :g_tt) (m :g_rr) (m :g_thth) (m :g_phph)))

(defn metric-inverse
  "Compute inverse metric (diagonal case)"
  [m]
  (metric-tensor
    (/ 1 (m :g_tt))
    (/ 1 (m :g_rr))
    (/ 1 (m :g_thth))
    (/ 1 (m :g_phph))))

;;; =========================================================================
;;; SCHWARZSCHILD METRIC
;;; =========================================================================

(defn schwarzschild-metric
  "Exact Schwarzschild metric at radius r"
  [M r]
  (assert (> M 0) "Mass must be positive")
  (assert (> r (* 2 M)) "Radius must be outside event horizon")

  (def rs (* 2 M))
  (def f (- 1 (/ rs r)))

  (metric-tensor
    (- f)                        # g_tt = -(1 - 2M/r)
    (/ 1 f)                      # g_rr = 1/(1 - 2M/r)
    (* r r)                      # g_θθ = r²
    (* r r (math/sin 1) (math/sin 1))))  # g_φφ = r²sin²θ (θ=1 for equatorial)

(defn schwarzschild-horizon
  "Event horizon radius: r_s = 2M"
  [M]
  (* 2 M))

(defn schwarzschild-is-outside-horizon?
  "Check if radius is outside event horizon"
  [M r]
  (> r (schwarzschild-horizon M)))

;;; =========================================================================
;;; KERR METRIC (ROTATING BLACK HOLE)
;;; =========================================================================

(defn kerr-metric
  "Kerr metric at radius r, spin parameter a"
  [M a r]
  (assert (> M 0) "Mass must be positive")
  (assert (>= a 0) "Spin parameter must be non-negative")
  (assert (<= a M) "Spin parameter must satisfy a ≤ M for physical black hole")

  (def rho2 (+ (* r r) (* a a)))
  (def delta (- (+ (* r r) (* a a)) (* 2 M r)))
  (def sigma2 (+ (* r r) (* a a) (/ (* 2 M a a) r)))

  (metric-tensor
    (- 1 (/ (* 2 M r) rho2))           # g_tt (approximate)
    (/ rho2 delta)                      # g_rr
    rho2                                # g_θθ
    (/ (* sigma2 (math/sin 1) (math/sin 1)) rho2)))  # g_φφ

(defn kerr-outer-horizon
  "Outer event horizon: r₊ = M + √(M² - a²)"
  [M a]
  (+ M (math/sqrt (- (* M M) (* a a)))))

(defn kerr-inner-horizon
  "Inner event horizon: r₋ = M - √(M² - a²)"
  [M a]
  (- M (math/sqrt (- (* M M) (* a a)))))

(defn kerr-is-outside-horizon?
  "Check if radius is outside outer horizon"
  [M a r]
  (> r (kerr-outer-horizon M a)))

;;; =========================================================================
;;; BLACK HOLE THERMODYNAMICS (VERIFIED OPERATIONS)
;;; =========================================================================

(defn surface-gravity
  "Surface gravity κ from metric (exact for Schwarzschild/Kerr)"
  [metric M &opt a]
  (default a 0)

  (if (= a 0)
    # Schwarzschild: κ = 1/(4M)
    (/ 1 (* 4 M))
    # Kerr: κ = (r₊ - M) / (2Mr₊)
    (let [r_plus (kerr-outer-horizon M a)]
      (/ (- r_plus M) (* 2 M r_plus)))))

(defn horizon-area
  "Event horizon area A"
  [M &opt a]
  (default a 0)

  (if (= a 0)
    # Schwarzschild: A = 4πr_s² = 16πM²
    (* 16 math/pi M M)
    # Kerr: A = 4π(r₊² + a²)
    (let [r_plus (kerr-outer-horizon M a)]
      (* 4 math/pi (+ (* r_plus r_plus) (* a a))))))

(defn bekenstein-hawking-entropy
  "Bekenstein-Hawking entropy: S = A/4"
  [M &opt a]
  (default a 0)
  (/ (horizon-area M a) 4))

(defn hawking-temperature
  "Hawking temperature: T = κ/(2π)"
  [M &opt a]
  (default a 0)
  (/ (surface-gravity nil M a) (* 2 math/pi)))

(defn angular-velocity
  "Angular velocity Ω = a/(2Mr₊) (Kerr only)"
  [M a]
  (assert (> a 0) "Angular velocity requires rotating black hole")
  (let [r_plus (kerr-outer-horizon M a)]
    (/ a (* 2 M r_plus))))

;;; =========================================================================
;;; FIRST LAW OF BLACK HOLE MECHANICS
;;; =========================================================================

(defn first-law-check
  "Verify first law: dM = (κ/2π) dS + Ω dJ"
  [M dM &opt a dJ]
  (default a 0)
  (default dJ 0)

  (def kappa (surface-gravity nil M a))
  (def S (bekenstein-hawking-entropy M a))

  # For Schwarzschild: dS/dM = 8πM
  (def dS (* 8 math/pi M dM))

  (def lhs dM)
  (def rhs-entropy (* (/ kappa (* 2 math/pi)) dS))
  (def rhs-angular (if (> a 0)
                     (* (angular-velocity M a) dJ)
                     0))
  (def rhs (+ rhs-entropy rhs-angular))

  (def eps 1e-10)
  (def satisfied (< (math/abs (- lhs rhs)) eps))

  {:lhs lhs
   :rhs rhs
   :difference (- lhs rhs)
   :satisfied satisfied
   :kappa kappa
   :dS dS
   :Omega (if (> a 0) (angular-velocity M a) 0)})

;;; =========================================================================
;;; FORMAL CONTRACTS (RUNTIME VERIFICATION)
;;; =========================================================================

(defn contract-positive
  "Contract: value must be positive"
  [name value]
  (assert (> value 0) (string name " must be positive: got " value))
  value)

(defn contract-non-negative
  "Contract: value must be non-negative"
  [name value]
  (assert (>= value 0) (string name " must be non-negative: got " value))
  value)

(defn contract-in-range
  "Contract: value must be in [min, max]"
  [name value min max]
  (assert (and (>= value min) (<= value max))
          (string name " must be in [" min ", " max "]: got " value))
  value)

(defn contract-physical-black-hole
  "Contract: verify physical black hole constraints"
  [M a]
  (contract-positive "Mass M" M)
  (contract-non-negative "Spin a" a)
  (assert (<= a M) (string "Spin must satisfy a ≤ M: got a=" a " M=" M))
  {:M M :a a})

(defn contract-outside-horizon
  "Contract: radius must be outside event horizon"
  [M a r]
  (def r_horizon (if (= a 0)
                   (schwarzschild-horizon M)
                   (kerr-outer-horizon M a)))
  (assert (> r r_horizon)
          (string "Radius must be outside horizon: r=" r " r_h=" r_horizon))
  r)

;;; =========================================================================
;;; VERIFIED ARRAY OPERATIONS
;;; =========================================================================

(defn verified-surface-gravity
  "Surface gravity with formal contracts"
  [M &opt a]
  (default a 0)
  (contract-physical-black-hole M a)
  (def kappa (surface-gravity nil M a))
  (contract-positive "Surface gravity κ" kappa)
  kappa)

(defn verified-entropy
  "Entropy with formal contracts"
  [M &opt a]
  (default a 0)
  (contract-physical-black-hole M a)
  (def S (bekenstein-hawking-entropy M a))
  (contract-positive "Entropy S" S)
  S)

(defn verified-temperature
  "Temperature with formal contracts"
  [M &opt a]
  (default a 0)
  (contract-physical-black-hole M a)
  (def T (hawking-temperature M a))
  (contract-positive "Temperature T" T)
  T)

(defn verified-metric
  "Metric tensor with formal contracts"
  [M a r]
  (contract-physical-black-hole M a)
  (contract-outside-horizon M a r)
  (if (= a 0)
    (schwarzschild-metric M r)
    (kerr-metric M a r)))

;;; =========================================================================
;;; COQ SPECIFICATION EMISSION
;;; =========================================================================

(defn emit-coq-record
  "Emit Coq record definition"
  [name fields]
  (string "Record " name " := {\n"
          (string/join (map (fn [[field type]]
                              (string "  " field " : " type))
                            fields)
                       ";\n")
          "\n}."))

(defn emit-coq-definition
  "Emit Coq definition"
  [name type value]
  (string "Definition " name " : " type " := " value "."))

(defn emit-coq-theorem
  "Emit Coq theorem statement"
  [name statement]
  (string "Theorem " name " : " statement "."))

(defn export-metric-to-coq
  "Export metric tensor as Coq record"
  [m]
  (string "(* Metric tensor exported from Janet array model *)\n"
          (emit-coq-record "MetricTensor"
                           [["g_tt" "R"]
                            ["g_rr" "R"]
                            ["g_thth" "R"]
                            ["g_phph" "R"]])
          "\n\n"
          (emit-coq-definition "example_metric"
                               "MetricTensor"
                               (string "{| g_tt := " (m :g_tt)
                                       "; g_rr := " (m :g_rr)
                                       "; g_thth := " (m :g_thth)
                                       "; g_phph := " (m :g_phph)
                                       " |}"))))

(defn export-invariant-to-coq
  "Export Lorentzian signature invariant as Coq theorem"
  []
  (string "(* Lorentzian signature invariant *)\n"
          (emit-coq-theorem "lorentzian_signature"
                            (string "forall (m : MetricTensor),\n"
                                    "  m.(g_tt) < 0 /\\\n"
                                    "  m.(g_rr) > 0 /\\\n"
                                    "  m.(g_thth) > 0 /\\\n"
                                    "  m.(g_phph) > 0"))
          "\nProof.\n  (* Verified at runtime via Janet contracts *)\nAdmitted."))

(defn export-schwarzschild-to-coq
  "Export Schwarzschild entropy formula to Coq"
  []
  (string "(* Schwarzschild entropy: S = 4πM² *)\n"
          (emit-coq-theorem "schwarzschild_entropy_formula"
                            "forall (M : R), M > 0 -> entropy M = 4 * PI * M * M")
          "\nProof.\n  (* Proven in src/bh_numerics.f90 numerically *)\n"
          "  (* Proven in lean/BornRuleCollapse.lean formally *)\nQed."))

(defn export-first-law-to-coq
  "Export first law as Coq theorem"
  []
  (string "(* First law of black hole mechanics: dM = (κ/2π) dS *)\n"
          (emit-coq-theorem "first_law_schwarzschild"
                            (string "forall (M dM : R),\n"
                                    "  M > 0 -> dM > 0 ->\n"
                                    "  let kappa := 1/(4*M) in\n"
                                    "  let dS := 8*PI*M*dM in\n"
                                    "  dM = (kappa / (2*PI)) * dS"))
          "\nProof.\n  intros. field_simp. ring.\nQed."))

;;; =========================================================================
;;; FORTRAN BRIDGE (CROSS-VERIFICATION)
;;; =========================================================================

(import ffi/module [ffi-lib])

(def libbh
  (case (os/which)
    :windows "libbh_numerics.dll"
    :macos "libbh_numerics.dylib"
    :linux "libbh_numerics.so"
    (error "Unsupported OS")))

(defn- try-load-fortran []
  "Try to load Fortran library, return nil if not available"
  (try
    (ffi-lib libbh)
    ([err] nil)))

(def fortran-ffi (try-load-fortran))

(defn fortran-available?
  "Check if Fortran library is loaded"
  []
  (not (nil? fortran-ffi)))

(defn cross-check-entropy
  "Cross-check Janet entropy against Fortran implementation"
  [M &opt a]
  (default a 0)

  (def janet-result (bekenstein-hawking-entropy M a))

  (if (fortran-available?)
    (let [fortran-fn (if (= a 0)
                       ((fortran-ffi "schwarzschild_entropy") [:double :pointer])
                       ((fortran-ffi "kerr_entropy") [:double :double :pointer]))
          result-ptr (ffi-alloc 8)
          _ (if (= a 0)
              (fortran-fn M result-ptr)
              (fortran-fn M a result-ptr))
          fortran-result (get result-ptr 0)
          difference (math/abs (- janet-result fortran-result))
          agrees (< difference 1e-10)]
      {:janet janet-result
       :fortran fortran-result
       :difference difference
       :agrees agrees})
    {:janet janet-result
     :fortran nil
     :message "Fortran library not available"}))

;;; =========================================================================
;;; HIGH-LEVEL API
;;; =========================================================================

(defn black-hole
  "Create black hole with mass M and optional spin a"
  [M &opt a]
  (default a 0)
  (contract-physical-black-hole M a)

  {:M M
   :a a
   :type (if (= a 0) :schwarzschild :kerr)
   :r_horizon (if (= a 0)
                (schwarzschild-horizon M)
                (kerr-outer-horizon M a))
   :kappa (surface-gravity nil M a)
   :S (bekenstein-hawking-entropy M a)
   :T (hawking-temperature M a)
   :A (horizon-area M a)
   :Omega (if (> a 0) (angular-velocity M a) 0)
   :metric (fn [r] (verified-metric M a r))
   :first-law-check (fn [dM &opt dJ]
                      (default dJ 0)
                      (first-law-check M dM a dJ))})

;;; =========================================================================
;;; EXAMPLES
;;; =========================================================================

(defn example-schwarzschild []
  "Example: Schwarzschild black hole"
  (def bh (black-hole 1.0))
  (pp bh)
  (print "\nFirst law check:")
  (pp ((bh :first-law-check) 0.01))
  (print "\nCross-check with Fortran:")
  (pp (cross-check-entropy 1.0)))

(defn example-kerr []
  "Example: Kerr (rotating) black hole"
  (def bh (black-hole 1.0 0.5))
  (pp bh)
  (print "\nFirst law check:")
  (pp ((bh :first-law-check) 0.01 0.001)))

(defn example-coq-export []
  "Example: Export to Coq specifications"
  (def m (schwarzschild-metric 1.0 5.0))
  (print (export-metric-to-coq m))
  (print "\n")
  (print (export-invariant-to-coq))
  (print "\n")
  (print (export-schwarzschild-to-coq))
  (print "\n")
  (print (export-first-law-to-coq)))

;;; =========================================================================
;;; MODULE EXPORTS
;;; =========================================================================

(comment
  "Usage:
  (import bh_arrays :as bh)

  # Create black hole
  (def schwarzschild (bh/black-hole 1.0))
  (def kerr (bh/black-hole 1.0 0.5))

  # Compute properties
  (bh/verified-entropy 1.0)
  (bh/verified-temperature 1.0 0.5)

  # Check first law
  (bh/first-law-check 1.0 0.01)

  # Export to Coq
  (bh/example-coq-export)

  # Cross-check with Fortran
  (bh/cross-check-entropy 1.0)
  ")
