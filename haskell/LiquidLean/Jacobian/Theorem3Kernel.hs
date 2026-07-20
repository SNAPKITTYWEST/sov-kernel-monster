{-# LANGUAGE DataKinds, GADTs, KindSignatures, TypeOperators, ScopedTypeVariables #-}
{-# LANGUAGE StrictData, BangPatterns, PatternSynonyms, ViewPatterns #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- =====================================================================
-- LIQUIDLEAN // THEOREM 3 CRACK: KERNEL & TYPES
-- Target: Genus-0 Forcing via δ-Invariants + Mora Standard Bases
-- Author: Ahmad Ali Parr <ahmedparr93@gmail.com>
-- =====================================================================

module LiquidLean.Jacobian.Theorem3Kernel
  ( Z
  , Polynomial(..)
  , RationalFunction(..)
  , LocalMonomial(..)
  , Thermal(..)
  , Energy(..)
  , Obstruction(..)
  , Result
  , phiDecay
  , emitEnergy
  , zeroPoly
  , onePoly
  , addPoly
  , subPoly
  , mulPoly
  , scalePoly
  , partialDerivative
  , evaluate
  , totalDegree
  , leadingTermLocal
  , isZeroPoly
  , terms
  , fromTerms
  , variable
  , monomial
  ) where

import Prelude hiding (Rational)
import GHC.TypeLits (Nat, KnownNat, natVal)
import Data.Ratio (Ratio, denominator, numerator)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Control.Monad.State.Strict

-- | Exact rationals (redefine to avoid shadowing Prelude.Rational in type sigs)
type Rational = Ratio Integer
type Z = Integer

-- | Polynomial in ℚ[u, x] (sparse representation)
newtype Polynomial = Poly { unPoly :: Map (Int, Int) Rational }
  deriving (Eq, Show, Ord)

-- | Rational function f/g
data RationalFunction = RF { rfNum :: !Polynomial, rfDen :: !Polynomial }
  deriving (Eq, Show)

-- | Monomial in ds-order (degree ascending, lex descending)
data LocalMonomial = LM { lmU :: !Int, lmX :: !Int }
  deriving (Eq, Show)

instance Ord LocalMonomial where
  compare (LM u1 x1) (LM u2 x2) =
    case compare (u1 + x1) (u2 + x2) of
      EQ -> compare u2 u1 <> compare x2 x1
      o -> o

-- | Thermal monad: energy-accounting computation
newtype Thermal a = Thermal { runThermal :: State Energy a }
  deriving (Functor, Applicative, Monad, MonadState Energy)

data Energy = Energy { spent :: !Integer, budget :: !Integer }
  deriving (Show)

-- | Obstruction types (total error handling)
data Obstruction
  = NotIsolatedSingularity String
  | HigherGenusObstruction Int
  | NonRationalCurve String
  | AdjointSystemDegenerate String
  | VerificationFailure String
  | PointNotOnCurve (Rational, Rational)
  | SingularBasePoint (Rational, Rational)
  | ConicFactorizationFailed
  | DivisionByZero String
  deriving (Show, Eq)

type Result a = Either Obstruction a

-- | Energy constant (φ⁻¹ discretized)
phiDecay :: Integer
phiDecay = 1

emitEnergy :: Integer -> Thermal ()
emitEnergy n = Thermal $ modify $ \e -> e { spent = spent e + n }

-- =====================================================================
-- Polynomial Operations (Total Functions)
-- =====================================================================

zeroPoly, onePoly :: Polynomial
zeroPoly = Poly Map.empty
onePoly = Poly (Map.singleton (0,0) 1)

addPoly, subPoly, mulPoly :: Polynomial -> Polynomial -> Polynomial
addPoly (Poly f) (Poly g) = Poly (Map.unionWith (+) f g)
subPoly (Poly f) (Poly g) = Poly (Map.unionWith (-) f g)
mulPoly (Poly f) (Poly g) = Poly $ Map.fromListWith (+)
  [ ((u1+u2, x1+x2), c1*c2) | ((u1,x1),c1) <- Map.toList f
                             , ((u2,x2),c2) <- Map.toList g
                             , c1*c2 /= 0 ]

scalePoly :: Rational -> Polynomial -> Polynomial
scalePoly c (Poly f) = Poly (Map.map (c*) f)

-- =====================================================================
-- Differential & Evaluation
-- =====================================================================

partialDerivative :: Polynomial -> Int -> Polynomial
partialDerivative (Poly f) v = Poly $ Map.fromList
  [ ((if v == 0 then u-1 else u, if v == 0 then x else x-1), c * fromIntegral (if v == 0 then u else x))
  | ((u,x), c) <- Map.toList f
  , (v == 0 && u > 0) || (v /= 0 && x > 0)
  ]

evaluate :: Polynomial -> [Rational] -> Rational
evaluate (Poly f) vals =
  sum [ c * (u^u') * (x^x')
      | ((u',x'),c) <- Map.toList f
      , let u = if null vals then 0 else vals !! 0
      , let x = if length vals < 2 then 0 else vals !! 1
      ]

-- =====================================================================
-- Basic Queries
-- =====================================================================

totalDegree :: Polynomial -> Int
totalDegree (Poly f) = if Map.null f then -1 else maximum [u+x | (u,x) <- Map.keys f]

leadingTermLocal :: Polynomial -> (Rational, LocalMonomial)
leadingTermLocal (Poly f) =
  if Map.null f
    then (0, LM 0 0)
    else let (lm, c) = Map.foldlWithKey (\acc (u,x) c ->
                let lm' = LM u x
                in if lm' < fst acc then (lm', c) else acc)
                (LM maxBound maxBound, 0) f
         in (c, lm)

isZeroPoly :: Polynomial -> Bool
isZeroPoly (Poly f) = Map.null f

terms :: Polynomial -> [(Int, Int, Rational)]
terms (Poly f) = [ (u,x,c) | ((u,x),c) <- Map.toList f, c /= 0 ]

fromTerms :: [(Int, Int, Rational)] -> Polynomial
fromTerms = Poly . Map.fromListWith (+) . map (\(u,x,c) -> ((u,x),c)) . filter (\(_,_,c)->c/=0)

-- =====================================================================
-- Variables & Monomials
-- =====================================================================

variable :: Int -> Polynomial
variable 0 = monomial 1 0  -- u
variable 1 = monomial 0 1  -- x
variable i = error ("variable: unsupported index " ++ show i)

monomial :: Int -> Int -> Polynomial
monomial u x = Poly (Map.singleton (u,x) 1)
