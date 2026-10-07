# prevalence

## Goals

### Prevalence

> Does the pipeline use corpus frequency?

No. I choose prevalence. That way, you can use the dataset to be confident you know the phrases most people know.

### Exhaustiveness

> Does the pipeline pull data from Wiktionary?

Yes. `prevalence` processes Wiktionary data and writes the output to `wiktionary.tsv`.

> Does the pipeline pull data from Wikipedia?

Yes. `prevalence` processes Wikipedia data and writes the output to `wikipedia.tsv`.

### Efficiency

> Does `wiktionary.tsv` distinguish between single words and multi-word phrases?

Yes. `wiktionary.tsv` tells you if it's a single word or a multi-word phrase using a boolean column.

Going through single words is about checking if you know what each word means. But sifting through multi-word phrases is about making sure you understand the idiomatic meaning of the phrase. Going over the lists separately can cut down on context switching.

> Does the pipeline filter out glosses?

Yes. The pipeline drops specific glosses before it calculates the prevalence scores. If an entry ends up with no glosses left after filtering, the entry itself is dropped.

Reviewing misspellings wastes time. `prevalence` drops glosses containing any of the following strings:
- `misspelling of`

Reviewing weird forms just pulls your attention away. `prevalence` removes any glosses with the following strings:
- `alternative form of`
- `alternative letter-case form of`
- `alternative spelling of`
- `archaic form of`
- `archaic spelling of`
- `eye dialect spelling of`
- `informal spelling of`
- `nonstandard form of`
- `nonstandard spelling of`
- `obsolete form of`
- `obsolete spelling of`
- `pronunciation spelling of`

Reviewing an isolated fragment is confusing when the term only ever exists inside a fixed idiom. `prevalence` removes any glosses with the following strings:
- `only used in`

When a phrase is merely the sum of its parts, there's no need to review it on its own if you've gone over the words individually. `prevalence` strips out any glosses that have these strings:
- `used other than figuratively or idiomatically`

Inflected forms bloat your list. You could deal with irregular inflections by using a dedicated reference list that's separate from this dataset. `prevalence` drops glosses containing any of the following strings:
- `gerund of`
- `past participle of`
- `plural of`
- `present participle and gerund of`
- `present participle of`
- `simple past of`
- `third-person singular simple present indicative of`
