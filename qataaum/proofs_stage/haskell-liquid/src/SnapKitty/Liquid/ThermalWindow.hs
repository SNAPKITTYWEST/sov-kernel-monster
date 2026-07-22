{-# LANGUAGE GADTs #-}

module SnapKitty.Liquid.ThermalWindow where

import SnapKitty.Liquid.Core

data ThermalWindow = TW
  { twLo   :: Int
  , twHi   :: Int
  , twSpan :: Int
  }

{-@
data ThermalWindow = TW
  { twLo   :: U16
  , twHi   :: {v:U16 | twLo < v}
  , twSpan :: {v:Pos | v == twHi - twLo}
  }
@-}

{-@ mkWindow :: lo:U16 -> hi:{v:U16 | lo < v} -> ThermalWindow @-}
mkWindow :: Int -> Int -> ThermalWindow
mkWindow lo hi = TW lo hi (hi - lo)

{-@ theorem_window_order :: w:ThermalWindow -> { twLo w < twHi w } @-}
theorem_window_order :: ThermalWindow -> Proof
theorem_window_order _ = ()

{-@ theorem_window_span_positive :: w:ThermalWindow -> { 0 < twSpan w } @-}
theorem_window_span_positive :: ThermalWindow -> Proof
theorem_window_span_positive _ = ()

computeThermalWindow :: Int -> ThermalWindow
computeThermalWindow f =
  let lo = min 16383 (max 0 (round (fromIntegral f * 16383.0 :: Double)))
      hi = max 49151 (min 65535 (65535 - round (fromIntegral f * 16384.0 :: Double)))
  in mkWindow lo hi
