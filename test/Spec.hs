module Spec where

import Data.Aeson (Value, encode, object, (.=))
import Data.Map.Strict qualified as Map
import Main (Row (..), buildRows, escapeField, isLemma, renderTsv, scanWiktextract, toRow)
import Relude
import Test.Hspec (describe, hspec, it, shouldBe)

record :: Text -> [Text] -> [Text] -> Value
record word categories senseCategories =
  object
    [ "word" .= word,
      "lang" .= ("English" :: Text),
      "categories" .= categories,
      "senses" .= [object ["categories" .= senseCategories]]
    ]

main :: IO ()
main = hspec $ do
  describe "isLemma" $ do
    it "detects an entry-level lemma tag"
      $ isLemma (record "left" ["English lemmas", "English adjectives"] [])
      `shouldBe` True
    it "rejects a record without the tag"
      $ isLemma (record "lefts" ["English noun forms"] [])
      `shouldBe` False
    it "detects a sense-level lemma tag"
      $ isLemma (record "phone number" [] ["English lemmas"])
      `shouldBe` True

  describe "toRow" $ do
    let glosses = Map.fromList [("A", 10), ("B", 45.5), ("C", 3)]
    it "takes the max across glosses"
      $ (toRow Map.empty ("touchstone", glosses)).prevalence
      `shouldBe` 45.5
    it "flags phrases containing a space" $ do
      (toRow Map.empty ("phone number", glosses)).space `shouldBe` True
      (toRow Map.empty ("touchstone", glosses)).space `shouldBe` False
    it "defaults lemma to false for phrases without a record"
      $ (toRow Map.empty ("$100 hamburgers", glosses)).lemma
      `shouldBe` False

  describe "scanWiktextract" $ do
    let scores = Map.fromList [("left", Map.singleton "gloss" 90)]
        lemmasOf = scanWiktextract scores . encodeLines
    it "ORs the lemma flag across duplicate records" $ do
      lemmasOf [record "left" ["English lemmas"] [], record "left" ["English verb forms"] []] `shouldBe` Map.singleton "left" True
      lemmasOf [record "left" ["English verb forms"] [], record "left" ["English lemmas"] []] `shouldBe` Map.singleton "left" True
    it "keeps only English records for scored phrases"
      $ lemmasOf
        [ object ["word" .= ("left" :: Text), "lang" .= ("French" :: Text), "categories" .= ["English lemmas" :: Text]],
          record "right" ["English lemmas"] []
        ]
      `shouldBe` Map.empty

  describe "buildRows"
    $ it "sorts by prevalence descending, then entry ascending"
    $ (.entry)
    <$> buildRows
      Map.empty
      (Map.fromList [("b", Map.singleton "g" 50), ("a", Map.singleton "g" 50), ("c", Map.singleton "g" 90), ("d", Map.singleton "g" 1)])
    `shouldBe` ["c", "a", "b", "d"]

  describe "escapeField" $ do
    it "leaves plain fields alone"
      $ escapeField "phone number"
      `shouldBe` "phone number"
    it "quotes fields with special characters and doubles inner quotes" $ do
      escapeField "say \"hi\"" `shouldBe` "\"say \"\"hi\"\"\""
      escapeField "a\tb" `shouldBe` "\"a\tb\""
      escapeField "a\nb" `shouldBe` "\"a\nb\""
      escapeField "a\rb" `shouldBe` "\"a\rb\""

  describe "renderTsv"
    $ it "writes the header and rows"
    $ renderTsv [Row {entry = "phone number", prevalence = 99.5, lemma = True, space = True}]
    `shouldBe` "entry\tprevalence\tlemma\tspace\nphone number\t99.5\ttrue\ttrue\n"
  where
    encodeLines = mconcat . fmap ((<> "\n") . encode)
