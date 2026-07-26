module Main where

test :: [Int]
test =
  let x = 5
  in [ i
     | i <- [0..x-1]
     ]

main = return ()
