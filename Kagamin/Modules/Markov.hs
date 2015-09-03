{-# LANGUAGE OverloadedStrings #-}
-- | Module that builds a Markov chain from chat messages and responds to
--   questions using sentences generated by that chain.
module Kagamin.Modules.Markov (kagaMarkov) where
import Kagamin.Modules
import Kagamin.TextUtils
import Control.Concurrent.MVar
import Control.Monad.State (MonadIO (..))
import qualified Data.Text as T
import Web.Slack
import Web.Slack.Message
import System.Random (newStdGen, randomIO, randomRIO)
import DissociatedPress
import Data.Text.Binary ()
import KagaInfo (kagaID)

kagaMarkov :: IO KagaModule
kagaMarkov = do
  d <- newMVar defDict
  return $ defaultModule {
      kagaMsgHook   = handleKagaMsg d,
      kagaOtherHook = handleOtherMsg d,
      kagaSaveHook  = save d,
      kagaLoadHook  = Kagamin.Modules.Markov.load d
    }

save :: MVar (Dictionary T.Text) -> FilePath -> IO ()
save d dir = withMVar d $ \dict -> store (dir ++ "/kagamin.dict") dict

load :: MVar (Dictionary T.Text) -> FilePath -> IO ()
load d dir = do
  olddict <- takeMVar d
  dict <- DissociatedPress.load $ dir ++ "/kagamin.dict"
  putMVar d $ maybe olddict id dict

handleKagaMsg :: MVar (Dictionary T.Text) -> MsgHook
handleKagaMsg dict cid _from msg
  | "vad är" `T.isPrefixOf` msg' = do
    d <- liftIO $ withMVar dict return
    let q = T.strip $ dropPrefix "vad är" $ dropSuffix "?" msg'
    quote <- ask q d <$> liftIO newStdGen
    if T.null quote
      then dontKnow cid
      else sendMessage cid quote
    return Next
  | "citat" == msg' = do
    d <- liftIO $ withMVar dict return
    quote <- randomSentence d <$> liftIO newStdGen
    sendMessage cid quote
    return Next
  | otherwise = do
    return Next
  where
    msg' = stripLeadingTrailingMention kagaID msg

handleOtherMsg :: MVar (Dictionary T.Text) -> MsgHook
handleOtherMsg dict _cid _from msg
  | Just _ <- extractUrl msg = do
    return Next -- ignore URLs
  | otherwise                = do
    liftIO $ modifyMVar dict $ \d -> return (updateDict (T.words msg) d, Next)

dontKnow :: ChannelId -> Slack s ()
dontKnow cid = do
  msg <- oneOf [
      "hur ska jag kunna veta det?!",
      "idiotfråga!!",
      "varför skulle jag svara på dina frågor?!",
      "idiot!",
      "jag är inte din googleslav!",
      "skärp dig!"
    ]
  st <- liftIO randomIO
  sendMessage cid (if st then stutter msg else msg)

oneOf :: MonadIO m => [a] -> m a
oneOf xs = do
  ix <- liftIO $ randomRIO (0, length xs-1)
  return $ xs !! ix