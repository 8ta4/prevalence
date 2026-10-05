# Generate `wiktionary.tsv` from `mean-data`

## Context

`prevalence` publishes `wiktionary.tsv` (to the prevalence-data repo). The current generator (`clj/`, `PLAN.md`) is built on `pun` / `pun-data` and is outdated. The scores now come from `mean`, which scores each (phrase, gloss) pair separately, so `mean-data` replaces `pun-data`. Keep `README.md` and `DONTREADME.md`. Replace everything else.

What `DONTREADME.md` requires: one row per phrase, a `lemma` boolean taken from Wiktionary metadata (no NLP lemmatizer), a `space` boolean, and no entries dropped.

## Language: Haskell

I picked Haskell because it matches `mean`:
- I can copy `mean`'s Wiktextract handling as-is: `parts` download with SHA-256 checks, gunzip of the concatenated parts, and `isEnglish` (`lang == "English"`) on the `word` field. That way the phrase keys match `mean.json` exactly.
- It uses the same toolchain as `mean`: devenv, stack, the same LTS 24.52 snapshot, relude, aeson, and lens-aeson.

## Inputs (pinned to mean-data commit `0a69fe730a0ea1bfaef84eba0dbe0f68ce991683`)

- `https://raw.githubusercontent.com/8ta4/mean-data/<commit>/manifest.json`: read `parts` (URL and sha256) from it, so the dump is the same snapshot that `mean` scored.
- `https://raw.githubusercontent.com/8ta4/mean-data/<commit>/mean.json.zst` (34 MB). Its shape is `{phrase: {gloss: score}}`.
- Cache downloads in `~/.local/state/prevalence/`, the same way `mean` caches in `~/.local/state/mean`. Use `wget -c` and skip any file that already passes its hash check.

## Output: `wiktionary.tsv` (repo root, already gitignored)

Header: `entry	prevalence	lemma	space`
- `entry`: a phrase key from `mean.json`.
- `prevalence`: the **max** score across that phrase's glosses.
- `lemma`: `true` iff any English Wiktextract record whose `word` equals `entry` has `"English lemmas"` in its entry-level `categories`. Sense-level `categories` are ignored. Wiktextract has one record per part of speech or etymology, so a phrase can match several records. The phrase is a lemma if **any** matching record has the tag. For example, `left` is `true` because its adjective record has the tag, even though its verb record does not.
- `space`: `true` iff `entry` contains an ASCII space.
- Sort by prevalence descending, then entry ascending.
- TSV escaping: if a field contains `"`, a tab, `\n` or `\r`, wrap it in quotes and double any inner `"` (the same rule as the old `escape-tsv-field`).
- Every phrase in `mean.json` gets a row. If a phrase has no matching Wiktextract record, it gets `lemma=false`. Log the count of such phrases and a sample of 20 to stderr. This should be 0.

## Files

Delete: `clj/` (all of it) and `PLAN.md`.

Add, modeled on `~/dev/mean`:
- `package.yaml`: copy `mean`'s dependency and ghc-options style. Deps: base, relude, aeson, lens, lens-aeson, bytestring, base16-bytestring, cryptohash, zlib, containers, directory, filepath, process. Use the `zstd` package if it is in the snapshot. Otherwise shell out to the `zstd` CLI and add `pkgs.zstd` to devenv.
- `stack.yaml`: the same snapshot URL as `mean`.
- `app/Main.hs`:
  - `main`: ensure inputs, then `loadScores`, then `scanWiktextract`, then `buildRows`, then write the TSV.
  - `scanWiktextract`: lazily stream the gunzipped dump with `Char8.lines` and `decode`. Keep only `isEnglish` records whose `word` is in the scores map. Fold into `Map Text Bool` (the lemma flags) with `insertWith (||)`.
  - Pure functions, exported so tests can use them: `isLemma :: Value -> Bool`, `toRow`, `compareRows`, `escapeField`, `renderTsv`.
- `test/Spec.hs`: an hspec suite for the pure functions:
  - entry-level lemma, the non-lemma case, and a record with `"English lemmas"` only at sense level (expect `false`)
  - the space flag
  - max across glosses
  - OR across duplicate records
  - sort order
  - escaping
- `devenv.nix`, `devenv.yaml`, `devenv.lock`, `Brewfile`: copy from `mean`. Change the scripts to `prevalence` (`stack run`) and `test-watch`.
- `.gitignore`: drop the `clj/` lines. Add `.stack-work/`, the devenv ignores, and keep `/wiktionary.tsv`.

## Verification

1. Run `stack test` and confirm the unit tests pass.
2. Run `stack run` (or `prevalence` in devenv) and confirm it produces `wiktionary.tsv`.
3. Sanity-check the output:
   - The header is exact.
   - The row count equals the number of `mean.json` keys (`zstd -dc mean.json.zst | jq 'length'`).
   - There are no duplicate entries (`cut -f1 | sort | uniq -d`).
   - The stderr missing count is 0.
   - Spot checks: `touchstone` shows about 45.53; `phone number` shows `space=true`; `$100 hamburgers` shows `lemma=false`.
4. Compare the top rows against the old `~/dev/prevalence-data/wiktionary.tsv` to check they're broadly plausible.
