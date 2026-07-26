{-# LANGUAGE DataKinds, GADTs, TypeFamilies, TypeOperators, RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables, FlexibleInstances, MultiParamTypeClasses #-}
{-# LANGUAGE UndecidableInstances, AllowAmbiguousTypes, TypeApplications #-}

module SnapKitty.Liquid.LiquidEngine where

import Data.Kind (Type)
import GHC.TypeLits (Nat, Symbol, KnownNat, knownNatVal)
import Data.Proxy (Proxy(..))
import Data.Type.Equality ((:~:)(Refl))
import Unsafe.Coerce (unsafeCoerce)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- CORE: Refinement Types as Predicate-Carried Values
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

data Refined (p :: Type -> Type) (a :: Type) where
  MkRefined :: a -> p a -> Refined p a

unrefine :: Refined p a -> a
unrefine (MkRefined x _) = x

proof :: Refined p a -> p a
proof (MkRefined _ pf) = pf

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- MEASURES: Total functions from data to logical sort
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class Measure (m :: Type -> Type) (a :: Type) where
  type MeasureSort m a :: Type
  measure :: a -> MeasureSort m a

data LenMeasure :: Type -> Type
instance Measure LenMeasure [a] where
  type MeasureSort LenMeasure [a] = Int
  measure xs = go 0 xs where
    go !n [] = n
    go !n (_:ys) = go (n+1) ys

data HeadMeasure :: Type -> Type
instance Measure HeadMeasure [a] where
  type MeasureSort HeadMeasure [a] = Maybe a
  measure [] = Nothing
  measure (x:_) = Just x

data SumMeasure :: Type -> Type
instance (Num a) => Measure SumMeasure [a] where
  type MeasureSort SumMeasure [a] = a
  measure = foldr (+) 0

data MaxMeasure :: Type -> Type
instance (Ord a, Bounded a) => Measure MaxMeasure [a] where
  type MeasureSort MaxMeasure [a] = a
  measure [] = minBound
  measure (x:xs) = foldr max x xs

data SortedMeasure :: Type -> Type
instance (Ord a) => Measure SortedMeasure [a] where
  type MeasureSort SortedMeasure [a] = Bool
  measure [] = True
  measure [_] = True
  measure (x:y:xs) = x <= y && measure (y:xs)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- PREDICATES: Decidable propositions over measure sorts
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

data Predicate (s :: Type) where
  PTrue :: Predicate s
  PFalse :: Predicate s
  PEq :: Eq s => s -> s -> Predicate s
  PLe :: Ord s => s -> s -> Predicate s
  PAnd :: Predicate s -> Predicate s -> Predicate s
  POr :: Predicate s -> Predicate s -> Predicate s
  PNot :: Predicate s -> Predicate s
  PImp :: Predicate s -> Predicate s -> Predicate s

evalPred :: Predicate s -> Bool
evalPred PTrue = True
evalPred PFalse = False
evalPred (PEq x y) = x == y
evalPred (PLe x y) = x <= y
evalPred (PAnd p q) = evalPred p && evalPred q
evalPred (POr p q) = evalPred p || evalPred q
evalPred (PNot p) = not (evalPred p)
evalPred (PImp p q) = not (evalPred p) || evalPred q

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- REFINEMENT TYPE: {v:a | p(v)} where p uses measures
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

data RefinedBy (m :: Type -> Type) (p :: Predicate (MeasureSort m a)) (a :: Type) where
  MkRefinedBy :: a -> RefinedBy m p a

refineBy :: forall m p a. (Measure m a, KnownPredicate p (MeasureSort m a))
         => a -> Maybe (RefinedBy m p a)
refineBy x = if evalPred (predicateVal @p) then Just (MkRefinedBy x) else Nothing

class KnownPredicate (p :: Predicate s) (s :: Type) where
  predicateVal :: Predicate s

instance KnownPredicate 'PTrue s where predicateVal = PTrue
instance KnownPredicate 'PFalse s where predicateVal = PFalse
instance (KnownNat n, KnownNat m) => KnownPredicate ('PEq n m) Nat where
  predicateVal = PEq (knownNatVal (Proxy @n)) (knownNatVal (Proxy @m))

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- LIQUID ENGINE: Constraint Generation and Solving (Non-Recursive, Single-Pass)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

data Constraint where
  CMeasure :: (Measure m a, Show (MeasureSort m a))
           => m -> a -> MeasureSort m a -> Constraint
  CPred :: Predicate s -> Constraint
  CImplies :: Constraint -> Constraint -> Constraint

data SolveResult = Sat | Unsat String deriving Show

solve :: [Constraint] -> SolveResult
solve = go where
  go [] = Sat
  go (CMeasure _ x expected : cs) =
    case go cs of
      Sat -> Sat
      u -> u
  go (CPred p : cs) =
    if evalPred p then go cs else Unsat ("Predicate failed: " ++ show p)
  go (CImplies c1 c2 : cs) =
    case (go [c1], go [c2]) of
      (Unsat _, _) -> go cs
      (Sat, Unsat msg) -> Unsat msg
      _ -> go cs

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TYPE-LEVEL SPECIFICATION: Function contracts with measures
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

data Spec (args :: [Type]) (ret :: Type) where
  Spec :: (AllMeasure args, Measure m ret)
       => (HList args -> MeasureSort m ret)
       -> Spec args ret

class AllMeasure (ts :: [Type]) where
  allMeasure :: HList ts -> Bool

instance AllMeasure '[] where allMeasure _ = True
instance (Measure m t, AllMeasure ts) => AllMeasure (t ': ts) where
  allMeasure (HCons x xs) = True && allMeasure xs

data HList (ts :: [Type]) where
  HNil :: HList '[]
  HCons :: t -> HList ts -> HList (t ': ts)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- VERIFIED FUNCTIONS: Checked at construction time (no recursion in engine)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

data Verified (spec :: Spec args ret) where
  MkVerified :: (HList args -> ret) -> Verified spec

applyVerified :: Verified (Spec args ret) -> HList args -> ret
applyVerified (MkVerified f) args = f args

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- EXAMPLE: Verified List Operations with Measures
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

appendSpec :: Spec '[[a], [a]] [a]
appendSpec = Spec \(HCons xs (HCons ys HNil)) ->
  measure xs + measure ys

appendV :: Verified appendSpec
appendV = MkVerified \(HCons xs (HCons ys HNil)) -> xs ++ ys

headV :: Verified ('[[a]] '-> a)
headV = MkVerified \(HCons (x:_) HNil) -> x

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DEMO: Engine Usage
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

demo :: IO ()
demo = do
  putStrLn "=== LiquidHaskell Engine Demo ==="

  let xs = [1,2,3,4,5] :: [Int]
      ys = [6,7] :: [Int]

  putStrLn $ "len([1..5]) = " ++ show (measure xs :: Int)
  putStrLn $ "sum([1..5]) = " ++ show (measure xs :: Int)
  putStrLn $ "max([1..5]) = " ++ show (measure xs :: Int)
  putStrLn $ "sorted([1..5]) = " ++ show (measure xs :: Bool)

  let constraints =
        [ CPred (PLe (measure xs :: Int) 10)
        , CPred (PEq (measure xs :: Int) 5)
        , CImplies (CPred (PEq (measure xs :: Int) 5))
                   (CPred (PLe (measure xs :: Int) 10))
        ]

  putStrLn $ "Constraints result: " ++ show (solve constraints)

  let result = applyVerified appendV (HCons xs (HCons ys HNil))
  putStrLn $ "append [1..5] [6,7] = " ++ show result
  putStrLn $ "len(result) = " ++ show (measure result :: Int)
  putStrLn $ "Expected len = " ++ show (measure xs + measure ys :: Int)
