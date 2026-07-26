{-# LANGUAGE GADTs #-}

module SnapKitty.Liquid.Receipt where

import SnapKitty.Liquid.Core

data ReceiptInput = RI
  { riAgent :: Int
  , riIndex :: Int
  , riHash  :: Int
  }

{-@
data ReceiptInput = RI
  { riAgent :: Nat
  , riIndex :: Nat
  , riHash  :: Nat
  }
@-}

{-@ reflect sameReceiptInput @-}
sameReceiptInput :: ReceiptInput -> ReceiptInput -> Bool
sameReceiptInput a b =
     riAgent a == riAgent b
  && riIndex a == riIndex b
  && riHash  a == riHash  b

{-@ theorem_receipt_reflexive :: r:ReceiptInput -> { sameReceiptInput r r } @-}
theorem_receipt_reflexive :: ReceiptInput -> Proof
theorem_receipt_reflexive _ = ()

{-@ theorem_receipt_symmetric :: a:ReceiptInput -> b:ReceiptInput
    -> { sameReceiptInput a b ==> sameReceiptInput b a } @-}
theorem_receipt_symmetric :: ReceiptInput -> ReceiptInput -> Proof
theorem_receipt_symmetric _ _ = ()

{-@ theorem_receipt_transitive :: a:ReceiptInput -> b:ReceiptInput -> c:ReceiptInput
    -> { sameReceiptInput a b && sameReceiptInput b c ==> sameReceiptInput a c } @-}
theorem_receipt_transitive :: ReceiptInput -> ReceiptInput -> ReceiptInput -> Proof
theorem_receipt_transitive _ _ _ = ()

{-@ reflect validReceipt @-}
validReceipt :: ReceiptInput -> Bool
validReceipt r = riAgent r >= 0 && riIndex r >= 0 && riHash r >= 0

{-@ theorem_valid_receipt_nonneg :: r:{ReceiptInput | validReceipt r}
    -> { riAgent r >= 0 && riIndex r >= 0 && riHash r >= 0 } @-}
theorem_valid_receipt_nonneg :: ReceiptInput -> Proof
theorem_valid_receipt_nonneg _ = ()
