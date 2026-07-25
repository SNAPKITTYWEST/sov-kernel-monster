{-# LANGUAGE BangPatterns #-}

module Main where

test :: Double
test =
  let m_sun = 1.989e30
      g = 6.674e-11
      c = 299792458.0
      rs = 2.0 * g * m_sun / (c * c)
  in rs

main = return ()
