theory MOCJordanRoundtrip
  imports Main
begin

(* ═══════════════════════════════════════════════════════════════════════════
   MOCJordanRoundtrip.thy — Closes gap 2: MOC 108-dim ↔ Jordan 10×10 roundtrip
   Ahmad Ali Parr · SnapKitty Collective · 2026
   Zero sorry. Pure arithmetic. simp + metis only.
   ═══════════════════════════════════════════════════════════════════════════ *)

definition MOC_DIM  :: nat where "MOC_DIM  = 108"
definition JORDAN_N :: nat where "JORDAN_N = 10"

(* 100 ≤ 108: the matrix fits in the MOC array *)
lemma jordan_fits_in_moc: "JORDAN_N * JORDAN_N ≤ MOC_DIM"
  by (simp add: MOC_DIM_def JORDAN_N_def)

(* Every valid matrix index is a valid MOC index *)
lemma index_bound:
  assumes "i < JORDAN_N" "j < JORDAN_N"
  shows "i * JORDAN_N + j < MOC_DIM"
  using assms by (simp add: MOC_DIM_def JORDAN_N_def)

(* The data region: i*10 + j < 100 *)
lemma in_data_region:
  assumes "i < JORDAN_N" "j < JORDAN_N"
  shows "i * JORDAN_N + j < JORDAN_N * JORDAN_N"
  using assms by (simp add: JORDAN_N_def)

(* Row recovery: (i*10 + j) div 10 = i *)
lemma decode_row:
  assumes "j < JORDAN_N"
  shows "(i * JORDAN_N + j) div JORDAN_N = i"
  using assms by (simp add: JORDAN_N_def)

(* Column recovery: (i*10 + j) mod 10 = j *)
lemma decode_col:
  assumes "j < JORDAN_N"
  shows "(i * JORDAN_N + j) mod JORDAN_N = j"
  using assms by (simp add: JORDAN_N_def)

(* Encoding: (i,j) ↦ i*10 + j *)
definition encode_idx :: "nat ⇒ nat ⇒ nat" where
  "encode_idx i j = i * JORDAN_N + j"

(* Encoding is injective on valid indices *)
lemma encode_injective:
  assumes "i1 < JORDAN_N" "j1 < JORDAN_N"
          "i2 < JORDAN_N" "j2 < JORDAN_N"
          "encode_idx i1 j1 = encode_idx i2 j2"
  shows "i1 = i2 ∧ j1 = j2"
proof
  show "i1 = i2"
    using assms
    by (metis decode_row encode_idx_def)
  show "j1 = j2"
    using assms
    by (metis decode_col encode_idx_def)
qed

(* Encoding + decoding as functions over an arbitrary type 'a *)
definition encode_matrix :: "(nat ⇒ nat ⇒ 'a) ⇒ 'a ⇒ nat ⇒ 'a" where
  "encode_matrix m pad_val k =
    (if k < JORDAN_N * JORDAN_N
     then m (k div JORDAN_N) (k mod JORDAN_N)
     else pad_val)"

definition decode_matrix :: "(nat ⇒ 'a) ⇒ nat ⇒ nat ⇒ 'a" where
  "decode_matrix f i j = f (encode_idx i j)"

(* ═══════════════════════════════════════════════════════
   MAIN THEOREM: decode ∘ encode = id   ZERO SORRY
   ═══════════════════════════════════════════════════════ *)
theorem moc_jordan_roundtrip:
  assumes "i < JORDAN_N" "j < JORDAN_N"
  shows "decode_matrix (encode_matrix m pad_val) i j = m i j"
proof -
  have h_lt  : "encode_idx i j < JORDAN_N * JORDAN_N"
    using assms by (simp add: encode_idx_def JORDAN_N_def)
  have h_row : "(encode_idx i j) div JORDAN_N = i"
    using assms by (simp add: encode_idx_def decode_row)
  have h_col : "(encode_idx i j) mod JORDAN_N = j"
    using assms by (simp add: encode_idx_def decode_col)
  show ?thesis
    by (simp add: decode_matrix_def encode_matrix_def h_lt h_row h_col)
qed

(* COROLLARY: encode is injective — no information lost *)
corollary moc_encode_no_collision:
  assumes "i1 < JORDAN_N" "j1 < JORDAN_N"
          "i2 < JORDAN_N" "j2 < JORDAN_N"
          "encode_matrix m pad_val (encode_idx i1 j1) =
           encode_matrix m pad_val (encode_idx i2 j2)"
  shows "m i1 j1 = m i2 j2"
proof -
  have h1: "encode_idx i1 j1 < JORDAN_N * JORDAN_N"
    using assms by (simp add: encode_idx_def JORDAN_N_def)
  have h2: "encode_idx i2 j2 < JORDAN_N * JORDAN_N"
    using assms by (simp add: encode_idx_def JORDAN_N_def)
  have h_row1: "(encode_idx i1 j1) div JORDAN_N = i1"
    using assms(2) by (simp add: encode_idx_def decode_row)
  have h_col1: "(encode_idx i1 j1) mod JORDAN_N = j1"
    using assms(2) by (simp add: encode_idx_def decode_col)
  have h_row2: "(encode_idx i2 j2) div JORDAN_N = i2"
    using assms(4) by (simp add: encode_idx_def decode_row)
  have h_col2: "(encode_idx i2 j2) mod JORDAN_N = j2"
    using assms(4) by (simp add: encode_idx_def decode_col)
  show ?thesis
    using assms(5)
    by (simp add: encode_matrix_def h1 h2 h_row1 h_col1 h_row2 h_col2)
qed

end
