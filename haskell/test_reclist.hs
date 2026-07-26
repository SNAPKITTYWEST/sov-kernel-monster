module Main where

data Foo = Foo { id :: Int, name :: String } deriving (Show)

test :: Int -> [Foo]
test n =
  [ Foo
    { id = i
    , name = "x"
    }
  | i <- [0..n-1]
  ]

main = return ()
