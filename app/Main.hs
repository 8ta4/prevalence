module Main where

import Codec.Compression.GZip qualified as GZip
import Codec.Compression.Zstd.Lazy qualified as Zstd
import Control.Lens ((^..), (^?))
import Crypto.Hash.SHA256 (hashlazy)
import Data.Aeson (FromJSON, Value, decode, eitherDecode)
import Data.Aeson.Lens (key, values, _String)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy (LazyByteString)
import Data.ByteString.Lazy.Char8 qualified as Char8
import Data.Map.Strict (insertWith, member)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Relude
import System.Directory (createDirectoryIfMissing, doesFileExist, getHomeDirectory)
import System.FilePath (takeFileName, (</>))
import System.IO (hPutStrLn)
import System.Process (callProcess)

type Scores = Map Text (Map Text Double)

data Part = Part
  { url :: !Text,
    hash :: !Text
  }
  deriving (Generic, FromJSON)

data Manifest = Manifest
  { parts :: [Part]
  }
  deriving (Generic, FromJSON)

data Row = Row
  { entry :: !Text,
    prevalence :: !Double,
    lemma :: !Bool,
    space :: !Bool
  }
  deriving (Eq, Show)

main :: IO ()
main = do
  home <- getHomeDirectory
  let statePath = home </> ".local/state/prevalence"
      partsPath = statePath </> "parts"
  createDirectoryIfMissing True partsPath
  manifestContent <- ensureFile statePath $ Part {url = meanDataUrl <> "manifest.json", hash = manifestHash}
  manifest :: Manifest <- either (error . toText) pure $ eitherDecode manifestContent
  scoresContent <- ensureFile statePath $ Part {url = meanDataUrl <> "mean.json.zst", hash = scoresHash}
  partContents <- traverse (ensureFile partsPath) manifest.parts
  let scores = loadScores scoresContent
      lemmas = scanWiktextract scores $ GZip.decompress $ fold partContents
      rows = buildRows lemmas scores
      missing = filter (`Map.notMember` lemmas) $ Map.keys scores
  writeFileText "wiktionary.tsv" $ renderTsv rows
  hPutStrLn stderr $ "Phrases without a Wiktextract record: " <> show (length missing)
  traverse_ (hPutStrLn stderr . toString) $ take 20 missing

meanDataUrl :: Text
meanDataUrl = "https://raw.githubusercontent.com/8ta4/mean-data/0a69fe730a0ea1bfaef84eba0dbe0f68ce991683/"

manifestHash :: Text
manifestHash = "1c777136c1628379c060c9ae224838f0268af80d9381202b34f3352dcef0564d"

scoresHash :: Text
scoresHash = "1e00110a0791fdb856d0151769022b5760e971048c9dd50b313bae80ae5b717a"

ensureFile :: FilePath -> Part -> IO LazyByteString
ensureFile directory part = do
  let path = directory </> takeFileName (toString part.url)
  exists <- doesFileExist path
  cached <- if exists then verify path else pure False
  unless cached $ do
    callProcess "wget" ["-c", "-O", path, toString part.url]
    verified <- verify path
    unless verified $ error $ "Checksum verification failed: " <> toText path
  readFileLBS path
  where
    verify path = do
      content <- readFileLBS path
      pure $ part.hash == decodeUtf8 (Base16.encode $ hashlazy content)

loadScores :: LazyByteString -> Scores
loadScores = either (error . toText) id . eitherDecode . Zstd.decompress

scanWiktextract :: Scores -> LazyByteString -> Map Text Bool
scanWiktextract scores = foldl' insertLemma Map.empty . mapMaybe decode . Char8.lines
  where
    insertLemma lemmas record = case record ^? key "word" . _String of
      Just phrase | isEnglish record && member phrase scores -> insertWith (||) phrase (isLemma record) lemmas
      _ -> lemmas

isEnglish :: Value -> Bool
isEnglish entry = case entry ^? key "lang" . _String of
  Just "English" -> True
  _ -> False

isLemma :: Value -> Bool
isLemma record = "English lemmas" `elem` (categories record <> (record ^.. key "senses" . values >>= categories))
  where
    categories value = value ^.. key "categories" . values . _String

buildRows :: Map Text Bool -> Scores -> [Row]
buildRows lemmas = sortBy compareRows . fmap (toRow lemmas) . Map.toList

toRow :: Map Text Bool -> (Text, Map Text Double) -> Row
toRow lemmas (phrase, glosses) =
  Row
    { entry = phrase,
      prevalence = foldl' max 0 glosses,
      lemma = Map.findWithDefault False phrase lemmas,
      space = Text.any (== ' ') phrase
    }

compareRows :: Row -> Row -> Ordering
compareRows = comparing (Down . (.prevalence)) <> comparing (.entry)

escapeField :: Text -> Text
escapeField field
  | Text.any (`elem` ['"', '\t', '\n', '\r']) field = "\"" <> Text.replace "\"" "\"\"" field <> "\""
  | otherwise = field

renderTsv :: [Row] -> Text
renderTsv rows = Text.unlines $ "entry\tprevalence\tlemma\tspace" : (renderRow <$> rows)
  where
    renderRow row = Text.intercalate "\t" $ escapeField <$> [row.entry, show row.prevalence, renderBool row.lemma, renderBool row.space]
    renderBool = Text.toLower . show
