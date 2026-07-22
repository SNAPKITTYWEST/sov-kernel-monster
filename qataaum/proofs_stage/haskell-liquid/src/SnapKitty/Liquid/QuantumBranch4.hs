{-# LANGUAGE GADTs #-}

module SnapKitty.Liquid.QuantumBranch4 where

import SnapKitty.Liquid.Core

data Tower = EXARP | BITOM | HCOMA | NANTA
  deriving (Eq, Show)

data Branch = Branch
  { bTower  :: Tower
  , bWeight :: Int
  , bPass   :: Pass
  }

{-@
data Branch = Branch
  { bTower  :: Tower
  , bWeight :: Prob
  , bPass   :: Pass
  }
@-}

data Branch4 = Branch4 Branch Branch Branch Branch

{-@ reflect survives @-}
survives :: Branch -> Bool
survives b = isPass (bPass b) && bWeight b > 0

{-@ reflect totalWeight4 @-}
totalWeight4 :: Branch4 -> Int
totalWeight4 (Branch4 a b c d) =
  bWeight a + bWeight b + bWeight c + bWeight d

{-@ theorem_total_weight_nonnegative :: q:Branch4 -> { 0 <= totalWeight4 q } @-}
theorem_total_weight_nonnegative :: Branch4 -> Proof
theorem_total_weight_nonnegative _ = ()

{-@ reflect countSurviving @-}
countSurviving :: Branch4 -> Int
countSurviving (Branch4 a b c d) =
  (if survives a then 1 else 0) +
  (if survives b then 1 else 0) +
  (if survives c then 1 else 0) +
  (if survives d then 1 else 0)

{-@ reflect majorityThreshold @-}
majorityThreshold :: Int
majorityThreshold = 500000

{-@ reflect metatronCertify @-}
metatronCertify :: Branch4 -> Bool
metatronCertify q = totalWeight4 q > majorityThreshold && countSurviving q > 0

exarp :: Branch
exarp = Branch EXARP 250000 Pass

bitom :: Branch
bitom = Branch BITOM 250000 Pass

hcoma :: Branch
hcoma = Branch HCOMA 250000 Pass

nanta :: Branch
nanta = Branch NANTA 250000 Pass

defaultBranch4 :: Branch4
defaultBranch4 = Branch4 exarp bitom hcoma nanta
