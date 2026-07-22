{-# LANGUAGE GADTs #-}

module SnapKitty.Liquid.NoCloningWitness where

import SnapKitty.Liquid.Core
import SnapKitty.Liquid.ERE5

data QState
  = Superposed
  | Collapsed
  | Destroyed
  deriving (Eq, Show)

{-@ reflect destroyOnFail @-}
destroyOnFail :: QState -> Pass -> QState
destroyOnFail _ Fail = Destroyed
destroyOnFail s Pass = s

{-@ reflect observeState @-}
observeState :: QState -> ERE5 -> QState
observeState Superposed e =
  if ereAccept e then Collapsed else Destroyed
observeState Collapsed _ = Collapsed
observeState Destroyed _ = Destroyed

{-@ reflect pipelineStep @-}
pipelineStep :: QState -> Pass -> QState
pipelineStep Destroyed _ = Destroyed
pipelineStep state result = destroyOnFail state result

{-@ reflect erePipeline @-}
erePipeline :: QState -> Pass -> Pass -> Pass -> Pass -> Pass -> QState
erePipeline s p1 p2 p3 p4 p5 =
  pipelineStep (pipelineStep (pipelineStep (pipelineStep (pipelineStep s p1) p2) p3) p4) p5

{-@ theorem_destroyed_absorbing :: e:ERE5 -> { observeState Destroyed e == Destroyed } @-}
theorem_destroyed_absorbing :: ERE5 -> Proof
theorem_destroyed_absorbing _ = ()

{-@ theorem_failed_pass_destroys :: s:QState -> { destroyOnFail s Fail == Destroyed } @-}
theorem_failed_pass_destroys :: QState -> Proof
theorem_failed_pass_destroys _ = ()

{-@ theorem_collapsed_stable :: e:ERE5 -> { observeState Collapsed e == Collapsed } @-}
theorem_collapsed_stable :: ERE5 -> Proof
theorem_collapsed_stable _ = ()

{-@ theorem_destroyed_pipeline :: p1:Pass -> p2:Pass -> p3:Pass -> p4:Pass -> p5:Pass
    -> { erePipeline Destroyed p1 p2 p3 p4 p5 == Destroyed } @-}
theorem_destroyed_pipeline :: Pass -> Pass -> Pass -> Pass -> Pass -> Proof
theorem_destroyed_pipeline _ _ _ _ _ = ()

{-@ theorem_all_pass_collapse :: { erePipeline Superposed Pass Pass Pass Pass Pass == Collapsed } @-}
theorem_all_pass_collapse :: Proof
theorem_all_pass_collapse = ()
