{-# LANGUAGE DataKinds, GADTs, OverloadedStrings, RecordWildCards, DeriveGeneric #-}

-- =====================================================================
-- LIQUIDLEAN // IBM QUANTUM RUNTIME CLIENT
-- Qiskit Runtime V2 API Integration
-- Zero dependencies for Phase 2 (mock only)
-- Fortran 2018 / C ABI bridge ready for Phase 3
-- =====================================================================

module LiquidLean.Jacobian.IBMQuantum
  ( IBMQuantumEnv(..)
  , IBMJob(..)
  , JobStatus(..)
  , QuantumCircuit(..)
  , CircuitInstruction(..)
  , PulseSchedule(..)
  , SubmitJobRequest(..)
  , getAvailableBackends
  , getBackendProperties
  , submitJob
  , pollJobStatus
  , getJobResult
  , ibmQuantumInit
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Maybe (fromMaybe)
import Data.List (sortBy)
import Data.Ord (comparing)
import Control.Monad.State.Strict
import Data.Word (Word32, Word16, Word64, Word8)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

-- =====================================================================
-- IBM QUANTUM TYPES
-- =====================================================================

type JobID = Text
type BackendName = Text
type ProgramID = Text

data JobStatus
  = Queued
  | Running
  | Done
  | Failed
  | Cancelled
  deriving (Show, Eq, Ord)

data IBMJob = IBMJob
  { jobId :: JobID
  , jobBackend :: BackendName
  , jobStatus :: JobStatus
  , jobCreationTime :: Word64
  , jobResult :: Maybe JobResult
  } deriving (Show)

data JobResult = JobResult
  { jrCounts :: Map Text Word64
  , jrStatevector :: Maybe [Double]
  } deriving (Show)

data QuantumCircuit = QuantumCircuit
  { qcQubits :: Word16
  , qcClbits :: Word16
  , qcInstructions :: [CircuitInstruction]
  , qcName :: Text
  } deriving (Show)

data CircuitInstruction
  = GateInst Text [Word16] [Double]
  | MeasureInst Word16 Word16
  | ResetInst Word16
  deriving (Show)

data PulseSchedule = PulseSchedule
  { psChannels :: [Text]
  , psDuration :: Word64
  , psLabel :: Text
  } deriving (Show)

-- =====================================================================
-- REQUEST TYPES
-- =====================================================================

data SubmitJobRequest = SubmitJobRequest
  { sjrProgramId :: ProgramID
  , sjrBackend :: BackendName
  , sjrCircuits :: [QuantumCircuit]
  , sjrShots :: Word32
  } deriving (Show)

-- =====================================================================
-- IBM QUANTUM ENVIRONMENT
-- =====================================================================

data IBMQuantumEnv = IBMQuantumEnv
  { iqeAPIKey :: ByteString
  , iqeBaseURL :: Text
  , iqeHub :: Text
  , iqeGroup :: Text
  , iqeProject :: Text
  , iqeBackends :: [BackendInfo]
  , iqeUseRealAPI :: Bool
  } deriving (Show)

data BackendInfo = BackendInfo
  { biName :: Text
  , biStatus :: Text
  , biQubits :: Word16
  , biVersion :: Text
  , biPendingJobs :: Word32
  } deriving (Show)

-- =====================================================================
-- MOCK IBM QUANTUM CLIENT (Phase 2 — feature-gated)
-- =====================================================================

-- | List available backends (mocked for now)
getAvailableBackends :: IBMQuantumEnv -> Either String [BackendInfo]
getAvailableBackends env
  | iqeUseRealAPI env = Right []  -- TODO: Call real IBM Quantum API
  | otherwise = Right
      [ BackendInfo "ibm_nairobi" "active" 7 "1.0.0" 0
      , BackendInfo "ibm_kyiv" "active" 127 "1.0.0" 5
      , BackendInfo "ibm_condor" "maintenance" 1121 "0.9.0" 0
      ]

-- | Get backend properties (mocked for now)
getBackendProperties :: BackendName -> IBMQuantumEnv -> Either String BackendProperties
getBackendProperties backend env
  | iqeUseRealAPI env = Right emptyProps  -- TODO: Call real API
  | otherwise = Right
      BackendProperties
        { bpBackendName = backend
        , bpQubits = fromIntegral $ length [1..10]
        , bpVersion = "1.0.0"
        , bpT1s = replicate 10 50.0  -- 50 μs T1
        , bpT2s = replicate 10 40.0  -- 40 μs T2
        , bpFrequencies = replicate 10 5.0  -- 5 GHz
        }

data BackendProperties = BackendProperties
  { bpBackendName :: Text
  , bpQubits :: Word16
  , bpVersion :: Text
  , bpT1s :: [Double]
  , bpT2s :: [Double]
  , bpFrequencies :: [Double]
  } deriving (Show)

emptyProps :: BackendProperties
emptyProps = BackendProperties "" 0 "" [] [] []

-- | Submit quantum job (mocked for now)
submitJob :: SubmitJobRequest -> IBMQuantumEnv -> Either String JobID
submitJob req env
  | iqeUseRealAPI env = Right ""  -- TODO: Call real API
  | otherwise = Right ("mock_job_" <> T.pack (show (length (sjrCircuits req))))

-- | Poll job status (mocked for now)
pollJobStatus :: JobID -> IBMQuantumEnv -> Either String IBMJob
pollJobStatus jid env
  | iqeUseRealAPI env = Right emptyJob  -- TODO: Call real API
  | otherwise = Right
      IBMJob
        { jobId = jid
        , jobBackend = "ibm_nairobi"
        , jobStatus = Done
        , jobCreationTime = 0
        , jobResult = Just (JobResult (Map.fromList [("0", 4096), ("1", 4096)]) Nothing)
        }

emptyJob :: IBMJob
emptyJob = IBMJob "" "" Failed 0 Nothing

-- | Get job result (polls until done)
getJobResult :: JobID -> IBMQuantumEnv -> Either String JobResult
getJobResult jid env = do
  job <- pollJobStatus jid env
  case jobResult job of
    Just res -> Right res
    Nothing -> Left "Job not yet complete"

-- =====================================================================
-- INITIALIZATION
-- =====================================================================

ibmQuantumInit :: ByteString -> Text -> Bool -> IBMQuantumEnv
ibmQuantumInit apiKey baseUrl useReal = IBMQuantumEnv
  { iqeAPIKey = apiKey
  , iqeBaseURL = baseUrl
  , iqeHub = "ibm-q"
  , iqeGroup = "open"
  , iqeProject = "main"
  , iqeBackends = []
  , iqeUseRealAPI = useReal
  }

-- =====================================================================
-- FORTRAN FFI BRIDGE (Phase 2.5 onwards)
-- =====================================================================

{- TODO: Wire these via QuantumFortranBridge.hs when Phase 2.5 begins

foreign import ccall unsafe "bob_submit_to_ibm_quantum"
  c_submit_to_ibm :: CString -> CInt -> IO CInt

foreign import ccall unsafe "bob_poll_ibm_job"
  c_poll_ibm :: CString -> IO CInt

submitJobViaFortran :: SubmitJobRequest -> IO (Either String JobID)
submitJobViaFortran req = do
  -- TODO: Marshal req to C representation
  -- TODO: Call c_submit_to_ibm
  -- TODO: Return JobID
  pure (Right "job_placeholder")

-}

-- =====================================================================
-- WORM CHAIN INTEGRATION (Phase 2.5)
-- =====================================================================

{- TODO: Wire into bob_worm.f90 when Phase 2.5 begins

attestQuantumJob :: JobID -> JobResult -> WORMChain -> IO ()
attestQuantumJob jid result wc = do
  -- TODO: Create QuantumWORMTx
  -- TODO: Sign with Ed25519
  -- TODO: Append to WORM chain
  pure ()

-}
