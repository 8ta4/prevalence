# Drop `lemma` and filter glosses before scoring

## Context

`DONTREADME.md` (commit 3829eb9) replaced the lemma FAQ with a gloss filtering requirement:

- Remove the `lemma` column.
- Before computing prevalence, drop every gloss that contains any of the listed strings. If an entry has no glosses left, drop the entry.

`app/Main.hs` downloads and scans the Wiktextract dump only to get the `lemma` flag (and to log a count of missing records to stderr). With `lemma` gone, that whole path goes away. The pipeline becomes: download `mean.json.zst`, filter glosses, take the max, and write the TSV.

## Data facts (from `~/.local/state/prevalence/mean.json.zst`)

- Gloss casing varies. Examples: `Misspelling of $h!tted.`, `plural of $2 shop`, `Used other than figuratively or idiomatically: see hamburger.` That means matching **must be case-insensitive**: lowercase the gloss with `Text.toLower`, then test it with `Text.isInfixOf` against the lowercase strings from `DONTREADME.md`.
- Substring matching also catches combined glosses. For example, `simple past and past participle of leave (…)` matches through `past participle of`, which is the intended behavior.
- There are 1,385,122 entries before filtering and **776,466** after (counted from the `stack run` output).

## Inputs (pinned to mean-data commit `0a69fe730a0ea1bfaef84eba0dbe0f68ce991683`)

- `https://raw.githubusercontent.com/8ta4/mean-data/<commit>/mean.json.zst`, with shape `{phrase: {gloss: score}}`. It is cached in `~/.local/state/prevalence/` and checked against its SHA-256 hash, as it is now.
- The pipeline no longer needs `manifest.json` or the Wiktextract `parts`. Leave the existing cache on disk alone.

## Output: `wiktionary.tsv`

Header: `entry	prevalence	space`

- `entry`: a phrase key from `mean.json` that still has at least one gloss after filtering.
- `prevalence`: the **max** score across the phrase's remaining glosses.
- `space`: `true` iff `entry` contains an ASCII space.
- Sort by prevalence descending, then by entry ascending.
- TSV escaping stays the same.

## Changes

### `app/Main.hs`

- `Row`: remove `lemma`.
- Add `blockedPhrases :: [Text]`: the 25 strings from `DONTREADME.md`, in the same order.
- Add `isKept :: Text -> Bool`: no entry in `blockedPhrases` is an infix of `Text.toLower gloss`.
- Add `filterGlosses :: Scores -> Scores`: keep only the glosses that pass `isKept`, then drop phrases whose gloss map is empty.
- `buildRows :: Scores -> [Row]`: `sortBy compareRows . fmap toRow . Map.toList . filterGlosses`.
- `toRow :: (Text, Map Text Double) -> Row`: drop the lemmas argument.
- `renderTsv`: drop the `lemma` header and field.
- `main`: download only `mean.json.zst`, then write the TSV.
- Delete `Manifest`, `manifestHash`, `scanWiktextract`, `isEnglish`, `isLemma`, the missing-record logging, and the imports that become unused. `-Weverything` flags any that are left.

### `package.yaml`

- Remove the deps that are now unused: `zlib`, `lens`, `lens-aeson`.

### `test/Spec.hs`

- Remove the `isLemma` and `scanWiktextract` specs and their helpers.
- `toRow`: remove the lemma test and update the call sites.
- `isKept`: one case per group in `DONTREADME.md`, plus a plain gloss that is kept, plus a mixed-case match (`Misspelling of x.`).
- `buildRows`:
  - The max ignores blocked glosses, even when a blocked gloss scores higher.
  - An entry whose glosses are all blocked is dropped.
- `renderTsv`: expect `entry\tprevalence\tspace\nphone number\t99.5\ttrue\n`.

## Verification

1. `stack test` passes.
2. `stack run` produces `wiktionary.tsv` without downloading the Wiktextract dump.
3. The header is exactly `entry	prevalence	space`. There are 776,466 data rows and no duplicate entries.
4. Spot checks:
   - `touchstone` is about 45.53.
   - `left` is about 99.81.
   - `$100 hamburgers` is absent, because its only gloss is a `plural of`.
   - `phone number` has `space=true`.
