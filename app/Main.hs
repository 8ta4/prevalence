module Main where

import Codec.Compression.Zstd.Lazy qualified as Zstd
import Crypto.Hash.SHA256 (hashlazy)
import Data.Aeson (eitherDecode)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy (LazyByteString)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Relude
import System.Directory (createDirectoryIfMissing, doesFileExist, getHomeDirectory)
import System.FilePath (takeFileName, (</>))
import System.Process (callProcess)

type Scores = Map Text (Map Text Double)

data Part = Part
  { url :: !Text,
    hash :: !Text
  }

data Row = Row
  { entry :: !Text,
    prevalence :: !Double,
    space :: !Bool
  }
  deriving (Eq, Show)

main :: IO ()
main = do
  home <- getHomeDirectory
  let statePath = home </> ".local/state/prevalence"
  createDirectoryIfMissing True statePath
  scoresContent <- ensureFile statePath $ Part {url = meanDataUrl <> "mean.json.zst", hash = scoresHash}
  writeFileText "wiktionary.tsv" $ renderTsv $ buildRows $ loadScores scoresContent

meanDataUrl :: Text
meanDataUrl = "https://raw.githubusercontent.com/8ta4/mean-data/0a69fe730a0ea1bfaef84eba0dbe0f68ce991683/"

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

blockedPhrases :: [Text]
blockedPhrases =
  [ "misspelling of",
    "alternative form of",
    "alternative letter-case form of",
    "alternative spelling of",
    "archaic form of",
    "archaic spelling of",
    "eye dialect spelling of",
    "informal spelling of",
    "nonstandard form of",
    "nonstandard spelling of",
    "obsolete form of",
    "obsolete spelling of",
    "pronunciation spelling of",
    "only used in",
    "used other than figuratively or idiomatically",
    "gerund of",
    "past participle of",
    "plural of",
    "present participle and gerund of",
    "present participle of",
    "simple past of",
    "third-person singular simple present indicative of"
  ]

isKept :: Text -> Bool
isKept gloss = not $ any (`Text.isInfixOf` Text.toLower gloss) blockedPhrases

filterGlosses :: Scores -> Scores
filterGlosses = Map.filter (not . null) . fmap (Map.filterWithKey (const . isKept))

buildRows :: Scores -> [Row]
buildRows = sortBy compareRows . fmap toRow . Map.toList . filterGlosses

toRow :: (Text, Map Text Double) -> Row
toRow (phrase, glosses) =
  Row
    { entry = phrase,
      prevalence = foldl' max 0 glosses,
      space = Text.any (== ' ') phrase
    }

compareRows :: Row -> Row -> Ordering
compareRows = comparing (Down . (.prevalence)) <> comparing (.entry)

escapeField :: Text -> Text
escapeField field
  | Text.any (`elem` ['"', '\t', '\n', '\r']) field = "\"" <> Text.replace "\"" "\"\"" field <> "\""
  | otherwise = field

renderTsv :: [Row] -> Text
renderTsv rows = Text.unlines $ "entry\tprevalence\tspace" : (renderRow <$> rows)
  where
    renderRow row = Text.intercalate "\t" $ escapeField <$> [row.entry, show row.prevalence, renderBool row.space]
    renderBool = Text.toLower . show
