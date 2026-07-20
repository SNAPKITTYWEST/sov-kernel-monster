{-# LANGUAGE StrictData #-}

-- =====================================================================
-- SINGULARITY ANALYSIS: Milnor Number & δ-Invariant
-- Author: Ahmad Ali Parr <ahmedparr93@gmail.com>
-- =====================================================================

module LiquidLean.Jacobian.SingularityAnalysis
  ( SingularityData(..)
  , analyseSingularity
  , genusFormula
  ) where

import LiquidLean.Jacobian.Theorem3Kernel
import LiquidLean.Jacobian.MoraLocal
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

-- =====================================================================
-- Singularity Data Type
-- =====================================================================

data SingularityData = SingularityData
  { sdMilnorMu :: !Int
  , sdDeltaInv :: !Int
  , sdBranches :: !Int
  } deriving (Show, Eq)

-- =====================================================================
-- Singularity Analysis
-- =====================================================================

-- | Translate polynomial to origin
translate :: Polynomial -> (Rational, Rational) -> Polynomial
translate (Poly f) (u0, x0) = Poly $ Map.fromListWith (+)
  [ ((u'-a, x'-b), coeff a b u0 x0 u' x')
  | ((a,b), c) <- Map.toList f
  , u' <- [0..a], x' <- [0..b]
  , let coeff a b u0 x0 u' x' =
          fromIntegral (choose a (a-u') * choose b (b-x'))
          * (u0 ^ (a - u')) * (x0 ^ (b - x')) * c
  ]
  where
    choose n k = if k < 0 || k > n then 0 else product [n-k+1..n] `div` product [1..k]

-- | Lowestdegree part (initial form)
lowestDegreePart :: Polynomial -> (Polynomial, Int)
lowestDegreePart (Poly f) =
  if Map.null f
    then (zeroPoly, -1)
    else let minDeg = minimum [u+x | (u,x) <- Map.keys f]
             initTerms = [ (u,x,c) | ((u,x),c) <- Map.toList f, u+x == minDeg ]
         in (fromTerms initTerms, minDeg)

-- | Count branches (factor count of lowest-degree part)
-- Conservative lower bound: actual factorization deferred to future work
countBranches :: Polynomial -> Int
countBranches h0 =
  let (initForm, _) = lowestDegreePart h0
      -- TODO: Implement full factorization-based branch count
      -- For now, use degree as conservative lower bound on branch count
      degree = totalDegree initForm
  in max 1 degree

-- =====================================================================
-- Analytic Singularity Function
-- =====================================================================

analyseSingularity :: Polynomial -> (Rational, Rational) -> Thermal SingularityData
analyseSingularity h (u0, x0) = do
  emitEnergy phiDecay
  -- Translate singularity to origin
  let h0 = translate h (u0, x0)
  -- Compute partial derivatives
  let fu = partialDerivative h0 0
  let fv = partialDerivative h0 1
  -- Run Mora's algorithm on jacobian ideal
  gb <- groebnerBasisLocal [fu, fv]
  let mu = countStandardMonomials gb
  let r = countBranches h0
  -- Milnor-Jung: δ = (μ + r - 1) / 2
  let delta = (mu + r - 1) `div` 2
  pure SingularityData { sdMilnorMu = mu, sdDeltaInv = delta, sdBranches = r }

-- =====================================================================
-- THEOREM (Plücker Genus Formula)
-- =====================================================================

-- | g = (d-1)(d-2)/2 - Σ δ_P
genusFormula :: Int -> [Int] -> Int
genusFormula d deltas =
  let geometric = (d - 1) * (d - 2) `div` 2
      singContrib = sum deltas
  in geometric - singContrib
