{-# LANGUAGE GADTs #-}

module SnapKitty.Liquid.Core where

type Proof = ()

{-@ type Nat = {v:Int | 0 <= v} @-}
{-@ type Pos = {v:Int | 0 < v} @-}
{-@ type U16 = {v:Int | 0 <= v && v <= 65535} @-}
{-@ type Prob = {v:Int | 0 <= v && v <= 1000000} @-}

data Pass = Pass | Fail
  deriving (Eq, Show)

{-@ reflect isPass @-}
isPass :: Pass -> Bool
isPass Pass = True
isPass Fail = False
