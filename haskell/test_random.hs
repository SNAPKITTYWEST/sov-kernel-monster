import System.Random

test :: StdGen -> (Int, StdGen)
test gen = randomR (1, 10) gen

main = return ()
