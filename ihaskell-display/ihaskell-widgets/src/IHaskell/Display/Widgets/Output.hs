{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeSynonymInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module IHaskell.Display.Widgets.Output
  ( -- * The Output Widget
    OutputWidget
    -- * Constructor
  , mkOutputWidget
    -- * Using the output widget
  , appendStdout
  , appendStderr
  , appendDisplay
  , clearOutput
  , clearOutput_
  , replaceOutput
  ) where

-- To keep `cabal repl` happy when running from the ihaskell repo
import           Prelude

import           Data.Aeson
import           Data.IORef (newIORef)
import           Data.Text
import           Data.Vinyl (Rec(..), (<+>))

import           IHaskell.Display
import           IHaskell.Eval.Widgets
import           IHaskell.IPython.Message.UUID as U

import           IHaskell.Display.Widgets.Types
import           IHaskell.Display.Widgets.Common
import           IHaskell.Display.Widgets.Layout.LayoutWidget

-- | An 'OutputWidget' represents a Output widget from IPython.html.widgets.
type OutputWidget = IPythonWidget 'OutputType

-- | Create a new output widget
mkOutputWidget :: IO OutputWidget
mkOutputWidget = do
  -- Default properties, with a random uuid
  wid <- U.random
  layout <- mkLayout

  let domAttrs = defaultDOMWidget "OutputView" "OutputModel" layout
      outAttrs = (ViewModule =:! "@jupyter-widgets/output")
                 :& (ModelModule =:! "@jupyter-widgets/output")
                 :& (ViewModuleVersion =:! "1.0.0")
                 :& (ModelModuleVersion =:! "1.0.0")
                 :& (MsgID =:: "")
                 :& (Outputs =:: [])
                 :& RNil
      widgetState = WidgetState $ domAttrs <+> outAttrs

  stateIO <- newIORef widgetState

  let widget = IPythonWidget wid stateIO

  -- Open a comm for this widget, and store it in the kernel state
  widgetSendOpen widget $ toJSON widgetState

  -- Return the image widget
  return widget

appendStd :: StreamName -> OutputWidget -> Text -> IO ()
appendStd n out t = do
  getField out Outputs >>= setField out Outputs . updateOutputs
  where updateOutputs :: [OutputMsg] -> [OutputMsg]
        updateOutputs = (++[OutputStream n t])

appendStdout :: OutputWidget -> Text -> IO ()
appendStdout = appendStd STR_STDOUT

appendStderr :: OutputWidget -> Text -> IO ()
appendStderr = appendStd STR_STDERR

-- | Clears the output widget
clearOutput' :: OutputWidget -> IO ()
clearOutput' w = do
  _ <- setField w Outputs []
  _ <- setField w MsgID ""
  return ()

appendDisplay :: IHaskellDisplay a => OutputWidget -> a -> IO ()
appendDisplay a d = error "To be implemented"

-- | Clear the output widget immediately
clearOutput :: OutputWidget -> IO ()
clearOutput widget = widgetClearOutput False >> clearOutput' widget

-- | Clear the output widget on next append
clearOutput_ :: OutputWidget -> IO ()
clearOutput_ widget = widgetClearOutput True >> clearOutput' widget

-- | Replace the currently displayed output for output widget
replaceOutput :: IHaskellDisplay a => OutputWidget -> a -> IO ()
replaceOutput widget d = do
    clearOutput_ widget
    appendDisplay widget d

instance IHaskellWidget OutputWidget where
  getCommUUID = uuid
  comm widget val _ = print val
