# Word lists QA report

Written by `Scripts/build_wordlists.py` on every dictionary build (docs/specs/0130-word-lists.md, "List data"); do not edit by hand.

## Inputs

| Input | sha256 |
|---|---|
| `Scripts/data/wordlists/ky-ell-a1.csv` | `591d5c1fbe6714e3f9c6c3099f32c196f46eb4afe424badb950a787171c98d7b` |
| `Scripts/data/wordlists/ky-ell-a2.csv` | `bed81a951a0f2fdc84e6dc071c0ff0b27f9da4326f218f33852178313ee3fdb9` |
| `Scripts/data/wordlists/ky-ell-b1.csv` | `816a888bc8fb1d16210bf66f5de22bdac35a9027f0ef5f52a8d6e7b96f9829f3` |
| `frequencywords/el_50k.txt` | `7ec8f6de52c38f36a04add5d1613b116aed576e10c5e3b40d0001e8572de978c` |

## Gates

| Gate | Measured | Needed | |
|---|---|---|---|
| Input problems (Latin letters in Greek, Greek letters in Latin words, rows that become no word, bad rows, overrides) | 0 | 0 | ok |
| ky-ell linked | 88.0% (4,090 of 4,648) | ≥ 84% | ok |
| word_count equals rows | all | all | ok |
| Empty lists | 0 | 0 | ok |
| E3 tables | 1.78 MB | ≤ 4 MB | ok |

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

## Frequency ranks

| Language | Input | Tokens | Keys |
|---|---|---|---|
| ell | `frequencywords/el_50k.txt` | 50,000 | 47,749 |

## Table sizes

Copied into a new file and VACUUMed, as they ship.

| Table | Bytes |
|---|---|
| wordlist | 8,192 |
| wordlist_item | 430,080 |
| word_rank | 1,339,392 |
| total | 1,777,664 |
