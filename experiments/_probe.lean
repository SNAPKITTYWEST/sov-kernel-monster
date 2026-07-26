import Init.Algebra.Order
import Init.Data.Rat.Lemmas
example (k : Rat) : k ^ 0 = 1 := by exact pow_zero k
example (a b c : Rat) (h : a ≤ b) (hc : 0 ≤ c) : c * a ≤ c * b := by exact mul_le_mul_of_nonneg_left h hc
example (k : Rat) (h : 0 < k) : 0 < 1 - k := by exact sub_pos.mpr h
example (a b : Rat) (h : 0 < a) : a ≠ 0 := by exact ne_of_gt h
