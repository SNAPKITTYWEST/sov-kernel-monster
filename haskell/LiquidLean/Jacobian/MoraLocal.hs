{-# LANGUAGE StrictData #-}

-- =====================================================================
-- MORA'S STANDARD BASIS ALGORITHM (Local Ring ℂ[[u,x]])
-- Author: Ahmad Ali Parr <ahmedparr93@gmail.com>
-- =====================================================================

module LiquidLean.Jacobian.MoraLocal
  ( weakNF
  , groebnerBasisLocal
  , countStandardMonomials
  , dividesLocal
  ) where

import LiquidLean.Jacobian.Theorem3Kernel
import qualified Data.Map.Strict as Map

-- =====================================================================
-- Weak Normal Form (Mora Reduction)
-- =====================================================================

weakNF :: [Polynomial] -> Polynomial -> Polynomial
weakNF basis f = go f
  where
    go h | isZeroPoly h = h
         | otherwise = case findReducer basis h of
             Nothing -> h
             Just (g, coeff, lmDiff) ->
               go (subPoly h (scalePoly coeff (mulPoly g (uncurry monomial lmDiff))))

    findReducer :: [Polynomial] -> Polynomial -> Maybe (Polynomial, Rational, (Int, Int))
    findReducer [] _ = Nothing
    findReducer (g:gs) h =
      let (ltH, lmH) = leadingTermLocal h
          (ltG, lmG) = leadingTermLocal g
      in if dividesLocal lmG lmH
            then Just (g, ltH / ltG, monomialDiff lmH lmG)
            else findReducer gs h

-- | Local divisibility: lm1 divides lm2 iff deg(lm1) ≤ deg(lm2) and both exps fit
dividesLocal :: LocalMonomial -> LocalMonomial -> Bool
dividesLocal (LM u1 x1) (LM u2 x2) = u1 <= u2 && x1 <= x2

monomialDiff :: LocalMonomial -> LocalMonomial -> (Int, Int)
monomialDiff (LM u1 x1) (LM u2 x2) = (u2 - u1, x2 - x1)

-- =====================================================================
-- Mora's Algorithm (Tangent Cone Variant)
-- =====================================================================

groebnerBasisLocal :: [Polynomial] -> Thermal [Polynomial]
groebnerBasisLocal fs = do
  emitEnergy phiDecay
  let tc0 = map leadingForm fs
  moraLoop tc0 fs []
  where
    leadingForm p =
      let (c, LM u x) = leadingTermLocal p
      in if c == 0 then zeroPoly else scalePoly c (monomial u x)

    moraLoop :: [Polynomial] -> [Polynomial] -> [Polynomial] -> Thermal [Polynomial]
    moraLoop tangentCone [] acc = pure (reverse acc ++ tangentCone)
    moraLoop tangentCone (f:fs) acc = do
      emitEnergy phiDecay
      let nf = weakNF tangentCone f
      if isZeroPoly nf
        then moraLoop tangentCone fs acc
        else do
          let newTC = leadingForm nf : tangentCone
          moraLoop newTC fs (nf : acc)

-- =====================================================================
-- Standard Monomial Counting (μ = dim ℂ[[u,x]] / ⟨LT(GB)⟩)
-- =====================================================================

countStandardMonomials :: [Polynomial] -> Int
countStandardMonomials gb =
  let lms = map (snd . leadingTermLocal) gb
      maxDeg = if null lms then 1 else 2 * maximum [lmU lm + lmX lm | lm <- lms]
      isStd (LM u x) = all (\(LM a b) -> a > u || b > x) lms
  in length [ () | u <- [0..maxDeg], x <- [0..maxDeg], u+x <= maxDeg, isStd (LM u x) ]
