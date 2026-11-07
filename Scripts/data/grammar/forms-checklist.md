# Forms tables: checklist

For #171 (`Scripts/build_grammar.py`) and Kirill's second review pass over the rendered tables in `Scripts/reports/grammar-review.md`. From Kirill's review of the first draft, 2026-11-04. The tables come from the Wiktionary forms, so each item is checked on the rendered table, not in the topic source.

## Nouns and adjectives

- [ ] Noun tables show only the nominative and the accusative, singular and plural. No genitive or vocative: they would confuse an A1 learner.
- [ ] `ell-noun-endings`: all eight nouns (δρόμος, πατέρας, μαθητής, γυναίκα, κόρη, βιβλίο, σπίτι, όνομα) give all four forms, with no empty cell.

## Verbs

- [ ] The future renders the simple form: θα γράψω, not θα γράφω.
- [ ] The present's third person plural shows -ουν, not only -ουνε.
- [ ] αγαπάω: the two sets of endings (αγαπάω, αγαπάς, αγαπάει … and αγαπώ, αγαπά, αγαπούν) are not mixed together.
- [ ] The aorist of πηγαίνω is πήγα, with no augment added.
- [ ] The simple subjunctive of πηγαίνω is να πάω (`ell-na-perfective`).
- [ ] `ell-future`'s second table gives θα πάω, θα δω, θα φάω.
- [ ] The aorist of έρχομαι may be ήλθα in the data; the app needs ήρθα (Definition table and drill; the topics have no έρχομαι table).
- [ ] The simple imperative of διαβάζω is διάβασε, διαβάστε.
- [ ] τρώω: aorist έφαγα, but φάγαμε in the plural, without έ-.

## Headwords (build gate)

Kirill's decisions for links that may fail the gate (every `words` entry must be a headword of El–En · FD or El–En · WN):

- [x] `ell-articles`: if ο, η, το are not headwords, drop them and keep ένας. η is none, so the links are ο, το, ένας.
- [x] `ell-pronouns`: if αυτοί is not a headword, drop it. Dropped.
- [x] `ell-negation-questions`: if the dictionaries list μη (or μη(ν)) and not μην, use their form. μην is a headword. ποιανού is none, so it left the links; it stays in the table and in the `ell-possessives` example.
