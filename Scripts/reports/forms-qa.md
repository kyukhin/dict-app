# Greek word forms: QA report

Written by `Scripts/build_forms.py` on every build of the forms step ([0136-word-forms.md](../../docs/specs/0136-word-forms.md)). Do not edit by hand.

## Snapshot

| Input | Pin |
|---|---|
| Greek subset | `Scripts/data/kaikki-el-20261001.jsonl.gz`, sha256 `9713b588476bcf2eced6dea1aa46ea686163403c347bb71d8c33367ece214dd5`, 85,425 lines |
| Dump | enwiktionary 2026-10-01, https://kaikki.org/dictionary/raw-wiktextract-data.jsonl.gz, 3,082,185,963 bytes, 11,121,531 lines, sha256 `784574cc577d333bbf9e659be38efa27e75e9bfc0a2a8c7ab2371bb5fec29b2d` |
| Frequency list (QA only) | https://raw.githubusercontent.com/hermitdave/FrequencyWords/072bbed282316a23651aa7068c7173aa7898cf80/content/2018/el/el_50k.txt, sha256 `7ec8f6de52c38f36a04add5d1613b116aed576e10c5e3b40d0001e8572de978c` |

## Counts

- Pages: 85,425 (29,449 lemma pages, 55,976 form pages)
- Lemmas: 27,352 (noun 14,370, adj 5,760, verb 3,934, name 1,813, adv 999, intj 115, num 79, pron 70, conj 53, character 51, symbol 42, prep 41, particle 14, article 7, det 4)
- Lemmas with a table: 21,998 (noun 13,342, adj 5,569, verb 1,863, name 1,178, pron 24, num 16, det 4, article 2)
- Table cells: 390,583; lookup rows: 247,477; lookup keys: 236,938, of which ambiguous (more than one lemma): 9,744; tag sets: 971
- Links: alt_of 3,147, form_of 67,463, gloss 461; aspect taken from the gloss: 5,232; unresolved targets: 388 (613 links); link spellings that are no cell of their lemma's table (`form_link`): 8,994

## Junk caught

| Rule | Caught | Samples |
|---|---|---|
| bare ending | 37 |  |
| cell of a pronoun table that mixes persons | 76 | εγώ@τα, γώ@τα, εσύ@τα, σύ@τα, αυτός@τα, αυτή@τα, αυτό@τα, εμείς@τα, μείς@τα, εσείς@τα, σείς@τα, αυτοί@τα |
| cell of a table declined from another word | 571 |  |
| cell split into its ' - ' variants (kept) | 1,088 | αγρυπνάω - αγρυπνώ@αγρυπνώ, αγρυπνάς - αγρυπνείς@αγρυπνώ, αγρυπνά - αγρυπνεί@αγρυπνώ, αγρυπνάμε - αγρυπνούμε@αγρυπνώ, αγρυπνάτε - αγρυπνείτε@αγρυπνώ, αγρυπνάτε - αγρυπνείτε@αγρυπνώ, αδικούμαι - αδικιέμαι@αδικώ, αδικείσαι - αδικιέσαι@αδικώ, αδικείται - αδικιέται@αδικώ, αδικούμαστε - αδικιόμαστε@αδικώ, αδικείστε - αδικιέστε@αδικώ, αδικούνται - αδικιούνται@αδικώ |
| cell tagged error-* | 220 | άπτομαι@άπτομαι, άπτεσαι@άπτομαι, απτόσουν@άπτομαι, άπτεται@άπτομαι, απτόταν@άπτομαι, απτόμαστε@άπτομαι, απτόμασταν@άπτομαι, απτόμαστε@άπτομαι, άπτεστε@άπτομαι, άπτεσθε@άπτομαι, απτόσασταν@άπτομαι, απτόσαστε@άπτομαι |
| link from a multi-word or non-Greek page | 1,206 | α-λα-καρτ → α λα καρτ, πινγκ-πονγκ → πινγκ πονγκ, - → Τ, αν- → ανα-, αν- → privative of α-, ... → Σ, ... → EI, π.μ. → προ μεσημβρίας, μ.μ. → μετά το μεσημέρι, μ.μ. → μετά μεσημβρίαν, αλά καρτ → α λα κάρτ, σ' → σε |
| link tagged error-* or future | 26 | γάτος → masculine form of of γάτα (gáta) (cat): tomcat, a male domes, οδηγήσεις → second-person singular perfective future of οδηγώ (odigó), ξέρει → third-person singular imperfective future of ξέρω (xéro), μπορούμε → first-person plural imperfective future of μπορώ (boró), πάει → third-person singular imperfective future of πάω (páo), πάει → third-person singular perfective future of πάω (páo), αρέσει → third-person singular imperfective future of αρέσω (aréso), αρέσει → third-person singular perfective future of αρέσω (aréso), γίνεται → inflection of γίνομαι (gínomai):, πέρδεστε → second-person plural present/future of πέρδομαι (pérdomai), πέρδονται → third-person plural present/future of πέρδομαι (pérdomai), πέρδεται → third-person singular present/future of πέρδομαι (pérdomai) |
| misspelt cell: final sigma inside the word | 367 | άφυλλοςος@άφυλλος, άφυλλοςη@άφυλλος, άφυλλοςο@άφυλλος, άφυλλοςοι@άφυλλος, άφυλλοςες@άφυλλος, άφυλλοςα@άφυλλος, άφυλλοςου@άφυλλος, άφυλλοςης@άφυλλος, άφυλλοςου@άφυλλος, άφυλλοςων@άφυλλος, άφυλλοςων@άφυλλος, άφυλλοςων@άφυλλος |
| misspelt cell: two accents | 341 | Βαλτιμόρή@Βαλτιμόρη, Βαλτιμόρής@Βαλτιμόρη, Βαλτιμόρή@Βαλτιμόρη, Βαλτιμόρή@Βαλτιμόρη, Τσικνοπέμπτή@Τσικνοπέμπτη, Τσικνοπέμπτές@Τσικνοπέμπτη, Τσικνοπέμπτής@Τσικνοπέμπτη, Τσικνοπέμπτών@Τσικνοπέμπτη, Τσικνοπέμπτή@Τσικνοπέμπτη, Τσικνοπέμπτές@Τσικνοπέμπτη, Τσικνοπέμπτή@Τσικνοπέμπτη, Τσικνοπέμπτές@Τσικνοπέμπτη |
| multi-word cell | 11,835 | ὁ Λεϊβνίτιος@Λεϊβνίτιος, οἱ Λεϊβνίτιοι@Λεϊβνίτιος, τοῦ Λεϊβνιτίου@Λεϊβνίτιος, τῶν Λεϊβνιτίων@Λεϊβνίτιος, τῷ Λεϊβνιτίῳ@Λεϊβνίτιος, τοῖς Λεϊβνιτίοις@Λεϊβνίτιος, τὸν Λεϊβνίτιον@Λεϊβνίτιος, τοὺς Λεϊβνιτίους@Λεϊβνίτιος, Derivations: relative superlative: ο + comparative forms: e.g. ο αγιότερος , etc.@άγιος, Derivations: relative superlative: ο + comparative forms: e.g. ο αγριότερος , etc.@άγριος, θα άγω@άγω, θα ‑αγάγω@άγω |
| multi-word or non-Greek lemma | 1,936 | 'συ/pron, ,δ/symbol, ,ε/symbol, ,ζ/symbol, ,η/num, -Ο/suffix, -άδα/suffix, -άδικο/suffix, -άκης/suffix, -άκι/suffix, -άκις/suffix, -άκλας/suffix |
| note or footnote mark stripped (kept) | 131 | μίαν (mían¹⁺²)@ένας, μίαν (mían¹⁺²)@ένας, αγριοκοιτάζω (αγριοκοιτάω →)@αγριοκοιτάζω, αεροφωτογραφίζω (αεροφωτογραφώ →)@αεροφωτογραφίζω, αλείφω (αλείβω →)@αλείφω, αναγεννιέστε(‑ιόσαστε)@αναγεννώ, αναδεύτε²@αναδεύω, αναθαρρεύω (compare → αναθαρρώ)@αναθαρρεύω, αναλίσκω (αναλώνω →)@αναλίσκω, αναμειχθώ²@αναμειγνύω, αναμείχθηκα²@αναμειγνύω, αναπαριστάνω (αναπαρασταίνω →)@αναπαριστάνω |
| placeholder or non-Greek cell | 10,687 | -@Άβα, -@Άννα, -@Ήρα, -@Όλγα, -@Αγάπια, -@Αγγέλα, -@Αθίγγανη, -@Αιθιοπίνα, -@Αμερικάνα, -@Αμπχάζια, -@Αμφιτρίτη, Αναξιμένoυς@Αναξιμένης |
| single-word future cell | 315 | έρπομε@έρπω, έλθω@έρχομαι, αγγίσω@αγγίζω, αγγιστώ@αγγίζω, αγιαστώ@αγιάζω, αγοροφέρνουμε@αγοροφέρνω, αδικιέμαι@αδικώ, αεροφωτογραφιστώ@αεροφωτογραφίζω, ακολουθιέμαι@ακολουθώ, ακοντισθώ@ακοντίζω, ακούομαι@ακούω, ακροασθώ@ακροάζομαι |
| stoplisted form | 13 |  |
| synonym gloss: a meaning, no link | 4 | παχύς: fat, a formal synonym of χοντρός (chontrós), ψωμάς: baker, informal synonym of αρτοποιός (artopoiós), φούρναρης , υποδηματοποιός: a formal synonym of of τσαγκάρης (tsagkáris): shoemaker, cob, σιδερίτης: formal term, synonym of τσάι του βουνού (tsái tou vounoú): i |

### Tables declined from another word (40, all)

Κωσταντής (name): Κωνσταντής, …, Νοτιοαφρικάνος (noun): Ρουαντέζος, …, άλεστος (adj): αλεσμένος, …, αγκιστρωμένος (verb): αγκριστρωμένος, …, αισώπειος (adj): ος, …, αλυσοδέσμιος (adj): αλυσοδεμένος, …, αμνήστευση (noun): αμνηστία, …, αμοίραστος (adj): αδιαμοίραστος, …, ανεκτέλεστος (adj): ανεκτίμητος, …, ανερώτευτος (adj): ανέραστος, …, ανθόσπαρτος (adj): ανθοσκέπαστος, …, αντίθεος (noun): αθεϊστής, …, αντιρατσιστικός (adj): αντιπροστατευτικός, …, απολιτικός (adj): αντιπολιτικός, …, απόκλιση (noun): αγιογράφος, …, αργυρώνητος (adj): αργυρόηχος, …, αργόστροφος (adj): αργοκίνητος, …, ασαβούρωτος (adj): ανερμάτιστος, …, ασπράδα (noun): ασπάδα, …, ατροπολόγητος (adj): ατοπολόγητος, …, αττικιστής (noun): μιμητής, …, βάβουλας (noun): βαβούρα, …, εξάεδρος (adj): εξάπλευρος, …, κολοβός (adj): αναληπτικός, …, κουτορνίθι (noun): κουτορίθι, …, κρεατομηχανή (noun): μηχανή, …, μελεαγρίδα (noun): πετροπέρδικα, …, μιμόδραμα (noun): μελόδραμα, …, μοζαμβικανός (adj): μαροκινός, …, μουρμούρισμα (noun): μουμούρισμα, …, μπαρμπέρικο (noun): μπαρμμπέρικο, …, μπουμπούκα (noun): ντουντούκα, …, ουνουνέξιο (noun): ουνουνπέντιο, …, πανσέληνος (noun): πανσέλινος, …, τακτισμός (noun): τροπισμός, …, τσιχλαηδόνι (noun): τσίχλα, …, υπερβασίλειο (noun): αυτοκρατορία, …, υποσιτισμός (noun): υπερσιτισμός, …, φημίζομαι (verb): φημισμένος, …, χουρμαδιά (noun): χοθρμαδιά, …

### Bare endings (37, all)

όνων@αιθεροβάμων, όνων@αιθεροβάμων, όνων@αιθεροβάμων, ούσης@αρχαΐζων, όντων@αρχαΐζων, ουσών@αρχαΐζων, όντων@αρχαΐζων, ανε@διαβαίνω, ώ@σαλπάρω, είς@σαλπάρω, εί@σαλπάρω, όμαστε@σαλπάρω, ούμε@σαλπάρω, όσαστε@σαλπάρω, ούν@σαλπάρω, ούνε@σαλπάρω, όμουν@σαλπάρω, όμουνα@σαλπάρω, ηκα@σαλπάρω, όσουν@σαλπάρω, όσουνα@σαλπάρω, ηκες@σαλπάρω, ότανε@σαλπάρω, ηκε@σαλπάρω, όμασταν@σαλπάρω, όμαστε@σαλπάρω, ήκαμε@σαλπάρω, όσασταν@σαλπάρω, όσαστε@σαλπάρω, ήκατε@σαλπάρω, όντουσαν@σαλπάρω, ηκαν@σαλπάρω, ήκαν@σαλπάρω, ήκανε@σαλπάρω, εί@σαλπάρω, όμαστε@συνθέτω, όσαστε@συνθέτω

### Stoplist hits (13, all)

- είτε in the table of έλκω (verb)
- ο in the table of βάτος (noun)
- του in the table of βάτος (noun)
- τον in the table of βάτος (noun)
- τους in the table of βάτος (noun)
- αν in the table of διαβαίνω (verb)
- ο in the table of καλύπτω (verb)
- ο in the table of σέρνω (verb)
- είτε in the table of σαλπάρω (verb)
- όταν in the table of σαλπάρω (verb)
- είτε in the table of σαλπάρω (verb)
- θα → έχω (verb, gloss)
- θα → έχω (verb, gloss)

### Allowlist uses (4, all)

- παρά in the table of παράς (noun)
- παρά in the table of παράς (noun)
- παρά in the table of παράς (noun)
- παρά → παράς (noun, form_of)

### Table fixes (99, all; `Scripts/data/forms-fixes.tsv`)

- ανέκραξε (drop) in the table of ανακράζω: active imperative perfective second-person singular
- ανέκραζε (drop) in the table of ανακράζω: active imperative imperfective second-person singular
- ανέκτησε (drop) in the table of ανακτώ: active imperative perfective second-person singular
- ανέτρεφε (drop) in the table of ανατρέφω: active imperative imperfective second-person singular
- απεκόμισε (drop) in the table of αποκομίζω: active imperative perfective second-person singular
- αποσυνέδεσε (drop) in the table of αποσυνδέω: active imperative perfective second-person singular
- απέτυχε (drop) in the table of αποτυγχάνω: active imperative perfective second-person singular
- ιδές (rare) in the table of βλέπω: active imperative informal perfective second-person singular
- βόγγηξε (keep) in the table of βογκάω: active imperative perfective second-person singular
- βόγγησε (keep) in the table of βογκάω: active imperative perfective second-person singular
- διήνυσε (drop) in the table of διανύω: active imperative perfective second-person singular
- διήρκεσε (drop) in the table of διαρκώ: active imperative perfective second-person singular
- διέσχισε (drop) in the table of διασχίζω: active imperative perfective second-person singular
- διέσχιζε (drop) in the table of διασχίζω: active imperative imperfective second-person singular
- διέφερε (drop) in the table of διαφέρω: active imperative perfective second-person singular
- διέφερε (drop) in the table of διαφέρω: active imperative imperfective second-person singular
- ελάφρυνε (drop) in the table of ελαφραίνω: active imperative imperfective second-person singular
- ήλπισε (drop) in the table of ελπίζω: active imperative perfective second-person singular
- επαναπροώθησε (keep) in the table of επαναπροωθώ: active imperative perfective second-person singular
- επέζησε (drop) in the table of επιζώ: active imperative perfective second-person singular
- θυμήζω → θυμίζω (replace) in the table of θυμίζω: active first-person imperfective indicative present singular
- θυμήζεις → θυμίζεις (replace) in the table of θυμίζω: active imperfective indicative present second-person singular
- θυμήζει → θυμίζει (replace) in the table of θυμίζω: active imperfective indicative present singular third-person
- θυμήζουμε → θυμίζουμε (replace) in the table of θυμίζω: active first-person imperfective indicative plural present
- θυμήζομε → θυμίζομε (replace) in the table of θυμίζω: active first-person imperfective indicative plural present rare
- θυμήζετε → θυμίζετε (replace) in the table of θυμίζω: active imperfective indicative plural present second-person
- θυμήζουν → θυμίζουν (replace) in the table of θυμίζω: active imperfective indicative plural present third-person
- θυμήζουνε → θυμίζουνε (replace) in the table of θυμίζω: active imperfective indicative plural present third-person
- θυμήζαμε → θυμίζαμε (replace) in the table of θυμίζω: active first-person imperfect imperfective indicative plural
- θυμήζατε → θυμίζατε (replace) in the table of θυμίζω: active imperfect imperfective indicative plural second-person
- θυμήζαν → θυμίζαν (replace) in the table of θυμίζω: active imperfect imperfective indicative plural third-person
- θυμήζανε → θυμίζανε (replace) in the table of θυμίζω: active imperfect imperfective indicative plural third-person
- θυμήζετε → θυμίζετε (replace) in the table of θυμίζω: active imperative imperfective plural second-person
- θυμήζοντας → θυμίζοντας (replace) in the table of θυμίζω: active indeclinable participle present
- καρτέρησε (keep) in the table of καρτερώ: active imperative perfective second-person singular
- καρτέραγε (drop) in the table of καρτερώ: active imperative imperfective second-person singular
- μαλώσε → μάλωσε (replace) in the table of μαλώνω: active imperative perfective second-person singular
- έμπαινε (keep) in the table of μπαίνω: active imperative imperfective informal second-person singular
- νύσταξε → νυστάξτε (replace) in the table of νυστάζω: active imperative perfective plural second-person
- ξύπνησε → ξύπνα (first) in the table of ξυπνάω: active imperative perfective second-person singular
- παρήγαγε (drop) in the table of παράγω: active imperative perfective second-person singular
- παρήγε (drop) in the table of παράγω: active imperative imperfective second-person singular
- παράτησε → παράτα (first) in the table of παρατάω: active imperative perfective second-person singular
- παρέτεινε (drop) in the table of παρατείνω: active imperative perfective second-person singular
- παρέτεινε (drop) in the table of παρατείνω: active imperative imperfective second-person singular
- πρέβαλε (drop) in the table of προβάλλω: active imperative perfective second-person singular
- πρέβαλλε (drop) in the table of προβάλλω: active imperative imperfective second-person singular
- προέτεινε (drop) in the table of προτείνω: active imperative perfective second-person singular
- προέτεινε (drop) in the table of προτείνω: active imperative imperfective second-person singular
- προχώρησε → προχώρα (first) in the table of προχωράω: active imperative perfective second-person singular
- σερβιρίζοναι → σερβιρίζονται (replace) in the table of σερβίρω: imperfective indicative passive plural present third-person
- σερβιριζόμαστε → σερβιρόμαστε (first) in the table of σερβίρω: first-person imperfective indicative passive plural present
- σερβιρίζω → σερβιρίζουμε (replace) in the table of σερβίρω: active first-person imperfective indicative plural present
- σερβαριστώ → σερβιριστώ (replace) in the table of σερβίρω: dependent first-person indicative passive perfective singular
- σερβαριστείς → σερβιριστείς (replace) in the table of σερβίρω: dependent indicative passive perfective second-person singular
- σερβαριστεί → σερβιριστεί (replace) in the table of σερβίρω: dependent indicative passive perfective singular third-person
- σερβαριστούμε → σερβιριστούμε (replace) in the table of σερβίρω: dependent first-person indicative passive perfective plural
- σερβαριστείτε → σερβιριστείτε (replace) in the table of σερβίρω: dependent indicative passive perfective plural second-person
- σερβαριστούν → σερβιριστούν (replace) in the table of σερβίρω: dependent indicative passive perfective plural third-person
- σερβαριστούνε → σερβιριστούνε (replace) in the table of σερβίρω: dependent indicative passive perfective plural third-person
- σερβαριζόμουν → σερβιριζόμουν (replace) in the table of σερβίρω: first-person imperfect imperfective indicative passive singular
- σερβαριζόμουνα → σερβιριζόμουνα (replace) in the table of σερβίρω: first-person imperfect imperfective indicative passive singular
- σερβαρίστηκα → σερβιρίστηκα (replace) in the table of σερβίρω: first-person indicative passive past perfective singular
- σερβαριζόσουν → σερβιριζόσουν (replace) in the table of σερβίρω: imperfect imperfective indicative passive second-person singular
- σερβαριζόσουνα → σερβιριζόσουνα (replace) in the table of σερβίρω: imperfect imperfective indicative passive second-person singular
- σερβαρίστηκες → σερβιρίστηκες (replace) in the table of σερβίρω: indicative passive past perfective second-person singular
- σερβαριζόταν → σερβιριζόταν (replace) in the table of σερβίρω: imperfect imperfective indicative passive singular third-person
- σερβαριζότανε → σερβιριζότανε (replace) in the table of σερβίρω: imperfect imperfective indicative passive singular third-person
- σερβαρίστηκε → σερβιρίστηκε (replace) in the table of σερβίρω: indicative passive past perfective singular third-person
- σερβαριζόμασταν → σερβιριζόμασταν (replace) in the table of σερβίρω: first-person imperfect imperfective indicative passive plural
- σερβαριζόμαστε → σερβιριζόμαστε (replace) in the table of σερβίρω: first-person imperfect imperfective indicative informal passive plural
- σερβαριστήκαμε → σερβιριστήκαμε (replace) in the table of σερβίρω: first-person indicative passive past perfective plural
- σερβαριζόσασταν → σερβιριζόσασταν (replace) in the table of σερβίρω: imperfect imperfective indicative passive plural second-person
- σερβαριζόσαστε → σερβιριζόσαστε (replace) in the table of σερβίρω: imperfect imperfective indicative informal passive plural second-person
- σερβαριστήκατε → σερβιριστήκατε (replace) in the table of σερβίρω: indicative passive past perfective plural second-person
- σερβαριζόντουσαν → σερβιριζόντουσαν (replace) in the table of σερβίρω: imperfect imperfective indicative informal passive plural third-person
- σερβαρίστηκαν → σερβιρίστηκαν (replace) in the table of σερβίρω: indicative passive past perfective plural third-person
- σερβαριστήκαν → σερβιριστήκαν (replace) in the table of σερβίρω: indicative passive past perfective plural third-person
- σερβαριστήκανε → σερβιριστήκανε (replace) in the table of σερβίρω: indicative passive past perfective plural third-person
- σερβαρίσου → σερβιρίσου (replace) in the table of σερβίρω: imperative passive perfective second-person singular
- σερβαριστείτε → σερβιριστείτε (replace) in the table of σερβίρω: imperative passive perfective plural second-person
- σερβαρισμένος → σερβιρισμένος (replace) in the table of σερβίρω: participle passive past
- σερβαριστεί → σερβιριστεί (replace) in the table of σερβίρω: infinitive-aorist passive
- έσπευσε (drop) in the table of σπεύδω: active imperative perfective second-person singular
- έσπευδε (drop) in the table of σπεύδω: active imperative imperfective second-person singular
- σταμάτησε → σταμάτα (first) in the table of σταματάω: active imperative perfective second-person singular
- συμμμετείχε → συμμετείχε (replace) in the table of συμμετέχω: active indicative past perfective singular third-person
- συμμετάσχτε → συμμετάσχετε (first) in the table of συμμετέχω: active imperative perfective plural second-person
- συνεδύασε (drop) in the table of συνδυάζω: active imperative perfective second-person singular
- συνέταξε (drop) in the table of συντάσσω: active imperative perfective second-person singular
- συνέτασσε (drop) in the table of συντάσσω: active imperative imperfective second-person singular
- έτσουξε (drop) in the table of τσούζω: active imperative perfective second-person singular
- έτσουζε (drop) in the table of τσούζω: active imperative imperfective second-person singular
- υπάρξαμε → υπήρξαμε (first) in the table of υπάρχω: active first-person indicative past perfective plural
- υπάρξατε → υπήρξατε (first) in the table of υπάρχω: active indicative past perfective plural second-person
- υπερέβαινε (drop) in the table of υπερβαίνω: active imperative imperfective second-person singular
- υπέφερε (drop) in the table of υποφέρω: active imperative perfective second-person singular
- υπέφερε (drop) in the table of υποφέρω: active imperative imperfective second-person singular
- χαμογέλασε → χαμογέλα (first) in the table of χαμογελάω: active imperative perfective second-person singular

### Imperative cells spelt like a past form (40, all; #362)

The past-form flag and the row of `forms-fixes.tsv` that reviewed it; a flag without a `drop` or `keep` row fails the build.

- ανέκραξε in the table of ανακράζω: active imperative perfective second-person singular: drop
- ανέκραζε in the table of ανακράζω: active imperative imperfective second-person singular: drop
- ανέκτησε in the table of ανακτώ: active imperative perfective second-person singular: drop
- ανέτρεφε in the table of ανατρέφω: active imperative imperfective second-person singular: drop
- απεκόμισε in the table of αποκομίζω: active imperative perfective second-person singular: drop
- αποσυνέδεσε in the table of αποσυνδέω: active imperative perfective second-person singular: drop
- απέτυχε in the table of αποτυγχάνω: active imperative perfective second-person singular: drop
- βόγγηξε in the table of βογκάω: active imperative perfective second-person singular: keep
- βόγγησε in the table of βογκάω: active imperative perfective second-person singular: keep
- διήνυσε in the table of διανύω: active imperative perfective second-person singular: drop
- διήρκεσε in the table of διαρκώ: active imperative perfective second-person singular: drop
- διέσχισε in the table of διασχίζω: active imperative perfective second-person singular: drop
- διέσχιζε in the table of διασχίζω: active imperative imperfective second-person singular: drop
- διέφερε in the table of διαφέρω: active imperative perfective second-person singular: drop
- διέφερε in the table of διαφέρω: active imperative imperfective second-person singular: drop
- ελάφρυνε in the table of ελαφραίνω: active imperative imperfective second-person singular: drop
- ήλπισε in the table of ελπίζω: active imperative perfective second-person singular: drop
- επαναπροώθησε in the table of επαναπροωθώ: active imperative perfective second-person singular: keep
- επέζησε in the table of επιζώ: active imperative perfective second-person singular: drop
- καρτέρησε in the table of καρτερώ: active imperative perfective second-person singular: keep
- καρτέραγε in the table of καρτερώ: active imperative imperfective second-person singular: drop
- έμπαινε in the table of μπαίνω: active imperative imperfective informal second-person singular: keep
- παρήγαγε in the table of παράγω: active imperative perfective second-person singular: drop
- παρήγε in the table of παράγω: active imperative imperfective second-person singular: drop
- παρέτεινε in the table of παρατείνω: active imperative perfective second-person singular: drop
- παρέτεινε in the table of παρατείνω: active imperative imperfective second-person singular: drop
- πρέβαλε in the table of προβάλλω: active imperative perfective second-person singular: drop
- πρέβαλλε in the table of προβάλλω: active imperative imperfective second-person singular: drop
- προέτεινε in the table of προτείνω: active imperative perfective second-person singular: drop
- προέτεινε in the table of προτείνω: active imperative imperfective second-person singular: drop
- έσπευσε in the table of σπεύδω: active imperative perfective second-person singular: drop
- έσπευδε in the table of σπεύδω: active imperative imperfective second-person singular: drop
- συνεδύασε in the table of συνδυάζω: active imperative perfective second-person singular: drop
- συνέταξε in the table of συντάσσω: active imperative perfective second-person singular: drop
- συνέτασσε in the table of συντάσσω: active imperative imperfective second-person singular: drop
- έτσουξε in the table of τσούζω: active imperative perfective second-person singular: drop
- έτσουζε in the table of τσούζω: active imperative imperfective second-person singular: drop
- υπερέβαινε in the table of υπερβαίνω: active imperative imperfective second-person singular: drop
- υπέφερε in the table of υποφέρω: active imperative perfective second-person singular: drop
- υπέφερε in the table of υποφέρω: active imperative imperfective second-person singular: drop

### Unresolved link targets (top 50)

ενδεδειγμένος (11), στρογγύλος (11), αβάς (8), αββάς (8), λυσιτελής (7), παρασύρω (7), γάτος (6), παραβάζω (6), συμπεριλαμβανόμενος (6), αγγαρείας (5), αγυιόπαις (5), εξελίσσομαι (5), πρωτομάρτυς (5), τετρακισεκατομμύριο (5), ψευδώνυμος (5), αποκλήωση (4), επισημαίνομαι (4), καουμπόικος (4), παρασέρνω (4), παρασημοφορούμαι (4), περισπώμενος (4), πο-πό (4), συλλαμβάνομαι (4), υποβάλλομαι (4), φέρι μποτ (4), ψαρής (4), Ωρίωνας (3), ήλιος m (3), αγκιό (3), αγριοτριαντάφυλλο (3), αλατοποθήκη (3), αμυχής (3), αποθεραπεύομαι (3), ασκεψία (3), βοοειδής (3), γκιό (3), δασύλλιο (3), δευτεραγωνιστής (3), διασώζομαι (3), διατίθεμαι (3), εξελίσσω (3), καθυστέρησης (3), κακάρισμα (3), πιόνιο (3), ρέμα (3), σταυρωμένος (3), συμπρωταγωνιστής (3), τριταγωνιστής (3), χαμομίλι (3), ψαρός (3)

## Coverage

| Gate | Measured | Needed | Result |
|---|---|---|---|
| Top-500 verbs covered | 96.4% | ≥ 95% | pass |
| Top-500 nouns covered | 95.4% | ≥ 90% | pass |
| Top-5,000 findable | 89.2% | ≥ 87% | pass |
| Stoplisted forms mapping to a verb | 0 | 0 | pass |
| Forms tables | 24.3 MB | ≤ 25 MB | pass |
| Table fixes (forms-fixes.tsv) whose wrong form is in the subset | 99 of 99 | all | pass |
| Imperative cells spelt like a past form (#362) with a drop or keep row | 40 of 40 | all | pass |

**Top-500 verbs**: covered 482 of 500 (96.4%): own table 437, via a linked lemma 45. Missing (18): συμβαίνει, συμβαίνω, υποθέτω, πυροβολώ, ξαναβλέπω, μέλλων, χαρούμενος, προηγούμενος, παρελθών, μεγαλώνω, λειτουργώ, αναλαμβάνω, μεθυσμένος, καταραμένος, επιτίθεμαι, έστω, ξεφεύγω, ξεπερνάω.

**Top-500 nouns**: covered 477 of 500 (95.4%): own table 468, via a linked lemma 9. Missing (23): ΝΑ, είναι, όχι, ναι, γιατί, εγώ, έτσι, δυο, δύο, σήμερα, πάλι, πιστεύω, αύριο, χθες, αντίο, αντρέ, ρε, ραντεβού, πάρτι, σεξ, πολλοί, ντετέκτιβ, μπαρ.

**Top-500 adjectives (reported, not gated)**: covered 485 of 500 (97.0%): own table 482, via a linked lemma 3. Missing (15): πανέ, σκατά, καφέ, πρώην, ιατρικός, μπλε, γκέι, επιπλέον, ενάντιος, επικεφαλής, τζιν, σέξι, ροζ, σούπερ, πνευματικός.

**Top-5,000 subtitle tokens**:

- headword: 1,944 (38.9%)
- via forms: 2,518 (50.4%)
- lemma missing from the dictionaries: 220 (4.4%): σας, μας, σ, απ, ακόμα, μ, μη, κοίτα, σένα, εσένα, ε, συνέβη, τ, χθες, συμβεί, εμάς, γύρω, εσάς, τζακ, πλέον, θ, τζον, ρωτήσω, όντως, μάικλ
- unknown: 275 (5.5%): γι, ΄, κ., vα, τo, κε, δρ., δεv, άλλον, σαμ, στ, τζο, υποτίθεται, οκ, τον., είvαι, τσάρλι, κου, τομ, φρανκ, μoυ, tι, πρεπε, δώσ, σα
- not Greek: 43 (0.9%): o, the, i, s, team, fbi, to, d, a, season, you, episode, t, apos, dna, and, h, of, ok, hey, oh, by, it, cia, for

## Size and table hashes

| Table | Rows | Bytes (dbstat) | sha256 of the rows in key order |
|---|---|---|---|
| `lemma` | 27,352 | 3,170,304 | `e57399c4ea3ee798431d4fcfff0333a16314ed4a7f39fd1c791df0213f55e963` |
| `tagset` | 971 | 106,496 | `bab8fedf90b4d8f7bca08841fa47a92723b5a36eab92cc8a85bb757b54da0718` |
| `paradigm` | 390,583 | 12,967,936 | `a2e3dd19e2507c3252d97b138b4d4be69eed435b6b43904b84bd0b5187cbd894` |
| `form_lookup` | 247,477 | 7,806,976 | `bb3f3a26fcc787b27aefb2c37f76d6f6ee91b43950acef2f69f20e92b7eb78e3` |
| `form_link` | 8,994 | 249,856 | `2ee70e32a632bd223068040e8441fb7220a5d078bc9ac20d790bd87567e027a9` |
| total | | 24,301,568 | |
