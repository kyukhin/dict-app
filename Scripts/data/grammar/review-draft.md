# Greek A1 grammar: review draft (first pass, corrected)

For Kirill's first review pass of #173 (spec `docs/specs/0133-grammar.md`): the 17 A1 topics in order, as drafted in `Scripts/data/grammar/eng/`. Drafted with AI from its own knowledge of Greek; no textbook, website or ΚΕΓ text was used.

**What to check in this pass:** the rule, the written tables, the examples and Watch out. Verb and noun tables are `forms` blocks here: the build (#171) fills them from the Wiktionary forms, and they come back for the second pass in `Scripts/reports/grammar-review.md`.

**How to answer:** tick the checklist under each topic, correct the text in place or in a note, and answer every ⚠ item (search for the sign). The corrections go into the topic files before the hashes go into `reviewed.tsv`.

**Applied from your notes** (`review-draft-notes.md`, 2026-11-04): all 20 rows of the error table, recommendations 1 and 3 to 6, and your answers to the ⚠ items. Recommendation 2 is in `forms-checklist.md`, recommendation 7 in `README.md` (for 2.1). All ⚠ items are resolved.

**Decisions across topics**

- Decided: a bold caption line replaces a forms block's default caption, never both.
- Decided: front matter keys with no value (`tenses`, `classes`, `words`) are left out, not written empty.
- Fixed after the first pass: in Noun endings, feminine nouns in -ος drop the -ς like masculine ones (την οδό), so the Watch out now says neuter nouns in -ος keep it.

## Contents

1. The alphabet, the stress mark and the diaeresis (`ell-alphabet`)
2. Articles and gender (`ell-articles`)
3. Noun endings: nominative and accusative (`ell-noun-endings`)
4. Adjective agreement (`ell-adjectives`)
5. Personal pronouns, strong and weak (`ell-pronouns`)
6. Possessives (`ell-possessives`)
7. είμαι and έχω (`ell-eimai-echo`)
8. Present tense: first conjugation (`ell-present-1`)
9. Present tense: second conjugation (`ell-present-2`)
10. Negation and question words (`ell-negation-questions`)
11. σε + article and basic prepositions (`ell-se-prepositions`)
12. Numbers, time and dates (`ell-numbers-time`)
13. The aorist of regular verbs and the augment (`ell-aorist-regular`)
14. Irregular aorists (`ell-aorist-irregular`)
15. The future with θα (`ell-future`)
16. να + the simple form (`ell-na-perfective`)
17. The imperative (`ell-imperative`)

---

## 1. The alphabet, the stress mark and the diaeresis

`ell-alphabet` · A1, order 1 · rule 107 words

- **Related topics:** Articles and gender

Greek has 24 letters. Seven are vowels: α, ε, η, ι, ο, υ, ω. η, ι and υ all sound "i", as in machine; ο and ω both sound "o". Σ is written ς at the end of a word: *σας*. Some pairs of letters make one sound: see the second table.

Every word of two or more syllables has a stress mark, the *τόνος*, on its stressed vowel: *μήλο*, *καφές*. On a capital it stands before the letter: *Άννα*. It can change the meaning: *πότε*, when, but *ποτέ*, never.

The diaeresis, *διαλυτικά*, shows that two vowels are said apart, not as a pair: *προϊόν* (pro-i-ón), *Αϊτή* (a-i-tí).

**Letters**

| Letter | Name | Sound |
|---|---|---|
| Α α | άλφα | a, as in father |
| Β β | βήτα | v |
| Γ γ | γάμα | y before e and i; elsewhere a g said with the throat open, like Spanish g in lago (never like g in gem) |
| Δ δ | δέλτα | th, as in this |
| Ε ε | έψιλον | e, as in pet |
| Ζ ζ | ζήτα | z |
| Η η | ήτα | i, as in machine |
| Θ θ | θήτα | th, as in think |
| Ι ι | γιώτα | i, as in machine |
| Κ κ | κάπα | k |
| Λ λ | λάμδα | l |
| Μ μ | μι | m |
| Ν ν | νι | n |
| Ξ ξ | ξι | x, as in box |
| Ο ο | όμικρον | o, as in lot |
| Π π | πι | p |
| Ρ ρ | ρο | r, rolled |
| Σ σ ς | σίγμα | s |
| Τ τ | ταυ | t |
| Υ υ | ύψιλον | i, as in machine |
| Φ φ | φι | f |
| Χ χ | χι | h, like ch in Scottish loch |
| Ψ ψ | ψι | ps, as in lips |
| Ω ω | ωμέγα | o, as in lot |

**Letter pairs**

| Pair | Sound | Example |
|---|---|---|
| ου | u, as in food | μουσική |
| αι | e, as in pet | και |
| ει, οι | i, as in machine | είναι, οικογένεια |
| αυ, ευ | av, ev; af, ef before θ, κ, ξ, π, σ, τ, φ, χ, ψ | αύριο, ευχαριστώ |
| μπ | b, or mb inside a word | μπλε |
| ντ | d, or nd inside a word | ντομάτα |
| γκ | g, or ng inside a word | γκρι |
| γγ | ng | Αγγλία |
| τσ | ts | τσάι |
| τζ | dz | τζάμι |

### Examples

- Πού είναι το μουσείο;
  Where is the museum?
- Ο παππούς μου είναι γέρος, αλλά γερός.
  My grandfather is old, but strong.
- Θέλεις τσάι ή καφέ;
  Would you like tea or coffee?
- Αυτό το προϊόν είναι ευρωπαϊκό.
  This product is European.

### Watch out

- Words of one syllable have no stress mark: *και*, *το*, *θα*. The exceptions are *ή*, or, and the question words *πού* and *πώς*: *Πού μένεις;*, Where do you live?
- The Greek question mark looks like an English semicolon: *Τι κάνεις;*, How are you?

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 2. Articles and gender

`ell-articles` · A1, order 2 · rule 114 words

- **Words:** ο, η, το, ένας
- **Related topics:** Noun endings: nominative and accusative, σε + article and basic prepositions
- **Classes:** noun

Every Greek noun is masculine, feminine or neuter, and its article shows which: *ο δρόμος*, *η πόρτα*, *το σπίτι*. Learn each noun with its article.

The ending is a good guide:
- masculine: -ος, -ας, -ης: *ο φίλος*, *ο πατέρας*, *ο μαθητής*;
- feminine: -α, -η: *η μητέρα*, *η κόρη*;
- neuter: -ο, -ι, -μα: *το βιβλίο*, *το παιδί*, *το όνομα*.

The article changes with the noun. Use the nominative for the subject and after *είμαι*: *Η Άννα είναι γιατρός*. Use the accusative for the object and after prepositions: *Ο Νίκος ξέρει τον Πέτρο*, Nikos knows Petros.

*ένας*, *μία*, *ένα* means both "a" and "one". In the plural there is no "a": *Έχω φίλους*, I have friends.

**The: ο, η, το**

| | Masculine | Feminine | Neuter |
|---|---|---|---|
| Nominative singular | ο | η | το |
| Accusative singular | τον | τη / την | το |
| Nominative plural | οι | οι | τα |
| Accusative plural | τους | τις | τα |

**A, one: ένας, μία, ένα**

| | Masculine | Feminine | Neuter |
|---|---|---|---|
| Nominative | ένας | μία / μια | ένα |
| Accusative | έναν | μία / μια | ένα |

### Examples

- Η Άννα έχει έναν σκύλο και μια γάτα.
  Anna has a dog and a cat.
- Ο καφές είναι κρύος.
  The coffee is cold.
- Οι γονείς μου μένουν στην Κρήτη.
  My parents live in Crete.
- Ξέρεις τη Μαρία;
  Do you know Maria?
- Θέλω ένα νερό, παρακαλώ.
  I'd like a water, please.

### Watch out

- -ος is not always masculine: *η οδός*, *η Ρόδος*; *το λάθος*, *το μέρος*, *το μέγεθος*. Trust the article, not the ending.
- Names take the article too: *Η Μαρία μένει εδώ*, not ~~Μαρία μένει εδώ~~. And *την* keeps its ν only before a vowel and before κ, π, τ, ξ, ψ, μπ, ντ, γκ, τσ, τζ: *την Άννα*, *την πόρτα*, but *τη Μαρία*. *τον* and *έναν* always keep it.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 3. Noun endings: nominative and accusative

`ell-noun-endings` · A1, order 3 · rule 113 words

- **Words:** δρόμος, πατέρας, μαθητής, γυναίκα, κόρη, βιβλίο, σπίτι, όνομα
- **Related topics:** Articles and gender, Adjective agreement
- **Classes:** noun

A noun changes its ending with case and number. At A1 you need two cases: the nominative for the subject, and the accusative for the object and after prepositions: *Ο φίλος μου μένει εδώ*, but *Περιμένω τον φίλο μου*.

- Masculine nouns drop the -ς in the accusative singular: *ο φίλος*, *τον φίλο*; *ο πατέρας*, *τον πατέρα*. In the plural, -ος becomes -οι and -ους; -ας and -ης become -ες.
- Feminine and neuter nouns look the same in both cases; only the article may change: *η γυναίκα*, *τη γυναίκα*.
- In the plural, feminine -α and most -η become -ες: *η κόρη*, *οι κόρες*. Neuter -ο becomes -α, -ι becomes -ια, and -μα becomes -ματα.

**Masculine**

*Forms table, filled by the build (second pass):*

```forms
words: δρόμος, πατέρας, μαθητής
headers: ο δρόμος, ο πατέρας, ο μαθητής
```

**Feminine**

*Forms table, filled by the build (second pass):*

```forms
words: γυναίκα, κόρη
headers: η γυναίκα, η κόρη
```

**Neuter**

*Forms table, filled by the build (second pass):*

```forms
words: βιβλίο, σπίτι, όνομα
headers: το βιβλίο, το σπίτι, το όνομα
```

### Examples

- Ο πατέρας μου είναι γιατρός.
  My father is a doctor.
- Περιμένω τον φίλο μου.
  I'm waiting for my friend.
- Η γυναίκα του έχει δύο κόρες.
  His wife has two daughters.
- Οι μαθητές διαβάζουν τα βιβλία τους.
  The students are reading their books.
- Τα σπίτια εδώ είναι μικρά.
  The houses here are small.

### Watch out

- Masculine nouns drop the -ς in the accusative singular: *Ξέρω τον Νίκο*, not ~~Ξέρω τον Νίκος~~. Neuter nouns in -ος keep it: *Κάνω ένα λάθος*.
- Some plurals are different: *η πόλη*, *οι πόλεις*; *η λέξη*, *οι λέξεις*; *η άσκηση*, *οι ασκήσεις*; *ο καφές*, *οι καφέδες*; *ο παππούς*, *οι παππούδες*. In others the stress moves: *το όνομα*, *τα ονόματα*; *ο άνθρωπος*, *τους ανθρώπους*.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 4. Adjective agreement

`ell-adjectives` · A1, order 4 · rule 92 words

- **Words:** καλός, ωραίος
- **Related topics:** Noun endings: nominative and accusative
- **Classes:** adj

An adjective takes the gender, case and number of its noun: *ο καλός φίλος*, *η καλή φίλη*, *το καλό παιδί*, *τα καλά παιδιά*.

Most adjectives end like *καλός*: -ος, -η, -ο. When a vowel comes before the ending, the feminine ends in -α: *ωραίος*, *ωραία*, *ωραίο*; *νέος*, *νέα*, *νέο*.

The adjective usually stands between the article and the noun: *το μεγάλο σπίτι*, the big house. After *είμαι* it agrees too: *Η πόλη είναι μεγάλη*, The city is big.

Masculine adjectives change like masculine nouns in -ος: *τον καλό φίλο*, *οι καλοί φίλοι*.

**καλός, good**

*Forms table, filled by the build (second pass):*

```forms
words: καλός
genders: masculine, feminine, neuter
```

**ωραίος, beautiful**

*Forms table, filled by the build (second pass):*

```forms
words: ωραίος
genders: masculine, feminine, neuter
```

### Examples

- Ο Νίκος είναι καλός φίλος.
  Nikos is a good friend.
- Η Αθήνα είναι μεγάλη πόλη.
  Athens is a big city.
- Έχουμε ένα μικρό σπίτι με ωραίο κήπο.
  We have a small house with a nice garden.
- Τα κόκκινα παπούτσια είναι ακριβά.
  The red shoes are expensive.
- Θέλω έναν μεγάλο καφέ, παρακαλώ.
  I'd like a large coffee, please.

### Watch out

- Follow the noun's gender, not its ending: *το πρόβλημα* is neuter, so *ένα μεγάλο πρόβλημα*; *οδός*, street, is feminine, so *η κεντρική οδός*, not ~~η κεντρικός οδός~~.
- *πολύ*, very, never changes: *πολύ καλή*, *πολύ ωραία*. "Many" is *πολλοί*, *πολλές*, *πολλά*: *πολλά παιδιά*.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 5. Personal pronouns, strong and weak

`ell-pronouns` · A1, order 5 · rule 98 words

- **Words:** εγώ, εσύ, αυτός, εμείς, εσείς, αυτοί
- **Related topics:** Possessives, The imperative

The verb ending already shows the person, so the subject pronoun is usually left out: *Μένω στην Αθήνα*, I live in Athens. Say *εγώ*, *εσύ* and the others for emphasis or contrast: *Εγώ μένω εδώ, εσύ μένεις εκεί*.

Objects have two forms:
- the weak form is short and unstressed, and goes right before the verb: *Σε ξέρω*, I know you; *Τον βλέπω*, I see him;
- the strong form is for emphasis and after prepositions: *Αυτό είναι για εσένα*, This is for you.

*εσείς* is also the polite "you" for one person: *Εσείς πώς είστε;*, And how are you?

**Subject and object**

| | Subject | Object, strong | Object, weak |
|---|---|---|---|
| I, me | εγώ | εμένα | με |
| you | εσύ | εσένα | σε |
| he, him | αυτός | αυτόν | τον |
| she, her | αυτή | αυτή / αυτήν | την |
| it | αυτό | αυτό | το |
| we, us | εμείς | εμάς | μας |
| you, plural or polite | εσείς | εσάς | σας |
| they, them: masculine | αυτοί | αυτούς | τους |
| they, them: feminine | αυτές | αυτές | τις |
| they, them: neuter | αυτά | αυτά | τα |

### Examples

- Πώς σε λένε; Με λένε Άννα.
  What's your name? My name is Anna.
- Ξέρεις τον Πέτρο; Ναι, τον ξέρω.
  Do you know Petros? Yes, I know him.
- Εμείς είμαστε από την Ιταλία. Εσείς;
  We are from Italy. And you?
- Αυτό το δώρο είναι για εσένα.
  This present is for you.
- Τους βλέπω κάθε Σάββατο.
  I see them every Saturday.

### Watch out

- The weak form goes before the verb: *Σε αγαπώ*, not ~~Αγαπώ σε~~. After *δεν* or *θα* it still comes right before the verb: *Δεν τον ξέρω*. The exception is after an imperative: *Πες μου* (see The imperative).
- After a preposition, *εμένα* and *εσένα* are often short: *για μένα*, *με σένα*.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 6. Possessives

`ell-possessives` · A1, order 6 · rule 88 words

- **Words:** μου, σου, δικός
- **Related topics:** Personal pronouns, strong and weak

For "my", "your" and the others, Greek puts a short word after the noun and keeps the article: *το σπίτι μου*, my house; *η μητέρα σου*, your mother. The short word does not change with the noun: *ο φίλος μου*, *οι φίλοι μου*.

"His" and "its" are *του*, "her" is *της*, "their" is *τους*: *η γάτα της*, her cat.

For "mine", "yours" and the others, use *δικός* with the short word. *δικός* agrees with the noun like an adjective: *Το κινητό είναι δικό μου*, The phone is mine.

**After the noun, and with δικός**

| | After the noun | Mine, yours … |
|---|---|---|
| my, mine | μου | δικός μου |
| your, yours | σου | δικός σου |
| his, its | του | δικός του |
| her, hers | της | δικός της |
| our, ours | μας | δικός μας |
| your, yours: plural or polite | σας | δικός σας |
| their, theirs | τους | δικός τους |

**δικός agrees with the noun**

| | Masculine | Feminine | Neuter |
|---|---|---|---|
| Singular | δικός μου | δική μου | δικό μου |
| Plural | δικοί μου | δικές μου | δικά μου |

### Examples

- Αυτή είναι η αδερφή μου, η Ελένη.
  This is my sister, Eleni.
- Πού είναι τα κλειδιά σου;
  Where are your keys?
- Ο γιος τους μένει στη Θεσσαλονίκη.
  Their son lives in Thessaloniki.
- Ποιανού είναι αυτό το βιβλίο; Είναι δικό μου.
  Whose book is this? It's mine.
- Το όνομά μου είναι Πέτρος.
  My name is Petros.

### Watch out

- Keep the article: *Η μητέρα μου είναι γιατρός*, not ~~Μητέρα μου είναι γιατρός~~. A noun stressed on the third syllable from the end gets a second stress mark before *μου*, *σου* and the others: *το όνομά μου*, *το τηλέφωνό σου*.
- The same short words also mean "to me", "to you". With *αρέσει*, the verb agrees with the thing you like: *Μου αρέσει η θάλασσα*, I like the sea; *Μου αρέσουν τα ζώα*, I like animals.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 7. είμαι and έχω

`ell-eimai-echo` · A1, order 7 · rule 97 words

- **Words:** είμαι, έχω
- **Related topics:** Present tense: first conjugation, The future with θα
- **Tenses:** present (button: Practise · Present)

*είμαι*, to be, and *έχω*, to have, are the most common Greek verbs. *είμαι* has its own endings, which you learn by heart. *έχω* takes the regular endings of *γράφω*.

*είμαι* says who, what, where or how someone is: *Είμαι δασκάλα*, I'm a teacher; *Είμαστε στο σπίτι*, We're at home; *Είσαι καλά;*, Are you OK?

*έχω* is for what you have, also family and time: *Έχω έναν αδερφό*, I have a brother; *Έχεις χρόνο;*, Do you have time?

Neither verb has an aorist. Their past is *ήμουν* and *είχα*, and their future *θα είμαι* and *θα έχω*.

**Present**

*Forms table, filled by the build (second pass):*

```forms
words: είμαι, έχω
tense: present
```

### Examples

- Από πού είσαι; Είμαι από την Αγγλία.
  Where are you from? I'm from England.
- Η Άννα είναι γιατρός.
  Anna is a doctor.
- Τα παιδιά είναι στο σχολείο.
  The children are at school.
- Έχουμε δύο παιδιά, έναν γιο και μια κόρη.
  We have two children, a son and a daughter.
- Έχεις χρόνο αύριο;
  Do you have time tomorrow?

### Watch out

- Age goes with *είμαι*: *Είμαι είκοσι χρονών*, I'm twenty, not ~~Έχω είκοσι χρόνια~~.
- *είναι* is both "is" and "are": *Ο Νίκος είναι εδώ*, *Οι φίλοι μου είναι εδώ*.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 8. Present tense: first conjugation

`ell-present-1` · A1, order 8 · rule 93 words

- **Words:** γράφω, δουλεύω
- **Related topics:** Present tense: second conjugation, Negation and question words
- **Tenses:** present (button: Practise · Present)
- **Classes:** verb.conj1

The present says what happens now, often or always. Greek has one present for both "I work" and "I'm working": *Δουλεύω σε ένα γραφείο*, *Τώρα γράφω ένα μήνυμα*.

Most verbs end in an unstressed -ω: *γράφω*, *δουλεύω*, *μένω*. They are the first conjugation and take these endings:
- -ω, -εις, -ει for I, you, he, she, it;
- -ουμε, -ετε, -ουν for we, you, they.

The stress stays on the same syllable: *γράφω*, *γράφουμε*.

A Greek verb is listed in its "I" form: *γράφω* is "I write", and the dictionary gives it for "to write".

**Present**

*Forms table, filled by the build (second pass):*

```forms
words: γράφω, δουλεύω
tense: present
```

### Examples

- Δουλεύω σε ένα ξενοδοχείο.
  I work in a hotel.
- Τι διαβάζεις; Ένα βιβλίο για την Κρήτη.
  What are you reading? A book about Crete.
- Ο Νίκος μένει κοντά στη θάλασσα.
  Nikos lives near the sea.
- Τα παιδιά παίζουν στο πάρκο.
  The children are playing in the park.
- Πού δουλεύετε;
  Where do you work?

### Watch out

- *λέω*, *τρώω*, *ακούω* and *πάω* have short forms: *λες*, *λέει*, *λέμε*, *λέτε*, *λένε*; *τρως*, *τρώει*, *τρώμε*; *ακούς*, *ακούει*, *ακούμε*; *πάω*, *πας*, *πάει*, *πάμε*, *πάτε*, *πάνε*.
- Don't add *είμαι* for "-ing": *Γράφω*, I'm writing, not ~~Είμαι γράφω~~. And you will hear *γράφουνε*; write *γράφουν*.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 9. Present tense: second conjugation

`ell-present-2` · A1, order 9 · rule 87 words

- **Words:** αγαπάω, μιλάω, μπορώ, ζω
- **Related topics:** Present tense: first conjugation
- **Tenses:** present (button: Practise · Present)
- **Classes:** verb.conj2

Verbs whose "I" form ends in a stressed -άω or -ώ are the second conjugation. The stress is always on the ending. They come in two groups:
- like *αγαπάω*: -άω, -άς, -άει, -άμε, -άτε, -άνε. Also *μιλάω*, *ρωτάω*, *πεινάω*;
- like *μπορώ*: -ώ, -είς, -εί, -ούμε, -είτε, -ούν. Also *ζω*, *οδηγώ*, *τηλεφωνώ*.

The first group has a second set of endings, just as correct: *αγαπώ*, *αγαπά*, *αγαπούν*.

A verb listed in -ώ can belong to either group, so learn it with its "you" form: *μπορώ*, *μπορείς*; *απαντώ*, *απαντάς*.

**Present**

*Forms table, filled by the build (second pass):*

```forms
words: αγαπάω, μπορώ
tense: present
```

### Examples

- Μιλάς ελληνικά; Ναι, λίγο.
  Do you speak Greek? Yes, a little.
- Τα παιδιά αγαπάνε τα ζώα.
  Children love animals.
- Δεν μπορώ σήμερα, έχω δουλειά.
  I can't today, I'm busy.
- Η γιαγιά μου ζει στην Κρήτη.
  My grandmother lives in Crete.
- Πεινάτε, παιδιά;
  Are you hungry, kids?

### Watch out

- Don't mix the groups: *μιλάς*, not ~~μιλείς~~; *μπορείς*, not ~~μποράς~~.
- *ζω* goes like *μπορώ*, but its one-syllable forms have no stress mark: *ζεις*, *ζει*, *ζουν*.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 10. Negation and question words

`ell-negation-questions` · A1, order 10 · rule 104 words

- **Words:** δεν, μην, όχι, τι, ποιος, πού, πότε, πώς, γιατί, πόσος, ποιανού
- **Related topics:** Present tense: first conjugation

Put *δεν* right before the verb to say "not": *Δεν ξέρω*, I don't know. A weak pronoun stays between them: *Δεν τον ξέρω*, I don't know him.

*όχι* means "no", and "not" when there is no verb: *Όχι, ευχαριστώ*; *Θέλω τσάι, όχι καφέ*.

*μην* means "don't" when you tell someone not to do something: *Μην τρέχεις!*, Don't run!

A yes-no question has the same words as a statement; only the voice rises at the end: *Μιλάς ελληνικά;* The Greek question mark looks like an English semicolon.

Other questions start with a question word, usually followed by the verb: *Πού μένεις;*, Where do you live?

**Question words**

| | Meaning |
|---|---|
| τι | what |
| ποιος, ποια, ποιο | who, which |
| πού | where |
| πότε | when |
| πώς | how |
| γιατί | why; because |
| πόσο | how much |
| πόσοι, πόσες, πόσα | how many |
| ποιανού | whose |

### Examples

- Δεν μιλάω γαλλικά.
  I don't speak French.
- Θέλεις καφέ; Όχι, ευχαριστώ.
  Would you like a coffee? No, thank you.
- Ποιος είναι αυτός; Είναι ο αδερφός μου.
  Who is he? He's my brother.
- Γιατί δεν τρως; Δεν πεινάω.
  Why aren't you eating? I'm not hungry.
- Πότε αρχίζει το μάθημα;
  When does the lesson start?

### Watch out

- *πού* with a stress mark asks "where": *Πού είσαι;* Without it, *που* means "that" or "who": *ο φίλος που μένει εδώ*.
- With *τίποτα*, nothing, and *ποτέ*, never, keep *δεν*: *Δεν ξέρω τίποτα*, I know nothing; *Δεν πίνω ποτέ καφέ*, I never drink coffee.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 11. σε + article and basic prepositions

`ell-se-prepositions` · A1, order 11 · rule 99 words

- **Words:** σε, από, με, για
- **Related topics:** Articles and gender

*σε* means "in", "at", "on" or "to": *Μένω στην Αθήνα*, I live in Athens; *Πάω στο σχολείο*, I'm going to school. Before the article *ο*, *η*, *το* it joins with it: *σε* + *το* = *στο*. Before other words it stays *σε*: *σε ένα ξενοδοχείο*, also *σ' ένα*.

Three more prepositions are everywhere:
- *από*, from: *από την Ιταλία*, *από τις εννιά*;
- *με*, with, and by for transport: *με τον φίλο μου*, *με το λεωφορείο*;
- *για*, for and about: *για τη Μαρία*, *ένα βιβλίο για την Κρήτη*.

After all four, the noun and its article are in the accusative: *από τον Πέτρο*.

**σε + article**

| | Masculine | Feminine | Neuter |
|---|---|---|---|
| Singular | στον | στη / στην | στο |
| Plural | στους | στις | στα |

### Examples

- Μένω στην Αθήνα και δουλεύω στο κέντρο.
  I live in Athens and work in the centre.
- Είμαι από την Ιταλία.
  I'm from Italy.
- Πάμε στη θάλασσα με το αυτοκίνητο.
  We're going to the sea by car.
- Αγοράζω λουλούδια για τη γιαγιά μου.
  I'm buying flowers for my grandmother.
- Το μάθημα αρχίζει στις εννιά.
  The lesson starts at nine.

### Watch out

- *σε* always joins the article: *στο σπίτι*, never ~~σε το σπίτι~~. Before *ένα* it stays: *σε ένα σπίτι*, also *σ' ένα σπίτι*.
- "Home" needs no preposition: *Πάω σπίτι*, I'm going home; *Είμαι σπίτι*, I'm at home. *στο σπίτι* is also right.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 12. Numbers, time and dates

`ell-numbers-time` · A1, order 12 · rule 113 words

- **Words:** ένας, δύο, τρία, ώρα
- **Related topics:** Articles and gender

Most numbers never change. 1, 3 and 4 agree with the noun, like adjectives: *ένας καφές*, *μία μπίρα*, *ένα νερό*; *τρεις φίλοι*, *τρία παιδιά*. To count, use the neuter: *ένα*, *δύο*, *τρία*, *τέσσερα*. For 7, 8 and 9, say *εφτά*, *οχτώ*, *εννιά*; *επτά*, *οκτώ*, *εννέα* are formal.

For the time, use *είναι* and the feminine forms, because *ώρα*, hour, is feminine: *Είναι μία*, It's one o'clock; *Είναι τρεις και μισή*, It's half past three. "At" is *στις*: *στις οχτώ*, at eight; at one o'clock is *στη μία*.

For dates, say the number and the month in the genitive: *στις πέντε Μαΐου*, on the fifth of May. The first is *η πρώτη*: *την πρώτη Ιουνίου*, on the first of June.

**Numbers**

| | Greek |
|---|---|
| 0 | μηδέν |
| 1 | ένα |
| 2 | δύο |
| 3 | τρία |
| 4 | τέσσερα |
| 5 | πέντε |
| 6 | έξι |
| 7 | εφτά / επτά |
| 8 | οχτώ / οκτώ |
| 9 | εννιά / εννέα |
| 10 | δέκα |
| 11 | έντεκα |
| 12 | δώδεκα |
| 13 | δεκατρία |
| 14 | δεκατέσσερα |
| 15 | δεκαπέντε |
| 16 | δεκαέξι |
| 17 | δεκαεφτά / δεκαεπτά |
| 18 | δεκαοχτώ / δεκαοκτώ |
| 19 | δεκαεννιά / δεκαεννέα |
| 20 | είκοσι |
| 21 | είκοσι ένα |
| 30 | τριάντα |
| 40 | σαράντα |
| 50 | πενήντα |
| 60 | εξήντα |
| 70 | εβδομήντα |
| 80 | ογδόντα |
| 90 | ενενήντα |
| 100 | εκατό |

**1, 3 and 4 with a noun**

| | Masculine | Feminine | Neuter |
|---|---|---|---|
| 1 | ένας | μία / μια | ένα |
| 3 | τρεις | τρεις | τρία |
| 4 | τέσσερις | τέσσερις | τέσσερα |

**Τι ώρα είναι; What time is it?**

| | It's … |
|---|---|
| 1:00 | μία |
| 3:00 | τρεις |
| 3:10 | τρεις και δέκα |
| 3:15 | τρεις και τέταρτο |
| 3:30 | τρεις και μισή |
| 3:45 | τέσσερις παρά τέταρτο |
| 3:50 | τέσσερις παρά δέκα |

### Examples

- Τι ώρα είναι; Είναι τέσσερις και τέταρτο.
  What time is it? It's a quarter past four.
- Το μαγαζί ανοίγει στις εννιά.
  The shop opens at nine.
- Έχω τρεις αδερφές και έναν αδερφό.
  I have three sisters and one brother.
- Θέλουμε δύο καφέδες και ένα νερό.
  We'd like two coffees and a water.
- Τα γενέθλιά μου είναι στις δώδεκα Μαΐου.
  My birthday is on the twelfth of May.

### Watch out

- *τρεις* and *τέσσερις* go with masculine and feminine nouns, *τρία* and *τέσσερα* with neuter ones: *τρεις ώρες*, but *τρία λεπτά*.
- One o'clock is feminine: *στη μία*, not ~~στις ένα~~.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 13. The aorist of regular verbs and the augment

`ell-aorist-regular` · A1, order 13 · rule 102 words

- **Words:** γράφω, διαβάζω, αγοράζω
- **Related topics:** Irregular aorists, The future with θα
- **Tenses:** aorist (button: Practise · Aorist)
- **Classes:** verb

The aorist says what happened and is finished: *έγραψα*, I wrote. It is the everyday past tense.

The stem usually changes, and the endings are -α, -ες, -ε, -αμε, -ατε, -αν:
- -φω, -πω, -βω and -εύω take -ψ-: *γράφω*, *έγραψα*; *δουλεύω*, *δούλεψα*;
- most -ζω and all -ώνω take -σ-: *διαβάζω*, *διάβασα*; *πληρώνω*, *πλήρωσα*; *τελειώνω*, *τελείωσα*;
- -γω, -χω and -κω take -ξ-: *ανοίγω*, *άνοιξα*;
- most -άω and -ώ verbs take -ησ-: *μιλάω*, *μίλησα*.

The stress moves back to the third syllable from the end. When a form has only two syllables, an *έ-*, the augment, is added to carry it: *έγραψα*, but *γράψαμε*.

**Regular verbs**

*Forms table, filled by the build (second pass):*

```forms
words: γράφω, διαβάζω, αγοράζω
tense: aorist
```

### Examples

- Χθες έγραψα ένα γράμμα στη γιαγιά μου.
  Yesterday I wrote a letter to my grandmother.
- Πέρυσι διάβασα πολλά βιβλία.
  Last year I read a lot of books.
- Πού αγόρασες αυτά τα παπούτσια;
  Where did you buy these shoes?
- Το καλοκαίρι ο Νίκος δούλεψε σε μια ταβέρνα.
  In the summer Nikos worked in a taverna.
- Μιλήσαμε στο τηλέφωνο χθες το βράδυ.
  We talked on the phone last night.

### Watch out

- The augment comes and goes with the stress: *έγραψα*, *έγραψες*, *έγραψε*, *έγραψαν*, but *γράψαμε*, *γράψατε*. Longer verbs need none: *διάβασα*, *αγόρασα*, not ~~εδιάβασα~~.
- Some -άω and -ώ verbs take -ασ- or -εσ-: *πεινάω*, *πείνασα*; *διψάω*, *δίψασα*; *ξεχνάω*, *ξέχασα*; *περνάω*, *πέρασα*; *μπορώ*, *μπόρεσα*. And *φεύγω* is *έφυγα*, not ~~έφευξα~~ (see Irregular aorists).

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 14. Irregular aorists

`ell-aorist-irregular` · A1, order 14 · rule 113 words

- **Words:** πηγαίνω, έρχομαι, κάνω, βλέπω, λέω, τρώω, πίνω, βγαίνω, μπαίνω, παίρνω, βρίσκω, μένω
- **Related topics:** The aorist of regular verbs and the augment
- **Tenses:** aorist (button: Practise · Aorist)

Some of the most common verbs have an aorist stem you learn by heart. The endings are the regular ones: -α, -ες, -ε, -αμε, -ατε, -αν.

- *πηγαίνω*, go: *πήγα*
- *έρχομαι*, come: *ήρθα*
- *κάνω*, do, make: *έκανα*
- *βλέπω*, see: *είδα*
- *λέω*, say: *είπα*
- *τρώω*, eat: *έφαγα*
- *πίνω*, drink: *ήπια*
- *βγαίνω*, go out: *βγήκα*
- *μπαίνω*, go in: *μπήκα*
- *παίρνω*, take: *πήρα*
- *βρίσκω*, find: *βρήκα*
- *μένω*, live, stay: *έμεινα*
- *φεύγω*, leave: *έφυγα*
- *δίνω*, give: *έδωσα*
- *ξέρω*, know: *ήξερα* (past)
- *θέλω*, want: *ήθελα* (past)

*έρχομαι* ends in -μαι in the present, but its aorist *ήρθα* has the same endings as the others. *ξέρω* and *θέλω* have no everyday aorist, so learn *ήξερα* and *ήθελα* as their past.

**The stem changes**

*Forms table, filled by the build (second pass):*

```forms
words: πηγαίνω, βλέπω, λέω
tense: aorist
```

**Eat, drink, go out**

*Forms table, filled by the build (second pass):*

```forms
words: τρώω, πίνω, βγαίνω
tense: aorist
```

### Examples

- Χθες πήγαμε στη θάλασσα.
  Yesterday we went to the sea.
- Είδες τον Νίκο;
  Did you see Nikos?
- Τι είπε ο δάσκαλος;
  What did the teacher say?
- Φάγαμε ψάρι και ήπιαμε λίγο κρασί.
  We ate fish and drank a little wine.
- Βρήκα τα κλειδιά μου!
  I found my keys!

### Watch out

- *πήγα* is "I went", once. *πήγαινα* is "I was going" or "I used to go", another tense.
- *έφαγα* loses its *έ-* when the stress moves: *φάγαμε*. But *είδα*, *είπα*, *ήπια* and *ήρθα* keep their first syllable: *είδαμε*, *ήρθαμε*.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 15. The future with θα

`ell-future` · A1, order 15 · rule 114 words

- **Words:** θα
- **Related topics:** να + the simple form, The aorist of regular verbs and the augment
- **Tenses:** future (button: Practise · Future)
- **Classes:** verb

For something that will happen once, put *θα* before the simple form of the verb: *θα γράψω*, I will write.

The simple form has the stem of the aorist, without the augment, and the endings of the present: *έγραψα*, so *θα γράψω*, *θα γράψεις*, *θα γράψουμε*. The second conjugation does the same: *αγάπησα*, so *θα αγαπήσω*.

Verbs with an irregular aorist have short simple forms: *θα πάω*, *θα δω*, *θα πω*, *θα φάω*, *θα πιω*, *θα έρθω*.

*είμαι* and *έχω* have no aorist, so they keep the present: *θα είμαι*, *θα έχω*.

*θα* with the present is for something that will go on or repeat: *Θα γράφω κάθε μέρα*, I will write every day.

**Regular verbs**

*Forms table, filled by the build (second pass):*

```forms
words: γράφω, αγαπάω
tense: future
```

**Irregular verbs**

*Forms table, filled by the build (second pass):*

```forms
words: πηγαίνω, βλέπω, τρώω
tense: future
```

### Examples

- Αύριο θα πάμε στο χωριό.
  Tomorrow we'll go to the village.
- Θα σε δω το Σάββατο.
  I'll see you on Saturday.
- Τι θα φας;
  What are you going to eat?
- Θα σου τηλεφωνήσω το απόγευμα.
  I'll call you in the afternoon.
- Δεν θα έρθω το βράδυ, έχω δουλειά.
  I won't come in the evening, I'm busy.

### Watch out

- *θα* never changes and stands before the verb; only *δεν* goes before *θα*, and a weak pronoun goes between *θα* and the verb: *Δεν θα σε δω*.
- For one action, use the simple form: *Θα πάω αύριο*, not ~~Θα πηγαίνω αύριο~~.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 16. να + the simple form

`ell-na-perfective` · A1, order 16 · rule 117 words

- **Words:** να
- **Related topics:** The future with θα, The imperative
- **Tenses:** subjunctiveSimple (button: Practise · Subjunctive (simple))
- **Classes:** verb

Greek has no infinitive like "to go". After verbs such as *θέλω*, *μπορώ* and *πρέπει*, it uses *να* and a verb with its own person: *Θέλω να πάω*, I want to go; *Θέλεις να πας;*, Do you want to go?

For one action, the verb after *να* takes the simple form (the subjunctive, *υποτακτική*), the same as after *θα*: *να γράψω*, *να πάω*, *να φάω*. For a habit or something that goes on, it keeps the present: *Μου αρέσει να διαβάζω*, I like reading.

*πρέπει* never changes: *Πρέπει να φύγω*, I have to go; *Πρέπει να φύγεις*, You have to go.

*να* on its own makes an offer: *Να ανοίξω το παράθυρο;*, Shall I open the window?

**Simple form**

*Forms table, filled by the build (second pass):*

```forms
words: γράφω, πηγαίνω
tense: subjunctiveSimple
```

### Examples

- Θέλω να μάθω ελληνικά.
  I want to learn Greek.
- Μπορείς να έρθεις αύριο;
  Can you come tomorrow?
- Πρέπει να αγοράσουμε ψωμί.
  We have to buy bread.
- Τι θέλετε να πιείτε;
  What would you like to drink?
- Να σας βοηθήσω;
  Can I help you?

### Watch out

- Both verbs take the person: *Θέλουμε να πάμε*, We want to go. *Θέλω να πάει* means "I want him or her to go".
- For one action, use the simple form: *Θέλω να αγοράσω ένα αυτοκίνητο*, not ~~Θέλω να αγοράζω ένα αυτοκίνητο~~.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow

---

## 17. The imperative

`ell-imperative` · A1, order 17 · rule 88 words

- **Words:** γράφω, διαβάζω
- **Related topics:** να + the simple form
- **Tenses:** imperativeSimple, imperativeContinuous (button: Practise · Imperative (simple) · Imperative (continuous))
- **Classes:** verb

The imperative gives orders, requests and directions. It has a form for *εσύ* and one for *εσείς*, which is also polite.

- The simple imperative is for one action. It comes from the aorist: *έγραψα*, so *γράψε*, *γράψτε*.
- The continuous imperative is for a habit or an action that goes on. It comes from the present: *γράφε*, *γράφετε*.

Most everyday requests are simple: *Κλείσε την πόρτα, σε παρακαλώ*, Close the door, please.

Some common verbs are irregular: *έλα*, *ελάτε*, come; *πες*, *πείτε*, say; *δες*, *δείτε*, see; *πάρε*, *πάρτε*, take.

**Simple: one action**

*Forms table, filled by the build (second pass):*

```forms
words: γράφω, διαβάζω
tense: imperativeSimple
```

**Continuous: again and again**

*Forms table, filled by the build (second pass):*

```forms
words: γράφω, διαβάζω
tense: imperativeContinuous
```

### Examples

- Έλα εδώ, σε παρακαλώ.
  Come here, please.
- Διαβάστε το κείμενο και γράψτε τις απαντήσεις.
  Read the text and write the answers.
- Πες μου τι θέλεις.
  Tell me what you want.
- Πίνε πολύ νερό το καλοκαίρι.
  Drink a lot of water in the summer.
- Κλείστε τα κινητά σας, παρακαλώ.
  Please switch off your phones.

### Watch out

- For "don't", use *μην* and the form after *να*: *Μην ξεχάσεις!*, Don't forget!, not ~~Μην ξέχασε!~~
- Weak pronouns come after the imperative: *Πες μου*, tell me; *Δώσε μου το αλάτι*, pass me the salt.

### Review

- [ ] Accents (monotonic) right in the rule, tables, examples and Watch out
- [ ] Examples are natural, correct Modern Greek
- [ ] English translations are accurate
- [ ] Level fit: A1 words, short sentences, a rule a beginner can follow
