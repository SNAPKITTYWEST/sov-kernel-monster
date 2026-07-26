module Main where

data Complex = Complex Double Double deriving (Show)
data Vector = Vector [Double] deriving (Show)
data QuantumBranch = QuantumBranch
  { branchId :: Int
  , branchLabel :: String
  , amplitude :: Complex
  , stateVector :: Vector
  , probability :: Double
  , decoherenceTime :: Double
  } deriving (Show)

vectorAdd :: Vector -> Vector -> Vector
vectorAdd (Vector a) (Vector b) = Vector (zipWith (+) a b)

initializeSuperposition :: String -> Int -> Vector -> [QuantumBranch]
initializeSuperposition regionId numBranches center =
  let initialBranches = [ QuantumBranch
        { branchId = i
        , branchLabel = "branch-" ++ show i
        , amplitude = Complex (1.0 / sqrt (fromIntegral numBranches)) 0.0
        , stateVector = vectorAdd center (Vector [sin (fromIntegral i), cos (fromIntegral i), 0])
        , probability = 1.0 / fromIntegral numBranches
        , decoherenceTime = 1.0 / fromIntegral (i + 1)  -- Different rates per branch
        }
      | i <- [0..numBranches-1]
      ]
  in initialBranches

main = return ()
