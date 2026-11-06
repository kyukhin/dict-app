# Word lists QA report

Written by `Scripts/build_wordlists.py` on every dictionary build (docs/specs/0130-word-lists.md, "List data"); do not edit by hand.

## Inputs

| Input | sha256 |
|---|---|
| `Scripts/data/wordlists/ky-ell-a1.csv` | `591d5c1fbe6714e3f9c6c3099f32c196f46eb4afe424badb950a787171c98d7b` |
| `Scripts/data/wordlists/ky-ell-a2.csv` | `bed81a951a0f2fdc84e6dc071c0ff0b27f9da4326f218f33852178313ee3fdb9` |
| `Scripts/data/wordlists/ky-ell-b1.csv` | `816a888bc8fb1d16210bf66f5de22bdac35a9027f0ef5f52a8d6e7b96f9829f3` |
| `openlanguageprofiles/cefrj-vocabulary-profile-1.5.csv` | `b0dd3c635f1c9a4fdf1490c7e5b7c48e8bbe55b652ad0c9860a95f98e10ae498` |
| `openlanguageprofiles/octanove-vocabulary-profile-c1c2-1.0.csv` | `18c33a407f2f89f7b8de9671c6d45fe3ea0bce45e7d2d7dcaab48d73e0f7b380` |
| `frequencywords/el_50k.txt` | `7ec8f6de52c38f36a04add5d1613b116aed576e10c5e3b40d0001e8572de978c` |
| `frequencywords/en_50k.txt` | `5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458` |

## Gates

| Gate | Measured | Needed | |
|---|---|---|---|
| Input problems (Latin letters in Greek, Greek letters in Latin words, rows that become no word, rows without a level of their series, bad rows, overrides) | 0 | 0 | ok |
| ky-ell linked | 88.0% (4,090 of 4,648) | ≥ 84% | ok |
| cefr-eng linked | 98.6% (8,529 of 8,647) | ≥ 95% | ok |
| word_count equals rows | all | all | ok |
| Empty lists | 0 | 0 | ok |
| E3 tables | 3.27 MB | ≤ 4 MB | ok |

## ky-ell

### Counts

| Level | Rows | Words | Linked | Ranked |
|---|---|---|---|---|
| A1 | 1,496 | 1,457 | 94.1% | 92.0% |
| A2 | 777 | 756 | 78.7% | 75.1% |
| B1 | 2,444 | 2,435 | 87.2% | 75.0% |
| all | 4,717 | 4,648 | 88.0% | 80.4% |

69 rows merged into other rows' words (below).

### Link classes

| Level | exact | cleaned | near | form | override | unlinked |
|---|---|---|---|---|---|---|
| A1 | 1,330 | 5 | 14 | 19 | 3 | 86 |
| A2 | 565 | 4 | 8 | 18 | 0 | 161 |
| B1 | 2,052 | 1 | 2 | 69 | 0 | 311 |
| all | 3,947 | 10 | 24 | 106 | 3 | 558 |

### A1: the 20 most frequent words, before the shuffle

είμαι, αυτός, σε, και, θα, έχω, με, για, που, πού, κάνω, λέω, τι, από, μπορώ, άλλος, ξέρω, θέλω, όχι, εδώ

### Links to review: cleaned, near, form and override (152)

| Level | Term | Headword | Rule | The rules' link |
|---|---|---|---|---|
| A1 | Αγγελική | — | override | αγγελική |
| A1 | Άγγελος | — | override | άγγελος |
| A1 | Αθανασία | — | override | αθανασία |
| A1 | Αιγαίο (πέλαγος) | Αιγαίο Πέλαγος | near |  |
| A1 | αιγυπτιακά | αιγυπτιακός | form |  |
| A1 | (Στις 10) ακριβώς! | ακριβώς | cleaned |  |
| A1 | Αλεξία | — | override | αλεξία |
| A1 | Αόριστος | αόριστος | near |  |
| A1 | (Σαουδική) Αραβία | Αραβία | cleaned |  |
| A1 | βραδινό | βραδινός | form |  |
| A1 | Γεια! | γεια | near |  |
| A1 | Γυμνάσιο | γυμνάσιο | near |  |
| A1 | Δημοτικό σχολείο | δημοτικό σχολείο | near |  |
| A1 | εννέα | εννιά | override | — |
| A1 | επτά | εφτά | override | — |
| A1 | Ευχαριστώ! | ευχαριστώ | near |  |
| A1 | (Νέα) Ζηλανδία | Νέα Ζηλανδία | cleaned |  |
| A1 | κάθετα | κάθετος | form |  |
| A1 | (Τι) κρίμα! | κρίμα | cleaned |  |
| A1 | λαϊκή | — | override | λαϊκός |
| A1 | λαχανικά | λαχανικό | form |  |
| A1 | λίγοι | λίγος | form |  |
| A1 | Λύκειο | λύκειο | near |  |
| A1 | Μαθηματικά | μαθηματικά | near |  |
| A1 | Μπράβο! | μπράβο | near |  |
| A1 | ξεχωριστά | ξεχωριστός | form |  |
| A1 | οκτώ | οχτώ | override | — |
| A1 | όλοι | όλος | form |  |
| A1 | Ορίστε! | ορίστε | near |  |
| A1 | (Σε/Σας) παρακαλώ! | παρακαλώ | cleaned |  |
| A1 | Παρακαλώ! | παρακαλώ | near |  |
| A1 | πατατάκια | πατατάκι | form |  |
| A1 | ποιανού | ποιος | form |  |
| A1 | πολλοί | πολύς | form |  |
| A1 | πόσοι | πόσος | form |  |
| A1 | σκάλες | σκάλα | form |  |
| A1 | σπουδές | σπουδή | form |  |
| A1 | στολισμένος | στολίζω | form |  |
| A1 | Συγγνώμη! | συγγνώμη | near |  |
| A1 | (ένα) σωρό | σωρός | form |  |
| A1 | τέσσερις | τέσσερα | form |  |
| A1 | υπάρχει | υπάρχω | form |  |
| A1 | φτηνά | φτηνός | form |  |
| A1 | Φυσικά! | φυσικά | near |  |
| A1 | Χιονίζει | χιονίζει | near |  |
| A1 | ωραία | ωραίος | form |  |
| A2 | ανακατεμένος | ανακατεύω | form |  |
| A2 | (μου) αρέσει | αρέσει | cleaned |  |
| A2 | Δημαρχείο | δημαρχείο | near |  |
| A2 | δίκλινο | δίκλινος | form |  |
| A2 | δίνομαι | δίνω | form |  |
| A2 | εκείνη | εκείνος | form |  |
| A2 | ενδιαφέρομαι | ενδιαφέρω | form |  |
| A2 | Θρησκευτικά | θρησκευτικά | near |  |
| A2 | καλεσμένος | καλώ | form |  |
| A2 | Καλή όρεξη! | καλή όρεξη | near |  |
| A2 | Καλή χρονιά! | καλή χρονιά | near |  |
| A2 | κλεισμένος | κλείνω | form |  |
| A2 | (για) λίγο | λίγο | cleaned |  |
| A2 | (σε) λίγο | λίγο | cleaned |  |
| A2 | οδηγάω | οδηγώ | form |  |
| A2 | όσα | όσος | form |  |
| A2 | παιδιά | παιδί | form |  |
| A2 | (δεν) πειράζει | πειράζω | form |  |
| A2 | πειράζει | πειράζω | form |  |
| A2 | Περαστικά! | περαστικά | near |  |
| A2 | ποιον | ποιος | form |  |
| A2 | ποντίκια | ποντίκι | form |  |
| A2 | (στη) συνέχεια | συνέχεια | cleaned |  |
| A2 | συστημένος | συστήνω | form |  |
| A2 | Σωτηρία | — | override | σωτηρία |
| A2 | τονισμένος | τονίζω | form |  |
| A2 | Τροχαία | τροχαία | near |  |
| A2 | χαίρετε | χαίρω | form |  |
| A2 | Χριστός Ανέστη! | Χριστός ανέστη | near |  |
| A2 | Χρόνια πολλά! | χρόνια πολλά | near |  |
| A2 | χωρισμένος | χωρίζω | form |  |
| B1 | Αινστάιν | Αϊνστάιν | near |  |
| B1 | ακυρώνομαι | ακυρώνω | form |  |
| B1 | αλώβητα | αλώβητος | form |  |
| B1 | αναγκάζομαι | αναγκάζω | form |  |
| B1 | ανακαινισμένος | ανακαινίζω | form |  |
| B1 | ανακυκλωμένος | ανακυκλώνω | form |  |
| B1 | αντίστροφα | αντίστροφος | form |  |
| B1 | αξέχαστα | αξέχαστος | form |  |
| B1 | αόριστα | αόριστος | form |  |
| B1 | απαγορευμένος | απαγορεύω | form |  |
| B1 | απειλούμαι | απειλώ | form |  |
| B1 | απλωμένος | απλώνω | form |  |
| B1 | Αστεροσκοπείο | αστεροσκοπείο | near |  |
| B1 | βάφομαι | βάφω | form |  |
| B1 | βιολετί | βιολετής | form |  |
| B1 | βόρεια | βόρειος | form |  |
| B1 | βουτυρωμένος | βουτυρώνω | form |  |
| B1 | γενική (πτώση) | γενική | cleaned |  |
| B1 | γεννημένος | γεννάω | form |  |
| B1 | γερασμένος | γερνάω | form |  |
| B1 | γυμνάζομαι | γυμνάζω | form |  |
| B1 | διόδια | — | override | Διόδια |
| B1 | ενοχλούμαι | ενοχλώ | form |  |
| B1 | εξαντλούμαι | εξαντλώ | form |  |
| B1 | εξετάζομαι | εξετάζω | form |  |
| B1 | εξηγούμαι | εξηγώ | form |  |
| B1 | επηρεάζομαι | επηρεάζω | form |  |
| B1 | θεωρούμαι | θεωρώ | form |  |
| B1 | ικανοποιούμαι | ικανοποιώ | form |  |
| B1 | καλλιεργούμαι | καλλιεργώ | form |  |
| B1 | καστανάς | — | override | Καστανάς |
| B1 | καταναλώνομαι | καταναλώνω | form |  |
| B1 | κατοικούμαι | κατοικώ | form |  |
| B1 | κεντρικά | κεντρικός | form |  |
| B1 | κλίνομαι | κλίνω | form |  |
| B1 | κουνάω | κουνώ | form |  |
| B1 | κρίνομαι | κρίνω | form |  |
| B1 | κυριολεκτικά | κυριολεκτικός | form |  |
| B1 | κυριότερος | κύριος | form |  |
| B1 | λαίμαργα | λαίμαργος | form |  |
| B1 | λέγομαι | λέω | form |  |
| B1 | λησμονιέμαι | λησμονώ | form |  |
| B1 | λιωμένος | λιώνω | form |  |
| B1 | λούζομαι | λούζω | form |  |
| B1 | μοναδικά | μοναδικός | form |  |
| B1 | ξυρίζομαι | ξυρίζω | form |  |
| B1 | ολυμπιακός | — | override | Ολυμπιακός |
| B1 | ονομάζομαι | ονομάζω | form |  |
| B1 | οργανωμένος | οργανώνω | form |  |
| B1 | οφείλομαι | οφείλω | form |  |
| B1 | πετυχημένος | πετυχαίνω | form |  |
| B1 | πιέζομαι | πιέζω | form |  |
| B1 | πικραμένος | πικραίνω | form |  |
| B1 | πουλιέμαι | πουλάω | form |  |
| B1 | προβάλλομαι | προβάλλω | form |  |
| B1 | προστατεύομαι | προστατεύω | form |  |
| B1 | σβησμένος | σβήνω | form |  |
| B1 | σημειωμένος | σημειώνω | form |  |
| B1 | σκληρά | σκληρός | form |  |
| B1 | σταματημένος | σταματάω | form |  |
| B1 | συμπληρωμένος | συμπληρώνω | form |  |
| B1 | συναντιέμαι | συναντάω | form |  |
| B1 | συνοδεύομαι | συνοδεύω | form |  |
| B1 | ταλαιπωρούμαι | ταλαιπωρώ | form |  |
| B1 | ταράζομαι | ταράζω | form |  |
| B1 | τρέφομαι | τρέφω | form |  |
| B1 | τρομοκρατημένος | τρομοκρατώ | form |  |
| B1 | τρομοκρατούμαι | τρομοκρατώ | form |  |
| B1 | υδραυλικά | υδραυλικός | form |  |
| B1 | υιοθετούμαι | υιοθετώ | form |  |
| B1 | φιλοξενούμαι | φιλοξενώ | form |  |
| B1 | φτιαγμένος | φτιάχνω | form |  |
| B1 | χαρτιά | χαρτί | form |  |
| B1 | χορτασμένος | χορταίνω | form |  |
| B1 | χτενίζομαι | χτενίζω | form |  |

### Unlinked words (558)

| Level | Term | Translation |
|---|---|---|
| A1 | Αγγελική | Angelica |
| A1 | Άγγελος | Angelo |
| A1 | Αθανασία | Athanassia |
| A1 | Άιφελ (Πύργος) | Eiffel Tower |
| A1 | Αλεξία | Alexia |
| A1 | Ανδριανούπολη | Andrianoupoli |
| A1 | Ανέστης | Anestis |
| A1 | Αντιγόνη | Antigone |
| A1 | Αντρέας | Andrew |
| A1 | αντρικός | male, man’s |
| A1 | Αντώνης | Anthony |
| A1 | Αργοστόλι | Argostoli |
| A1 | αρμενικός | Armenian |
| A1 | βαθύς | deep |
| A1 | βαπόρι | boat |
| A1 | βασιλόπιτα | Greek New Year’s Cake (vassilopita) |
| A1 | Βάσω | Vasso |
| A1 | βιβλιάριο | booklet |
| A1 | βραζιλιανικά | Brazilian |
| A1 | βραζιλιανικός | Brazilian |
| A1 | γελαστός | laughing |
| A1 | γιαπωνέζικα | Japanese |
| A1 | Γιαπωνέζος | Japanese |
| A1 | γλώσσα μητρική | mother tongue |
| A1 | Γρηγόρης | Gregory |
| A1 | δανέζικα | Danish |
| A1 | δανέζικος | Danish |
| A1 | δεκαεπτά | seventeen |
| A1 | δεκαοκτώ | eighteen |
| A1 | Δημήτρης | Jim/Dimitris |
| A1 | δυόμισι | two and a half |
| A1 | εφτακόσιοι | seven hundred |
| A1 | Ζηλανδός | (New) Zelander |
| A1 | Η ώρα είναι τέσσερις | (It is) four o’clock |
| A1 | Η ώρα είναι τεσσερισήμισι | (It is) half past four |
| A1 | ίντερνετ | internet |
| A1 | ισλανδικός | Icelandic |
| A1 | Κάνει ζέστη | It is hot |
| A1 | κεφαλαίο γράμμα | capital letter |
| A1 | κινέζικα | Chinese |
| A1 | κινεζικός | Chinese |
| A1 | κολυμπάω | to swim |
| A1 | Κορέα | Corea |
| A1 | Κορεάτης | Corean |
| A1 | κορεάτικα | Corean |
| A1 | λαϊκή | street market |
| A1 | μαθήματα για το σπίτι | homework |
| A1 | μέλη του σώματος | parts of the body |
| A1 | μονόκλινος | one-bed |
| A1 | μονός | single |
| A1 | ντόνατ | donut |
| A1 | Νυχτώνει | The night falls / It gets dark |
| A1 | ξεκινάω | to begin, to start |
| A1 | ξύδι | vinegar |
| A1 | οχτακόσιοι | eight hundred |
| A1 | πάρκιγκ | parking |
| A1 | πεινάω | to be hungry |
| A1 | πεντέμισι | five and a half |
| A1 | περνάω καλά | to have a good time |
| A1 | πιθανώς | probably, possibly |
| A1 | πιτζάμες | pyjamas |
| A1 | Πόσων χρονών είσαι; | How old are you? |
| A1 | Πώς σε λένε; | What’s your name? |
| A1 | ρωτάω | to ask |
| A1 | Σίδνεϋ | Sydney |
| A1 | σούπερμάρκετ | super market |
| A1 | στάση λεωφορείου | bus stop |
| A1 | συστημένο γράμμα | registered letter |
| A1 | σχολική χρονιά | school year |
| A1 | ταξιδιωτικό γραφείο | travel agency |
| A1 | τέρμα λεωφορείου | final stop |
| A1 | Τι καιρό κάνει; | What’s the weather like? |
| A1 | τρεισήμισι | three and a half |
| A1 | τριακόσιοι | three hundred |
| A1 | τσάντα σχολική | schoolbag |
| A1 | Φίλιππος | Philip |
| A1 | Φυσάει | It is windy |
| A1 | χαιρετάω | to say hello |
| A1 | χαιρετισμοί/χαιρετίσματα | regards, greetings |
| A1 | Χαλκιδική | Chalkidiki |
| A1 | Χάρηκα που σας γνώρισα! | Nice to meet you! |
| A1 | χειρούργος | surgeon |
| A1 | χθες | yesterday |
| A1 | χίλιοι | a thousand |
| A1 | χριστουγεννιάτικο δέντρο | Christmas tree |
| A1 | χωριάτικη σαλάτα | Greek salad |
| A2 | αθλητικά γεγονότα | sports events |
| A2 | αθλητικοί αγώνες | sports games |
| A2 | Αληθώς Ανέστη! | He is risen indeed! |
| A2 | ανάληψη χρημάτων | withdrawal |
| A2 | ανεβαίνει μια θεατρική παράσταση | a play is put on |
| A2 | Αννα | Anna |
| A2 | απλό εισιτήριο | one way ticket |
| A2 | από μέσα/έξω | from inside/outside |
| A2 | Από πού είσαι/είστε? | Where are you from? |
| A2 | από τότε | since then |
| A2 | Απόκριες | Carnival time / Halloween |
| A2 | ασθενής άνεμος | mild wind |
| A2 | αστράφτει | it’s lightning |
| A2 | αστράφτω | to sparkle |
| A2 | αυτοί | these, they |
| A2 | αυτόν τον καιρό | at the moment |
| A2 | αφετηρία λεωφορείου | bus starting point |
| A2 | βάζω βάρος | to gain weight |
| A2 | βάζω πλυντήριο | to do the laundry |
| A2 | βιβλιάριο τράπεζας | bankbook, passbook |
| A2 | Βίκυ | Vicky |
| A2 | βρεφονηπιακός σταθμός | nursery |
| A2 | Γεράσιμος | Gerasimos |
| A2 | γι' αυτό | that’s why |
| A2 | γυαλιά ηλίου | sunglasses |
| A2 | γυρίζω/γυρνάω | to come back |
| A2 | γύρω | around |
| A2 | δεκατέσσερις | fourteen |
| A2 | δουλειές σπιτιού | housework, housekeeping chores |
| A2 | δραματική ταινία | drama |
| A2 | δύο φορές | twice |
| A2 | εδώ γύρω | around here |
| A2 | εδώ και πολύ καιρό | for a long time |
| A2 | είμαι σπίτι | to be (at) home |
| A2 | εισιτήριο με επιστροφή | return ticket |
| A2 | εκείνον | him |
| A2 | Ελίνα | Elina |
| A2 | Έλσα | Elsa |
| A2 | εξετάσεις | examinations, exams |
| A2 | έργο θεατρικό | play |
| A2 | ερωτηματολόγιο | questionnaire |
| A2 | εσένα | you |
| A2 | Ευτυχισμένος ο καινούριος χρόνος! | Happy new year! |
| A2 | έχει αέρα | it is windy |
| A2 | έχει ήλιο | it is sunny |
| A2 | έχει συννεφιά | it is cloudy |
| A2 | Ζέτα | Zeta |
| A2 | ζωντανή μουσική | live music |
| A2 | η σειρά μου | my turn |
| A2 | ηλεκτρικά είδη | electric devices |
| A2 | θα είμαι πίσω | I’ll be back |
| A2 | Θανάσης | Thanassis |
| A2 | θεατρικό έργο | play |
| A2 | Θωμαή | Thomais |
| A2 | Καβάλα | Kavala |
| A2 | και οι δύο | both |
| A2 | Καλές γιορτές! | Happy holidays! |
| A2 | Καλή Ανάσταση! | Happy Easter! |
| A2 | Καλή διασκέδαση! | Have fun! / Enjoy! / Enjoy yourself! |
| A2 | Καλή επιτυχία! | Good luck! |
| A2 | Καλό Πάσχα! | Happy Easter! |
| A2 | κάνει/έχει κρύο | it is cold |
| A2 | κάνω βόλτα | to take a walk |
| A2 | Κάρμεν | Carmen |
| A2 | κατανόηση γραπτού λόγου | reading comprehension |
| A2 | κατανόηση προφορικού λόγου | listening comprehension |
| A2 | κατεβάζω μουσική | to download music |
| A2 | Κατερίνα | Catherine |
| A2 | Κάτια | Katja |
| A2 | κεντρικό δελτίο ειδήσεων | news |
| A2 | ΚΕΠ (Κέντρο Εξυπηρέτησης Πολιτών) | Citizen Service Centre |
| A2 | κλειδί-λέξη | key word |
| A2 | κοιτώ | to look (at) |
| A2 | Κομοτηνή | Komotimi |
| A2 | κουζίνα ηλεκτρική | (electric) stove, (electric) cooker |
| A2 | κουμπάρα | maid of honor |
| A2 | Κυριάκος | Kyriakos |
| A2 | λαϊκή μουσική | popular music |
| A2 | λάτιν χορός | latin dance |
| A2 | Λευκός Πύργος | White Tower |
| A2 | λέω ψέματα | to lie |
| A2 | Λίνκον Αβραάμ | Abraham Lincoln |
| A2 | Λίτσα | Litsa |
| A2 | Λούβρο | Louvre |
| A2 | μαζεύω από κάτω | to pick |
| A2 | μάρκα αυτοκινήτου | model |
| A2 | μάσκα ομορφιάς | beauty mask |
| A2 | με λένε | my name is |
| A2 | μένω σπίτι | to stay indoors |
| A2 | μία φορά | once |
| A2 | Μίρκα | Mirka |
| A2 | Μιχάλης | Michael |
| A2 | μου πηγαίνει | something looks good on me, something suits me |
| A2 | μου φαίνεται | it seems to me |
| A2 | μουσακάς | moussaka |
| A2 | μουσικό κουτί | music box |
| A2 | Μπάμπης | Babis |
| A2 | Να ζήσεις! | Happy birthday! |
| A2 | Να ζήσετε! | May you have a life long marriage! / Congratulations! |
| A2 | Να τα εκατοστίσεις! | Happy birthday! |
| A2 | Ναβαρίνου (πλατεία) | Navarinou square |
| A2 | Νεκτάριος | Nektarios |
| A2 | νησιώτικος | of the island |
| A2 | Ντίνα | Ntina |
| A2 | ξαναβλέπω | to meet again |
| A2 | ξαναδίνω | to give again |
| A2 | ξαναλέω | to repeat, to say again |
| A2 | ξαναμιλάω | to talk again |
| A2 | ξαναπερνάω | to come/pass again |
| A2 | «Ο Θάνατος του εμποράκου» | “Death of a Salesman” |
| A2 | Όσκαρ βραβείο | Oscar award |
| A2 | ουζερί | greek tavern |
| A2 | παίρνω συνέντευξη | to take an interview, to interview |
| A2 | παραγγέλλω/παραγγέλνω | to order |
| A2 | παραγωγή γραπτού λόγου | writing |
| A2 | παραγωγή προφορικού λόγου | speaking |
| A2 | πέρσι | last year |
| A2 | πηγαίνω για τρέξιμο | to go running |
| A2 | πηγαίνω διακοπές | to go on holiday/vacation |
| A2 | πηγαίνω στο σχολείο | to go to school |
| A2 | πιάτσα ταξί | taxi rank, taxi stand |
| A2 | Πλατεία Συντάγματος | Syntagma/Constitution Square |
| A2 | πλένω τα πιάτα | to do the washing up |
| A2 | πονάει η κοιλιά μου | to have a stomach ache |
| A2 | Πόσο κάνει; | How much does it cost? |
| A2 | πριν από λίγο (καιρό) | a while ago |
| A2 | προσχολικός | preschool, nursery school |
| A2 | προτιμάω | to prefer |
| A2 | Πώς σε/σας λένε; | What’s your name? |
| A2 | ραδιοφωνική εκπομπή | radio program |
| A2 | ράτσα ζώου | pedigree |
| A2 | ροκ μουσική | rock music |
| A2 | «Ρωμαίος και Ιουλιέτα» | “Romeo and Juliet” |
| A2 | Σαίξπηρ Ουίλιαμ | Shakespeare William |
| A2 | Σαμ | Sam |
| A2 | Σας παρακαλώ! | Please! Παρακαλώ! [in response to |
| A2 | σβήνω τη φωτιά | to put out |
| A2 | σγουρός | curly |
| A2 | σε σχέση με | relating to |
| A2 | σημειώνω / κρατάω σημειώσεις | to take down notes, to write down |
| A2 | στεναχωρημένος | sad, unhappy, depressed |
| A2 | στην τηλεόραση | on the television / on the TV |
| A2 | συζητάω | to discuss |
| A2 | συλληπητήρια | condolences |
| A2 | Σωτηρία | Sotiria |
| A2 | τάγκο | tango |
| A2 | Τάσος | Tassos |
| A2 | Τασούλα | Tassoula |
| A2 | ταυτότητα αστυνομική | identification card / ID |
| A2 | τζάζ,η | jazz |
| A2 | τηλεφωνώ / παίρνω τηλέφωνο | to call, to phone |
| A2 | τμήμα αστυνομικό | police department/station |
| A2 | τρία πόδια Χαλκιδικής | the three legs/fingers of the Chalkidiki peninsula |
| A2 | Τσιτσάνης Βασίλης | Vassilis Tsitsanis |
| A2 | Φάμπιο | Fabio |
| A2 | φθηνός | cheap |
| A2 | φιλάω | to kiss |
| A2 | φοιτητική εστία | student residence |
| A2 | Χαράλαμπος | Charalambos |
| A2 | Χαρίκλεια | Chariklia |
| A2 | χτυπάει το τηλέφωνο | the phone is ringing |
| B1 | Άγιος Μαυρίκιος | Mauritius |
| B1 | αεροπορικός | air, aviation, of air travel |
| B1 | Αιγαίο | the Aegean sea |
| B1 | ακροστιχίδα | acrostic, acronym |
| B1 | αλευρώνω | to flour, to dust with flour |
| B1 | αλλάζω γνώμη | to change my mind |
| B1 | άλλωστε | besides, moreover, after all |
| B1 | αμυγδαλωτός | almond-shaped |
| B1 | αναζητάω | to seek, to look for |
| B1 | ανακεφαλαίωση | summary |
| B1 | ανεβοκατεβαίνω | to go up and down, to fluctuate |
| B1 | ανεκτίμητος | priceless, invaluable |
| B1 | ανθότυρο | a kind of soft cheese |
| B1 | αντιβίωση | antibiotics |
| B1 | αντιηλιακό | sun block, sunscreen |
| B1 | αντικολλητικός | nonstick |
| B1 | αντίλογος | riposte, counterargument |
| B1 | Άνω Πορόια | Ano Poroia |
| B1 | ανώι | first floor |
| B1 | αξιοποίηση | utilization |
| B1 | αόριστο άρθρο | indefinite article |
| B1 | άπλα | roominess, spaciousness |
| B1 | αποδρώ | to escape, to get away |
| B1 | Αποστόλης | Apostolis |
| B1 | αποτυχαίνω | to fail |
| B1 | αραιωμένος | diluted |
| B1 | αραχτός | loafing around, loafing about, hanging around |
| B1 | αρραβωνιαστικός | fiancé, fiancée |
| B1 | αρρωστιάρης | ill, sick, who becomes ill often |
| B1 | Άρτεμη | Artemis |
| B1 | αρχικός | initial |
| B1 | αρωματίζω | to scent, to perfume, to flavor, to spice |
| B1 | Αστυπάλαια | Astypalaia |
| B1 | αφιέρωμα | dedication, tribute |
| B1 | αφιερωμένος | dedicated |
| B1 | άχνη | powdered sugar |
| B1 | βαθμολογούμαι | to be graded |
| B1 | βάθρα | a natural pool (in Samothraki) |
| B1 | βαρκάδα | boat ride |
| B1 | βεγγέρα | visit, dinner party |
| B1 | βραβεύομαι | to be awarded, to receive a prize or award |
| B1 | βραβεύω | to award |
| B1 | βραδιάζει | it’s getting dark |
| B1 | βράσιμο | boiling |
| B1 | βρεφικός | infant |
| B1 | βρομιάρης | dirty |
| B1 | βωβός | silent, mute |
| B1 | γαϊδουράκι | small donkey |
| B1 | γάργαρος | gurgling, clear |
| B1 | γεμιστές πιπεριές | stuffed peppers |
| B1 | γεράματα | old age |
| B1 | γεράνι | geranium |
| B1 | γεφύρι | bridge |
| B1 | γι’ αυτό | that’s why |
| B1 | για το δικό σας καλό | for your own good |
| B1 | Γιάννενα | Giannena |
| B1 | γιαουρτάς | man who sells yoghurt |
| B1 | γιορταστικός | festive |
| B1 | γιουβαρλάκια | giouvarlakia (rice meat ball soup with egg-lemon sauce) |
| B1 | γιουβέτσι | giouvetsi (veal and orzo baked in tomato sauce) |
| B1 | γκρινιάζω | to nag |
| B1 | γλυκό του ταψιού | baked dessert, a dessert made in a sheet pan |
| B1 | γουλί | bald, clean-shaven |
| B1 | γούνινος | furry |
| B1 | γουρλής | person who brings good look to others |
| B1 | γραπτές εξετάσεις | written exams |
| B1 | γραφίστας | graphic designer |
| B1 | δανειστικός | loan |
| B1 | δασικός | woodland |
| B1 | δεκαήμερο | ten day period |
| B1 | δελτίο καιρού | weather forcast |
| B1 | Δημητρός | Dimitros |
| B1 | δημοσιοποίηση | publication |
| B1 | διαδικτυακός | online, internet |
| B1 | διαιτητικός | dietary |
| B1 | διαμπερές | with openings or windows on opposite sides, through and through |
| B1 | διανυκτέρευση | staying overnight, spending the night, overnight stop, all night service |
| B1 | διαρρύθμιση | arrangement |
| B1 | διασκευασμένος | adapted |
| B1 | διατύπωνομαι | to be formulated, to be expressed |
| B1 | διόδια | tolls |
| B1 | δίχως | without |
| B1 | διώροφος | with two floors |
| B1 | δυναμωτικός | strengthening |
| B1 | δώμα | small appartement on the top floor |
| B1 | εθνότητα | ethnicity |
| B1 | εκβιαστικός | extortionate |
| B1 | εκδοτικός | publishing, issuing |
| B1 | εκπτωτικός | cut-rate, discount |
| B1 | Ελεγκάκη | Elegaki (character from a novel) |
| B1 | ενημερωτικός | informative |
| B1 | έξοχος | superb, excellent, exquisite |
| B1 | Ευρυπίδης | Euripides |
| B1 | Ευρωπαϊκή Ενωση | European Union |
| B1 | ζεστασιά | heat, warmth |
| B1 | ζύμωμα | kneading |
| B1 | ημερίδα | meeting |
| B1 | ηφαίστιο | volcano |
| B1 | θαλασσής | light blue |
| B1 | θαλασσινός | sea, marine |
| B1 | Θερμαϊκός | Thermaikos bay |
| B1 | ιδιότροπος | eccentric |
| B1 | κάθε φορά | every time |
| B1 | καλότυχος | person who has good luck |
| B1 | κανάτι | cruse, pitcher, jug |
| B1 | κάνω παιδί | to have a child |
| B1 | καστανάς | man who sells roasted chestnuts |
| B1 | κατατεθέν | registered [trademark] |
| B1 | κάτοψη | floor plan |
| B1 | κατώι | the ground floor of old rural houses |
| B1 | καφετζής | barista, person who makes coffee in a coffee shop |
| B1 | Κελσίου (βαθμοί) | Celsius (degrees) |
| B1 | Κερκίνη | (Lake) Kerkini |
| B1 | κινητικός | energetic, kinetic |
| B1 | κινούμενα σχέδια | cartoons |
| B1 | κοιτάω | to look (at) |
| B1 | κοκκινιστό | kokkinisto (veal cooked in red sauce) |
| B1 | κορινθιακός | Corinthian |
| B1 | κοσμοπολίτικος | cosmopolitan |
| B1 | κοτόσουπα | chicken soup |
| B1 | κουλούρι σουσαμένιο | sesame bagel |
| B1 | κουλουρτζής | man who sells bagels |
| B1 | κουσκούσι | cous cous |
| B1 | κουταλάκι του γλυκού | teaspoon |
| B1 | κούφωμα | wooden case, door or window frame |
| B1 | κοχύλι | seashell |
| B1 | κρατάω σημειώσεις | to take down notes, to keep notes to write down |
| B1 | κρεατικά | meats |
| B1 | κρεατόσουπα | meat soup |
| B1 | κροκάδι | yolk |
| B1 | κρυπτόλεξο | word search puzzle |
| B1 | κυρίως | mainly |
| B1 | λαδερά | dishes cooked with olive oil (usually vegetables) |
| B1 | λαδί | olive |
| B1 | λαδόκολα | baking paper |
| B1 | λαλάω | to crow |
| B1 | λαπάς | mashed, overcooked rice |
| B1 | λατρεύω | to adore |
| B1 | λεκτικός | verbal |
| B1 | λεπτομύτα | slender-billed curlew [bird] |
| B1 | Λευτέρης | Lefteris |
| B1 | λογιών λογιών | of all sorts |
| B1 | μαγειρείο | cookshop, cook house, tavern |
| B1 | μεταξωτός | silk |
| B1 | μικρόσωμος | petite, little |
| B1 | μισοτιμής | at half price, very cheap |
| B1 | μόδιστρος | fashion designer, tailor, seamstress seamstress |
| B1 | μολονότι | although, though |
| B1 | μονάχα | only |
| B1 | μονολεκτικός | with one word |
| B1 | μοσχοβολάω | to smell nice |
| B1 | Μπαξέδες | Baxedes |
| B1 | μπομπονιέρα | jordan almonds, wedding favor |
| B1 | μπροστινός | anterior |
| B1 | μύδια σαγανάκι | fried mussels |
| B1 | μυδοπίλαφο | mussels with rice |
| B1 | μύτι | nose |
| B1 | μωβ | purple |
| B1 | νανόχηνα | lesser white-fronted goose |
| B1 | νεόδμητος | newly built |
| B1 | νηπιακός | toddler |
| B1 | νηστικός | hungry, starved |
| B1 | νοηματικός | conceptual, notional |
| B1 | νοθεύω | to adulterate, to falsify |
| B1 | νοίκι | rent |
| B1 | νομός | district, county |
| B1 | νοστιμεύω | to spice up, to flavor with |
| B1 | νοτιανατολικός | southeast |
| B1 | ντάκος | dakos (barley toast with tomato, feta, and olive oil) |
| B1 | ντάλα | full, right in the middle of |
| B1 | ξαναγίνομαι | to become again, to be made again |
| B1 | ξαναθυμάμαι | to remember again, to recall |
| B1 | ξαναμαζεύω | to regather |
| B1 | ξαναπηγαίνω | to go back, to go again |
| B1 | ξανασκέφτομαι | to reconsider |
| B1 | ξαναφωνάζω | to recall |
| B1 | ξεβάφω | to bleach, to fade |
| B1 | ξεκολλάω | to come off |
| B1 | ξενυχτάω | to stay out late |
| B1 | ξεφουσκωμένος | deflated |
| B1 | οδικός | road |
| B1 | οικία,η | house |
| B1 | ολυμπιακός | olympic |
| B1 | ομαδικός | group, team |
| B1 | οργανωτικός | organizational |
| B1 | ορθοπεταλιά | pedaling |
| B1 | οριστικό άρθρο | definite article |
| B1 | οροφοδιαμέρισμα | one floor apartment |
| B1 | παγωτατζής | ice cream man |
| B1 | παιδότοπος | playground, playing facilities |
| B1 | παινεύω | to praise |
| B1 | παίρνω μέρος | to take part, participate |
| B1 | παίρνω τηλέφωνο | to call, to phone, to make a phonecall |
| B1 | παλ | pale, very soft hue |
| B1 | πανάκριβος | extremely expensive |
| B1 | πανελλαδικός | panhellenic |
| B1 | Παπαδιαμάντης | Papadiamantis, Alexander (Greek novelist, short-story writer and poet) |
| B1 | παράς | money |
| B1 | παρατάω | to abandon, to give up |
| B1 | παρόλο | even though |
| B1 | πατέρας, | father |
| B1 | πεδινός | flat, level, of a plain |
| B1 | πέλαγος | sea |
| B1 | Περσεφόνη | Persephone |
| B1 | πήλινος | made of clay, ceramic, earthenware |
| B1 | πιεστικός | pressing, pushing, urgent |
| B1 | πικάντικη | pikantiki, or else politiki (a salad made with shredded cabbage, carrots, celery, red peppers, and parsley) |
| B1 | πίκλα | pickle |
| B1 | πιλάτες | pilates |
| B1 | πιλοτή | free space on the ground floor |
| B1 | πλαγιαστός | sideways, inclined, aslant, reclining, recumbent |
| B1 | πλακατζής | worker who lays tiles |
| B1 | πλακώνω | to press down, to cover |
| B1 | πλαστελίνη | play dough, plasticine |
| B1 | πνευματικό κέντρο | cultural club |
| B1 | πνευμονολόγος | pulmonologist |
| B1 | πνέω | to blow, to breath, to waft |
| B1 | ποδαρικό | good luck that [sb] brings, being the first one to enter at a specific time of the year, e.g. at New Year’s Day |
| B1 | πολίτικος | from Constantinople/Istanbul |
| B1 | πολύξερος | knowledgeable, know-it-all |
| B1 | πολυταξιδευμένος | who has travelled extensively |
| B1 | ποπ μουσική | pop music |
| B1 | Πόπη | Popi (usually short for Penelope) |
| B1 | πουά | spotted, polka dotted |
| B1 | προξενιό | matchmaking |
| B1 | προπώληση | pre-sale |
| B1 | προφορικές εξετάσεις | oral exams |
| B1 | πρωταγωνιστικός | leading |
| B1 | πρωτοβρόχια | the first rain of the fall season |
| B1 | ρακόμελο | rakomelo, usually made with the combination of raki and honey and other spices |
| B1 | ραπ μουσική | rap music |
| B1 | ράφτιγκ | rafting |
| B1 | ρεβεγιόν | celebration |
| B1 | ρεμπέτικο | urban folk song, mainly from Asia Minor |
| B1 | ρίχνω μια ματιά | to have a look |
| B1 | ροδίζω | to brown |
| B1 | ροδοπελεκάνος | great white pelican |
| B1 | σαλεπτζής | man who sells salep (a traditional winter beverage) |
| B1 | σαρίκι | turban |
| B1 | σγουρομάλλης | curly haired |
| B1 | σε λίγο καιρό | in a while |
| B1 | σεμνότητα | modesty |
| B1 | Σε/Σας παρακαλώ! | Please! |
| B1 | σιέλ | arctic blue |
| B1 | σιτεύω | to age meat after butchering |
| B1 | σκάζω | to chap |
| B1 | σκηνοθετικός | relating to direction (movie/theater) |
| B1 | σοκολατί | chocolate brown |
| B1 | σοφιστικέ | sophisticated |
| B1 | σπανακόπιτα | spanakopita, a spinach pie |
| B1 | σπανακόρυζο | spanakorizo, a spinach and rice pilaf |
| B1 | σπαρτό | crops |
| B1 | σπαταλάω | to waste |
| B1 | σπιτοκαλυβάκι | very small house |
| B1 | Σποράδες | Sporades |
| B1 | στάση προσευχής | prayer position |
| B1 | Στέλιος | Stelios |
| B1 | στενοχώρια | sadness |
| B1 | στη συνέχεια | afterwards, after that |
| B1 | στραπατσάδα | strapatsada (a dish made with tomatos and eggs) |
| B1 | συμβαίνω | to happen, to occur |
| B1 | συμβουλευτικός | advisory |
| B1 | συμμαχικός | allied |
| B1 | συμπερασματικά | in conclusion |
| B1 | συνθετικός | synthetic |
| B1 | Σωτήρης | Sotiris |
| B1 | ταινία μικρού μήκος | short film |
| B1 | ταρό | tarot cards |
| B1 | τετραώροφος | with four floors |
| B1 | τζάζ | jazz |
| B1 | τζακούζι | jacuzzi |
| B1 | τζάμπα | for free, free of charge |
| B1 | τζιτζίκι | cicada |
| B1 | τίνος | whose |
| B1 | του φούρνου | food cooked in the oven |
| B1 | τρανός | important, large |
| B1 | τρείς | three |
| B1 | τριώροφος | with three floors |
| B1 | τσικουδιά | tsikoudia, raki |
| B1 | τυροπιτάκι | handheld individual little cheese pie |
| B1 | τυροσαλάτα | tyrosalata, a feta dip (sometimes spicy) |
| B1 | υπερσύγχρονος | ultramodern |
| B1 | φαρδύς | broad, wide |
| B1 | φιδάκι | Snakes and Ladders board game |
| B1 | φλούδι | peel |
| B1 | φογάτσα | traditional tsoureki from Corfu |
| B1 | φοινικόπτερο | flamingo |
| B1 | χαγιάτι | roofed balcony at the front of the house |
| B1 | χαδιάρης | tender, who likes caresses and displays of affection |
| B1 | χαλκόκοτα | glossy ibis |
| B1 | χαμός | a bit of a mess, commotion |
| B1 | χάρος | death |
| B1 | χείλι | lip |
| B1 | χειμωνιάτικος | winterly |
| B1 | χιλιομετρικός | kilometric |
| B1 | χιονοδρομικό κέντρο | ski resort |
| B1 | χιονοδρομικός | ski, skiing |
| B1 | χλωμός | pale |
| B1 | χουβαρντάς | bighearted, generous |
| B1 | χρυσάφι | gold |
| B1 | χτίσιμο | building, construction |
| B1 | χωμάτινος | earthen |
| B1 | χωμένος | hidden, nested |
| B1 | χωριάτικος | country, village, peasant, rustic |
| B1 | Ψ | ψι |
| B1 | ψαρικά | plates with fish |
| B1 | ψαρόσουπα | fish soup |
| B1 | ψηλώνω | to grow taller |
| B1 | ψήσιμο | grilling, roasting, baking |
| B1 | ψιλικατζής | owner of a small convenience store or kiosk |
| B1 | ψυχραίνω | to make cold, to freeze out |

### Unranked words (913)

| Level | Term |
|---|---|
| A1 | Αιγαίο (πέλαγος) |
| A1 | Αίγινα |
| A1 | Αιμιλία |
| A1 | αλβανικά |
| A1 | αλβανικός |
| A1 | Αλβανός |
| A1 | Αλεξανδρούπολη |
| A1 | Αλέξης |
| A1 | Αλεξία |
| A1 | Ανδριανούπολη |
| A1 | Ανέστης |
| A1 | Αντιγόνη |
| A1 | Αντώνης |
| A1 | Αργοστόλι |
| A1 | Αρμενία |
| A1 | αρμενικά |
| A1 | αρμενικός |
| A1 | Αρμένιος |
| A1 | αυστραλιανός |
| A1 | αυστριακός |
| A1 | βαπόρι |
| A1 | βασιλόπιτα |
| A1 | Βάσω |
| A1 | βελγικός |
| A1 | βελούδινος |
| A1 | βερίκοκο |
| A1 | βουλγαρικά |
| A1 | βουλγαρικός |
| A1 | Βούλγαρος |
| A1 | βραζιλιανικά |
| A1 | βραζιλιανικός |
| A1 | Βραζιλιάνος |
| A1 | γλώσσα μητρική |
| A1 | δανέζικα |
| A1 | δανέζικος |
| A1 | Δήμητρα |
| A1 | Δημήτρης |
| A1 | Δημοτικό σχολείο |
| A1 | διαγράφω |
| A1 | διακόσιοι |
| A1 | Δούναβης |
| A1 | είκοσι ένα |
| A1 | ενικός αριθμός |
| A1 | επιτραπέζιο παιχνίδι |
| A1 | εφτακόσιοι |
| A1 | Ζαΐρ |
| A1 | Ζάκυνθος |
| A1 | (Νέα) Ζηλανδία |
| A1 | Ζηλανδός |
| A1 | Η ώρα είναι τέσσερις |
| A1 | Η ώρα είναι τεσσερισήμισι |
| A1 | Θεσσαλονίκη |
| A1 | ιρλανδικά |
| A1 | ισλανδικά |
| A1 | ισλανδικός |
| A1 | Ισλανδός |
| A1 | Κάνει ζέστη |
| A1 | κασετίνα |
| A1 | Κέρκυρα |
| A1 | κεφαλαίο γράμμα |
| A1 | κορεατικός |
| A1 | κρεοπώλης |
| A1 | μαθήματα για το σπίτι |
| A1 | μανάβης |
| A1 | μέλη του σώματος |
| A1 | μονοκατοικία |
| A1 | μονόκλινος |
| A1 | μπακάλης |
| A1 | Μύκονος |
| A1 | νορβηγικά |
| A1 | νορβηγικός |
| A1 | Νορβηγός |
| A1 | οικογενειακό δέντρο |
| A1 | ούζο |
| A1 | οχτακόσιοι |
| A1 | πάρκιγκ |
| A1 | πεντακόσιοι |
| A1 | πεντέμισι |
| A1 | περνάω καλά |
| A1 | πιστωτική κάρτα |
| A1 | Πορτογάλος |
| A1 | Πόσων χρονών είσαι; |
| A1 | Πώς σε λένε; |
| A1 | σβήστρα |
| A1 | Σίδνεϋ |
| A1 | στάση λεωφορείου |
| A1 | στολίζω |
| A1 | στολισμένος |
| A1 | συστημένο γράμμα |
| A1 | σχολική χρονιά |
| A1 | ταξιδιωτικό γραφείο |
| A1 | τέρμα λεωφορείου |
| A1 | τετρακόσιοι |
| A1 | τηγανίζω |
| A1 | Τι καιρό κάνει; |
| A1 | τουρκικά |
| A1 | τουρκικός |
| A1 | τριακόσιοι |
| A1 | τριανταφυλλιά |
| A1 | τσάντα σχολική |
| A1 | Τσεχία |
| A1 | υπογραμμίζω |
| A1 | υπογραμμισμένος |
| A1 | φινλανδικά |
| A1 | φινλανδικός |
| A1 | Φινλανδός |
| A1 | φροντιστήριο |
| A1 | φωτογραφική μηχανή |
| A1 | χαιρετισμοί/χαιρετίσματα |
| A1 | Χαλκιδική |
| A1 | Χανιά |
| A1 | χάρακας |
| A1 | Χάρηκα που σας γνώρισα! |
| A1 | χριστουγεννιάτικο δέντρο |
| A1 | χωριάτικη σαλάτα |
| A1 | ψάθα |
| A2 | αεροπορικό ταξίδι |
| A2 | αθλητικά γεγονότα |
| A2 | αθλητικοί αγώνες |
| A2 | Αληθώς Ανέστη! |
| A2 | ανάληψη χρημάτων |
| A2 | ανεβαίνει μια θεατρική παράσταση |
| A2 | απλό εισιτήριο |
| A2 | από μέσα/έξω |
| A2 | Από πού είσαι/είστε? |
| A2 | από τότε |
| A2 | αρχαία ελληνικά |
| A2 | ασθενής άνεμος |
| A2 | αστράφτει |
| A2 | αστράφτω |
| A2 | αυτόν τον καιρό |
| A2 | αφετηρία λεωφορείου |
| A2 | βάζω βάρος |
| A2 | βάζω πλυντήριο |
| A2 | βιβλιάριο τράπεζας |
| A2 | βρεφονηπιακός σταθμός |
| A2 | γαρίφαλο |
| A2 | Γεράσιμος |
| A2 | γι' αυτό |
| A2 | γιαλός |
| A2 | γυαλιά ηλίου |
| A2 | γυρίζω/γυρνάω |
| A2 | δερμάτινος |
| A2 | Δέσποινα |
| A2 | δηλητηριάζω |
| A2 | διαγώνια |
| A2 | διαδοχικά |
| A2 | διαδοχικός |
| A2 | δίκλινο |
| A2 | δουλειές σπιτιού |
| A2 | δραματική ταινία |
| A2 | δύο φορές |
| A2 | εδώ γύρω |
| A2 | εδώ και πολύ καιρό |
| A2 | είμαι σπίτι |
| A2 | εισιτήριο με επιστροφή |
| A2 | Ελίνα |
| A2 | εμπορικό κέντρο |
| A2 | ενθουσιάζω |
| A2 | επώνυμος |
| A2 | έργο θεατρικό |
| A2 | Ευτυχισμένος ο καινούριος χρόνος! |
| A2 | έχει αέρα |
| A2 | έχει ήλιο |
| A2 | έχει συννεφιά |
| A2 | Ζέτα |
| A2 | Ζήσης |
| A2 | ζωντανή μουσική |
| A2 | η σειρά μου |
| A2 | ηλεκτρικά είδη |
| A2 | θα είμαι πίσω |
| A2 | Θανάσης |
| A2 | θεατρικό έργο |
| A2 | Θωμαή |
| A2 | και οι δύο |
| A2 | Καλές γιορτές! |
| A2 | Καλή Ανάσταση! |
| A2 | Καλή διασκέδαση! |
| A2 | Καλή επιτυχία! |
| A2 | Καλή όρεξη! |
| A2 | Καλή χρονιά! |
| A2 | Καλό Πάσχα! |
| A2 | κάνει/έχει κρύο |
| A2 | κάνω βόλτα |
| A2 | κάνω μπάνιο |
| A2 | κατανόηση γραπτού λόγου |
| A2 | κατανόηση προφορικού λόγου |
| A2 | κατεβάζω μουσική |
| A2 | κεντρικό δελτίο ειδήσεων |
| A2 | ΚΕΠ (Κέντρο Εξυπηρέτησης Πολιτών) |
| A2 | κινητό τηλέφωνο |
| A2 | κλειδί-λέξη |
| A2 | κολυμβητήριο |
| A2 | Κομοτηνή |
| A2 | κουζίνα ηλεκτρική |
| A2 | Κρητικός |
| A2 | Κυριάκος |
| A2 | Κώστας |
| A2 | λαϊκή μουσική |
| A2 | Λάρισα |
| A2 | λάτιν χορός |
| A2 | Λευκός Πύργος |
| A2 | λέω ψέματα |
| A2 | ληξιαρχείο |
| A2 | Λίνκον Αβραάμ |
| A2 | Λίτσα |
| A2 | μαζεύω από κάτω |
| A2 | Μανόλης |
| A2 | Μάριος |
| A2 | μάρκα αυτοκινήτου |
| A2 | μάσκα ομορφιάς |
| A2 | με λένε |
| A2 | μεζές |
| A2 | μένω σπίτι |
| A2 | μεταφορικό μέσο |
| A2 | μία φορά |
| A2 | Μίρκα |
| A2 | Μιχάλης |
| A2 | μονόκλινο |
| A2 | μου πηγαίνει |
| A2 | μου φαίνεται |
| A2 | μουσακάς |
| A2 | μουσικό κουτί |
| A2 | μουσικό όργανο |
| A2 | μπακλαβάς |
| A2 | Μπάμπης |
| A2 | Να ζήσεις! |
| A2 | Να ζήσετε! |
| A2 | Να τα εκατοστίσεις! |
| A2 | Ναβαρίνου (πλατεία) |
| A2 | Νεκτάριος |
| A2 | νησιώτικος |
| A2 | ξαναδιαβάζω |
| A2 | ξαναδίνω |
| A2 | ξαναμιλάω |
| A2 | ξαναπερνάω |
| A2 | Ξάνθη |
| A2 | ξεπλένω |
| A2 | ξηρός καρπός |
| A2 | «Ο Θάνατος του εμποράκου» |
| A2 | οικογενειακή κατάσταση |
| A2 | ονοματεπώνυμο |
| A2 | Όσκαρ βραβείο |
| A2 | όσπριο |
| A2 | ό,τι |
| A2 | ουζερί |
| A2 | παίρνω συνέντευξη |
| A2 | παραγγέλλω/παραγγέλνω |
| A2 | παραγωγή γραπτού λόγου |
| A2 | παραγωγή προφορικού λόγου |
| A2 | παρουσιάζομαι |
| A2 | πεντάγραμμο |
| A2 | πηγαίνω για τρέξιμο |
| A2 | πηγαίνω διακοπές |
| A2 | πηγαίνω στο σχολείο |
| A2 | πιάτσα ταξί |
| A2 | Πλατεία Συντάγματος |
| A2 | πλένω τα πιάτα |
| A2 | πονάει η κοιλιά μου |
| A2 | ποντιακός |
| A2 | Πόσο κάνει; |
| A2 | πριν από λίγο (καιρό) |
| A2 | προσχολικός |
| A2 | πρώτες βοήθειες |
| A2 | Πύργος του Άιφελ |
| A2 | Πώς σε/σας λένε; |
| A2 | ραδιοφωνική εκπομπή |
| A2 | ραδιοφωνικός σταθμός |
| A2 | ράτσα ζώου |
| A2 | ρίγανη |
| A2 | ροκ μουσική |
| A2 | «Ρωμαίος και Ιουλιέτα» |
| A2 | Σαίξπηρ Ουίλιαμ |
| A2 | Σας παρακαλώ! |
| A2 | σβήνω τη φωτιά |
| A2 | σε σχέση με |
| A2 | σημειώνω / κρατάω σημειώσεις |
| A2 | σκορπίζω |
| A2 | στην τηλεόραση |
| A2 | συρτάκι |
| A2 | Τασούλα |
| A2 | ταυτότητα αστυνομική |
| A2 | τζάζ,η |
| A2 | τηλεφωνώ / παίρνω τηλέφωνο |
| A2 | τ.μ. |
| A2 | τμήμα αστυνομικό |
| A2 | τραπεζομάντιλο |
| A2 | τρία πόδια Χαλκιδικής |
| A2 | Τρίπολη |
| A2 | Τσιτσάνης Βασίλης |
| A2 | υψηλή θερμοκρασία |
| A2 | φέιγ βολάν |
| A2 | φθηνός |
| A2 | φοιτητική εστία |
| A2 | φοιτώ |
| A2 | φουντούκι |
| A2 | φυσικό αέριο |
| A2 | Χαράλαμπος |
| A2 | Χαρίκλεια |
| A2 | χλιαρός |
| A2 | Χριστός Ανέστη! |
| A2 | Χρόνια πολλά! |
| A2 | χτυπάει το τηλέφωνο |
| A2 | ψιχαλίζει |
| B1 | αγιόκλημα |
| B1 | Άγιος Μαυρίκιος |
| B1 | αγκινάρα |
| B1 | αγοραπωλησία |
| B1 | αγορασμένος |
| B1 | Αγρίνιο |
| B1 | άθληση |
| B1 | αθλούμαι |
| B1 | Αιγαίο |
| B1 | Αιγόκερως |
| B1 | αισιοδοξώ |
| B1 | αιτιολογώ |
| B1 | άκομψος |
| B1 | ακρογιαλιά |
| B1 | ακροστιχίδα |
| B1 | ακτινολόγος |
| B1 | αλείφω |
| B1 | αλευρώνω |
| B1 | αλκοολούχος |
| B1 | αλλαγμένος |
| B1 | αλλάζω γνώμη |
| B1 | αλλαντικό |
| B1 | αλώβητα |
| B1 | αμοιβαιότητα |
| B1 | Αμοργός |
| B1 | αμυγδαλωτός |
| B1 | αν και |
| B1 | αναγνωστήριο |
| B1 | ανακεφαλαίωση |
| B1 | ανακυκλωμένος |
| B1 | ανακυκλώνω |
| B1 | αναπτύσσομαι |
| B1 | ανεβοκατεβαίνω |
| B1 | ανευθυνότητα |
| B1 | άνηθος |
| B1 | ανθοδοχείο |
| B1 | ανθότυρο |
| B1 | ανοιχτωσιά |
| B1 | ανοργάνωτος |
| B1 | ανταμώνω |
| B1 | αντιβίωση |
| B1 | αντιδραστικός |
| B1 | αντιηλιακό |
| B1 | αντικαταβολή |
| B1 | αντικειμενικότητα |
| B1 | αντικολλητικός |
| B1 | αντικρίζω |
| B1 | αντίλογος |
| B1 | αντιστοιχίζω |
| B1 | αντωνυμία |
| B1 | άνω κάτω |
| B1 | Άνω Πορόια |
| B1 | ανώι |
| B1 | ανωριμότητα |
| B1 | αξιοποίηση |
| B1 | αόριστο άρθρο |
| B1 | απαριθμώ |
| B1 | απασχολούμαι |
| B1 | απελπίζομαι |
| B1 | απόβλητο |
| B1 | αποδίδω |
| B1 | αποδρώ |
| B1 | απολυμαίνω |
| B1 | απορρίμματα |
| B1 | αποτελούμαι |
| B1 | αποτυχαίνω |
| B1 | απουσιάζω |
| B1 | αποφάγι |
| B1 | αραιωμένος |
| B1 | αραχτός |
| B1 | αργυροπελεκάνος |
| B1 | αριθμώ |
| B1 | Αρίων |
| B1 | αρρωστιάρης |
| B1 | Άρτεμη |
| B1 | αρωματίζω |
| B1 | αρωματισμός |
| B1 | ασπρομάλλης |
| B1 | Αστεροσκοπείο |
| B1 | αστροφυσικός |
| B1 | Αστυπάλαια |
| B1 | ατμομάγειρας |
| B1 | ατσαλάκωτος |
| B1 | Αττική |
| B1 | αυξημένος |
| B1 | αυστηρότητα |
| B1 | αυτόνομος |
| B1 | αυτοσχεδιάζω |
| B1 | αφηγούμαι |
| B1 | αφιλόξενος |
| B1 | αφορώ |
| B1 | άχνη |
| B1 | αχυρένιος |
| B1 | βαθμολογούμαι |
| B1 | βαθμολογώ |
| B1 | βάθρα |
| B1 | βαλκανικός |
| B1 | Βαλτική |
| B1 | βασιλόπουλο |
| B1 | βατραχοπέδιλο |
| B1 | βεγγέρα |
| B1 | βερικοκιά |
| B1 | βερμούδα |
| B1 | βιβλιοπώλης |
| B1 | βιολετής |
| B1 | βιολετί |
| B1 | βλαβερός |
| B1 | βουρτσίζω |
| B1 | βουτυρωμένος |
| B1 | βραβεύομαι |
| B1 | βραβεύω |
| B1 | βραδιάζει |
| B1 | βράσιμο |
| B1 | βρεφικός |
| B1 | βρομιάρης |
| B1 | βρομώ |
| B1 | βροντάω |
| B1 | βροντερός |
| B1 | βωβός |
| B1 | γάβρος |
| B1 | γαζώνω |
| B1 | γαϊδουράκι |
| B1 | γαϊτάνι |
| B1 | γαλατάς |
| B1 | γάργαρος |
| B1 | γεμιστές πιπεριές |
| B1 | γεράνι |
| B1 | γέρικος |
| B1 | γευματίζω |
| B1 | γεφύρι |
| B1 | γεωπόνος |
| B1 | γεωργός |
| B1 | γι’ αυτό |
| B1 | για το δικό σας καλό |
| B1 | Γιάννενα |
| B1 | γιαουρτάς |
| B1 | γίδι |
| B1 | γιορταστικός |
| B1 | γιουβαρλάκια |
| B1 | γιουβέτσι |
| B1 | γκέμι |
| B1 | γλυκαίνω |
| B1 | γλυκό του κουταλιού |
| B1 | γλυκό του ταψιού |
| B1 | γούνινος |
| B1 | γουρλής |
| B1 | γραπτές εξετάσεις |
| B1 | γραφίστας |
| B1 | γρουσούζης |
| B1 | δανεισμός |
| B1 | δανειστικός |
| B1 | δασικός |
| B1 | δεκαήμερο |
| B1 | δελτίο καιρού |
| B1 | δένομαι |
| B1 | δερματολόγος |
| B1 | δηλητηριάζομαι |
| B1 | δηλητηριασμένος |
| B1 | Δήλος |
| B1 | Δημητρός |
| B1 | δημιουργούμαι |
| B1 | δημοσιοποίηση |
| B1 | διαιτητικός |
| B1 | διαιτολόγος |
| B1 | διακοσιοστός |
| B1 | διακρίνομαι |
| B1 | διαμένω |
| B1 | διανυκτέρευση |
| B1 | διανυκτερεύω |
| B1 | διαπροσωπικός |
| B1 | διαρρύθμιση |
| B1 | διασκευασμένος |
| B1 | διατύπωνομαι |
| B1 | διδάκτορας |
| B1 | διήγημα |
| B1 | διπλωματικός |
| B1 | διώροφος |
| B1 | δοκιμασμένος |
| B1 | δοκίμιο |
| B1 | δροσίζω |
| B1 | δυναμισμός |
| B1 | δυναμώνω |
| B1 | δυναμωτικός |
| B1 | δυόσμος |
| B1 | Δωδεκάνησα |
| B1 | δώμα |
| B1 | Έβρος |
| B1 | εθνότητα |
| B1 | ειδικευμένος |
| B1 | εκβιάζω |
| B1 | εκβιαστικός |
| B1 | εκδηλώνομαι |
| B1 | εκδοτήριο |
| B1 | εκπτωτικός |
| B1 | εκτυπώνω |
| B1 | εκφοβίζω |
| B1 | εκφοβιστής |
| B1 | εκφοβιστικός |
| B1 | εκφράζομαι |
| B1 | ελαττωματικός |
| B1 | Ελεγκάκη |
| B1 | ενημερωτικός |
| B1 | ενθαρρυντικός |
| B1 | εννιάχρονος |
| B1 | ενορχήστρωση |
| B1 | εντυπωσιάζω |
| B1 | εξαντλητικός |
| B1 | εξελίσσομαι |
| B1 | εξεταστής |
| B1 | εξεταστικός |
| B1 | εξοικονομώ |
| B1 | εξοπλίζω |
| B1 | επαγγελματισμός |
| B1 | επιβιβάζομαι |
| B1 | επιδιώκω |
| B1 | επικαιρότητα |
| B1 | επιλεγμένος |
| B1 | επιπλωμένος |
| B1 | επίρρημα |
| B1 | επισκευάζω |
| B1 | εποχιακός |
| B1 | εργατική τάξη |
| B1 | ερωδιός |
| B1 | έτσι κι έτσι |
| B1 | ευέλικτος |
| B1 | Ευρυπίδης |
| B1 | Ευρωπαϊκή Ενωση |
| B1 | ευωδιάζω |
| B1 | ζαχαροπλαστική |
| B1 | ζευγαρώνω |
| B1 | ζορίζω |
| B1 | ζουμερός |
| B1 | ζύμωμα |
| B1 | ζυμώνω |
| B1 | ηλεκτρική ενέργεια |
| B1 | ηλεκτρική συσκευή |
| B1 | ηλεκτρικό ρεύμα |
| B1 | ηλεκτρολογικός |
| B1 | ηλεκτρονικός υπολογιστής |
| B1 | ημερίδα |
| B1 | ημιδιατροφή |
| B1 | ηφαίστιο |
| B1 | ηχογραφώ |
| B1 | ηχορύπανση |
| B1 | Θεόδωρος |
| B1 | θεραπεύομαι |
| B1 | θερίζω |
| B1 | Θερμαϊκός |
| B1 | θερμαίνω |
| B1 | Θράκη |
| B1 | θρεπτικός |
| B1 | ιβουάρ |
| B1 | ισότιμος |
| B1 | κάθε φορά |
| B1 | καλαμαράκι |
| B1 | Καλαμάτα |
| B1 | καλλιεργημένος |
| B1 | καλορίζικος |
| B1 | καλότυχος |
| B1 | κάμπιγκ |
| B1 | κανάτι |
| B1 | κάνω παιδί |
| B1 | κάρδαμο |
| B1 | κασέρι |
| B1 | καταναλωτικός |
| B1 | καταπιέζω |
| B1 | καταπράσινος |
| B1 | κατασκευασμένος |
| B1 | κατασκευαστικός |
| B1 | καταστροφικός |
| B1 | κάτοψη |
| B1 | κατώι |
| B1 | καυσαέριο |
| B1 | καφετζής |
| B1 | κεραμίδι |
| B1 | Κερκίνη |
| B1 | κεφαλοτύρι |
| B1 | Κηφισιά |
| B1 | κινητικός |
| B1 | κινούμενα σχέδια |
| B1 | κλινικός |
| B1 | κοινόχρηστος |
| B1 | κοινωνικότητα |
| B1 | κοκκινιστό |
| B1 | κολοκύθι |
| B1 | κολοκυθόπιτα |
| B1 | κοπιάζω |
| B1 | κορινθιακός |
| B1 | κοροϊδευτικός |
| B1 | κοσκινίζω |
| B1 | κοσμικός |
| B1 | κοσμοπολίτικος |
| B1 | κότσος |
| B1 | κουλούρι σουσαμένιο |
| B1 | κουλουρτζής |
| B1 | κουσκούσι |
| B1 | κουταλάκι του γλυκού |
| B1 | κούφωμα |
| B1 | κρατάω σημειώσεις |
| B1 | κρεατικά |
| B1 | κρεατόσουπα |
| B1 | κροκάδι |
| B1 | κροκέτα |
| B1 | κρυπτόλεξο |
| B1 | Κυκλάδες |
| B1 | κυκλοφοριακός |
| B1 | κυλάω |
| B1 | κυρίως πιάτο |
| B1 | κώνος |
| B1 | Κως |
| B1 | λαδερά |
| B1 | λαδόκολα |
| B1 | λαίμαργα |
| B1 | λαλάω |
| B1 | Λάρνακα |
| B1 | λαχανί |
| B1 | λεπτομύτα |
| B1 | Λευτέρης |
| B1 | λησμονιέμαι |
| B1 | λογαριάζω |
| B1 | λογιών λογιών |
| B1 | λούζομαι |
| B1 | Λωξάντρα |
| B1 | μαγειρεμένος |
| B1 | μαγειρίτσα |
| B1 | μεταφορικός |
| B1 | μεταχειρίζομαι |
| B1 | μηδενίζω |
| B1 | μηχανοδηγός |
| B1 | μικροβιολόγος |
| B1 | μισοτιμής |
| B1 | μόδιστρος |
| B1 | μοιραίος |
| B1 | μολύνω |
| B1 | μονιμότητα |
| B1 | μονολεκτικός |
| B1 | μονόχρωμος |
| B1 | μονώροφος |
| B1 | μορταδέλα |
| B1 | μοσχοβολάω |
| B1 | Μπαξέδες |
| B1 | μπέικιν πάουντερ |
| B1 | μπέμπης |
| B1 | μπομπονιέρα |
| B1 | μποφόρ |
| B1 | μπρίκι |
| B1 | μυγιάζομαι |
| B1 | μύδια σαγανάκι |
| B1 | μυδοπίλαφο |
| B1 | μύτι |
| B1 | νανόχηνα |
| B1 | Ναύπακτος |
| B1 | νεανικός |
| B1 | νεόδμητος |
| B1 | νεοκλασικός |
| B1 | νέφωση |
| B1 | νηπιακός |
| B1 | νηστικός |
| B1 | Νικολέτα |
| B1 | νοηματικός |
| B1 | νοθεύω |
| B1 | νοικοκύρης |
| B1 | νομάς |
| B1 | νοστιμεύω |
| B1 | νοστιμιά |
| B1 | νοτιανατολικός |
| B1 | ντάκος |
| B1 | ντάλα |
| B1 | ντολμάς |
| B1 | ξακουστός |
| B1 | ξαναγίνομαι |
| B1 | ξαναθυμάμαι |
| B1 | ξαναμαζεύω |
| B1 | ξαναπηγαίνω |
| B1 | ξαναφωνάζω |
| B1 | ξεβάφω |
| B1 | ξεκολλάω |
| B1 | ξεκούραστος |
| B1 | ξεφλουδίζω |
| B1 | ξεφουσκωμένος |
| B1 | ξεχειλώνω |
| B1 | ξηρότητα |
| B1 | ξυλοδαρμός |
| B1 | ξύσμα |
| B1 | οικία,η |
| B1 | οργανωτικός |
| B1 | ορεινός |
| B1 | ορθοπεδικός |
| B1 | ορθοπεταλιά |
| B1 | οριστικό άρθρο |
| B1 | οροφοδιαμέρισμα |
| B1 | οστρακοειδής |
| B1 | οφθαλμίατρος |
| B1 | παγωτατζής |
| B1 | παιδική χαρά |
| B1 | παιδότοπος |
| B1 | παινεύω |
| B1 | παίρνω μέρος |
| B1 | παίρνω τηλέφωνο |
| B1 | παιχνιδιάρης |
| B1 | παλέτα |
| B1 | Παναγιώτης |
| B1 | πανελλαδικός |
| B1 | παπαγαλία |
| B1 | παπάγια |
| B1 | Παπαδιαμάντης |
| B1 | παράγομαι |
| B1 | παραδεισένιος |
| B1 | παρασκευάζομαι |
| B1 | παρασύρομαι |
| B1 | πασπαλίζω |
| B1 | παστίτσιο |
| B1 | πατέρας, |
| B1 | παχαίνω |
| B1 | παχουλός |
| B1 | παχυντικός |
| B1 | πεδινός |
| B1 | πέλαγος |
| B1 | Πελοπόννησος |
| B1 | περιέχω |
| B1 | περιπτεράς |
| B1 | Περσεφόνη |
| B1 | πετιέμαι |
| B1 | πετρόλ |
| B1 | πήλινος |
| B1 | πιέτα |
| B1 | πιλοτή |
| B1 | πιλοτικός |
| B1 | πινακοθήκη |
| B1 | πλαγιαστός |
| B1 | πλαγιότιτλος |
| B1 | πλακάκι |
| B1 | πλαστελίνη |
| B1 | πλάτανος |
| B1 | πλέκω |
| B1 | πλένομαι |
| B1 | πληκτρολογώ |
| B1 | πληροφοριακός |
| B1 | πνευματικό κέντρο |
| B1 | πνευμονολόγος |
| B1 | πνέω |
| B1 | ποδαρικό |
| B1 | ποδηλάτης |
| B1 | πολύξερος |
| B1 | πολυταξιδευμένος |
| B1 | ποπ μουσική |
| B1 | Πόπη |
| B1 | πουά |
| B1 | πουλερικό |
| B1 | πουλημένος |
| B1 | πρόβειος |
| B1 | προεξέχω |
| B1 | προοδεύω |
| B1 | προορίζω |
| B1 | προπώληση |
| B1 | προσαρμόζομαι |
| B1 | πρόσθετος |
| B1 | προσπερνάω |
| B1 | προτέρημα |
| B1 | προφορικές εξετάσεις |
| B1 | πρωτοβρόχια |
| B1 | ρακή |
| B1 | ρακόμελο |
| B1 | ραπ μουσική |
| B1 | ράφτιγκ |
| B1 | ρεβανί |
| B1 | ρεβεγιόν |
| B1 | ρεβίθι |
| B1 | ρεμπέτικο |
| B1 | ρίχνω μια ματιά |
| B1 | ρόδι |
| B1 | ροδίζω |
| B1 | ροδοπελεκάνος |
| B1 | ροκφόρ |
| B1 | ρολόι τοίχου |
| B1 | ρυπαίνω |
| B1 | σαλεπτζής |
| B1 | Σαμοθράκη |
| B1 | σαρίκι |
| B1 | σγουρομάλλης |
| B1 | σε λίγο καιρό |
| B1 | Σε/Σας παρακαλώ! |
| B1 | σιδερώνω |
| B1 | σιέλ |
| B1 | σιτεύω |
| B1 | σκάζω |
| B1 | σκαντζόχοιρος |
| B1 | σκηνοθετικός |
| B1 | σκηνοθετώ |
| B1 | σκισμένος |
| B1 | σκοτεινιάζω |
| B1 | σκουντάω |
| B1 | σλαβικός |
| B1 | Σμύρνη |
| B1 | σοκολατί |
| B1 | σπανακόπιτα |
| B1 | σπανακόρυζο |
| B1 | σπάταλος |
| B1 | σπιτοκαλυβάκι |
| B1 | Σποράδες |
| B1 | στάση προσευχής |
| B1 | στέγνωμα |
| B1 | Στέλιος |
| B1 | στενεύω |
| B1 | στενόχωρος |
| B1 | στη συνέχεια |
| B1 | στραβός |
| B1 | στραγάλι |
| B1 | στραπατσάδα |
| B1 | στύβω |
| B1 | συγγενικός |
| B1 | συγκλονιστικός |
| B1 | συζητιέμαι |
| B1 | συμβάλλω |
| B1 | συμβουλεύομαι |
| B1 | συμμαχικός |
| B1 | συμπερασματικά |
| B1 | συμπεριλαμβάνομαι |
| B1 | συμφέρω |
| B1 | συννεφιάζω |
| B1 | συννεφιασμένος |
| B1 | συντελεστής |
| B1 | συντροφεύω |
| B1 | συστηματικός |
| B1 | σφουγγαρίζω |
| B1 | σχεδιασμένος |
| B1 | Σωτήρης |
| B1 | ταγέρ |
| B1 | ταινία μικρού μήκος |
| B1 | ταρό |
| B1 | τεμπελιάζω |
| B1 | τενεκές |
| B1 | τετραώροφος |
| B1 | τζατζίκι |
| B1 | τζιτζίκι |
| B1 | τηγάνισμα |
| B1 | τονισμός |
| B1 | τονώνω |
| B1 | του φούρνου |
| B1 | τούρκικος |
| B1 | τρεμοσβήνω |
| B1 | τριάρι |
| B1 | τριώροφος |
| B1 | τροφικός |
| B1 | τσαγκάρης |
| B1 | τσικουδιά |
| B1 | τσίπουρο |
| B1 | τσουρέκι |
| B1 | τυροπιτάκι |
| B1 | τυροσαλάτα |
| B1 | υγρότοπος |
| B1 | υλοποιώ |
| B1 | υπερσύγχρονος |
| B1 | υπνόσακος |
| B1 | υπολογισμένος |
| B1 | υφασμάτινος |
| B1 | φασολάδα |
| B1 | φέρσιμο |
| B1 | φιδάκι |
| B1 | φίλαθλος |
| B1 | Φιλανδία |
| B1 | φλούδι |
| B1 | φοβερίζω |
| B1 | φογάτσα |
| B1 | φοινικόπτερο |
| B1 | φοίτηση |
| B1 | φούρνος μικροκυμάτων |
| B1 | φουσκώνω |
| B1 | φτήνια |
| B1 | φυσιογνωμικός |
| B1 | φυτικός |
| B1 | φυτοφάρμακο |
| B1 | φωτοτυπικός |
| B1 | φωτοτυπώ |
| B1 | χαγιάτι |
| B1 | χαδιάρης |
| B1 | χαλβάς |
| B1 | χαλκόκοτα |
| B1 | χάσιμο χρόνου |
| B1 | χασμουριέμαι |
| B1 | χασομέρι |
| B1 | χειροτεχνία |
| B1 | χιλιομετρικός |
| B1 | χιονισμένος |
| B1 | χιονοδρομικό κέντρο |
| B1 | χιονοδρομικός |
| B1 | χιονόπτωση |
| B1 | Χονγκ Κονγκ |
| B1 | χορογράφος |
| B1 | χορογραφώ |
| B1 | χορταστικός |
| B1 | χουβαρντάς |
| B1 | χτενίζομαι |
| B1 | χτισμένος |
| B1 | χτίστης |
| B1 | χωμάτινος |
| B1 | χωριάτικος |
| B1 | ψαρικά |
| B1 | ψηλοτάκουνος |
| B1 | ψηλώνω |
| B1 | ψιλικατζής |
| B1 | ψίχα |
| B1 | ψίχουλο |
| B1 | ψυχαγωγικός |
| B1 | ψυχαγωγώ |
| B1 | ψυχραίνω |
| B1 | ωτορινολαρυγγολόγος |
| B1 | ωφέλεια |
| B1 | ωφέλιμος |

### Merged rows (62 words of 131 rows)

| Level | Word | Rows (level:line term) | Translation | Endings |
|---|---|---|---|---|
| A1 | άγνωστος | A1:19 άγνωστος, A1:20 άγνωστος | unknown, stranger; known, unfamiliar | -η, -ο |
| A1 | αστυνομικός | A1:173 αστυνομικός, A1:174 αστυνομικός | policewoman, police officer; policeman, police officer | η / ο |
| A1 | Αύγουστος | A1:181 Αύγουστος, A1:204 Αύγουστος | August | ο |
| A1 | αυστριακός | A1:188 Αυστριακός, A1:189 αυστριακός | Austrian | -ή / -ή, -ό |
| A1 | αυτός | A1:192 αυτός, A1:193 αυτός | he, she, it (for persons); this (not for persons) | -ή, -ό |
| A1 | γάμος | A1:276 γάμος, A1:277 γάμος | wedding (ceremony); marriage (institution) | ο |
| A1 | γιατί | A1:305 γιατί, A1:306 γιατί | [interrogative] why; [causative] because | — |
| A1 | γλώσσα | A1:315 γλώσσα, A1:316 γλώσσα | language; (body) tongue | η |
| A1 | γραφείο | A1:332 γραφείο, A1:333 γραφείο | office; (furniture) desk | το |
| A1 | διευθυντής | A1:409 διευθυντής, A1:410 διευθυντής | director (in general); Headmaster (in school) | -ντρια |
| A1 | δικός | A1:411 δικός, A1:412 δικός, A1:413 δικός, A1:414 δικός, A1:415 δικός, A1:416 δικός, A1:417 δικός, A1:418 δικός | my, mine; your, yours; his; her, hers; its; our, ours; their, theirs | -ή, -ό / δικοί, -ές, -ά μου / -ή, -ό / δικοί, -ές, -ά σου/σας / -ή, -ό / δικοί, -ές, -ά του / -ή, -ό / δικοί, -ές, -ά της / -ή, -ό / δικοί, -ές, -ά μας / -ή, -ό / δικοί, -ές, -ά σας / -ή, -ό / δικοί, -ές, -ά τους |
| A1 | δοκιμάζω | A1:427 δοκιμάζω, A1:428 δοκιμάζω | to try (in general); to taste (food) | — |
| A1 | δύση | A1:440 Δύση, A1:441 δύση | West; sunset | η |
| A1 | είμαι | A1:454 είμαι, A1:455 είμαι | to be; I am | — |
| A1 | εννέα | A1:468 εννέα, A2:204 εννέα | nine | εννιά |
| A1 | επτά | A1:519 επτά, B1:922 επτά | seven | εφτά |
| A1 | ηθοποιός | A1:540 ηθοποιός, A1:541 ηθοποιός | actress; actor | η / ο |
| A1 | ισραηλινός | A1:594 ισραηλινός, A1:595 Ισραηλινός | Israeli | -ή, -ό / -ή |
| A1 | κάποιος | A1:637 κάποιος, A1:638 κάποιος | someone; some, a | -α, -ο |
| A1 | κάτω | A1:658 κάτω, A1:659 κάτω | down; under | — |
| A1 | κεφαλαίο γράμμα | A1:669 κεφαλαίο γράμμα, A2:317 κεφαλαίο γράμμα | capital letter | το |
| A1 | κουζίνα | A1:711 κουζίνα, A1:712 κουζίνα | kitchen (room); cuisine, style of cooking | η |
| A1 | μέσα | A1:807 μέσα, A1:808 μέσα | (to stay) indoors; in | — |
| A1 | μέση | A1:810 μέση, A1:811 μέση | (body) waist; middle (place) | η |
| A1 | μουσικός | A1:848 μουσικός, A1:849 μουσικός | musical; musician | -ή, -ό / ο/η |
| A1 | μπάνιο | A1:857 μπάνιο, A1:858 μπάνιο | bathroom; bath | το |
| A1 | πάνω | A1:987 πάνω, A1:988 πάνω | up; on, onto | — |
| A1 | πίνακας | A1:1049 πίνακας, A1:1050 πίνακας, A1:1051 πίνακας | blackboard (in classroom); schedule; painting, work of art | ο |
| A1 | ποιος | A1:1074 ποιος, A1:1075 ποιος | (thing) which; (person) who | -α, -ο |
| A1 | πρόσωπο | A1:1124 πρόσωπο, A1:1125 πρόσωπο | (individual) person, (grammatical) person; (body) face | το |
| A1 | ρολόι | A1:1147 ρολόι, A1:1148 ρολόι | (wall) clock; (hand) watch | το |
| A1 | σπίτι | A1:1207 σπίτι, A1:1208 σπίτι | house, residence; (family) home | το |
| A1 | τρία | A1:1326 τρία, A1:1332 τρία | three | — |
| A1 | φέτα | A1:1379 φέτα, A1:1380 φέτα | feta cheese; slice | η |
| A1 | φούρνος | A1:1402 φούρνος, A1:1403 φούρνος | the baker’s, bakery; oven | ο |
| A2 | αίθουσα | A2:14 αίθουσα, A2:15 αίθουσα | classroom; hall | η |
| A2 | Αλέξανδρος | A2:18 Αλέξανδρος, A2:19 Αλέξανδρος | Alexander; Alexander the Great | ο / ο Μέγας |
| A2 | διάστημα | A2:134 διάστημα, A2:135 διάστημα | period, time; space | το |
| A2 | δύο φορές | A2:149 δύο φορές, A2:737 δύο φορές | twice | — |
| A2 | ειρήνη | A2:169 ειρήνη, A2:170 Ειρήνη | peace; Irene | η |
| A2 | εκπομπή | A2:176 εκπομπή, A2:182 εκπομπή | show, program | η |
| A2 | ελεύθερος | A2:191 ελεύθερος, A2:192 ελεύθερος | free; single | -η, -ο / ο ελεύθερη, η |
| A2 | ένας | A2:199 ένας, A2:200 ένας | one; a/an | μία, ένα / μια, ένα |
| A2 | έξω | A2:217 έξω, A2:218 έξω | out; outside | — |
| A2 | κάνω μπάνιο | A2:443 κάνω μπάνιο, A2:444 κάνω μπάνιο | to have/take a bath; to swim, to have a swim | — |
| A2 | κλειστός | A2:331 κλειστός, A2:332 κλειστός | shut, closed; turned off | ή, -ό |
| A2 | λειτουργώ | A2:375 λειτουργώ, A2:376 λειτουργώ | to be open; to work, to function | — |
| A2 | λήγω | A2:381 λήγω, A2:382 λήγω | to expire; to end | — |
| A2 | μεγαλώνω | A2:415 μεγαλώνω, A2:416 μεγαλώνω | to grow up, to grow old; to get/become bigger | — |
| A2 | ξένος | A2:475 ξένος, A2:476 ξένος | foreign; stranger | -η, -ο / ο / ξένη η |
| A2 | ξεπερνάω | A2:477 ξεπερνάω, A2:478 ξεπερνάω | to overcome; to exceed | — |
| A2 | πετάω | A2:543 πετάω, A2:544 πετάω | to fly; to throw | -ώ |
| A2 | πνίγομαι | A2:556 πνίγομαι, A2:557 πνίγομαι | to choke, to suffocate; to be drawn | — |
| A2 | Χρόνια πολλά! | A2:771 Χρόνια πολλά!, A2:772 Χρόνια πολλά! | Merry Christmas!; Happy birthday! | — |
| B1 | Άρης | B1:295 Άρης, B1:296 Άρης | Mars; Aris, Ares | ο |
| B1 | γκρινιάρης | B1:514 γκρινιάρης, B1:515 γκρινιάρης | nagging; Ludo (board game) | -α, -ικο / ο |
| B1 | έκθεση | B1:711 έκθεση, B1:712 έκθεση | essay writing; exhibition, exposition | η |
| B1 | ελπίδα | B1:742 Ελπίδα, B1:743 ελπίδα | Elpida; hope | η |
| B1 | ζώνη | B1:946 ζώνη, B1:947 ζώνη | belt; zone, area | η |
| B1 | καρπός | B1:1092 καρπός, B1:1093 καρπός | wrist; fruit | ο |
| B1 | υποβρύχιο | B1:2232 υποβρύχιο, B1:2233 υποβρύχιο | submarine; ipovrichio (a kind of spoon sweet, usually vanilla-flavored; it is usually served on ateaspoon and dipped into a glass of cold water) | το |
| B1 | φανάρι | B1:2253 Φανάρι, B1:2254 φανάρι | Fanari, a neighborhood in Constantinople; traffic light | το |

### Case pairs (6)

| Capitalised | Merged into |
|---|---|
| Αυστριακός | αυστριακός |
| Δύση | δύση |
| Ειρήνη | ειρήνη |
| Ελπίδα | ελπίδα |
| Ισραηλινός | ισραηλινός |
| Φανάρι | φανάρι |

## cefr-eng

### Counts

| Level | Rows | Words | Linked | Ranked |
|---|---|---|---|---|
| A1 | 1,164 | 1,063 | 100.0% | 98.6% |
| A2 | 1,411 | 1,241 | 99.8% | 96.5% |
| B1 | 2,446 | 2,138 | 99.4% | 96.0% |
| B2 | 2,778 | 2,417 | 99.0% | 91.1% |
| C1 | 1,111 | 913 | 97.2% | 77.7% |
| C2 | 1,025 | 875 | 93.9% | 52.8% |
| all | 9,935 | 8,647 | 98.6% | 88.7% |

1,288 rows merged into other rows' words (below).

### Link classes

| Level | exact | cleaned | near | form | override | unlinked |
|---|---|---|---|---|---|---|
| A1 | 1,053 | 0 | 0 | 4 | 6 | 0 |
| A2 | 1,237 | 0 | 0 | 1 | 0 | 3 |
| B1 | 2,125 | 0 | 0 | 0 | 0 | 13 |
| B2 | 2,394 | 0 | 0 | 0 | 0 | 23 |
| C1 | 884 | 0 | 0 | 3 | 0 | 26 |
| C2 | 821 | 0 | 0 | 1 | 0 | 53 |
| all | 8,514 | 0 | 0 | 9 | 6 | 118 |

### A1: the 20 most frequent words, before the shuffle

you, I, am, are, be, is, 'm, 're, was, were, the, to, a, 's, it, and, that, of, in, had

### Links to review: cleaned, near, form and override (15)

| Level | Term | Headword | Rule | The rules' link |
|---|---|---|---|---|
| A1 | am | be | override | am |
| A1 | are | be | override | are |
| A1 | did | do | form |  |
| A1 | does | do | override | — |
| A1 | had | have | form |  |
| A1 | is | be | override | IS |
| A1 | 'm | be | override | — |
| A1 | 're | be | override | — |
| A1 | was | be | form |  |
| A1 | were | be | form |  |
| A2 | been | be | form |  |
| C1 | chiselled | chisel | form |  |
| C1 | criteria | criterion | form |  |
| C1 | minutiae | minutia | form |  |
| C2 | metalled | metal | form |  |

### Unlinked words (118)

| Level | Term | Part of speech |
|---|---|---|
| A2 | headteacher | noun |
| A2 | ID card | noun |
| A2 | penfriend | noun |
| B1 | cashpoint | noun |
| B1 | eco | noun |
| B1 | extreme sports | noun |
| B1 | film-maker | noun |
| B1 | first-floor | adjective |
| B1 | hearted | adjective |
| B1 | message board | noun |
| B1 | next-door | adjective |
| B1 | noticeboard | noun |
| B1 | recycled | adjective |
| B1 | social networking | noun |
| B1 | sports | adjective |
| B1 | telecommunications | noun |
| B2 | bio | noun |
| B2 | carpool | noun |
| B2 | conferencing | noun |
| B2 | cyberaddict | noun |
| B2 | cyberpet | noun |
| B2 | cyberschool | noun |
| B2 | estimated | adjective |
| B2 | facilities | noun |
| B2 | glocal | adjective |
| B2 | grown-up | adjective, noun |
| B2 | inverted commas | noun |
| B2 | moonscape | noun |
| B2 | nano | noun |
| B2 | netsurfer | noun |
| B2 | non-smoking | adjective |
| B2 | ow | noun |
| B2 | prehuman | noun |
| B2 | preindustrial | adjective |
| B2 | semi-final | noun |
| B2 | showbiz | noun |
| B2 | unto | preposition |
| B2 | well-organized | adjective |
| B2 | well-paid | adjective |
| C1 | apt to | verb |
| C1 | beguilingly | adverb |
| C1 | bulk up | verb |
| C1 | chauffer | noun, verb |
| C1 | compliantly | adverb |
| C1 | compromised | adjective |
| C1 | demographically | adverb |
| C1 | docilely | adverb |
| C1 | dominantly | adverb |
| C1 | exotically | adverb |
| C1 | inclusively | adverb |
| C1 | insightfully | adverb |
| C1 | insubordinately | adverb |
| C1 | meaninglessly | adverb |
| C1 | norms | noun |
| C1 | pertain to | verb |
| C1 | prolifically | adverb |
| C1 | raunchily | adverb |
| C1 | stressfully | adverb |
| C1 | succulently | adverb |
| C1 | sustainably | adverb |
| C1 | unenviably | adverb |
| C1 | unscathing | adjective |
| C1 | unsustainable | adjective |
| C1 | unsustainably | adverb |
| C1 | whilst | conjunction |
| C2 | abhorrently | adverb |
| C2 | amorphously | adverb |
| C2 | angsty | adjective |
| C2 | anticlimactically | adverb |
| C2 | arcanely | adverb |
| C2 | bereftly | adverb |
| C2 | calamitously | adverb |
| C2 | choreographical | adjective |
| C2 | cogently | adverb |
| C2 | commensurately | adverb |
| C2 | compellingly | adverb |
| C2 | confrontationally | adverb |
| C2 | counterproductively | adverb |
| C2 | cultish | adjective |
| C2 | deficiently | adverb |
| C2 | deprecatingly | adverb |
| C2 | deviantly | adverb |
| C2 | echolocate | verb |
| C2 | emulsification | noun |
| C2 | euphorically | adverb |
| C2 | evokingly | adverb |
| C2 | exaltedly | adverb |
| C2 | fabulate | verb |
| C2 | fabulation | noun |
| C2 | flatout | adverb |
| C2 | floodgates | noun |
| C2 | genomic | adjective |
| C2 | genomically | adverb |
| C2 | glitzy | adjective |
| C2 | glory in | verb |
| C2 | hauntingly | adverb |
| C2 | histrionically | adverb |
| C2 | impressionistically | adverb |
| C2 | improvisational | adjective |
| C2 | inchoately | adverb |
| C2 | marketability | noun |
| C2 | mutinously | adverb |
| C2 | paralyzingly | adverb |
| C2 | porten | noun |
| C2 | promotable | adjective |
| C2 | proprietorial | adjective |
| C2 | reverb | noun |
| C2 | sandwiched | adjective |
| C2 | side-step | verb |
| C2 | squirmy | adjective |
| C2 | stultifyingly | adverb |
| C2 | undemonstratively | adverb |
| C2 | undiminishing | adjective |
| C2 | unexceptionally | adverb |
| C2 | unfeasibly | adverb |
| C2 | unharried | adjective |
| C2 | vestigially | adverb |
| C2 | wordage | noun |

### Unranked words (976)

| Level | Term |
|---|---|
| A1 | all right |
| A1 | CD player |
| A1 | credit card |
| A1 | dining room |
| A1 | each other |
| A1 | good afternoon |
| A1 | good morning |
| A1 | good night |
| A1 | have to |
| A1 | ice cream |
| A1 | last name |
| A1 | living room |
| A1 | mobile phone |
| A1 | o'clock |
| A1 | swimming pool |
| A2 | alarm clock |
| A2 | board game |
| A2 | bus station |
| A2 | bus stop |
| A2 | capital letter |
| A2 | car park |
| A2 | classical music |
| A2 | department store |
| A2 | digital camera |
| A2 | driver's license |
| A2 | fast food |
| A2 | first name |
| A2 | grocery store |
| A2 | headphone |
| A2 | headteacher |
| A2 | high school |
| A2 | ID card |
| A2 | main course |
| A2 | mineral water |
| A2 | MP3 player |
| A2 | next to |
| A2 | no one |
| A2 | olive oil |
| A2 | out of |
| A2 | penfriend |
| A2 | petrol station |
| A2 | police officer |
| A2 | police station |
| A2 | post office |
| A2 | schoolchild |
| A2 | shop assistant |
| A2 | sitting room |
| A2 | soft drink |
| A2 | sports center |
| A2 | superlative |
| A2 | swimming costume |
| A2 | table tennis |
| A2 | tablespoon |
| A2 | text message |
| A2 | tour guide |
| A2 | traffic light |
| A2 | video game |
| A2 | washing machine |
| A2 | web page |
| B1 | aborigine |
| B1 | according to |
| B1 | accustom |
| B1 | addressee |
| B1 | adverb |
| B1 | adverbial |
| B1 | air conditioning |
| B1 | air force |
| B1 | antonym |
| B1 | backpacker |
| B1 | bank account |
| B1 | because of |
| B1 | cashpoint |
| B1 | CD-ROM |
| B1 | central heating |
| B1 | chat show |
| B1 | chest of drawers |
| B1 | chewing gum |
| B1 | common sense |
| B1 | consonant |
| B1 | courgette |
| B1 | definite article |
| B1 | disc jockey |
| B1 | duty-free |
| B1 | earache |
| B1 | exchange rate |
| B1 | extreme sports |
| B1 | face to face |
| B1 | feverishly |
| B1 | film-maker |
| B1 | fire station |
| B1 | first floor |
| B1 | first lady |
| B1 | first-floor |
| B1 | frying pan |
| B1 | full stop |
| B1 | ground floor |
| B1 | heart attack |
| B1 | ice hockey |
| B1 | ice skating |
| B1 | identity card |
| B1 | immigrate |
| B1 | impair |
| B1 | indefinite article |
| B1 | infinitive |
| B1 | inscribe |
| B1 | instead of |
| B1 | interviewee |
| B1 | latecomer |
| B1 | message board |
| B1 | mixing bowl |
| B1 | modal verb |
| B1 | navy blue |
| B1 | next door |
| B1 | noticeboard |
| B1 | ought to |
| B1 | participle |
| B1 | phrasal verb |
| B1 | pocket money |
| B1 | pollutant |
| B1 | prefix |
| B1 | preposition |
| B1 | primary school |
| B1 | procrastination |
| B1 | public transport |
| B1 | question mark |
| B1 | remote control |
| B1 | retell |
| B1 | reunify |
| B1 | science fiction |
| B1 | secondary school |
| B1 | self-service |
| B1 | soap opera |
| B1 | social networking |
| B1 | suffix |
| B1 | traffic jam |
| B1 | travel agent |
| B1 | uplifted |
| B1 | used to |
| B1 | vice president |
| B1 | video clip |
| B1 | washbowl |
| B1 | weather forecast |
| B1 | wetland |
| B1 | windsurfing |
| B2 | accessibility |
| B2 | achievable |
| B2 | admiringly |
| B2 | adversely |
| B2 | agonize |
| B2 | aircrew |
| B2 | anchorperson |
| B2 | antiaircraft |
| B2 | antibacterial |
| B2 | anticancer |
| B2 | antipollution |
| B2 | antistatic |
| B2 | antivirus |
| B2 | armful |
| B2 | attainable |
| B2 | attainment |
| B2 | aubergine |
| B2 | balky |
| B2 | beautify |
| B2 | bewilder |
| B2 | bewilderment |
| B2 | biotechnology |
| B2 | bookish |
| B2 | breakable |
| B2 | burdensome |
| B2 | burgle |
| B2 | carbon dioxide |
| B2 | carbon footprint |
| B2 | carbon monoxide |
| B2 | categorization |
| B2 | cheerfulness |
| B2 | clearness |
| B2 | climate change |
| B2 | coherence |
| B2 | collocation |
| B2 | communicative |
| B2 | conferencing |
| B2 | countrywide |
| B2 | coziness |
| B2 | crossly |
| B2 | crystallize |
| B2 | cubism |
| B2 | cursor |
| B2 | cyberaddict |
| B2 | cybercafe |
| B2 | cybercrime |
| B2 | cyberpet |
| B2 | cyberschool |
| B2 | de facto |
| B2 | debit card |
| B2 | deforestation |
| B2 | dehumanize |
| B2 | determiner |
| B2 | dispensable |
| B2 | doorkeeper |
| B2 | downsize |
| B2 | drapery |
| B2 | drinkable |
| B2 | duplication |
| B2 | ecologically |
| B2 | ecologist |
| B2 | entitle |
| B2 | environmentally friendly |
| B2 | essayist |
| B2 | exactness |
| B2 | exalt |
| B2 | examinee |
| B2 | exclamation mark |
| B2 | exultant |
| B2 | fed up |
| B2 | ferryboat |
| B2 | fire brigade |
| B2 | first language |
| B2 | first person |
| B2 | flexibly |
| B2 | fluency |
| B2 | functionality |
| B2 | furor |
| B2 | generalization |
| B2 | generalize |
| B2 | glacis |
| B2 | global warming |
| B2 | glocal |
| B2 | gracefulness |
| B2 | graphically |
| B2 | guideline |
| B2 | gymnastic |
| B2 | habitant |
| B2 | handicraft |
| B2 | handrail |
| B2 | hard drive |
| B2 | health care |
| B2 | hospitalize |
| B2 | housemaster |
| B2 | human rights |
| B2 | humanize |
| B2 | hyphen |
| B2 | impermanent |
| B2 | impolitely |
| B2 | inborn |
| B2 | indent |
| B2 | industrialize |
| B2 | infringe |
| B2 | intransitive |
| B2 | invariable |
| B2 | inverted commas |
| B2 | invitingly |
| B2 | irresistibly |
| B2 | islander |
| B2 | italicize |
| B2 | junk food |
| B2 | keystroke |
| B2 | last minute |
| B2 | lawmaker |
| B2 | layabout |
| B2 | legislate |
| B2 | legislator |
| B2 | lowland |
| B2 | martial art |
| B2 | mechanize |
| B2 | microcomputer |
| B2 | micrometer |
| B2 | microorganism |
| B2 | microscopy |
| B2 | mistrustful |
| B2 | modernization |
| B2 | moonscape |
| B2 | mutability |
| B2 | mutable |
| B2 | native speaker |
| B2 | netsurfer |
| B2 | nonprofessional |
| B2 | outdistance |
| B2 | overbook |
| B2 | overemphasize |
| B2 | overshadow |
| B2 | oversize |
| B2 | owing to |
| B2 | paperless |
| B2 | penalize |
| B2 | permeate |
| B2 | point of view |
| B2 | polar bear |
| B2 | polity |
| B2 | popularize |
| B2 | predicate |
| B2 | predicative |
| B2 | predictor |
| B2 | prehuman |
| B2 | preindustrial |
| B2 | prejudge |
| B2 | prime minister |
| B2 | proponent |
| B2 | quarrelsome |
| B2 | quotable |
| B2 | rafter |
| B2 | real estate |
| B2 | recommendable |
| B2 | referent |
| B2 | reprint |
| B2 | reprove |
| B2 | respectably |
| B2 | ruinous |
| B2 | rush hour |
| B2 | salesmanship |
| B2 | scholasticism |
| B2 | second person |
| B2 | semicolon |
| B2 | simplification |
| B2 | skateboarder |
| B2 | skyward |
| B2 | smokestack |
| B2 | solidity |
| B2 | soliloquy |
| B2 | southward |
| B2 | sparerib |
| B2 | speeder |
| B2 | spokeswoman |
| B2 | stanza |
| B2 | steering wheel |
| B2 | stock market |
| B2 | stonework |
| B2 | subcontinent |
| B2 | subculture |
| B2 | subjunctive |
| B2 | subplot |
| B2 | synonym |
| B2 | tatter |
| B2 | thickly |
| B2 | third person |
| B2 | timeliness |
| B2 | tortoiseshell |
| B2 | transitive |
| B2 | truthfulness |
| B2 | unashamedly |
| B2 | uncharacteristic |
| B2 | unclearly |
| B2 | undreamed |
| B2 | uneasily |
| B2 | unenthusiastic |
| B2 | unmistakably |
| B2 | unthinkably |
| B2 | untrimmed |
| B2 | unusualness |
| B2 | unworldly |
| B2 | upside down |
| B2 | virtual reality |
| B2 | wallboard |
| B2 | wearisome |
| B2 | well-organized |
| B2 | woodcarving |
| B2 | wordlessly |
| B2 | workbench |
| B2 | worktable |
| B2 | worn out |
| C1 | acoustically |
| C1 | adjoin |
| C1 | allege |
| C1 | amplification |
| C1 | animatedly |
| C1 | anticlimactic |
| C1 | appallingly |
| C1 | apt to |
| C1 | baldly |
| C1 | beguilingly |
| C1 | believably |
| C1 | benignly |
| C1 | blankness |
| C1 | blithely |
| C1 | bulk up |
| C1 | bureaucratically |
| C1 | ceaselessly |
| C1 | chaotically |
| C1 | characterization |
| C1 | chauffer |
| C1 | climactic |
| C1 | compliantly |
| C1 | conditionally |
| C1 | conscientiously |
| C1 | consultancy |
| C1 | contextual |
| C1 | contextually |
| C1 | cost-effective |
| C1 | credential |
| C1 | credibly |
| C1 | cynically |
| C1 | damply |
| C1 | daunt |
| C1 | demographically |
| C1 | demography |
| C1 | detrimentally |
| C1 | detritus |
| C1 | digitalization |
| C1 | digitalize |
| C1 | disillusionment |
| C1 | dismally |
| C1 | disquieting |
| C1 | dither |
| C1 | diverge |
| C1 | divergence |
| C1 | divergent |
| C1 | docilely |
| C1 | domestically |
| C1 | domesticate |
| C1 | domestication |
| C1 | dominantly |
| C1 | dramatist |
| C1 | dutifully |
| C1 | dynamically |
| C1 | eccentrically |
| C1 | eclectically |
| C1 | ecstatically |
| C1 | elaboration |
| C1 | elongate |
| C1 | engross |
| C1 | engrossing |
| C1 | envisage |
| C1 | exhilarate |
| C1 | exotically |
| C1 | explanatory |
| C1 | explosively |
| C1 | exuberantly |
| C1 | facilitation |
| C1 | fanatically |
| C1 | fiddly |
| C1 | fiendishly |
| C1 | folktale |
| C1 | fragmentation |
| C1 | frostily |
| C1 | gamely |
| C1 | geologically |
| C1 | glumly |
| C1 | gruesomely |
| C1 | gushingly |
| C1 | hypocritically |
| C1 | immortalize |
| C1 | impersonally |
| C1 | impish |
| C1 | impishly |
| C1 | incisor |
| C1 | inclusively |
| C1 | induct |
| C1 | inexcusably |
| C1 | insecurely |
| C1 | insensitively |
| C1 | insightfully |
| C1 | insubordinately |
| C1 | interjection |
| C1 | intuit |
| C1 | intuitively |
| C1 | irately |
| C1 | lackluster |
| C1 | lethargically |
| C1 | linearly |
| C1 | ludicrously |
| C1 | magnetically |
| C1 | mark-up |
| C1 | maternalistic |
| C1 | meaninglessly |
| C1 | minutiae |
| C1 | monotonously |
| C1 | naively |
| C1 | naturalness |
| C1 | neglectful |
| C1 | negligently |
| C1 | neutralization |
| C1 | obscurely |
| C1 | paternalistic |
| C1 | paywall |
| C1 | pendulous |
| C1 | perceptively |
| C1 | personalization |
| C1 | personalize |
| C1 | persuasively |
| C1 | pertain to |
| C1 | phenomenally |
| C1 | placidly |
| C1 | plausibility |
| C1 | plausibly |
| C1 | poetess |
| C1 | popularization |
| C1 | possessor |
| C1 | primitively |
| C1 | prohibitive |
| C1 | prohibitively |
| C1 | proliferate |
| C1 | prolifically |
| C1 | provocatively |
| C1 | quip |
| C1 | raunchily |
| C1 | readable |
| C1 | recessive |
| C1 | recognizably |
| C1 | refreshingly |
| C1 | refurbish |
| C1 | refurbishment |
| C1 | remorsefully |
| C1 | remorseless |
| C1 | remorselessly |
| C1 | repellant |
| C1 | repertory |
| C1 | robustly |
| C1 | rudiments |
| C1 | salivate |
| C1 | scornful |
| C1 | scornfully |
| C1 | scrutinize |
| C1 | sedately |
| C1 | sedentary |
| C1 | sentimentally |
| C1 | shortlist |
| C1 | slackly |
| C1 | smugly |
| C1 | socialization |
| C1 | somberly |
| C1 | specification |
| C1 | staccato |
| C1 | startlingly |
| C1 | stressfully |
| C1 | stuffily |
| C1 | stuffiness |
| C1 | stylistic |
| C1 | stylistically |
| C1 | succulently |
| C1 | superficially |
| C1 | sustainably |
| C1 | synthetically |
| C1 | tactfully |
| C1 | tastebud |
| C1 | tautly |
| C1 | tediously |
| C1 | tedium |
| C1 | temperamentally |
| C1 | transfix |
| C1 | turn to |
| C1 | unassisted |
| C1 | unconvincing |
| C1 | unconvincingly |
| C1 | unenviable |
| C1 | unenviably |
| C1 | uniformity |
| C1 | uninspiring |
| C1 | unmanageable |
| C1 | unmusical |
| C1 | unmusically |
| C1 | unreliably |
| C1 | unscathing |
| C1 | unsettle |
| C1 | unsustainably |
| C1 | untangled |
| C1 | unwaveringly |
| C1 | venerate |
| C1 | verandah |
| C1 | verve |
| C1 | victoriously |
| C1 | voraciously |
| C1 | washtub |
| C1 | wizened |
| C1 | wryly |
| C2 | abhorrently |
| C2 | accrue |
| C2 | acrobatically |
| C2 | ad lib |
| C2 | adhesion |
| C2 | ad-lib |
| C2 | adornment |
| C2 | adulterate |
| C2 | affectation |
| C2 | aghast |
| C2 | allegorical |
| C2 | all-encompassing |
| C2 | allude |
| C2 | allusion |
| C2 | amorphous |
| C2 | amorphously |
| C2 | anarchic |
| C2 | angsty |
| C2 | angularity |
| C2 | antediluvian |
| C2 | anthology |
| C2 | anthropologically |
| C2 | anticlimactically |
| C2 | antithesis |
| C2 | antithetical |
| C2 | arcanely |
| C2 | archetypal |
| C2 | archival |
| C2 | arduously |
| C2 | articulation |
| C2 | artifice |
| C2 | astringent |
| C2 | athleticism |
| C2 | attributive |
| C2 | austerely |
| C2 | automate |
| C2 | autonomously |
| C2 | axiom |
| C2 | axiomatic |
| C2 | belligerence |
| C2 | bereftly |
| C2 | besiege |
| C2 | blandishment |
| C2 | blubbery |
| C2 | blurb |
| C2 | bona fide |
| C2 | brandish |
| C2 | brevity |
| C2 | brouhaha |
| C2 | buffoonery |
| C2 | caffeinate |
| C2 | calamitous |
| C2 | calamitously |
| C2 | callously |
| C2 | calorific |
| C2 | capacious |
| C2 | carbonize |
| C2 | catastrophically |
| C2 | cay |
| C2 | choreographical |
| C2 | chronologically |
| C2 | chronology |
| C2 | circumnavigate |
| C2 | circumnavigation |
| C2 | cogent |
| C2 | cogently |
| C2 | colloquial |
| C2 | colloquially |
| C2 | colloquium |
| C2 | commensurate |
| C2 | commensurately |
| C2 | compellingly |
| C2 | computerize |
| C2 | conciliation |
| C2 | conciliatory |
| C2 | concurrence |
| C2 | confabulate |
| C2 | confabulation |
| C2 | confection |
| C2 | confrontationally |
| C2 | connotation |
| C2 | connote |
| C2 | consign |
| C2 | consternation |
| C2 | contemptuously |
| C2 | contractually |
| C2 | contrive |
| C2 | correlate |
| C2 | cosset |
| C2 | counterproductively |
| C2 | crony |
| C2 | crystallization |
| C2 | cultish |
| C2 | deaden |
| C2 | decentralize |
| C2 | declination |
| C2 | deficiently |
| C2 | demystification |
| C2 | demystify |
| C2 | denotation |
| C2 | denunciation |
| C2 | deprecate |
| C2 | deprecatingly |
| C2 | derision |
| C2 | derisive |
| C2 | derisively |
| C2 | detract |
| C2 | deviantly |
| C2 | disdainful |
| C2 | disparage |
| C2 | disparagement |
| C2 | disparagingly |
| C2 | dissemble |
| C2 | disseminate |
| C2 | dissemination |
| C2 | distillation |
| C2 | dole out |
| C2 | domesticity |
| C2 | drabness |
| C2 | dubiously |
| C2 | dwarfism |
| C2 | eccentricity |
| C2 | echolocate |
| C2 | echolocation |
| C2 | economize |
| C2 | ecotourism |
| C2 | edification |
| C2 | edify |
| C2 | egalitarian |
| C2 | eke out |
| C2 | elephantine |
| C2 | emolument |
| C2 | emulation |
| C2 | emulsification |
| C2 | emulsifier |
| C2 | emulsify |
| C2 | enabler |
| C2 | encompass |
| C2 | encumber |
| C2 | encumbrance |
| C2 | enduringly |
| C2 | engender |
| C2 | enthuse |
| C2 | ephemera |
| C2 | ephemerality |
| C2 | equable |
| C2 | etching |
| C2 | euphemistic |
| C2 | euphemistically |
| C2 | euphorically |
| C2 | evokingly |
| C2 | exaltedly |
| C2 | extant |
| C2 | fabulate |
| C2 | fabulation |
| C2 | farcical |
| C2 | flagging |
| C2 | flatout |
| C2 | flightiness |
| C2 | floe |
| C2 | fluctuate |
| C2 | forlornly |
| C2 | formidably |
| C2 | fractious |
| C2 | genomic |
| C2 | genomically |
| C2 | glitzy |
| C2 | glory in |
| C2 | gravitate |
| C2 | gravitationally |
| C2 | haphazardly |
| C2 | happenstance |
| C2 | haughtily |
| C2 | hauntingly |
| C2 | hermetic |
| C2 | histrionic |
| C2 | histrionically |
| C2 | hotelier |
| C2 | hypnotherapy |
| C2 | hypothesize |
| C2 | idiomatic |
| C2 | idiomatically |
| C2 | idiosyncrasy |
| C2 | idiosyncratic |
| C2 | ignominious |
| C2 | ignominiously |
| C2 | imperceptible |
| C2 | imperceptibly |
| C2 | impressionistic |
| C2 | impressionistically |
| C2 | improvisational |
| C2 | inartistic |
| C2 | inchoate |
| C2 | inchoately |
| C2 | incipient |
| C2 | incise |
| C2 | incongruity |
| C2 | incongruous |
| C2 | incongruously |
| C2 | indignantly |
| C2 | indiscrete |
| C2 | indolence |
| C2 | indolent |
| C2 | indolently |
| C2 | inducement |
| C2 | indulgently |
| C2 | inexorability |
| C2 | infallibility |
| C2 | infallibly |
| C2 | infernally |
| C2 | ingenuous |
| C2 | ingenuously |
| C2 | ingratiate |
| C2 | ingratiating |
| C2 | ingratiatingly |
| C2 | insular |
| C2 | interrogative |
| C2 | interrogatively |
| C2 | intersperse |
| C2 | interweave |
| C2 | intrinsically |
| C2 | irrelevancy |
| C2 | kinetically |
| C2 | lamentation |
| C2 | lassitude |
| C2 | laud |
| C2 | laudatory |
| C2 | leaven |
| C2 | leavening |
| C2 | locomotion |
| C2 | luridly |
| C2 | lyrically |
| C2 | lyricist |
| C2 | magnanimity |
| C2 | magnanimously |
| C2 | malleability |
| C2 | marketability |
| C2 | materialization |
| C2 | melodiously |
| C2 | menacingly |
| C2 | mesmeric |
| C2 | meteorology |
| C2 | methodological |
| C2 | methodologically |
| C2 | midwifery |
| C2 | mien |
| C2 | modernism |
| C2 | moribund |
| C2 | mottled |
| C2 | mull over |
| C2 | mundanity |
| C2 | munificence |
| C2 | muscle-bound |
| C2 | mutinous |
| C2 | mutinously |
| C2 | nascent |
| C2 | neophyte |
| C2 | nonchalantly |
| C2 | nostalgically |
| C2 | octogenarian |
| C2 | opacity |
| C2 | opulence |
| C2 | opulently |
| C2 | ordain |
| C2 | ostensible |
| C2 | paradoxically |
| C2 | paralyzingly |
| C2 | patchily |
| C2 | patronizingly |
| C2 | pervasiveness |
| C2 | perversity |
| C2 | philanthropically |
| C2 | physiologically |
| C2 | plutocrat |
| C2 | polysyllabic |
| C2 | ponderous |
| C2 | ponderously |
| C2 | porten |
| C2 | portraiture |
| C2 | posit |
| C2 | postural |
| C2 | precociously |
| C2 | preconception |
| C2 | predilection |
| C2 | preeminent |
| C2 | prescriptive |
| C2 | presentational |
| C2 | preservationist |
| C2 | pressurization |
| C2 | pressurize |
| C2 | presuppose |
| C2 | presupposition |
| C2 | prise |
| C2 | profitability |
| C2 | promotable |
| C2 | proportionally |
| C2 | proprietorial |
| C2 | proscribe |
| C2 | proscription |
| C2 | protrude |
| C2 | protrusion |
| C2 | prurience |
| C2 | prurient |
| C2 | punitively |
| C2 | qualitative |
| C2 | qualm |
| C2 | rapturous |
| C2 | rapturously |
| C2 | recumbent |
| C2 | recuperation |
| C2 | recuperative |
| C2 | redundantly |
| C2 | reissue |
| C2 | relegate |
| C2 | remittance |
| C2 | remonstrance |
| C2 | remonstrate |
| C2 | resoundingly |
| C2 | retrospection |
| C2 | revelatory |
| C2 | reverb |
| C2 | reverberate |
| C2 | reverberation |
| C2 | revile |
| C2 | rhetorically |
| C2 | romper |
| C2 | ruminant |
| C2 | ruminate |
| C2 | rumination |
| C2 | ruminative |
| C2 | salivary |
| C2 | secularly |
| C2 | selectivity |
| C2 | self-aggrandizement |
| C2 | shamble |
| C2 | side-step |
| C2 | skew |
| C2 | smattering |
| C2 | snippet |
| C2 | snobbery |
| C2 | soliloquize |
| C2 | solipsism |
| C2 | solitariness |
| C2 | spatially |
| C2 | spuriously |
| C2 | squirmy |
| C2 | stoicism |
| C2 | stringently |
| C2 | stultify |
| C2 | stultifyingly |
| C2 | subsist |
| C2 | subsistence |
| C2 | suffuse |
| C2 | sulphuric |
| C2 | summarily |
| C2 | superfluously |
| C2 | surreptitious |
| C2 | surreptitiously |
| C2 | syllabic |
| C2 | tacit |
| C2 | tacitly |
| C2 | taciturn |
| C2 | taciturnity |
| C2 | tantalize |
| C2 | tantalizingly |
| C2 | taste-maker |
| C2 | teem |
| C2 | telescopic |
| C2 | telescopically |
| C2 | tenaciously |
| C2 | tetchy |
| C2 | timidity |
| C2 | topographical |
| C2 | topographically |
| C2 | totemic |
| C2 | totter |
| C2 | tranquilize |
| C2 | treacherously |
| C2 | truism |
| C2 | undemonstrative |
| C2 | undemonstratively |
| C2 | undiminishing |
| C2 | unencumbered |
| C2 | unexceptional |
| C2 | unexceptionally |
| C2 | unexcused |
| C2 | unfeasible |
| C2 | unfeasibly |
| C2 | unharried |
| C2 | unmediated |
| C2 | unnerve |
| C2 | unnervingly |
| C2 | unobtrusive |
| C2 | unobtrusively |
| C2 | unobtrusiveness |
| C2 | unpromising |
| C2 | unsurpassed |
| C2 | unsuspected |
| C2 | utilitarian |
| C2 | utilization |
| C2 | vandalize |
| C2 | venomously |
| C2 | verisimilitude |
| C2 | vestigial |
| C2 | vestigially |
| C2 | vindicate |
| C2 | virtuosity |
| C2 | vis-a-vis |
| C2 | voracity |
| C2 | wistfully |
| C2 | wordage |
| C2 | wordsmith |
| C2 | wrack |

### Merged rows (1,156 words of 2,444 rows)

| Level | Word | Rows (level:line term) | Part of speech | Endings |
|---|---|---|---|---|
| A1 | about | A1:14 about, A1:15 about | adverb, preposition | — |
| A1 | above | B1:16 above, A1:17 above, A1:18 above | adjective, adverb, preposition | — |
| A1 | address | A1:95 address, B1:96 address | noun, verb | — |
| A1 | after | A2:149 after, B1:150 after, A1:151 after | adverb, conjunction, preposition | — |
| A1 | all | A2:198 all, A1:199 all, A1:200 all | adverb, determiner, pronoun | — |
| A1 | all right | A1:201 all right, A1:202 all right | adjective, adverb | — |
| A1 | alone | A2:210 alone, A1:211 alone | adjective, adverb | — |
| A1 | along | A1:212 along, A2:213 along | adverb, preposition | — |
| A1 | another | A1:289 another, A2:290 another | determiner, pronoun | — |
| A1 | answer | A1:291 answer, A1:292 answer | noun, verb | — |
| A1 | any | A1:309 any, A1:310 any | determiner, pronoun | — |
| A1 | arm | A1:365 arm, B1:366 arm | noun, verb | — |
| A1 | around | A2:371 around, A1:372 around | adverb, preposition | — |
| A1 | as | A2:391 as, A1:392 as | conjunction, preposition | — |
| A1 | back | A2:495 back, A1:496 back, A1:497 back, B1:498 back | adjective, adverb, noun, verb | — |
| A1 | bank | A1:536 bank, A2:537 bank | noun, verb | — |
| A1 | bar | A1:543 bar, B1:544 bar | noun, verb | — |
| A1 | bat | A1:574 bat, B1:575 bat | noun, verb | — |
| A1 | bear | A1:591 bear, A2:592 bear | noun, verb | — |
| A1 | before | A1:613 before, A2:614 before, A1:615 before | adverb, conjunction, preposition | — |
| A1 | behind | A1:623 behind, A1:624 behind, C1:698 behind | adverb, preposition | — |
| A1 | below | A1:634 below, A1:635 below | adverb, preposition | — |
| A1 | best | A1:651 best, A1:652 best | adjective, adverb | — |
| A1 | better | A1:657 better, A2:658 better | adjective, adverb | — |
| A1 | black | A1:694 black, A1:695 black | adjective, noun | — |
| A1 | block | A1:715 block, B1:716 block | noun, verb | — |
| A1 | blow | A2:727 blow, A1:728 blow | noun, verb | — |
| A1 | blue | A1:729 blue, A1:730 blue | adjective, noun | — |
| A1 | board | A1:735 board, B1:736 board | noun, verb | — |
| A1 | book | A1:758 book, B1:759 book | noun, verb | — |
| A1 | both | A1:783 both, A1:784 both, A1:785 both | adverb, determiner, pronoun | — |
| A1 | bottle | A1:790 bottle, B2:791 bottle | noun, verb | — |
| A1 | bowl | A1:799 bowl, B1:800 bowl | noun, verb | — |
| A1 | break | A2:824 break, A1:825 break | noun, verb | — |
| A1 | brown | A1:866 brown, A2:867 brown | adjective, noun | — |
| A1 | brush | A1:871 brush, A1:872 brush | noun, verb | — |
| A1 | but | A1:920 but, B1:921 but | conjunction, preposition | — |
| A1 | call | A1:947 call, A2:948 call | noun, verb | — |
| A1 | camp | A1:955 camp, A2:956 camp | noun, verb | — |
| A1 | can | A1:961 can, A2:962 can | modal auxiliary, noun | — |
| A1 | care | A1:996 care, B1:997 care | noun, verb | — |
| A1 | catch | A1:1030 catch, A1:1031 catch | noun, verb | — |
| A1 | change | A1:1083 change, A1:1084 change | noun, verb | — |
| A1 | check | A1:1107 check, A2:1108 check | noun, verb | — |
| A1 | circle | A1:1160 circle, B1:1161 circle | noun, verb | — |
| A1 | class | A1:1178 class, C1:107 class | noun, verb | — |
| A1 | clean | A1:1188 clean, A1:1189 clean | adjective, verb | — |
| A1 | climb | A1:1204 climb, A2:1205 climb | noun, verb | — |
| A1 | close | A1:1213 close, A1:1214 close | adjective, verb | — |
| A1 | coach | A1:1227 coach, B2:1228 coach | noun, verb | — |
| A1 | cold | A1:1252 cold, A1:1253 cold | adjective, noun | — |
| A1 | color | A1:1265 color, A1:1266 color | noun, verb | colour |
| A1 | contest | A1:1437 contest, C1:885 contest | noun, verb | — |
| A1 | cook | A1:1470 cook, A1:1471 cook | noun, verb | — |
| A1 | cool | A1:1475 cool, B2:1476 cool | adjective, verb | — |
| A1 | copy | A1:1484 copy, A2:1485 copy | noun, verb | — |
| A1 | correct | A1:1497 correct, B2:1498 correct | adjective, verb | — |
| A1 | cover | A1:1539 cover, A2:1540 cover | noun, verb | — |
| A1 | cream | A2:1556 cream, A1:1557 cream | adjective, noun | — |
| A1 | cry | A1:1601 cry, A2:1602 cry | noun, verb | — |
| A1 | cut | B1:1635 cut, A1:1636 cut | noun, verb | — |
| A1 | dance | A1:1663 dance, A1:1664 dance | noun, verb | — |
| A1 | date | A1:1680 date, B1:1681 date | noun, verb | — |
| A1 | dear | A1:1700 dear, B2:1701 dear | adjective, noun | — |
| A1 | design | A1:1808 design, B1:1809 design | noun, verb | — |
| A1 | dig | A1:1871 dig, B1:1872 dig | noun, verb | — |
| A1 | down | B2:2031 down, A1:2032 down, A2:2033 down | adjective, adverb, preposition | — |
| A1 | draw | A2:2054 draw, A1:2055 draw | noun, verb | — |
| A1 | dream | A1:2060 dream, A2:2061 dream | noun, verb | — |
| A1 | dress | A1:2063 dress, A2:2064 dress | noun, verb | — |
| A1 | drink | A1:2067 drink, A1:2068 drink | noun, verb | — |
| A1 | drive | A1:2070 drive, A2:2071 drive, C1:172 drive, C1:173 drive | noun, verb | — |
| A1 | drop | A2:2075 drop, A1:2076 drop | noun, verb | — |
| A1 | dry | A1:2084 dry, A2:2085 dry | adjective, verb | — |
| A1 | each | A1:2108 each, A1:2109 each | determiner, pronoun | — |
| A1 | early | A2:2117 early, A1:2118 early | adjective, adverb | — |
| A1 | either | A1:2171 either, A2:2172 either, B1:2173 either, B1:2174 either | adverb, conjunction, determiner, pronoun | — |
| A1 | email | A2:2204 email, A1:2205 email | verb, noun | e-mail, E-mail |
| A1 | end | A1:2236 end, A2:2237 end | noun, verb | — |
| A1 | engineer | A1:2256 engineer, C1:479 engineer | noun, verb | — |
| A1 | excuse | A1:2393 excuse, B1:2394 excuse | noun, verb | — |
| A1 | exercise | A2:2399 exercise, A1:2400 exercise | noun, verb | — |
| A1 | face | A1:2473 face, A2:2474 face | noun, verb | — |
| A1 | fair | A1:2489 fair, B1:2490 fair | adjective, noun | — |
| A1 | fast | A1:2530 fast, A1:2531 fast | adjective, adverb | — |
| A1 | fat | A1:2534 fat, B2:2535 fat | adjective, noun | — |
| A1 | favorite | A1:2544 favorite, A1:2545 favorite | adjective, noun | favourite |
| A1 | feed | A1:2560 feed, B1:2561 feed | noun, verb | — |
| A1 | feel | A2:2563 feel, A1:2564 feel | noun, verb | — |
| A1 | fight | A1:2588 fight, B1:2589 fight | noun, verb | — |
| A1 | file | A1:2595 file, B2:2596 file | noun, verb | — |
| A1 | fine | A1:2613 fine, B2:2614 fine, B1:2615 fine, B2:2616 fine | adjective, adverb, noun, verb | — |
| A1 | finish | A1:2620 finish, A1:2621 finish | noun, verb | — |
| A1 | fire | A1:2622 fire, B2:2623 fire | noun, verb | — |
| A1 | first | A1:2634 first, A1:2635 first | adjective, adverb | — |
| A1 | fish | A1:2644 fish, B1:2645 fish | noun, verb | — |
| A1 | flat | B1:2662 flat, B2:2663 flat, A1:2664 flat | adjective, adverb, noun | — |
| A1 | fly | A1:2696 fly, A1:2697 fly | noun, verb | — |
| A1 | focus | B2:2698 focus, A1:2699 focus | noun, verb | — |
| A1 | following | A1:2708 following, B2:2709 following | adjective, preposition | — |
| A1 | for | A2:2723 for, A1:2724 for | conjunction, preposition | — |
| A1 | form | A1:2742 form, B1:2743 form | noun, verb | — |
| A1 | free | A1:2777 free, A2:2778 free, B2:2779 free | adjective, adverb, verb | — |
| A1 | front | A1:2804 front, A2:2805 front | adjective, noun | — |
| A1 | fun | A1:2824 fun, A1:2825 fun | adjective, noun | — |
| A1 | future | B1:2848 future, A1:2849 future | adjective, noun | — |
| A1 | go | B1:2945 go, A1:2946 go | noun, verb | — |
| A1 | gold | A1:2953 gold, A2:2954 gold | adjective, noun | — |
| A1 | good | A1:2958 good, B2:2959 good | adjective, noun | — |
| A1 | grade | A1:2982 grade, B2:2983 grade | noun, verb | — |
| A1 | gray | A1:3018 gray, A1:3019 gray | adjective, noun | grey |
| A1 | green | A1:3024 green, A2:3025 green | adjective, noun | — |
| A1 | ground | A1:3041 ground, C1:560 ground | noun, verb | — |
| A1 | group | A1:3043 group, B1:3044 group | noun, verb | — |
| A1 | guess | B1:3056 guess, A1:3057 guess | noun, verb | — |
| A1 | half | B1:3087 half, A2:3088 half, A1:3089 half, A2:3090 half | adverb, determiner, noun, pronoun | — |
| A1 | hand | A1:3098 hand, A2:3099 hand | noun, verb | — |
| A1 | hard | A1:3123 hard, A1:3124 hard | adjective, adverb | — |
| A1 | head | A1:3158 head, A2:3159 head | noun, verb | — |
| A1 | help | A2:3195 help, A1:3196 help | noun, verb | — |
| A1 | her | A1:3201 her, A1:3202 her | determiner, pronoun | — |
| A1 | high | A1:3216 high, A2:3217 high | adjective, adverb | — |
| A1 | his | A1:3236 his, A1:3237 his | determiner, pronoun | — |
| A1 | hold | A1:3247 hold, A2:3248 hold | noun, verb | — |
| A1 | home | A2:3255 home, A1:3256 home | adverb, noun | — |
| A1 | hope | A1:3274 hope, B1:3275 hope | noun, verb | — |
| A1 | house | A1:3296 house, C1:77 house | noun, verb | — |
| A1 | hurry | A1:3332 hurry, A2:3333 hurry | noun, verb | — |
| A1 | hurt | B1:3334 hurt, A1:3335 hurt | adjective, verb | — |
| A1 | in | A2:3431 in, A1:3432 in | adverb, preposition | — |
| A1 | inside | B2:3536 inside, A2:3537 inside, B2:3538 inside, A1:3539 inside | adjective, adverb, noun, preposition | — |
| A1 | interview | A1:3600 interview, B1:3601 interview | noun, verb | — |
| A1 | it | A2:3656 IT, A1:3657 it | noun, pronoun | — |
| A1 | its | A1:3661 its, A1:3662 its | determiner, pronoun | — |
| A1 | judge | B1:3697 judge, A1:3698 judge | noun, verb | — |
| A1 | jump | B2:3705 jump, A1:3706 jump | noun, verb | — |
| A1 | key | A1:3725 key, A1:3726 key | adjective, noun | — |
| A1 | kick | A1:3729 kick, A1:3730 kick | noun, verb | — |
| A1 | kid | A1:3731 kid, B1:3732 kid | noun, verb | — |
| A1 | kind | A2:3739 kind, A1:3740 kind | adjective, noun | — |
| A1 | kiss | A1:3746 kiss, B1:3747 kiss | noun, verb | — |
| A1 | late | A1:3801 late, A1:3802 late | adjective, adverb | — |
| A1 | later | B2:3805 later, A1:3806 later | adjective, adverb | — |
| A1 | laugh | B1:3811 laugh, A1:3812 laugh | noun, verb | — |
| A1 | leave | B1:3852 leave, A1:3853 leave | noun, verb | — |
| A1 | left | A1:3857 left, A2:3858 left, A2:3859 left | adjective, adverb, noun | — |
| A1 | light | A1:3913 light, A1:3914 light, B1:3915 light | adjective, noun, verb | — |
| A1 | like | B1:3921 like, A1:3922 like, A1:3923 like | conjunction, preposition, verb | — |
| A1 | line | A1:3934 line, B2:3935 line | noun, verb | — |
| A1 | list | A1:3946 list, B2:3947 list | noun, verb | — |
| A1 | little | A1:3956 little, A1:3957 little, B1:3958 little, B1:3959 little | adjective, adverb, determiner, pronoun | — |
| A1 | live | B1:3960 live, A1:3961 live | adjective, verb | — |
| A1 | living | A1:3964 living, B2:3965 living | adjective, noun | — |
| A1 | long | A1:3984 long, A2:3985 long | adjective, adverb | — |
| A1 | look | A1:3988 look, A1:3989 look | noun, verb | — |
| A1 | lot | A1:3996 lot, A2:3997 lot, A1:3998 lot | adverb, noun, pronoun | — |
| A1 | love | A1:4005 love, A1:4006 love | noun, verb | — |
| A1 | mail | A1:4044 mail, B1:4045 mail | noun, verb | — |
| A1 | make | B2:4055 make, A1:4056 make | noun, verb | — |
| A1 | man | A1:4065 man, C1:494 man | noun, verb | — |
| A1 | many | A1:4080 many, A1:4081 many | determiner, pronoun | — |
| A1 | march | A1:4086 March, B1:4087 march, B1:4088 march | noun, verb | — |
| A1 | match | A1:4113 match, B1:4114 match | noun, verb | — |
| A1 | matter | A1:4121 matter, A2:4122 matter | noun, verb | — |
| A1 | may | A1:4128 may, A1:4129 May | modal auxiliary, noun | — |
| A1 | mean | A2:4134 mean, B2:4135 mean, A1:4136 mean | adjective, noun, verb | — |
| A1 | middle | A1:4208 middle, A2:4209 middle | adjective, noun | — |
| A1 | mind | A1:4225 mind, A2:4226 mind | noun, verb | — |
| A1 | mine | B2:4227 mine, A1:4228 mine | noun, pronoun | — |
| A1 | miss | A1:4250 Miss, A1:4251 miss | noun, verb | — |
| A1 | mobile | A2:4266 mobile, A1:4267 mobile | adjective, noun | — |
| A1 | more | B1:4313 more, A1:4314 more, A1:4315 more | adverb, determiner, pronoun | — |
| A1 | most | A2:4325 most, A1:4326 most, A2:4327 most | adverb, determiner, pronoun | — |
| A1 | move | A1:4352 move, A2:4353 move | noun, verb | — |
| A1 | much | A1:4362 much, A1:4363 much, A1:4364 much | adverb, determiner, pronoun | — |
| A1 | name | A1:4403 name, B1:4404 name | noun, verb | — |
| A1 | near | B1:4432 near, B1:4433 near, A1:4434 near | adjective, adverb, preposition | — |
| A1 | need | A1:4445 need, B2:4446 need, A2:4447 need | modal auxiliary, noun, verb | — |
| A1 | no | A1:4503 no, A1:4504 no | adverb, determiner | — |
| A1 | note | A1:4541 note, A1:4542 note | noun, verb | — |
| A1 | now | A1:4559 now, B2:4560 now | adverb, conjunction | — |
| A1 | nurse | A1:4569 nurse, B1:4570 nurse | noun, verb | — |
| A1 | off | A1:4611 off, A2:4612 off, B1:4613 off | adjective, adverb, preposition | — |
| A1 | OK | A1:4631 OK, A1:4632 OK | adjective, adverb | okay |
| A1 | on | A2:4642 on, A1:4643 on | adverb, preposition | — |
| A1 | once | A1:4644 once, B2:4645 once | adverb, conjunction | — |
| A1 | one | A1:4646 one, A1:4647 one, A2:4648 one | determiner, number, pronoun | — |
| A1 | only | A1:4653 only, A1:4654 only | adjective, adverb | — |
| A1 | open | A1:4657 open, A1:4658 open | adjective, verb | — |
| A1 | orange | A1:4684 orange, A1:4685 orange | adjective, noun | — |
| A1 | order | A1:4691 order, A2:4692 order | noun, verb | — |
| A1 | other | A1:4710 other, A2:4711 other | determiner, pronoun | — |
| A1 | outside | B2:4743 outside, A1:4744 outside, B2:4745 outside, A2:4746 outside | adjective, adverb, noun, preposition | — |
| A1 | over | A2:4755 over, A1:4756 over | adverb, preposition | — |
| A1 | own | A1:4791 own, A2:4792 own, B1:4793 own | adjective, pronoun, verb | — |
| A1 | paint | A1:4814 paint, A1:4815 paint | noun, verb | — |
| A1 | pardon | A1:4847 pardon, B1:4848 pardon | noun, verb | — |
| A1 | park | A1:4851 park, A2:4852 park | noun, verb | — |
| A1 | past | B1:4883 past, A1:4884 past, A1:4885 past | adjective, adverb, preposition | — |
| A1 | pay | A1:4908 pay, A1:4909 pay | noun, verb | — |
| A1 | phone | A1:4999 phone, A1:5000 phone | noun, verb | — |
| A1 | pick | B1:5015 pick, A1:5016 pick | noun, verb | — |
| A1 | picture | A1:5020 picture, B2:5021 picture | noun, verb | — |
| A1 | pink | A1:5037 pink, A2:5038 pink | adjective, noun | — |
| A1 | place | A1:5048 place, B1:5049 place | noun, verb | — |
| A1 | plan | A1:5052 plan, B1:5053 plan | noun, verb | — |
| A1 | plane | A1:5054 plane, C2:1622 plane | noun | — |
| A1 | play | A1:5063 play, A1:5064 play | noun, verb | — |
| A1 | please | A1:5073 please, B1:5074 please | adverb, verb | — |
| A1 | point | A1:5096 point, A2:5097 point | noun, verb | — |
| A1 | pop | A1:5129 pop, B2:5130 pop | noun, verb | — |
| A1 | post | A1:5153 post, A2:5154 post | noun, verb | — |
| A1 | practice | A1:5180 practice, A1:5181 practice | noun, verb | practise |
| A1 | present | B1:5222 present, A1:5223 present, B2:5224 present | adjective, noun, verb | — |
| A1 | pretty | A1:5240 pretty, A2:5241 pretty | adjective, adverb | — |
| A1 | price | A1:5248 price, B2:5249 price | noun, verb | — |
| A1 | program | A1:5301 program, B1:5302 program | noun, verb | programme |
| A1 | purple | A2:5390 purple, A1:5391 purple | adjective, noun | — |
| A1 | push | B1:5397 push, A1:5398 push | noun, verb | — |
| A1 | question | A1:5418 question, B2:5419 question | noun, verb | — |
| A1 | quiet | A1:5426 quiet, B2:5427 quiet | adjective, noun | — |
| A1 | rain | A1:5458 rain, A1:5459 rain | noun, verb | — |
| A1 | real | A1:5506 real, A1:5507 real | adjective, adverb | — |
| A1 | red | A1:5554 red, A2:5555 red | adjective, noun | — |
| A1 | result | A1:5721 result, B1:5722 result | noun, verb | — |
| A1 | review | A1:5748 review, B2:5749 review | noun, verb | — |
| A1 | rich | A1:5768 rich, C1:576 rich | adjective | — |
| A1 | ride | A1:5772 ride, A1:5773 ride | noun, verb | — |
| A1 | right | A1:5777 right, A1:5778 right, A2:5779 right | adjective, adverb, noun | — |
| A1 | ring | A2:5784 ring, A1:5785 ring | noun, verb | — |
| A1 | room | A1:5818 room, B1:5819 room | noun, verb | — |
| A1 | row | A1:5836 row, B2:5837 row | noun, verb | — |
| A1 | rule | A1:5851 rule, B2:5852 rule | noun, verb | — |
| A1 | run | A1:5855 run, A1:5856 run | noun, verb | — |
| A1 | same | A1:5896 same, A1:5897 same, A1:5898 same | adjective, adverb, pronoun | — |
| A1 | saw | A1:5919 saw, B2:5920 saw | noun, verb | — |
| A1 | say | B2:5921 say, A1:5922 say | noun, verb | — |
| A1 | second | A1:5989 second, B1:5990 second, A2:5991 second, A2:5992 second | adjective, adverb, noun, pronoun | — |
| A1 | sentence | A1:6039 sentence, B2:6040 sentence | noun, verb | — |
| A1 | set | A2:6058 set, A1:6059 set | noun, verb | — |
| A1 | shake | A1:6082 shake, B1:6083 shake | noun, verb | — |
| A1 | share | A2:6094 share, A1:6095 share | noun, verb | — |
| A1 | ship | A1:6116 ship, B1:6117 ship | noun, verb | — |
| A1 | shop | A1:6129 shop, B1:6130 shop | noun, verb | — |
| A1 | short | A1:6139 short, A1:6140 short, A2:6141 short | adjective, adverb, noun | shorts |
| A1 | show | A2:6151 show, A1:6152 show | noun, verb | — |
| A1 | shower | A1:6155 shower, B2:6156 shower | noun, verb | — |
| A1 | sign | A1:6172 sign, B1:6173 sign | noun, verb | — |
| A1 | sleep | B1:6254 sleep, A1:6255 sleep | noun, verb | — |
| A1 | slow | A1:6274 slow, B1:6275 slow, B1:6276 slow | adjective, adverb, verb | — |
| A1 | smell | A1:6281 smell, B1:6282 smell | noun, verb | — |
| A1 | smile | A1:6283 smile, B1:6284 smile | noun, verb | — |
| A1 | smoke | A1:6286 smoke, A2:6287 smoke | noun, verb | — |
| A1 | snow | A1:6303 snow, A2:6304 snow | noun, verb | — |
| A1 | so | A2:6310 so, A1:6311 so | adverb, conjunction | — |
| A1 | some | A1:6349 some, A1:6350 some | determiner, pronoun | — |
| A1 | spell | A1:6424 spell, A2:6425 spell | noun, verb | — |
| A1 | spot | A1:6457 spot, B2:6458 spot | noun, verb | — |
| A1 | stand | A1:6490 stand, A2:6491 stand | noun, verb | — |
| A1 | star | A1:6497 star, B1:6498 star | noun, verb | — |
| A1 | start | A1:6500 start, A1:6501 start | noun, verb | — |
| A1 | stay | B1:6516 stay, A1:6517 stay | noun, verb | — |
| A1 | step | A2:6529 step, A1:6530 step | noun, verb | — |
| A1 | still | A1:6541 still, A2:6542 still | adjective, adverb | — |
| A1 | stop | A1:6558 stop, A1:6559 stop | noun, verb | — |
| A1 | store | A1:6563 store, B2:6564 store | noun, verb | — |
| A1 | straight | A2:6570 straight, A1:6571 straight | adjective, adverb | — |
| A1 | study | A2:6620 study, A1:6621 study | noun, verb | — |
| A1 | sure | A1:6718 sure, A2:6719 sure | adjective, adverb | — |
| A1 | surf | A1:6721 surf, A2:6722 surf | noun, verb | — |
| A1 | surprise | A1:6729 surprise, B1:6730 surprise | noun, verb | — |
| A1 | sweet | A1:6759 sweet, A2:6760 sweet | adjective, noun | — |
| A1 | swim | A1:6764 swim, A1:6765 swim | noun, verb | — |
| A1 | take | B1:6801 take, A1:6802 take | noun, verb | — |
| A1 | talk | B1:6808 talk, A1:6809 talk | noun, verb | — |
| A1 | telephone | A1:6853 telephone, A2:6854 telephone | noun, verb | — |
| A1 | test | A1:6892 test, B2:6893 test | noun, verb | — |
| A1 | than | A1:6900 than, A1:6901 than | conjunction, preposition | — |
| A1 | that | B2:6905 that, A1:6906 that, A1:6907 that, A1:6908 that | adverb, conjunction, determiner, pronoun | — |
| A1 | these | A1:6926 these, A1:6927 these | determiner, pronoun | — |
| A1 | this | A1:6947 this, A1:6948 this | determiner, pronoun | — |
| A1 | those | A1:6951 those, A1:6952 those | determiner, pronoun | — |
| A1 | through | B1:6969 through, A1:6970 through | adverb, preposition | — |
| A1 | throw | A1:6972 throw, A2:6973 throw | noun, verb | — |
| A1 | tight | A1:6991 tight, B2:6992 tight | adjective, adverb | — |
| A1 | time | A1:7000 time, B2:7001 time | noun, verb | — |
| A1 | to | A1:7020 to, A1:7021 to | infinitive-to, preposition | — |
| A1 | today | A1:7024 today, A1:7025 today | adverb, noun | — |
| A1 | tomorrow | A1:7036 tomorrow, A1:7037 tomorrow | adverb, noun | — |
| A1 | tonight | A1:7041 tonight, A2:7042 tonight | adverb, noun | — |
| A1 | top | B1:7049 top, A1:7050 top | adjective, noun | — |
| A1 | touch | A1:7060 touch, B1:7061 touch | noun, verb | — |
| A1 | train | A1:7094 train, A2:7095 train | noun, verb | — |
| A1 | travel | A2:7126 travel, A1:7127 travel | noun, verb | — |
| A1 | trip | A1:7154 trip, B2:7155 trip | noun, verb | — |
| A1 | try | A1:7179 try, A2:7180 try | noun, verb | — |
| A1 | turn | A1:7197 turn, A1:7198 turn | noun, verb | — |
| A1 | type | A1:7212 type, B1:7213 type | noun, verb | — |
| A1 | underline | A1:7255 underline, B1:7256 underline | noun, verb | — |
| A1 | until | B1:7352 until, A1:7353 until | conjunction, preposition | — |
| A1 | up | A2:7365 up, A1:7366 up | adverb, preposition | — |
| A1 | use | A2:7394 use, A1:7395 use | noun, verb | — |
| A1 | very | B2:7444 very, A1:7445 very | adjective, adverb | — |
| A1 | visit | A1:7484 visit, A1:7485 visit | noun, verb | — |
| A1 | vote | A1:7502 vote, B1:7503 vote | noun, verb | — |
| A1 | wait | B2:7512 wait, A1:7513 wait | noun, verb | — |
| A1 | wake | A1:7516 wake, B1:7517 wake | noun, verb | — |
| A1 | walk | A1:7518 walk, A1:7519 walk | noun, verb | — |
| A1 | want | B2:7528 want, A1:7529 want | noun, verb | — |
| A1 | warm | A1:7533 warm, B1:7534 warm | adjective, verb | — |
| A1 | wash | A1:7544 wash, A1:7545 wash | noun, verb | — |
| A1 | watch | A1:7554 watch, A1:7555 watch | noun, verb | — |
| A1 | water | A1:7556 water, B2:7557 water | noun, verb | — |
| A1 | welcome | B1:7596 welcome, A1:7597 welcome, B2:7598 welcome, A1:7599 welcome | adjective, interjection, noun, verb | — |
| A1 | well | A1:7601 well, A1:7602 well | adjective, adverb | — |
| A1 | what | A1:7618 what, A1:7619 what | determiner, pronoun | — |
| A1 | when | A1:7625 when, A1:7626 when | adverb, conjunction | — |
| A1 | where | A1:7629 where, A1:7630 where | adverb, conjunction | — |
| A1 | which | A1:7634 which, A1:7635 which | determiner, pronoun | — |
| A1 | white | A1:7646 white, A1:7647 white | adjective, noun | — |
| A1 | whose | A1:7653 whose, A1:7654 whose | determiner, pronoun | — |
| A1 | will | A1:7668 will, B2:7669 will | modal auxiliary, noun | — |
| A1 | win | B2:7673 win, A1:7674 win | noun, verb | — |
| A1 | wind | A1:7675 wind, B2:7676 wind | noun, verb | — |
| A1 | wish | A1:7693 wish, A2:7694 wish | noun, verb | — |
| A1 | work | A1:7718 work, A1:7719 work | noun, verb | — |
| A1 | worry | A1:7738 worry, A2:7739 worry | noun, verb | — |
| A1 | wrong | A1:7766 wrong, A2:7767 wrong | adjective, adverb | — |
| A1 | yellow | A1:7779 yellow, A1:7780 yellow | adjective, noun | — |
| A1 | yet | A1:7783 yet, B1:7784 yet | adverb, conjunction | — |
| A2 | account | A2:51 account, B1:52 account | noun, verb | — |
| A2 | across | A2:72 across, A2:73 across | adverb, preposition | — |
| A2 | act | A2:74 act, B1:75 act | noun, verb | — |
| A2 | adult | A2:118 adult, A2:119 adult | adjective, noun | — |
| A2 | agency | A2:160 agency, C2:1865 agency | noun | — |
| A2 | alarm | A2:186 alarm, B1:187 alarm | noun, verb | — |
| A2 | alright | A2:219 alright, A2:220 alright | adjective, adverb | — |
| A2 | assistant | A2:412 assistant, B1:413 assistant | adjective, noun | — |
| A2 | attack | A2:438 attack, A2:439 attack | noun, verb | — |
| A2 | attempt | A2:443 attempt, B1:444 attempt | noun, verb | — |
| A2 | automatic | A2:469 automatic, C1:297 automatic | adjective, verb | — |
| A2 | automatically | A2:470 automatically, C1:298 automatically | adverb | — |
| A2 | average | A2:476 average, A2:477 average | adjective, noun | — |
| A2 | award | A2:481 award, B1:482 award | noun, verb | — |
| A2 | barbecue | A2:545 barbecue, B1:546 barbecue | noun, verb | — |
| A2 | bargain | A2:552 bargain, B2:553 bargain | noun, verb | — |
| A2 | base | A2:564 base, B1:565 base | noun, verb | — |
| A2 | battery | A2:581 battery, C1:604 battery | noun | — |
| A2 | bend | B2:638 bend, A2:639 bend | noun, verb | — |
| A2 | besides | A2:649 besides, B1:650 besides | adverb, preposition | — |
| A2 | bill | A2:670 bill, B1:671 bill | noun, verb | — |
| A2 | bite | A2:689 bite, B1:690 bite | noun, verb | — |
| A2 | blame | B1:698 blame, A2:699 blame | noun, verb | — |
| A2 | bloom | A2:724 bloom, C1:478 bloom | noun, verb | — |
| A2 | bother | B1:786 bother, A2:787 bother | noun, verb | — |
| A2 | brake | A2:813 brake, B2:814 brake | noun, verb | — |
| A2 | branch | A2:815 branch, B1:816 branch | noun, verb | — |
| A2 | budget | B2:877 budget, A2:878 budget | adjective, noun | — |
| A2 | burn | A2:904 burn, B1:905 burn | noun, verb | — |
| A2 | cause | B2:1039 cause, A2:1040 cause | noun, verb | — |
| A2 | challenge | A2:1075 challenge, B2:1076 challenge | noun, verb | — |
| A2 | chart | A2:1099 chart, C1:994 chart | noun, verb | — |
| A2 | chat | B1:1102 chat, A2:1103 chat | noun, verb | — |
| A2 | chemical | A2:1121 chemical, B1:1122 chemical | adjective, noun | — |
| A2 | claim | B1:1173 claim, A2:1174 claim | noun, verb | — |
| A2 | classic | A2:1179 classic, B2:1180 classic | adjective, noun | — |
| A2 | clear | A2:1191 clear, B1:1192 clear | adjective, verb | — |
| A2 | click | B1:1198 click, A2:1199 click | noun, verb | — |
| A2 | coast | A2:1233 coast, B1:1234 coast | noun, verb | — |
| A2 | comb | A2:1271 comb, B2:1272 comb | noun, verb | — |
| A2 | comic | A2:1282 comic, A2:1283 comic | adjective, noun | — |
| A2 | complete | A2:1326 complete, B1:1327 complete | adjective, verb | — |
| A2 | concern | A2:1359 concern, B2:1360 concern | noun, verb | — |
| A2 | condition | A2:1370 condition, C1:542 condition | noun, verb | — |
| A2 | contact | A2:1428 contact, A2:1429 contact | noun, verb | — |
| A2 | control | A2:1453 control, B1:1454 control | noun, verb | — |
| A2 | cost | A2:1509 cost, A2:1510 cost | noun, verb | — |
| A2 | count | B1:1521 count, A2:1522 count | noun, verb | — |
| A2 | cross | A2:1585 cross, A2:1586 cross | noun, verb | — |
| A2 | cruise | A2:1598 cruise, B2:1599 cruise | noun, verb | — |
| A2 | daily | A2:1652 daily, A2:1653 daily | adjective, adverb | — |
| A2 | deal | A2:1697 deal, B1:1698 deal | noun, verb | — |
| A2 | deep | B2:1736 deep, A2:1737 deep | adjective, adverb | — |
| A2 | delay | A2:1756 delay, B1:1757 delay | noun, verb | — |
| A2 | desert | A2:1806 desert, C1:502 desert | noun, verb | — |
| A2 | direct | A2:1892 direct, B1:1893 direct | adjective, verb | — |
| A2 | dislike | A2:1942 dislike, B1:1943 dislike | noun, verb | — |
| A2 | display | A2:1950 display, B1:1951 display | noun, verb | — |
| A2 | divide | B1:1985 divide, A2:1986 divide | noun, verb | — |
| A2 | double | A2:2023 double, B2:2024 double, B2:2025 double | adjective, noun, verb | — |
| A2 | doubt | A2:2027 doubt, B2:2028 doubt | noun, verb | — |
| A2 | download | B2:2035 download, A2:2036 download | noun, verb | — |
| A2 | downstairs | B1:2038 downstairs, A2:2039 downstairs | adjective, adverb | — |
| A2 | drill | A2:2066 drill, C1:964 drill, C1:965 drill | noun, verb | — |
| A2 | east | A2:2128 east, A2:2129 east, A2:2130 east | adjective, adverb, noun | — |
| A2 | enough | A2:2265 enough, A2:2266 enough, A2:2267 enough | adverb, determiner, pronoun | — |
| A2 | envy | A2:2293 envy, B2:2294 envy | noun, verb | — |
| A2 | escape | A2:2311 escape, B1:2312 escape | noun, verb | — |
| A2 | even | B1:2335 even, A2:2336 even | adjective, adverb | — |
| A2 | except | A2:2372 except, A2:2373 except | conjunction, preposition | — |
| A2 | exchange | A2:2379 exchange, B1:2380 exchange | noun, verb | — |
| A2 | experience | A2:2422 experience, B1:2423 experience | noun, verb | — |
| A2 | expert | B2:2427 expert, A2:2428 expert | adjective, noun | — |
| A2 | express | A2:2442 express, B1:2443 express | noun, verb | — |
| A2 | extra | A2:2455 extra, A2:2456 extra, B1:2457 extra | adjective, adverb, noun | — |
| A2 | fall | B1:2496 fall, A2:2497 fall | noun, verb | — |
| A2 | fancy | A2:2507 fancy, B1:2508 fancy, B1:2509 fancy | adjective, noun, verb | — |
| A2 | far | B2:2513 far, A2:2514 far | adjective, adverb | — |
| A2 | fear | A2:2548 fear, B2:2549 fear | noun, verb | — |
| A2 | feature | A2:2554 feature, B2:2555 feature | noun, verb | — |
| A2 | female | A2:2568 female, B2:2569 female | adjective, noun | — |
| A2 | few | A2:2578 few, B1:2579 few | determiner, pronoun | — |
| A2 | figure | A2:2593 figure, A2:2594 figure | noun, verb | — |
| A2 | film | A2:2600 film, B1:2601 film | noun, verb | — |
| A2 | final | A2:2604 final, A2:2605 final | adjective, noun | — |
| A2 | fit | A2:2648 fit, B2:2649 fit, B1:2650 fit, C1:170 fit | adjective, noun, verb | — |
| A2 | fix | A2:2653 fix, B1:2654 fix | noun, verb | — |
| A2 | float | A2:2678 float, B1:2679 float | noun, verb | — |
| A2 | flood | A2:2681 flood, B1:2682 flood | noun, verb | — |
| A2 | fool | A2:2715 fool, B1:2716 fool | noun, verb | — |
| A2 | force | A2:2727 force, B2:2728 force | noun, verb | — |
| A2 | frame | A2:2770 frame, B2:2771 frame | noun, verb | — |
| A2 | fry | A2:2813 fry, B1:2814 fry | noun, verb | — |
| A2 | function | B1:2826 function, A2:2827 function | noun, verb | — |
| A2 | further | A2:2843 further, B1:2844 further | adjective, adverb | — |
| A2 | graduate | B1:2986 graduate, A2:2987 graduate | noun, verb | — |
| A2 | guard | A2:3053 guard, B2:3054 guard | noun, verb | — |
| A2 | half-price | A2:3091 half-price, A2:3092 half-price | adjective, adverb | — |
| A2 | handle | A2:3107 handle, B1:3108 handle | noun, verb | — |
| A2 | harm | B2:3130 harm, A2:3131 harm | noun, verb | — |
| A2 | harvest | A2:3137 harvest, C1:985 harvest | noun, verb | — |
| A2 | hate | B1:3145 hate, A2:3146 hate | noun, verb | — |
| A2 | heat | A2:3180 heat, B1:3181 heat | noun, verb | — |
| A2 | hit | B1:3242 hit, A2:3243 hit | noun, verb | — |
| A2 | honor | A2:3267 honor, B2:3268 honor | noun, verb | honour |
| A2 | hug | B2:3305 hug, A2:3306 hug | noun, verb | — |
| A2 | human | A2:3309 human, B1:3310 human | adjective, noun | — |
| A2 | inch | A2:3439 inch, B2:3440 inch | noun, verb | — |
| A2 | increase | B1:3447 increase, A2:3448 increase | noun, verb | — |
| A2 | influence | A2:3495 influence, B2:3496 influence | noun, verb | — |
| A2 | interest | A2:3580 interest, B1:3581 interest | noun, verb | — |
| A2 | issue | A2:3654 issue, B2:3655 issue | noun, verb | — |
| A2 | jam | A2:3668 jam, B2:3669 jam | noun, verb | — |
| A2 | joke | A2:3690 joke, B1:3691 joke | noun, verb | — |
| A2 | kindly | A2:3741 kindly, B1:3742 kindly | adjective, adverb | — |
| A2 | knock | A2:3756 knock, B1:3757 knock | noun, verb | — |
| A2 | lack | A2:3768 lack, B2:3769 lack | noun, verb | — |
| A2 | land | B1:3777 land, A2:3778 land | noun, verb | — |
| A2 | landscape | A2:3782 landscape, C1:475 landscape | noun, verb | — |
| A2 | last | B1:3792 last, A2:3793 last, A2:3794 last, B1:3795 last | adverb, determiner, pronoun, verb | — |
| A2 | latter | B2:3808 latter, A2:3809 latter, A2:3810 latter | adjective, adverb, pronoun | — |
| A2 | lead | B1:3828 lead, A2:3829 lead, B1:3830 lead | adjective, noun, verb | — |
| A2 | least | B1:3848 least, A2:3849 least, B2:3850 least | adverb, determiner, pronoun | — |
| A2 | less | A2:3881 less, A2:3882 less, A2:3883 less | adverb, determiner, pronoun | — |
| A2 | level | B1:3890 level, A2:3891 level, B2:3892 level | adjective, noun, verb | — |
| A2 | lie | B1:3903 lie, A2:3904 lie | noun, verb | — |
| A2 | load | A2:3967 load, B2:3968 load | noun, verb | — |
| A2 | lock | A2:3975 lock, B1:3976 lock | noun, verb | — |
| A2 | low | A2:4010 low, A2:4011 low | adjective, adverb | — |
| A2 | magic | A2:4038 magic, A2:4039 magic | adjective, noun | — |
| A2 | major | A2:4052 major, B2:4053 major | adjective, noun | — |
| A2 | male | B1:4061 male, A2:4062 male | adjective, noun | — |
| A2 | mark | A2:4091 mark, A2:4092 mark | noun, verb | — |
| A2 | market | A2:4094 market, B1:4095 market | noun, verb | — |
| A2 | mention | A2:4174 mention, B1:4175 mention | noun, verb | — |
| A2 | mix | B2:4262 mix, A2:4263 mix | noun, verb | — |
| A2 | model | B1:4272 model, A2:4273 model, B1:4274 model | adjective, noun, verb | — |
| A2 | murder | A2:4374 murder, B1:4375 murder | noun, verb | — |
| A2 | musical | A2:4383 musical, B2:4384 musical | adjective, noun | — |
| A2 | nature | A2:4425 nature, C1:270 nature | noun | — |
| A2 | net | A2:4470 net, B1:4471 net | adjective, noun | — |
| A2 | next | A2:4486 next, A2:4487 next, B2:4488 next | adverb, determiner, pronoun | — |
| A2 | north | A2:4527 north, A2:4528 north, A2:4529 north | adjective, adverb, noun | — |
| A2 | notice | A2:4545 notice, B1:4546 notice | noun, verb | — |
| A2 | offer | A2:4618 offer, A2:4619 offer | noun, verb | — |
| A2 | official | A2:4623 official, B2:4624 official | adjective, noun | — |
| A2 | online | A2:4651 online, A2:4652 online | adjective, adverb | — |
| A2 | opposite | A2:4669 opposite, B1:4670 opposite, B1:4671 opposite, A2:4672 opposite | adjective, adverb, noun, preposition | — |
| A2 | original | A2:4703 original, B2:4704 original | adjective, noun | — |
| A2 | orphan | A2:4709 orphan, C1:722 orphan | noun, verb | — |
| A2 | overseas | B2:4772 overseas, A2:4773 overseas | adjective, adverb | — |
| A2 | pack | A2:4802 pack, A2:4803 pack | noun, verb | — |
| A2 | panic | A2:4830 panic, B2:4831 panic | noun, verb | — |
| A2 | part | A2:4856 part, B2:4857 part | noun, verb | — |
| A2 | pass | A2:4873 pass, A2:4874 pass | noun, verb | — |
| A2 | patient | B1:4892 patient, A2:4893 patient | adjective, noun | — |
| A2 | perfect | A2:4952 perfect, C1:748 perfect | adjective, verb | — |
| A2 | photograph | A2:5003 photograph, B2:5004 photograph | noun, verb | — |
| A2 | plant | A2:5057 plant, B1:5058 plant | noun, verb | — |
| A2 | plastic | A2:5059 plastic, B1:5060 plastic | adjective, noun | — |
| A2 | plenty | A2:5078 plenty, B1:5079 plenty | noun, pronoun | — |
| A2 | plus | B1:5087 plus, B2:5088 plus, A2:5089 plus | conjunction, noun, preposition | — |
| A2 | pretend | B2:5238 pretend, A2:5239 pretend | adjective, verb | — |
| A2 | principal | A2:5262 principal, B2:5263 principal | adjective, noun | — |
| A2 | print | B1:5265 print, A2:5266 print | noun, verb | — |
| A2 | professional | A2:5295 professional, B2:5296 professional | adjective, noun | — |
| A2 | promise | A2:5316 promise, B1:5317 promise | noun, verb | — |
| A2 | public | B1:5362 public, A2:5363 public | adjective, noun | — |
| A2 | quality | B1:5406 quality, A2:5407 quality | adjective, noun | — |
| A2 | quit | B2:5429 quit, A2:5430 quit | adjective, verb | — |
| A2 | range | A2:5470 range, B2:5471 range | noun, verb | — |
| A2 | rap | A2:5474 rap, B1:5475 rap | noun, verb | — |
| A2 | rate | A2:5485 rate, B2:5486 rate | noun, verb | — |
| A2 | reach | B1:5497 reach, A2:5498 reach | noun, verb | — |
| A2 | record | B1:5543 record, A2:5544 record | noun, verb | — |
| A2 | regret | B2:5594 regret, A2:5595 regret | noun, verb | — |
| A2 | release | A2:5620 release, B1:5621 release | noun, verb | — |
| A2 | rent | A2:5649 rent, A2:5650 rent | noun, verb | — |
| A2 | repair | A2:5654 repair, A2:5655 repair | noun, verb | — |
| A2 | reply | A2:5664 reply, B1:5665 reply | noun, verb | — |
| A2 | report | A2:5666 report, B1:5667 report | noun, verb | — |
| A2 | request | A2:5678 request, B1:5679 request | noun, verb | — |
| A2 | research | A2:5684 research, B2:5685 research | noun, verb | — |
| A2 | return | A2:5737 return, A2:5738 return | noun, verb | — |
| A2 | roast | B2:5801 roast, A2:5802 roast | adjective, verb | — |
| A2 | rock | A2:5807 rock, B2:5808 rock | noun, verb | — |
| A2 | roll | A2:5812 roll, B2:5813 roll | noun, verb | — |
| A2 | round | B1:5828 round, A2:5829 round, B1:5830 round, B2:5831 round, B2:5832 round | adjective, adverb, noun, preposition, verb | — |
| A2 | ruin | B1:5848 ruin, A2:5849 ruin | noun, verb | — |
| A2 | rush | A2:5862 rush, B1:5863 rush | noun, verb | — |
| A2 | schedule | A2:5939 schedule, B2:5940 schedule | noun, verb | — |
| A2 | scream | A2:5966 scream, B1:5967 scream | noun, verb | — |
| A2 | screen | A2:5968 screen, B2:5969 screen | noun, verb | — |
| A2 | screw | A2:5970 screw, B2:5971 screw | noun, verb | — |
| A2 | search | A2:5981 search, B1:5982 search | noun, verb | — |
| A2 | secret | B1:5999 secret, A2:6000 secret | adjective, noun | — |
| A2 | senior | A2:6032 senior, A2:6033 senior | adjective, noun | — |
| A2 | sense | A2:6035 sense, B2:6036 sense | noun, verb | — |
| A2 | separate | A2:6041 separate, B2:6042 separate | adjective, verb | — |
| A2 | several | A2:6068 several, A2:6069 several | determiner, pronoun | — |
| A2 | shadow | A2:6079 shadow, B1:6080 shadow | noun, verb | — |
| A2 | shape | A2:6092 shape, B1:6093 shape | noun, verb | — |
| A2 | shell | A2:6107 shell, B2:6108 shell | noun, verb | — |
| A2 | shock | A2:6122 shock, B2:6123 shock | noun, verb | — |
| A2 | shout | A2:6149 shout, B1:6150 shout | noun, verb | — |
| A2 | shut | B1:6161 shut, A2:6162 shut | adjective, verb | — |
| A2 | silver | A2:6186 silver, A2:6187 silver | adjective, noun | — |
| A2 | since | B2:6198 since, B1:6199 since, A2:6200 since | adverb, conjunction, preposition | — |
| A2 | single | A2:6206 single, B1:6207 single | adjective, noun | — |
| A2 | singular | A2:6208 singular, A2:6209 singular | adjective, noun | — |
| A2 | sink | A2:6210 sink, B1:6211 sink | noun, verb | — |
| A2 | skate | A2:6223 skate, B1:6224 skate | noun, verb | — |
| A2 | ski | A2:6231 ski, B1:6232 ski | noun, verb | — |
| A2 | slice | A2:6259 slice, B2:6260 slice | noun, verb | — |
| A2 | slide | A2:6261 slide, B2:6262 slide | noun, verb | — |
| A2 | sound | B2:6375 sound, A2:6376 sound, A2:6377 sound | adjective, noun, verb | — |
| A2 | south | A2:6382 south, A2:6383 south, A2:6384 south | adjective, adverb, noun | — |
| A2 | speed | A2:6421 speed, B1:6422 speed | noun, verb | — |
| A2 | splash | B2:6440 splash, A2:6441 splash | noun, verb | — |
| A2 | split | A2:6443 split, B1:6444 split, B2:6445 split | adjective, noun, verb | — |
| A2 | spread | A2:6461 spread, B2:6462 spread | noun, verb | — |
| A2 | square | A2:6469 square, A2:6470 square | adjective, noun | — |
| A2 | stamp | A2:6488 stamp, B2:6489 stamp | noun, verb | — |
| A2 | state | B2:6506 state, A2:6507 state, B2:6508 state | adjective, noun, verb | — |
| A2 | strike | A2:6600 strike, B1:6601 strike | noun, verb | — |
| A2 | stuff | A2:6622 stuff, B2:6623 stuff | noun, verb | — |
| A2 | succeed | A2:6651 succeed, C2:1239 succeed | verb | — |
| A2 | such | A2:6656 such, A2:6657 such | determiner, pronoun | — |
| A2 | suit | A2:6671 suit, A2:6672 suit | noun, verb | — |
| A2 | support | A2:6711 support, B1:6712 support | noun, verb | — |
| A2 | sweat | B1:6754 sweat, A2:6755 sweat | noun, verb | — |
| A2 | tap | A2:6816 tap, B2:6817 tap | noun, verb | — |
| A2 | tape | A2:6818 tape, B1:6819 tape | noun, verb | — |
| A2 | tear | A2:6838 tear, B1:6839 tear | noun, verb | — |
| A2 | terrorist | A2:6890 terrorist, B1:6891 terrorist | adjective, noun | — |
| A2 | text | A2:6896 text, A2:6897 text | noun, verb | — |
| A2 | though | B2:6953 though, A2:6954 though | adverb, conjunction | — |
| A2 | tidy | A2:6986 tidy, A2:6987 tidy | adjective, verb | — |
| A2 | tie | A2:6988 tie, B1:6989 tie | noun, verb | — |
| A2 | till | B1:6998 till, A2:6999 till, C1:938 till | conjunction, preposition, noun | — |
| A2 | tip | A2:7010 tip, B2:7011 tip | noun, verb | — |
| A2 | tone | A2:7039 tone, C1:545 tone | noun, verb | — |
| A2 | tour | A2:7063 tour, B1:7064 tour | noun, verb | — |
| A2 | track | A2:7077 track, B2:7078 track | noun, verb | — |
| A2 | trade | A2:7080 trade, B2:7081 trade | noun, verb | — |
| A2 | trick | A2:7148 trick, B2:7149 trick | noun, verb | — |
| A2 | trouble | A2:7163 trouble, B1:7164 trouble | noun, verb | — |
| A2 | trust | B2:7172 trust, A2:7173 trust | noun, verb | — |
| A2 | tune | A2:7192 tune, C1:383 tune | noun, verb | — |
| A2 | underwater | A2:7266 underwater, B2:7267 underwater | adjective, adverb | — |
| A2 | uniform | A2:7300 uniform, A2:7301 uniform | adjective, noun | — |
| A2 | unlike | A2:7320 unlike, B2:7321 unlike | adjective, preposition | — |
| A2 | upset | A2:7378 upset, B2:7379 upset | adjective, verb | — |
| A2 | upstairs | B1:7382 upstairs, A2:7383 upstairs, B1:7384 upstairs | adjective, adverb, noun | — |
| A2 | value | A2:7418 value, B2:7419 value | noun, verb | — |
| A2 | view | A2:7459 view, B1:7460 view | noun, verb | — |
| A2 | voice | A2:7495 voice, C1:528 voice | noun, verb | — |
| A2 | wave | A2:7560 wave, B1:7561 wave | noun, verb | — |
| A2 | weekly | A2:7590 weekly, A2:7591 weekly | adjective, adverb | — |
| A2 | west | A2:7610 west, A2:7611 west, A2:7612 west | adjective, adverb, noun | — |
| A2 | whatever | A2:7620 whatever, B1:7621 whatever | determiner, pronoun | — |
| A2 | while | A2:7638 while, B1:7639 while | conjunction, noun | — |
| A2 | whole | A2:7650 whole, B1:7651 whole | adjective, noun | — |
| A2 | wide | A2:7656 wide, A2:7657 wide | adjective, adverb | — |
| A2 | wonder | B1:7708 wonder, A2:7709 wonder | noun, verb | — |
| A2 | worldwide | B2:7732 worldwide, A2:7733 worldwide | adjective, adverb | — |
| A2 | worse | A2:7741 worse, A2:7742 worse, B2:7743 worse | adjective, adverb, noun | — |
| A2 | worst | A2:7746 worst, B2:7747 worst, B1:7748 worst | adjective, adverb, noun | — |
| B1 | aboard | B1:10 aboard, C1:963 aboard | adverb, preposition | — |
| B1 | absolute | B1:24 absolute, C1:354 absolute | adjective, noun | — |
| B1 | abundance | B1:29 abundance, C2:1430 abundance | noun | — |
| B1 | abundant | B1:30 abundant, C2:1428 abundant | adjective | — |
| B1 | access | B1:38 access, B2:39 access | noun, verb | — |
| B1 | ache | B1:61 ache, B2:62 ache | noun, verb | — |
| B1 | advance | B2:120 advance, B1:121 advance | noun, verb | — |
| B1 | aid | B1:173 aid, B1:174 aid | noun, verb | — |
| B1 | aim | B1:175 aim, B2:176 aim | noun, verb | — |
| B1 | alcoholic | B1:191 alcoholic, B2:192 alcoholic | adjective, noun | — |
| B1 | alike | B1:195 alike, B1:196 alike | adjective, adverb | — |
| B1 | alternative | B1:225 alternative, B1:226 alternative | adjective, noun | — |
| B1 | angle | B1:270 angle, C1:398 angle | noun, verb | — |
| B1 | antique | B2:301 antique, B1:302 antique | adjective, noun | — |
| B1 | appeal | B1:326 appeal, B2:327 appeal | noun, verb | — |
| B1 | approach | B1:342 approach, B2:343 approach | noun, verb | — |
| B1 | arrest | B1:376 arrest, B1:377 arrest | noun, verb | — |
| B1 | balance | B1:518 balance, B2:519 balance | noun, verb | — |
| B1 | bald | B1:522 bald, C1:324 bald | adjective, verb | — |
| B1 | bang | B1:534 bang, B1:535 bang | noun, verb | — |
| B1 | bare | B1:549 bare, B2:550 bare | adjective, verb | — |
| B1 | bark | B1:554 bark, B2:555 bark | noun, verb | — |
| B1 | beat | B2:596 beat, B1:597 beat | noun, verb | — |
| B1 | benefit | B1:642 benefit, B2:643 benefit | noun, verb | — |
| B1 | blend | B2:707 blend, B1:708 blend | noun, verb | — |
| B1 | blush | B1:733 blush, B2:734 blush | noun, verb | — |
| B1 | boast | B1:738 boast, C1:331 boast | verb, noun | — |
| B1 | bold | B1:744 bold, B2:745 bold | adjective, noun | — |
| B1 | bomb | B1:749 bomb, B1:750 bomb | noun, verb | — |
| B1 | bounce | B2:793 bounce, B1:794 bounce | noun, verb | — |
| B1 | bow | B1:797 bow, B2:798 bow | noun, verb | — |
| B1 | breed | B2:836 breed, B1:837 breed | noun, verb | — |
| B1 | brief | B1:845 brief, C1:59 brief, C2:1142 brief | adjective, verb, noun | — |
| B1 | broadcast | B1:854 broadcast, B2:855 broadcast | noun, verb | — |
| B1 | burden | B1:894 burden, B2:895 burden | noun, verb | — |
| B1 | burst | B1:907 burst, C1:362 burst | verb, noun | — |
| B1 | butcher | B1:922 butcher, B2:923 butcher | noun, verb | — |
| B1 | calf | B1:946 calf, C1:315 calf | noun | — |
| B1 | capture | B1:984 capture, B1:985 capture | noun, verb | — |
| B1 | characteristic | B2:1090 characteristic, B1:1091 characteristic | adjective, noun | — |
| B1 | charge | B1:1093 charge, B1:1094 charge | noun, verb | — |
| B1 | chase | B1:1100 chase, B2:1101 chase | noun, verb | — |
| B1 | check-in | B1:1109 check-in, B1:1110 check-in | noun | check-in counter / check-in desk |
| B1 | chief | B1:1136 chief, B2:1137 chief | adjective, noun | — |
| B1 | chronological | B1:1154 chronological, C2:1490 chronological | adjective | — |
| B1 | collapse | B1:1254 collapse, B2:1255 collapse | noun, verb | — |
| B1 | comment | B1:1288 comment, B2:1289 comment | noun, verb | — |
| B1 | commercial | B1:1291 commercial, B2:1292 commercial | adjective, noun | — |
| B1 | compromise | B1:1345 compromise, B2:1346 compromise | noun, verb | — |
| B1 | conduct | B1:1371 conduct, B2:1372 conduct | noun, verb | — |
| B1 | content | B2:1435 content, B1:1436 content | adjective, noun | — |
| B1 | cough | B2:1516 cough, B1:1517 cough | noun, verb | — |
| B1 | counter | B2:1523 counter, B1:1524 counter | noun, verb | — |
| B1 | craft | B1:1549 craft, C1:120 craft | noun, verb | — |
| B1 | crash | B1:1551 crash, B1:1552 crash | noun, verb | — |
| B1 | criminal | B2:1573 criminal, B1:1574 criminal | adjective, noun | — |
| B1 | cure | B1:1615 cure, B2:1616 cure | noun, verb | — |
| B1 | curriculum | B1:1625 curriculum, C2:1419 curriculum | noun | — |
| B1 | cycle | B1:1645 cycle, B1:1646 cycle | noun, verb | — |
| B1 | damage | B1:1656 damage, B1:1657 damage | noun, verb | — |
| B1 | decline | B1:1722 decline, B2:1723 decline | noun, verb | — |
| B1 | decrease | B1:1728 decrease, B1:1729 decrease | noun, verb | — |
| B1 | defeat | B2:1740 defeat, B1:1741 defeat | noun, verb | — |
| B1 | delight | B1:1766 delight, B2:1767 delight | noun, verb | — |
| B1 | demand | B1:1772 demand, B1:1773 demand | noun, verb | — |
| B1 | dependent | B1:1792 dependent, C1:122 dependent | adjective, noun | — |
| B1 | deposit | B1:1793 deposit, B2:1794 deposit | noun, verb | — |
| B1 | designer | B2:1810 designer, B1:1811 designer | adjective, noun | — |
| B1 | desire | B1:1813 desire, B2:1814 desire | noun, verb | — |
| B1 | dial | B1:1852 dial, B1:1853 dial | noun, verb | — |
| B1 | diligence | B1:1879 diligence, C2:1759 diligence | noun | — |
| B1 | diligent | B1:1880 diligent, C2:1758 diligent | adjective | — |
| B1 | dive | B1:1979 dive, B1:1980 dive, C2:1360 dive | noun, verb | — |
| B1 | dozen | B1:2044 dozen, B1:2045 dozen | determiner, noun | — |
| B1 | dump | B1:2092 dump, B1:2093 dump | noun, verb | — |
| B1 | ecstasy | B1:2147 ecstasy, C1:266 ecstasy | noun | — |
| B1 | encounter | B1:2230 encounter, B2:2231 encounter | noun, verb | — |
| B1 | equal | B1:2296 equal, B2:2297 equal, B2:2298 equal | adjective, noun, verb | — |
| B1 | estimate | B2:2322 estimate, B1:2323 estimate | noun, verb | — |
| B1 | exact | B1:2356 exact, C2:1227 exact | adjective, verb | — |
| B1 | exit | B1:2411 exit, B1:2412 exit | noun, verb | — |
| B1 | experiment | B1:2425 experiment, B2:2426 experiment | noun, verb | — |
| B1 | faint | B1:2487 faint, B2:2488 faint | adjective, verb | — |
| B1 | fax | B1:2546 fax, B1:2547 fax | noun, verb | — |
| B1 | fellow | B2:2566 fellow, B1:2567 fellow | adjective, noun | — |
| B1 | finance | B2:2607 finance, B1:2608 finance | noun, verb | — |
| B1 | firm | B1:2630 firm, B1:2631 firm, C1:592 firm | adjective, noun, verb | — |
| B1 | flash | B1:2659 flash, B2:2660 flash, B2:2661 flash | adjective, noun, verb | — |
| B1 | flow | B1:2685 flow, B1:2686 flow | noun, verb | — |
| B1 | fold | B1:2702 fold, B1:2703 fold | noun, verb | — |
| B1 | format | B1:2746 format, B1:2747 format | noun, verb | — |
| B1 | frost | B1:2807 frost, C1:491 frost | noun, verb | — |
| B1 | full-time | B1:2820 full-time, B1:2821 full-time | adjective, adverb | — |
| B1 | fund | B1:2830 fund, B1:2831 fund | noun, verb | — |
| B1 | gain | B1:2851 gain, B1:2852 gain | noun, verb | — |
| B1 | general | B1:2880 general, B1:2881 general | adjective, noun | — |
| B1 | glance | B1:2924 glance, B1:2925 glance | noun, verb | — |
| B1 | glint | B1:2933 glint, C2:1847 glint, C2:1848 glint | noun, verb | — |
| B1 | gossip | B1:2971 gossip, B2:2972 gossip | noun, verb | — |
| B1 | grant | B1:3003 grant, B1:3004 grant | noun, verb | — |
| B1 | grill | B1:3031 grill, B1:3032 grill | noun, verb | — |
| B1 | guarantee | B1:3051 guarantee, B2:3052 guarantee | noun, verb | — |
| B1 | guide | B1:3060 guide, B1:3061 guide | noun, verb | — |
| B1 | hammer | B1:3096 hammer, B2:3097 hammer | noun, verb | — |
| B1 | hang | B2:3115 hang, B1:3116 hang | noun, verb | — |
| B1 | hanging | B1:3117 hanging, C1:85 hanging, C1:86 hanging | adjective, noun | — |
| B1 | harbor | B1:3122 harbor, C1:600 harbor | noun, verb | harbour |
| B1 | haunt | B1:3148 haunt, B2:3149 haunt | noun, verb | — |
| B1 | haven | B1:3153 haven, C2:1501 haven | noun | — |
| B1 | hazard | B1:3155 hazard, C2:1875 hazard | noun, verb | — |
| B1 | highlight | B2:3219 highlight, B1:3220 highlight | noun, verb | — |
| B1 | hunt | B1:3327 hunt, B1:3328 hunt | noun, verb | — |
| B1 | individual | B1:3469 individual, B2:3470 individual | adjective, noun | — |
| B1 | initial | B2:3510 initial, B1:3511 initial | adjective, noun | — |
| B1 | institute | B1:3556 institute, C1:395 institute | noun, verb | — |
| B1 | iron | B1:3636 iron, B1:3637 iron | noun, verb | — |
| B1 | jog | B2:3684 jog, B1:3685 jog, C1:431 jog | noun, verb | — |
| B1 | joint | B1:3688 joint, B2:3689 joint | adjective, noun | — |
| B1 | launch | B1:3814 launch, C1:718 launch, C1:927 launch | verb, noun | — |
| B1 | lean | B1:3839 lean, B2:3840 lean | adjective, verb | — |
| B1 | leap | B2:3841 leap, B1:3842 leap | noun, verb | — |
| B1 | lift | B1:3911 lift, B1:3912 lift | noun, verb | — |
| B1 | limit | B1:3929 limit, B1:3930 limit | noun, verb | — |
| B1 | link | B1:3940 link, B1:3941 link | noun, verb | — |
| B1 | liquid | B1:3944 liquid, B1:3945 liquid | adjective, noun | — |
| B1 | lodge | B1:3977 lodge, C1:909 lodge | noun, verb | — |
| B1 | loud | B1:4000 loud, B1:4001 loud | adjective, adverb | — |
| B1 | luxury | B2:4026 luxury, B1:4027 luxury | adjective, noun | — |
| B1 | mass | B1:4104 mass, B2:4105 mass | adjective, noun | — |
| B1 | maximum | B1:4126 maximum, B1:4127 maximum | adjective, noun | — |
| B1 | measure | B1:4141 measure, B1:4142 measure | noun, verb | — |
| B1 | medium | B1:4158 medium, B1:4159 medium | adjective, noun | — |
| B1 | mere | B1:4181 mere, C2:1384 mere | adjective | — |
| B1 | mess | B1:4186 mess, B2:4187 mess | noun, verb | — |
| B1 | minimum | B1:4233 minimum, B1:4234 minimum | adjective, noun | — |
| B1 | monitor | B1:4295 monitor, B1:4296 monitor | noun, verb | — |
| B1 | monthly | B1:4301 monthly, B1:4302 monthly | adjective, adverb | — |
| B1 | moral | B2:4309 moral, B1:4310 moral | adjective, noun | — |
| B1 | mount | B1:4344 mount, B2:4345 mount | noun, verb | — |
| B1 | nearby | B1:4435 nearby, B1:4436 nearby | adjective, adverb | — |
| B1 | nod | B1:4510 nod, B2:4511 nod | noun, verb | — |
| B1 | northeast | B1:4530 northeast, B1:4531 northeast | adjective, noun | — |
| B1 | northwest | B1:4535 northwest, B1:4536 northwest | adjective, noun | — |
| B1 | notorious | B1:4550 notorious, C2:1341 notorious | adjective | — |
| B1 | object | B1:4583 object, B2:4584 object | noun, verb | — |
| B1 | objective | B2:4586 objective, B1:4587 objective | adjective, noun | — |
| B1 | occasion | B1:4599 occasion, B1:4600 occasion | noun, verb | — |
| B1 | oral | B2:4682 oral, B1:4683 oral | adjective, noun | — |
| B1 | outline | B2:4733 outline, B1:4734 outline | noun, verb | — |
| B1 | overnight | B1:4770 overnight, B1:4771 overnight | adjective, adverb | — |
| B1 | pace | B1:4800 pace, C1:249 pace | noun, verb | — |
| B1 | paddle | B1:4809 paddle, C1:439 paddle | noun, verb | — |
| B1 | paralyze | B1:4843 paralyze, C2:1393 paralyze | verb | paralyse |
| B1 | part-time | B1:4870 part-time, B1:4871 part-time | adjective, adverb | — |
| B1 | pause | B1:4901 pause, B1:4902 pause | noun, verb | — |
| B1 | phantom | B1:4990 phantom, C2:1779 phantom | adjective, noun | — |
| B1 | pin | B2:5033 pin, B1:5034 pin | noun, verb | — |
| B1 | plug | B1:5082 plug, B2:5083 plug | noun, verb | — |
| B1 | poison | B1:5100 poison, B2:5101 poison | noun, verb | — |
| B1 | potential | B2:5164 potential, B1:5165 potential | adjective, noun | — |
| B1 | pound | B1:5168 pound, B2:5169 pound | noun, verb | — |
| B1 | powder | B1:5172 powder, B2:5173 powder | noun, verb | — |
| B1 | praise | B1:5182 praise, B2:5183 praise | noun, verb | — |
| B1 | press | B1:5232 press, B1:5233 press | noun, verb | — |
| B1 | process | B1:5285 process, B2:5286 process | noun, verb | — |
| B1 | progress | B1:5305 progress, B2:5306 progress | noun, verb | — |
| B1 | protest | B1:5345 protest, B2:5346 protest | noun, verb | — |
| B1 | pupil | B1:5384 pupil, C1:190 pupil | noun | — |
| B1 | puzzle | B1:5400 puzzle, C1:127 puzzle | noun, verb | — |
| B1 | queue | B1:5422 queue, B2:5423 queue | noun, verb | — |
| B1 | race | B1:5438 race, B1:5439 race | noun, verb | — |
| B1 | recall | B1:5523 recall, C1:512 recall | verb, noun | — |
| B1 | recite | B1:5532 recite, C1:265 recite | verb | — |
| B1 | refuse | B1:5579 refuse, B1:5580 refuse | noun, verb | — |
| B1 | regard | B2:5583 regard, B1:5584 regard | noun, verb | — |
| B1 | register | B1:5591 register, B1:5592 register | noun, verb | — |
| B1 | relative | B1:5611 relative, B1:5612 relative | adjective, noun | — |
| B1 | remark | B2:5636 remark, B1:5637 remark | noun, verb | — |
| B1 | rescue | B1:5682 rescue, B1:5683 rescue | noun, verb | — |
| B1 | reserve | B1:5689 reserve, B1:5690 reserve | noun, verb | — |
| B1 | resident | B1:5692 resident, B2:5693 resident | adjective, noun | — |
| B1 | resort | B1:5702 resort, C1:458 resort, C1:459 resort | noun, verb | — |
| B1 | respect | B1:5704 respect, B1:5705 respect | noun, verb | — |
| B1 | rest | B1:5715 rest, B1:5716 rest | noun, verb | — |
| B1 | retrospect | B1:5736 retrospect, C2:1436 retrospect | noun | — |
| B1 | reward | B1:5758 reward, B2:5759 reward | noun, verb | — |
| B1 | riddle | B2:5770 riddle, B1:5771 riddle | noun, verb | — |
| B1 | rise | B1:5788 rise, B1:5789 rise | noun, verb | — |
| B1 | risk | B1:5790 risk, B2:5791 risk | noun, verb | — |
| B1 | safeguard | B1:5874 safeguard, B2:5875 safeguard | noun, verb | — |
| B1 | scan | B1:5924 scan, B2:5925 scan | noun, verb | — |
| B1 | score | B1:5961 score, B1:5962 score | noun, verb | — |
| B1 | scratch | B1:5964 scratch, B2:5965 scratch | noun, verb | — |
| B1 | second-hand | B1:5996 second-hand, B1:5997 second-hand | adjective, adverb | — |
| B1 | secure | B1:6005 secure, C2:1335 secure | adjective, verb | — |
| B1 | select | B1:6015 select, B2:6016 select | adjective, verb | — |
| B1 | service | B1:6055 service, B1:6056 service | noun, verb | — |
| B1 | sharp | B1:6096 sharp, B2:6097 sharp | adjective, adverb | — |
| B1 | shift | B2:6112 shift, B1:6113 shift | noun, verb | — |
| B1 | sigh | B1:6168 sigh, B2:6169 sigh | noun, verb | — |
| B1 | signal | B1:6174 signal, C1:751 signal | noun, verb | — |
| B1 | slight | B2:6263 slight, B1:6264 slight | adjective, noun | — |
| B1 | slip | B1:6267 slip, B1:6268 slip | noun, verb | — |
| B1 | sneeze | B1:6298 sneeze, B2:6299 sneeze | noun, verb | — |
| B1 | soil | B2:6336 soil, B1:6337 soil | noun, verb | — |
| B1 | sort | B1:6372 sort, B2:6373 sort | noun, verb | — |
| B1 | southeast | B1:6385 southeast, B1:6386 southeast | adjective, noun | — |
| B1 | southwest | B1:6389 southwest, B1:6390 southwest | adjective, noun | — |
| B1 | sponsor | B1:6450 sponsor, B2:6451 sponsor | noun, verb | — |
| B1 | standard | B2:6492 standard, B1:6493 standard | adjective, noun | — |
| B1 | stick | B2:6536 stick, B1:6537 stick | noun, verb | — |
| B1 | strain | B1:6574 strain, B2:6575 strain | noun, verb | — |
| B1 | stream | B1:6586 stream, B1:6587 stream | noun, verb | — |
| B1 | stress | B1:6591 stress, B2:6592 stress | noun, verb | — |
| B1 | strip | B1:6604 strip, B2:6605 strip | noun, verb | — |
| B1 | struggle | B1:6613 struggle, B2:6614 struggle | noun, verb | — |
| B1 | substitute | B1:6644 substitute, B2:6645 substitute | noun, verb | — |
| B1 | supply | B1:6709 supply, B2:6710 supply | noun, verb | — |
| B1 | suspect | B1:6743 suspect, B2:6744 suspect | noun, verb | — |
| B1 | switch | B1:6773 switch, B1:6774 switch | noun, verb | — |
| B1 | talkative | B1:6810 talkative, C1:243 talkative | adjective | — |
| B1 | taste | B1:6822 taste, B1:6823 taste | noun, verb | — |
| B1 | tease | B1:6840 tease, B2:6841 tease | noun, verb | — |
| B1 | temper | B1:6859 temper, C2:2092 temper | noun, verb | — |
| B1 | tense | B1:6874 tense, B1:6875 tense | adjective, noun | — |
| B1 | thirst | B2:6942 thirst, B1:6943 thirst | noun, verb | — |
| B1 | tick | B1:6981 tick, B1:6982 tick | noun, verb | — |
| B1 | total | B1:7057 total, B1:7058 total | adjective, noun | — |
| B1 | trace | B1:7075 trace, B2:7076 trace | noun, verb | — |
| B1 | trail | B1:7091 trail, B2:7092 trail | noun, verb | — |
| B1 | transfer | B2:7105 transfer, B1:7106 transfer | noun, verb | — |
| B1 | transport | B1:7121 transport, B2:7122 transport | noun, verb | — |
| B1 | treat | B1:7134 treat, B2:7135 treat | noun, verb | — |
| B1 | twist | B1:7208 twist, B1:7209 twist | noun, verb | — |
| B1 | underneath | B2:7257 underneath, B1:7258 underneath | adverb, preposition | — |
| B1 | update | B2:7368 update, B1:7369 update | noun, verb | — |
| B1 | urge | B1:7388 urge, B2:7389 urge | noun, verb | — |
| B1 | vegetarian | B1:7431 vegetarian, B1:7432 vegetarian | adjective, noun | — |
| B1 | volunteer | B2:7499 volunteer, B1:7500 volunteer | noun, verb | — |
| B1 | waste | B1:7550 waste, B1:7551 waste, B1:7552 waste | adjective, noun, verb | — |
| B1 | wax | B1:7562 wax, B1:7563 wax, C2:1616 wax | noun, verb | — |
| B1 | whenever | B1:7627 whenever, B1:7628 whenever | adverb, conjunction | — |
| B1 | whichever | B1:7636 whichever, B2:7637 whichever | determiner, pronoun | — |
| B1 | whisper | B1:7642 whisper, B2:7643 whisper | noun, verb | — |
| B1 | whistle | B1:7644 whistle, B2:7645 whistle | noun, verb | — |
| B1 | wing | B1:7684 wing, C1:10 wing | noun | — |
| B1 | wire | B1:7689 wire, B2:7690 wire | noun, verb | — |
| B1 | wither | B1:7699 wither, C2:2014 wither | verb | — |
| B1 | witness | B2:7702 witness, B1:7703 witness | noun, verb | — |
| B1 | wound | B1:7754 wound, B2:7755 wound | noun, verb | — |
| B1 | wrap | B1:7756 wrap, B1:7757 wrap | noun, verb | — |
| B1 | yell | B1:7777 yell, B2:7778 yell | noun, verb | — |
| B2 | abolish | B2:11 abolish, C2:1392 abolish | verb | — |
| B2 | accessibility | B2:40 accessibility, C2:1878 accessibility | noun | — |
| B2 | adorn | B2:117 adorn, C2:1278 adorn | verb | — |
| B2 | adverse | B2:130 adverse, C2:1330 adverse | adjective | — |
| B2 | adversely | B2:131 adversely, C2:1331 adversely | adverb | — |
| B2 | agonize | B2:166 agonize, C1:262 agonize | verb | agonise |
| B2 | allegation | B2:203 allegation, C1:531 allegation | noun | — |
| B2 | ally | B2:208 ally, C2:1176 ally | noun, verb | — |
| B2 | anchor | B2:262 anchor, C1:625 anchor | noun, verb | — |
| B2 | articulate | B2:385 articulate, C2:1249 articulate | verb, adjective | — |
| B2 | attainment | B2:442 attainment, C2:1664 attainment | noun | — |
| B2 | attribute | B2:455 attribute, B2:456 attribute | noun, verb | — |
| B2 | audit | B2:461 audit, C2:1401 audit, C2:1402 audit | noun, verb | — |
| B2 | awe | B2:486 awe, C1:244 awe | noun, verb | — |
| B2 | ban | B2:529 ban, B2:530 ban | noun, verb | — |
| B2 | barometer | B2:559 barometer, C2:1714 barometer | noun | — |
| B2 | blast | B2:702 blast, B2:703 blast | noun, verb | — |
| B2 | blaze | B2:704 blaze, B2:705 blaze | noun, verb | — |
| B2 | bloody | B2:722 bloody, B2:723 bloody | adjective, adverb | — |
| B2 | bolt | B2:747 bolt, B2:748 bolt | noun, verb | — |
| B2 | bookmark | B2:764 bookmark, B2:765 bookmark | noun, verb | — |
| B2 | boost | B2:770 boost, B2:771 boost | noun, verb | — |
| B2 | buzz | B2:929 buzz, B2:930 buzz | noun, verb | — |
| B2 | campaign | B2:957 campaign, C1:843 campaign | noun, verb | — |
| B2 | cascade | B2:1015 cascade, C2:1993 cascade, C2:1994 cascade | noun, verb | — |
| B2 | cast | B2:1020 cast, B2:1021 cast, C1:64 cast, C1:65 cast, C1:66 cast | noun, verb | — |
| B2 | catastrophic | B2:1029 catastrophic, C2:1528 catastrophic | adjective | — |
| B2 | circuit | B2:1162 circuit, C2:1214 circuit | noun | — |
| B2 | commission | B2:1293 commission, C1:463 commission, C1:464 commission, C2:1530 commission, C2:1531 commission | noun, verb | — |
| B2 | complexity | B2:1332 complexity, C1:6 complexity | noun | — |
| B2 | conceivable | B2:1353 conceivable, C1:35 conceivable | adjective | — |
| B2 | conceive | B2:1354 conceive, C1:34 conceive | verb | — |
| B2 | concrete | B2:1367 concrete, B2:1368 concrete | adjective, noun | — |
| B2 | considering | B2:1410 considering, B2:1411 considering | conjunction, preposition | — |
| B2 | contract | B2:1445 contract, C1:483 contract, C1:484 contract | noun, verb | — |
| B2 | converse | B2:1463 converse, C2:1807 converse, C2:1808 converse | noun, adjective | — |
| B2 | crack | B2:1547 crack, B2:1548 crack | noun, verb | — |
| B2 | crystallize | B2:1603 crystallize, C2:1432 crystallize | verb | crystallise |
| B2 | damn | B2:1659 damn, B2:1660 damn, B2:1661 damn | adjective, adverb, interjection | — |
| B2 | darling | B2:1674 darling, B2:1675 darling | adjective, noun | — |
| B2 | dash | B2:1676 dash, B2:1677 dash | noun, verb | — |
| B2 | debit | B2:1705 debit, B2:1706 debit | noun, verb | — |
| B2 | deficit | B2:1746 deficit, C2:1357 deficit | noun | — |
| B2 | deliberate | B2:1760 deliberate, C2:1138 deliberate | adjective, verb | — |
| B2 | disguise | B2:1933 disguise, B2:1934 disguise | noun, verb | — |
| B2 | dispensable | B2:1948 dispensable, C1:356 dispensable | adjective | — |
| B2 | divorce | B2:1991 divorce, B2:1992 divorce | noun, verb | — |
| B2 | drain | B2:2048 drain, B2:2049 drain | noun, verb | — |
| B2 | dwarf | B2:2104 dwarf, C2:2020 dwarf | noun, verb | — |
| B2 | ease | B2:2125 ease, B2:2126 ease | noun, verb | — |
| B2 | ecstatic | B2:2148 ecstatic, C1:267 ecstatic | adjective | — |
| B2 | edit | B2:2150 edit, B2:2151 edit | noun, verb | — |
| B2 | evil | B2:2352 evil, B2:2353 evil | adjective, noun | — |
| B2 | executive | B2:2397 executive, B2:2398 executive | adjective, noun | — |
| B2 | exhaust | B2:2401 exhaust, C1:299 exhaust | noun, verb | — |
| B2 | exotic | B2:2413 exotic, C1:570 exotic | adjective | — |
| B2 | expedition | B2:2419 expedition, C1:448 expedition | noun | — |
| B2 | exploit | B2:2432 exploit, C1:164 exploit | verb | — |
| B2 | explosive | B2:2437 explosive, B2:2438 explosive | adjective, noun | — |
| B2 | export | B2:2439 export, B2:2440 export | noun, verb | — |
| B2 | extract | B2:2458 extract, B2:2459 extract | noun, verb | — |
| B2 | familiarize | B2:2503 familiarize, C2:1302 familiarize | verb | familiarise |
| B2 | figurative | B2:2592 figurative, C2:1645 figurative | adjective | — |
| B2 | formidable | B2:2751 formidable, C2:2003 formidable | adjective | — |
| B2 | grip | B2:3036 grip, B2:3037 grip | noun, verb | — |
| B2 | grown-up | B2:3048 grown-up, B2:3049 grown-up | adjective, noun | — |
| B2 | heap | B2:3170 heap, B2:3171 heap | noun, verb | — |
| B2 | hijack | B2:3224 hijack, B2:3225 hijack | noun, verb | — |
| B2 | hook | B2:3271 hook, B2:3272 hook | noun, verb | — |
| B2 | hover | B2:3302 hover, C2:2046 hover | verb | — |
| B2 | humble | B2:3316 humble, C1:54 humble, C1:55 humble | adjective, verb | — |
| B2 | idle | B2:3364 idle, C2:1279 idle | adjective, verb | — |
| B2 | imperative | B2:3399 imperative, C1:774 imperative, C1:775 imperative | noun, adjective | — |
| B2 | implement | B2:3401 implement, B2:3402 implement | noun, verb | — |
| B2 | indispensable | B2:3468 indispensable, C1:358 indispensable | adjective | — |
| B2 | indulge | B2:3473 indulge, C2:1199 indulge | verb | — |
| B2 | inert | B2:3479 inert, C2:1557 inert | adjective | — |
| B2 | innovation | B2:3525 innovation, C1:390 innovation | noun | — |
| B2 | innovative | B2:3526 innovative, C1:391 innovative | adjective | — |
| B2 | insult | B2:3563 insult, B2:3564 insult | noun, verb | — |
| B2 | intellectual | B2:3567 intellectual, B2:3568 intellectual | adjective, noun | — |
| B2 | lap | B2:3786 lap, C1:109 lap | noun | — |
| B2 | lark | B2:3790 lark, C2:1565 lark, C2:1566 lark | noun | — |
| B2 | leak | B2:3837 leak, B2:3838 leak | noun, verb | — |
| B2 | manual | B2:4074 manual, B2:4075 manual | adjective, noun | — |
| B2 | manufacture | B2:4076 manufacture, B2:4077 manufacture | noun, verb | — |
| B2 | merger | B2:4184 merger, C2:2051 merger | noun | — |
| B2 | mold | B2:4285 mold, C2:1390 mold | noun, verb | mould |
| B2 | mumble | B2:4372 mumble, B2:4373 mumble | noun, verb | — |
| B2 | mutter | B2:4391 mutter, B2:4392 mutter | noun, verb | — |
| B2 | nationwide | B2:4419 nationwide, B2:4420 nationwide | adjective, adverb | — |
| B2 | neither | B2:4459 neither, B2:4460 neither, B2:4461 neither, B2:4462 neither | adverb, conjunction, determiner, pronoun | — |
| B2 | outpatient | B2:4738 outpatient, C2:1123 outpatient | noun | — |
| B2 | overall | B2:4757 overall, B2:4758 overall | adjective, adverb | — |
| B2 | overtime | B2:4779 overtime, B2:4780 overtime | adverb, noun | — |
| B2 | paralysis | B2:4842 paralysis, C2:1394 paralysis | noun | — |
| B2 | pedestrian | B2:4925 pedestrian, C2:1671 pedestrian | noun, adjective | — |
| B2 | peel | B2:4927 peel, B2:4928 peel | noun, verb | — |
| B2 | personification | B2:4974 personification, C1:740 personification | noun | — |
| B2 | phase | B2:4993 phase, C2:1339 phase | noun | — |
| B2 | pitch | B2:5044 pitch, B2:5045 pitch | noun, verb | — |
| B2 | plague | B2:5050 plague, C1:721 plague | noun, verb | — |
| B2 | pluck | B2:5081 pluck, C2:1270 pluck | verb, noun | — |
| B2 | plum | B2:5084 plum, C2:1340 plum | noun, adjective | — |
| B2 | pose | B2:5141 pose, C1:426 pose | noun, verb | — |
| B2 | preoccupy | B2:5213 preoccupy, C2:1399 preoccupy | verb | — |
| B2 | project | B2:5310 project, B2:5311 project | noun, verb | — |
| B2 | prompt | B2:5320 prompt, B2:5321 prompt, B2:5322 prompt | adjective, noun, verb | — |
| B2 | punch | B2:5377 punch, B2:5378 punch | noun, verb | — |
| B2 | punctual | B2:5379 punctual, C2:1416 punctual | adjective | — |
| B2 | punctuality | B2:5380 punctuality, C2:1417 punctuality | noun | — |
| B2 | purchase | B2:5386 purchase, B2:5387 purchase | noun, verb | — |
| B2 | quarrel | B2:5411 quarrel, B2:5412 quarrel | noun, verb | — |
| B2 | query | B2:5417 query, C1:486 query | noun, verb | — |
| B2 | quote | B2:5435 quote, B2:5436 quote | noun, verb | — |
| B2 | rally | B2:5467 rally, C1:42 rally | noun, verb | — |
| B2 | rape | B2:5476 rape, B2:5477 rape | noun, verb | — |
| B2 | rebel | B2:5519 rebel, B2:5520 rebel | noun, verb | — |
| B2 | recollection | B2:5538 recollection, C1:513 recollection | noun | — |
| B2 | redundant | B2:5559 redundant, C2:1730 redundant | adjective | — |
| B2 | refresh | B2:5572 refresh, C1:685 refresh | noun, verb | — |
| B2 | retreat | B2:5733 retreat, B2:5734 retreat | noun, verb | — |
| B2 | scramble | B2:5963 scramble, C1:338 scramble | verb, noun | — |
| B2 | shed | B2:6102 shed, C1:344 shed | noun, verb | — |
| B2 | shrink | B2:6158 shrink, B2:6159 shrink | noun, verb | — |
| B2 | sketch | B2:6230 sketch, C1:639 sketch | verb, noun | — |
| B2 | skim | B2:6238 skim, C2:1688 skim | verb | — |
| B2 | slap | B2:6248 slap, B2:6249 slap | noun, verb | — |
| B2 | snore | B2:6301 snore, B2:6302 snore | noun, verb | — |
| B2 | soak | B2:6312 soak, B2:6313 soak | noun, verb | — |
| B2 | soliloquy | B2:6342 soliloquy, C2:1590 soliloquy | noun | — |
| B2 | solo | B2:6343 solo, B2:6344 solo, B2:6345 solo | adjective, adverb, noun | — |
| B2 | spare | B2:6399 spare, B2:6400 spare | adjective, verb | — |
| B2 | splatter | B2:6442 splatter, C1:296 splatter | noun, verb | — |
| B2 | spray | B2:6459 spray, B2:6460 spray | noun, verb | — |
| B2 | squash | B2:6471 squash, B2:6472 squash | noun, verb | — |
| B2 | stagger | B2:6481 stagger, C1:587 stagger | noun, verb | — |
| B2 | stain | B2:6482 stain, B2:6483 stain | noun, verb | — |
| B2 | stock | B2:6550 stock, C1:73 stock | noun, verb | — |
| B2 | strait | B2:6576 strait, C2:1723 strait | noun | — |
| B2 | stroke | B2:6608 stroke, B2:6609 stroke | noun, verb | — |
| B2 | surge | B2:6725 surge, C2:2110 surge, C2:2111 surge | noun, verb | — |
| B2 | swing | B2:6771 swing, B2:6772 swing | noun, verb | — |
| B2 | tabloid | B2:6794 tabloid, B2:6795 tabloid | adjective, noun | — |
| B2 | tactile | B2:6798 tactile, C2:1445 tactile | adjective | — |
| B2 | tomb | B2:7035 tomb, C1:87 tomb | noun | — |
| B2 | tread | B2:7132 tread, C1:529 tread | verb, noun | — |
| B2 | underground | B2:7253 underground, B2:7254 underground | adjective, adverb | — |
| B2 | understanding | B2:7263 understanding, B2:7264 understanding | adjective, noun | — |
| B2 | upgrade | B2:7370 upgrade, B2:7371 upgrade | noun, verb | — |
| B2 | upright | B2:7376 upright, B2:7377 upright | adjective, adverb | — |
| B2 | upside down | B2:7380 upside down, B2:7381 upside down | adjective, adverb | — |
| B2 | usher | B2:7401 usher, C1:515 usher | verb, noun | — |
| B2 | utility | B2:7404 utility, C2:1164 utility | noun | — |
| B2 | utilize | B2:7405 utilize, C2:1163 utilize | verb | utilise |
| B2 | utter | B2:7406 utter, C2:1184 utter, C2:1185 utter | verb, adjective | — |
| B2 | venture | B2:7435 venture, C2:1855 venture | noun | — |
| B2 | verse | B2:7440 verse, B2:7441 verse | noun, verb | — |
| B2 | vocalist | B2:7494 vocalist, C2:1469 vocalist | noun | — |
| B2 | withdrawal | B2:7698 withdrawal, C1:192 withdrawal | noun | — |
| B2 | yawn | B2:7772 yawn, B2:7773 yawn | noun, verb | — |
| C1 | advantageous | C1:181 advantageous, C2:1987 advantageous | adjective | — |
| C1 | align | C1:211 align, C1:546 align | verb | — |
| C1 | alignment | C1:212 alignment, C1:547 alignment | noun | — |
| C1 | amateur | C1:991 amateur, C1:992 amateur | noun, adjective | — |
| C1 | apprentice | C1:742 apprentice, C1:743 apprentice, C2:1125 apprentice | noun, verb | — |
| C1 | batter | C1:603 batter, C1:605 batter, C1:606 batter | verb, noun | — |
| C1 | battered | C1:611 battered, C1:612 battered | adjective | — |
| C1 | blister | C1:103 blister, C1:104 blister | noun, verb | — |
| C1 | bribe | C1:532 bribe, C1:533 bribe | verb, noun | — |
| C1 | buffer | C1:862 buffer, C1:863 buffer | verb, noun | — |
| C1 | charter | C1:941 charter, C1:942 charter | verb, noun | — |
| C1 | chauffer | C1:471 chauffer, C1:472 chauffer | noun, verb | — |
| C1 | chill | C1:488 chill, C1:489 chill | verb, noun | — |
| C1 | clutch | C1:585 clutch, C1:586 clutch | verb, noun | — |
| C1 | clutter | C1:907 clutter, C1:908 clutter | noun, verb | — |
| C1 | compel | C1:32 compel, C1:218 compel | verb | — |
| C1 | con | C1:125 con, C1:126 con | verb, noun | — |
| C1 | contextual | C1:1002 contextual, C2:1316 contextual | adjective | — |
| C1 | contextually | C1:1003 contextually, C2:1317 contextually | adverb | — |
| C1 | continuity | C1:95 continuity, C1:699 continuity | noun | — |
| C1 | convict | C1:794 convict, C1:795 convict | verb, noun | — |
| C1 | daunt | C1:832 daunt, C2:1209 daunt | verb | — |
| C1 | daunting | C1:833 daunting, C2:1210 daunting | adjective | — |
| C1 | daydream | C1:202 daydream, C1:203 daydream | noun, verb | — |
| C1 | debut | C1:1010 debut, C1:1011 debut | noun, verb | — |
| C1 | demographic | C1:918 demographic, C1:919 demographic | adjective, noun | — |
| C1 | deprivation | C1:1018 deprivation, C2:1297 deprivation | noun | — |
| C1 | dismay | C1:238 dismay, C1:239 dismay | verb, noun | — |
| C1 | durable | C1:846 durable, C1:847 durable | adjective, noun | — |
| C1 | eccentric | C1:26 eccentric, C1:730 eccentric, C1:731 eccentric | adjective, noun | — |
| C1 | eclectic | C1:596 eclectic, C1:597 eclectic | adjective, noun | — |
| C1 | elaborate | C1:147 elaborate, C1:148 elaborate | adjective, verb | — |
| C1 | elastic | C1:1066 elastic, C1:1067 elastic | noun, adjective | — |
| C1 | envisage | C1:858 envisage, C2:1114 envisage, C2:1315 envisage | verb | — |
| C1 | exhibitionist | C1:51 exhibitionist, C2:1962 exhibitionist | noun | — |
| C1 | facial | C1:552 facial, C1:553 facial | adjective, noun | — |
| C1 | fanatic | C1:825 fanatic, C1:826 fanatic | noun, adjective | — |
| C1 | fiddle | C1:817 fiddle, C1:818 fiddle | verb, noun | — |
| C1 | flourish | C1:623 flourish, C1:624 flourish | noun, verb | — |
| C1 | gape | C1:508 gape, C1:509 gape | verb | — |
| C1 | gourmet | C1:574 gourmet, C1:575 gourmet | adjective, noun | — |
| C1 | graft | C1:973 graft, C2:1275 graft | verb, noun | — |
| C1 | grounds | C1:557 grounds, C1:558 grounds, C1:559 grounds | noun | — |
| C1 | grumble | C1:275 grumble, C2:1676 grumble | verb | — |
| C1 | gush | C1:632 gush, C1:634 gush | verb, noun | — |
| C1 | hack | C1:1042 hack, C1:1043 hack | verb, noun | — |
| C1 | honk | C1:386 honk, C1:387 honk | verb, noun | — |
| C1 | hostile | C1:236 hostile, C1:401 hostile | adjective | — |
| C1 | hostility | C1:237 hostility, C1:402 hostility | noun | — |
| C1 | implicate | C1:119 implicate, C1:169 implicate | verb | — |
| C1 | inexhaustible | C1:313 inexhaustible, C1:1090 inexhaustible | adjective | — |
| C1 | insightful | C1:186 insightful, C1:258 insightful | adjective | — |
| C1 | jersey | C1:659 jersey, C1:660 jersey | noun, adjective | — |
| C1 | juvenile | C1:18 juvenile, C1:19 juvenile | noun, adjective | — |
| C1 | lapse | C1:332 lapse, C1:651 lapse, C1:652 lapse | noun, verb | — |
| C1 | maneuver | C1:1005 maneuver, C1:1006 maneuver, C2:1361 maneuver, C2:1362 maneuver | verb, noun | manoeuvre |
| C1 | manicure | C1:549 manicure, C1:550 manicure | noun, verb | — |
| C1 | marvel | C1:9 marvel, C2:1122 marvel | verb, noun | — |
| C1 | numb | C1:988 numb, C1:989 numb | adjective, verb | — |
| C1 | obscure | C1:421 obscure, C1:422 obscure | verb, adjective | — |
| C1 | overdraft | C1:881 overdraft, C1:882 overdraft | verb, noun | — |
| C1 | pendulum | C1:329 pendulum, C1:960 pendulum | noun | — |
| C1 | pioneer | C1:433 pioneer, C1:434 pioneer | verb, noun | — |
| C1 | plaster | C1:68 plaster, C1:69 plaster | noun, verb | — |
| C1 | plunge | C1:1008 plunge, C1:1009 plunge | verb, noun | — |
| C1 | poise | C1:184 poise, C2:1171 poise | noun, verb | — |
| C1 | portable | C1:134 portable, C1:135 portable | adjective, noun | — |
| C1 | posture | C1:581 posture, C2:1252 posture, C2:1347 posture | noun, verb | — |
| C1 | predecessor | C1:330 predecessor, C2:1175 predecessor | noun | — |
| C1 | premier | C1:823 premier, C1:824 premier | adjective, noun | — |
| C1 | premise | C1:180 premise, C1:594 premise | noun | — |
| C1 | proliferate | C1:841 proliferate, C2:1972 proliferate | verb | — |
| C1 | prop | C1:640 prop, C1:641 prop | verb, noun | — |
| C1 | quip | C1:369 quip, C1:370 quip | noun, verb | — |
| C1 | quirk | C1:30 quirk, C2:1127 quirk | noun, verb | — |
| C1 | quirky | C1:1051 quirky, C1:1052 quirky | adjective, noun | — |
| C1 | recess | C1:836 recess, C1:837 recess | noun | — |
| C1 | refreshingly | C1:56 refreshingly, C1:686 refreshingly | adverb | — |
| C1 | relapse | C1:653 relapse, C1:654 relapse | verb, noun | — |
| C1 | relinquish | C1:141 relinquish, C2:1829 relinquish | verb | — |
| C1 | repellant | C1:254 repellant, C1:255 repellant | noun, adjective | — |
| C1 | repute | C1:510 repute, C2:1245 repute | verb, noun | — |
| C1 | resin | C1:89 resin, C2:1835 resin | noun | — |
| C1 | rumble | C1:276 rumble, C1:277 rumble | verb, noun | — |
| C1 | rustle | C1:1032 rustle, C1:1033 rustle | verb, noun | — |
| C1 | sacrifice | C1:90 sacrifice, C1:91 sacrifice | noun, verb | — |
| C1 | sedate | C1:582 sedate, C1:584 sedate | verb, adjective | — |
| C1 | sedately | C1:583 sedately, C2:1836 sedately | adverb | — |
| C1 | shortlist | C1:197 shortlist, C1:198 shortlist | verb, noun | — |
| C1 | slack | C1:663 slack, C1:664 slack, C1:665 slack | verb, noun, adjective | — |
| C1 | somersault | C1:1036 somersault, C1:1037 somersault | noun, verb | — |
| C1 | sprawl | C1:1053 sprawl, C1:1054 sprawl | noun, verb | — |
| C1 | sprout | C1:978 sprout, C1:979 sprout | verb, noun | — |
| C1 | staccato | C1:692 staccato, C1:693 staccato | adjective, adverb | — |
| C1 | strap | C1:811 strap, C1:812 strap | noun, verb | — |
| C1 | stray | C1:674 stray, C1:675 stray, C1:676 stray | verb, adjective, noun | — |
| C1 | succulent | C1:1105 succulent, C1:1106 succulent | noun, adjective | — |
| C1 | swap | C1:294 swap, C1:746 swap, C1:747 swap | verb, noun | — |
| C1 | tailor | C1:736 tailor, C1:737 tailor | noun, verb | — |
| C1 | tangle | C1:709 tangle, C1:710 tangle | verb, noun | — |
| C1 | tantamount | C1:649 tantamount, C2:1523 tantamount | adjective | — |
| C1 | tedious | C1:142 tedious, C1:427 tedious | adjective | — |
| C1 | tedium | C1:143 tedium, C2:1238 tedium | noun | — |
| C1 | tinker | C1:445 tinker, C1:446 tinker | verb, noun | — |
| C1 | torment | C1:161 torment, C1:162 torment | verb, noun | — |
| C1 | twitch | C1:340 twitch, C1:341 twitch | verb, noun | — |
| C2 | additive | C2:1923 additive, C2:1924 additive | noun, adjective | — |
| C2 | adept | C2:1555 adept, C2:1556 adept | adjective, noun | — |
| C2 | annex | C2:1886 annex, C2:1887 annex | noun, verb | — |
| C2 | blight | C2:1147 blight, C2:1148 blight | noun, verb | — |
| C2 | blitz | C2:1221 blitz, C2:1222 blitz | verb, noun | — |
| C2 | brood | C2:1150 brood, C2:1151 brood | verb, noun | — |
| C2 | buccaneer | C2:1840 buccaneer, C2:1841 buccaneer | verb, noun | — |
| C2 | conjecture | C2:1280 conjecture, C2:1281 conjecture | verb, noun | — |
| C2 | correlate | C2:1449 correlate, C2:1451 correlate | noun, verb | — |
| C2 | derelict | C2:1179 derelict, C2:1180 derelict | adjective, noun | — |
| C2 | deviant | C2:1539 deviant, C2:1540 deviant | noun, adjective | — |
| C2 | diffuse | C2:1321 diffuse, C2:1322 diffuse | adjective, verb | — |
| C2 | dribble | C2:1790 dribble, C2:1791 dribble, C2:1792 dribble | verb, noun | — |
| C2 | echo | C2:1192 echo, C2:1193 echo, C2:1194 echo | noun, verb | — |
| C2 | egalitarian | C2:1323 egalitarian, C2:1324 egalitarian | adjective, noun | — |
| C2 | encumber | C2:1156 encumber, C2:1261 encumber | verb | — |
| C2 | encumbrance | C2:1155 encumbrance, C2:1262 encumbrance | noun | — |
| C2 | extracurricular | C2:1420 extracurricular, C2:1421 extracurricular | adjective, noun | — |
| C2 | herald | C2:1479 herald, C2:1480 herald | verb, noun | — |
| C2 | huddle | C2:1742 huddle, C2:1743 huddle | verb, noun | — |
| C2 | incumbent | C2:1602 incumbent, C2:1603 incumbent | noun, adjective | — |
| C2 | lament | C2:1486 lament, C2:1715 lament | verb | — |
| C2 | lamentation | C2:1487 lamentation, C2:1716 lamentation | noun | — |
| C2 | melancholy | C2:1567 melancholy, C2:1568 melancholy | noun, adjective | — |
| C2 | merit | C2:1577 merit, C2:1578 merit | noun, verb | — |
| C2 | perch | C2:1465 perch, C2:1466 perch, C2:1467 perch | verb, noun | — |
| C2 | procedural | C2:1517 procedural, C2:1518 procedural | adjective, noun | — |
| C2 | proliferation | C2:1268 proliferation, C2:1973 proliferation | noun | — |
| C2 | promotable | C2:1579 promotable, C2:2080 promotable | adjective | — |
| C2 | prostrate | C2:1351 prostrate, C2:1352 prostrate | verb, adjective | — |
| C2 | quiver | C2:1830 quiver, C2:1831 quiver | verb, noun | — |
| C2 | rebound | C2:1493 rebound, C2:1494 rebound | verb, noun | — |
| C2 | rebuke | C2:1914 rebuke, C2:1915 rebuke | verb, noun | — |
| C2 | relegate | C2:1371 relegate, C2:2102 relegate | verb | — |
| C2 | repose | C2:1259 repose, C2:1260 repose | verb, noun | — |
| C2 | solitary | C2:1781 solitary, C2:1782 solitary | adjective, noun | — |
| C2 | trifle | C2:2052 trifle, C2:2053 trifle | noun, verb | — |
| C2 | utilitarian | C2:1162 utilitarian, C2:1231 utilitarian | adjective | — |
| C2 | verbatim | C2:1981 verbatim, C2:1982 verbatim | adjective, adverb | — |

### Terms from a later variant (4)

The first variant links nowhere, a later one does.

| Level | Line | First variant | Term |
|---|---|---|---|
| B1 | 1109 | check-in counter | check-in |
| B1 | 1110 | check-in desk | check-in |
| A2 | 3234 | hip hop | hip-hop |
| B2 | 7736 | wornout | worn out |

### Case pairs (4)

| Capitalised | Merged into |
|---|---|
| IT | it |
| March | march |
| May | may |
| Miss | miss |

## Frequency ranks

| Language | Input | Tokens | Keys |
|---|---|---|---|
| ell | `frequencywords/el_50k.txt` | 50,000 | 47,749 |
| eng | `frequencywords/en_50k.txt` | 50,000 | 50,093 |

## Table sizes

Copied into a new file and VACUUMed, as they ship.

| Table | Bytes |
|---|---|
| wordlist | 8,192 |
| wordlist_item | 950,272 |
| word_rank | 2,310,144 |
| total | 3,268,608 |
