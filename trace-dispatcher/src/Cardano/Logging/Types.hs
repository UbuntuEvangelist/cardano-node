{-# LANGUAGE DefaultSignatures          #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralisedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE TypeSynonymInstances       #-}



module Cardano.Logging.Types where

import           Control.Tracer
import qualified Control.Tracer as T
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import qualified Data.HashMap.Strict as HM
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Text (Text)
import           GHC.Generics


-- | Every message needs this to define how to represent it
class LogFormatting a where
  -- | Machine readable representation with the possibility to represent
  -- with different details based on the detail level.
  -- Falls back to ToJson of Aeson in the default representation
  forMachine :: DetailLevel -> a -> A.Object
  default forMachine :: A.ToJSON a => DetailLevel -> a -> A.Object
  forMachine _ v = case A.toJSON v of
    A.Object o     -> o
    s@(A.String _) -> HM.singleton "string" s
    _              -> mempty

  -- | Human readable representation.
  forHuman :: a -> Text
  forHuman v = ""

  -- | Metrics representation.
  -- No metrics by default
  asMetrics :: a -> [Metric]
  asMetrics v = []

-- -- ||| Alternatively:
-- data LogFormatter a = LogFormatter {
--     -- | Machine readable representation with the possibility of representation
--     -- with different detail levels.
--     -- Can use ToJson of Aeson as default
--     machineRep :: DetailLevel -> a -> A.Object
--   , -- | Human readable representation.
--     -- An empty String represents no representation
--     humanRep   :: a -> Text
--   , -- | Metrics representation.
--     -- May be empty, meaning no metrics
--     metricsRep :: a -> [Metric]
-- }

data Metric
  -- | An integer metric.
  -- If a text is given it is appended as last element to the namespace
    = IntM (Maybe Text) Integer
  -- | A double metric.
  -- If a text is given it is appended as last element to the namespace
    | DoubleM (Maybe Text) Double
  deriving (Show, Eq, Generic)

type Namespace = [Text]
type Selector  = [Text]

-- | Context of a message
data LoggingContext = LoggingContext {
    lcContext  :: Namespace
  , lcSeverity :: Maybe SeverityS
  , lcPrivacy  :: Maybe Privacy
  , lcDetails  :: Maybe DetailLevel
  }
  deriving (Eq, Show, Generic)

-- | Tracer comes from the contra-tracer package and carries a context and maybe a trace
-- control object
newtype Trace m a = Trace {unpackTrace :: Tracer m (LoggingContext, Maybe TraceControl, a)}

-- | Contramap lifted to Trace
instance Monad m => Contravariant (Trace m) where
--  contravariant :: Monad m => (a -> b) -> Trace m b -> Trace m a
    contramap f (Trace tr) = Trace $
      T.contramap (\ (lc, mbC, a) -> (lc, mbC, f a)) tr

-- | @tr1 <> tr2@ will run @tr1@ and then @tr2@ with the same input.
instance Monad m => Semigroup (Trace m a) where
  Trace a1 <> Trace a2 = Trace (a1 <> a2)

instance Monad m => Monoid (Trace m a) where
    mappend = (<>)
    mempty  = Trace T.nullTracer

emptyLoggingContext :: LoggingContext
emptyLoggingContext = LoggingContext [] Nothing Nothing Nothing

-- | Formerly known as verbosity
data DetailLevel = DBrief | DRegular | DDetailed
  deriving (Show, Eq, Ord, Bounded, Enum, Generic)

-- | Privacy of a message
data Privacy =
      Public                    -- ^ can be public.
    | Confidential              -- ^ confidential information - handle with care
  deriving (Show, Eq, Ord, Bounded, Enum, Generic)

-- | Severity of a message
data SeverityS
    = Debug                   -- ^ Debug messages
    | Info                    -- ^ Information
    | Notice                  -- ^ Normal runtime Conditions
    | Warning                 -- ^ General Warnings
    | Error                   -- ^ General Errors
    | Critical                -- ^ Severe situations
    | Alert                   -- ^ Take immediate action
    | Emergency               -- ^ System is unusable
  deriving (Show, Eq, Ord, Bounded, Enum, Generic)

-- | Severity for a filter
data SeverityF
    = DebugF                   -- ^ Debug messages
    | InfoF                    -- ^ Information
    | NoticeF                  -- ^ Normal runtime Conditions
    | WarningF                 -- ^ General Warnings
    | ErrorF                   -- ^ General Errors
    | CriticalF                -- ^ Severe situations
    | AlertF                   -- ^ Take immediate action
    | EmergencyF               -- ^ System is unusable
    | SilenceF                 -- ^ Don't show anything
  deriving (Show, Eq, Ord, Bounded, Enum, Generic)

-- Configuration options for individual namespace elements
data ConfigOption =
    -- | Severity level for a filter (default is WarningF)
    CoSeverity SeverityF
    -- | Detail level (Default is DRegular)
  | CoDetail DetailLevel
    -- | Privacy level (Default is Public)
  | CoPrivacy Privacy
  deriving (Eq, Ord, Show, Generic)

data TraceConfig = TraceConfig {

     -- | Options specific to a certain namespace
    tcOptions :: Map.Map Namespace [ConfigOption]

  --  Forwarder:
     -- Can their only be one forwarder? Use one of:

     --  Forward messages to the following address
--  ,  tcForwardTo :: RemoteAddr

     --  Forward messages to the following address
--  ,  tcForwardTo :: Map TracerName RemoteAddr

  --  ** Katip:

--  ,  tcDefaultScribe :: ScribeDefinition

--  ,  tcScripes :: Map TracerName -> ScribeDefinition

  --  EKG:
     --  Port for EKG server
--  ,  tcPortEKG :: Int

  -- Prometheus:
    --  Host/port to bind Prometheus server at
--  ,  tcBindAddrPrometheus :: Maybe (String,Int)
}
  deriving (Eq, Ord, Show, Generic)

emptyTraceConfig = TraceConfig {tcOptions = Map.empty}

-- | When configuring a net of tracers, it should be run with Config on all
-- entry points first, and then with Optimize. When reconfiguring it needs to
-- run Reset followed by Config followed by Optimize
data TraceControl where
    Reset :: TraceControl
    Config :: TraceConfig -> TraceControl
    Optimize :: TraceControl
    Document :: DocCollector -> TraceControl
  deriving(Eq, Show, Generic)

-- Document all log messages by providing a list of (prototye, documentation) pairs
-- for all constructors. Because it is not enforced by the type system, it is very
-- important to provide a complete list, as the prototypes are used as well for documentation.
-- If you don't want to add an item for documentation enter an empty text.
newtype Documented a = Documented [(a,Text)]

data DocCollector = DocCollector {
    cDoc       :: Text
  , cContext   :: [Namespace]
  , cSeverity  :: [SeverityS]
  , cPrivacy   :: [Privacy]
  , cDetails   :: [DetailLevel]
  , cBackends  :: [Backend]
  , ccSeverity :: [SeverityS]
  , ccPrivacy  :: [Privacy]
  , ccDetails  :: [DetailLevel]
} deriving(Eq, Show, Generic)

emptyCollector :: DocCollector
emptyCollector = DocCollector "" [] [] [] [] [] [] [] []

data Backend =
    KatipBackend Text
  | EKGBackend Text
  deriving(Eq, Show, Generic)

-- | Type for a Fold
newtype Folding a b = Folding b

instance LogFormatting b => LogFormatting (Folding a b) where
  forMachine v (Folding b) =  forMachine v b
  forHuman (Folding b)     =  forHuman b
  asMetrics (Folding b)    =  asMetrics b

instance A.ToJSON Metric where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON LoggingContext where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON TraceControl where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON DocCollector where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON Backend where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON DetailLevel where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON Privacy where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON SeverityS where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON SeverityF where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON ConfigOption where
    toEncoding = A.genericToEncoding A.defaultOptions

instance A.ToJSON TraceConfig where
    toEncoding = A.genericToEncoding A.defaultOptions