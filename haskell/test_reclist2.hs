module Main where

data Foo = Foo { fooId :: Int, name :: String } deriving (Show)

test :: Int -> [Foo]
test n =
  [ Foo
    { fooId = i
    , name = "x"
    }
  | i <- [0..n-1]
  ]

main = return ()
