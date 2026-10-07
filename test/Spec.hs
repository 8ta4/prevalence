module Spec where

import Data.Map.Strict qualified as Map
import Main (Row (..), buildRows, escapeField, isKept, renderTsv, toRow)
import Relude
import Test.Hspec (describe, hspec, it, shouldBe)

main :: IO ()
main = hspec $ do
  describe "toRow" $ do
    let glosses = Map.fromList [("A", 10), ("B", 45.5), ("C", 3)]
    it "takes the max across glosses"
      $ (toRow ("touchstone", glosses)).prevalence
      `shouldBe` 45.5
    it "flags phrases containing a space" $ do
      (toRow ("phone number", glosses)).space `shouldBe` True
      (toRow ("touchstone", glosses)).space `shouldBe` False

  describe "isKept" $ do
    it "keeps a plain gloss"
      $ isKept "A test of quality or genuineness."
      `shouldBe` True
    it "drops misspellings"
      $ isKept "misspelling of $h!tted."
      `shouldBe` False
    it "drops weird forms"
      $ isKept "alternative spelling of colour"
      `shouldBe` False
    it "drops isolated fragments"
      $ isKept "only used in kith and kin"
      `shouldBe` False
    it "drops sum-of-parts phrases"
      $ isKept "Used other than figuratively or idiomatically: see hamburger."
      `shouldBe` False
    it "drops inflected forms"
      $ isKept "plural of $2 shop"
      `shouldBe` False
    it "matches case-insensitively"
      $ isKept "Misspelling of x."
      `shouldBe` False

  describe "buildRows" $ do
    it "sorts by prevalence descending, then entry ascending"
      $ (.entry)
      <$> buildRows (Map.fromList [("b", Map.singleton "g" 50), ("a", Map.singleton "g" 50), ("c", Map.singleton "g" 90), ("d", Map.singleton "g" 1)])
      `shouldBe` ["c", "a", "b", "d"]
    it "ignores blocked glosses when taking the max"
      $ (.prevalence)
      <$> buildRows (Map.singleton "left" (Map.fromList [("simple past and past participle of leave", 99), ("Toward the west.", 80)]))
      `shouldBe` [80]
    it "drops entries whose glosses are all blocked"
      $ buildRows (Map.singleton "$100 hamburgers" (Map.singleton "plural of $100 hamburger" 40))
      `shouldBe` []

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
    $ renderTsv [Row {entry = "phone number", prevalence = 99.5, space = True}]
    `shouldBe` "entry\tprevalence\tspace\nphone number\t99.5\ttrue\n"
