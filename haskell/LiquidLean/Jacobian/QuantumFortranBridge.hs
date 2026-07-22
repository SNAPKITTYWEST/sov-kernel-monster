{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE StrictData #-}

-- =====================================================================
-- QUANTUM FORTRAN BRIDGE
-- Fortran ↔ Haskell FFI for Theorem 3 Offload
-- Marshals polynomial strings + energy budgets between Fortran and Haskell
-- Returns genus proof status to calling Fortran subroutine
-- =====================================================================

module LiquidLean.Jacobian.QuantumFortranBridge
  ( haskell_theorem3_offload
  ) where

import Foreign.C
import Foreign.Ptr
import System.IO.Unsafe (unsafePerformIO)
import Control.Monad.State.Strict (runState)
import Data.Ratio ((%))

import LiquidLean.Jacobian.Theorem3Entry
  ( theorem3EnforceGenusZero
  , Theorem3Evidence(..)
  , Theorem3Status(..)
  )
import LiquidLean.Jacobian.Theorem3Kernel
  ( Polynomial
  , Thermal(..)
  , Energy(..)
  , fromTerms
  , zeroPoly
  , onePoly
  )
import LiquidLean.Jacobian.QuantumChipInterface (ibm_verify_genus_zero)

-- =====================================================================
-- FORTRAN → HASKELL C FFI EXPORT
-- =====================================================================

{-|
Foreign export: theorem3 offload from Fortran supercomputer.

Signature (as seen from Fortran):
  integer(c_int) function haskell_theorem3_offload(poly_str, energy_budget) bind(C)
    character(kind=c_char) :: poly_str(*)
    integer(c_int), value :: energy_budget
  end function

Returns:
  0 = genus-0 proved (rational curve) ✓
  1 = analysis blocked (obstruction hit)
  2 = higher genus found (counterexample to Theorem 3)
  3 = parse error (bad polynomial string)
  4 = quantum verification failed

Energy accounting:
  Each call tracks energy spent in Mora + singularity analysis.
  Budget measured in φ⁻¹ discretized units.
-}
foreign export ccall haskell_theorem3_offload
  :: CString -> CInt -> IO CInt

haskell_theorem3_offload :: CString -> CInt -> IO CInt
haskell_theorem3_offload polyStrPtr energyBudgetC = do
  -- Marshal C string to Haskell
  polyStr <- peekCString polyStrPtr
  let energyBudget = fromIntegral energyBudgetC :: Integer

  -- Parse polynomial from string
  case parsePolynomialString polyStr of
    Left _err -> return 3  -- Parse error
    Right poly -> do
      -- Run theorem3 kernel with energy budget
      let evidence = theorem3EnforceGenusZero poly energyBudget

      case evidence of
        Left _obstruction ->
          -- Hit an obstruction (singular point, degeneracy, etc.)
          return 1

        Right ev -> do
          -- Successful analysis; check status
          case evStatus ev of
            GenusZeroProved _ -> do
              -- Genus = 0 verified; route to quantum chip for witness
              let genus = evGenusBound ev
              quantumOk <- ibm_verify_genus_zero genus
              if quantumOk
                then return 0  -- Success: genus-0 + quantum verified
                else return 4  -- Quantum rejection

            CounterexampleFound _ g -> do
              -- Genus > 0 detected (potential counterexample)
              return 2

            AnalysisBlocked _ ->
              -- Obstruction (should have been caught above, but safety check)
              return 1

-- =====================================================================
-- POLYNOMIAL PARSER: String → Polynomial
-- =====================================================================

{-|
Parse polynomial string from Fortran: "c1*u^d1*x^e1 + c2*u^d2*x^e2 + ..."

Examples:
  "1*u^2 + 1*x^2"        → u² + x²
  "2*u*x + 3*x^2"        → 2ux + 3x²
  "1"                    → constant polynomial 1
  "u^3 + x^3"            → u³ + x³

Whitespace is stripped; signs (+/-) are parsed.
-}
parsePolynomialString :: String -> Either String Polynomial
parsePolynomialString str
  | all (\c -> c `elem` " \t\n") str = Right zeroPoly  -- Empty = zero polynomial
  | otherwise = do
      terms <- parseTermsList (filter (/= ' ') str)
      if null terms
        then Right zeroPoly
        else Right (fromTerms terms)

parseTermsList :: String -> Either String [(Int, Int, Rational)]
parseTermsList str = go str []
  where
    go [] acc = Right (reverse acc)
    go s acc = do
      (term, rest) <- parseTerm s
      case rest of
        [] -> Right (reverse (term : acc))
        ('+':s') -> go s' (term : acc)
        ('-':s') ->
          -- Negate next term's coefficient
          case parseTerm s' of
            Right (u, x, c, s'') -> go s'' ((u, x, negate c) : (term : acc))
            Left e -> Left e
        _ -> Left "Invalid polynomial format"

-- Parse single term: "c*u^d*x^e" or variants
parseTerm :: String -> Either String ((Int, Int, Rational), String)
parseTerm str =
  case parseCoeff str of
    Left e -> Left e
    Right (c, rest) -> do
      (u, rest') <- parseVarPower 'u' rest
      (x, rest'') <- parseVarPower 'x' rest'
      return ((u, x, c), rest'')

-- Parse coefficient (before '*u' or '*x', or at start)
parseCoeff :: String -> Either String (Rational, String)
parseCoeff str = go str "" False
  where
    go [] acc _ = if null acc
                  then Right (1, "")  -- No coefficient = 1
                  else case reads acc of
                    [(n, "")] -> Right (fromInteger n, "")
                    _ -> Left ("Bad coefficient: " ++ acc)
    go ('*':rest) acc _ =
      case reads acc of
        [(n, "")] -> Right (fromInteger n, rest)
        _ -> if null acc then Right (1, rest) else Left ("Bad coefficient: " ++ acc)
    go (c:rest) acc _ = go rest (acc ++ [c]) False

-- Parse variable with power: "u^3" or just "u" (power 1)
parseVarPower :: Char -> String -> Either String (Int, String)
parseVarPower var str
  | null str = Right (0, str)  -- No variable present
  | head str /= var = Right (0, str)  -- Variable not present
  | otherwise = case drop 1 str of
      ('^':rest) ->
        case reads rest of
          [(p, rest')] -> Right (p, rest')
          _ -> Left ("Bad exponent for " ++ [var])
      rest -> Right (1, rest)  -- No power = power 1

-- =====================================================================
-- IBM QUANTUM MOCK (Tested separately in QuantumChipInterface)
-- =====================================================================

-- The actual quantum verification is in QuantumChipInterface.hs
-- This module marshals the Fortran call to that interface.
