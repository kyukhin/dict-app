# Drill examples: a sample for review

Written by `Scripts/drill_examples.py --sample` ([0134-example-sentences.md](../../docs/specs/0134-example-sentences.md), "Checks", 3). Do not edit by hand.

50 of the 4,775 rows of `Scripts/data/drill-examples/ell.tsv` (wiktionary 351, generated 4,424), drawn by `random.Random(int(sha256, 16)).sample(rows, 50)` with the file's sha256 `629db49729c88a674f2a498906d2084baa593f81ad459671f407afece67c62be`, so nobody picks them; in id order.

kyukhin reads the Greek, the English and the Russian. A wrong form or a wrong meaning: its cause is fixed, the rows it touched are generated again and a new sample is drawn. A Wiktionary row's Greek and English are Wiktionary's; its Russian is generated.

| # | id | Source | Cell | Greek | English | Russian |
|---|---|---|---|---|---|---|
| 1 | 1000000182 | Wiktionary (στολίζομαι) | στολίζω · Present · passive · αυτός | Η πόλη **στολίζεται** για τα Χριστούγεννα! | The city is decorated for Christmas! | Город украшается к Рождеству! |
| 2 | 1000000284 | Wiktionary (γκρίνια) | απολαμβάνω · Subjunctive: continuous form (να) · εσύ | Κόψε την γκρίνια κι άρχισε **να απολαμβάνεις** την ζωή σου! | Quit moaning and start enjoying your life! | Хватит ныть, начни наслаждаться жизнью! |
| 3 | 1000000380 | Wiktionary (αρνίσιος) | κατασκευάζω · Perfect · passive · αυτός | Το προϊόν **έχει κατασκευαστεί** με φυσικό 90% αρνίσιο μαλλί. | The product is made with 90% natural lamb's wool. | Изделие изготовлено на 90% из натуральной овечьей шерсти. |
| 4 | 1000000394 | Wiktionary (μάτι του κυκλώνα) | βρίσκομαι · Aorist (simple past) · passive · εγώ | **Βρέθηκα** στο μάτι του κυκλώνα. | I found myself in the eye of the storm. | Я оказался в эпицентре бури. |
| 5 | 2000000022 | generated | μπορώ · Subjunctive: simple form (να) · εσείς | Πάρτε τον χάρτη για **να μπορέσετε** να βρείτε τον δρόμο. | Take the map so that you can find the way. | Возьмите карту, тогда вы сможете найти дорогу. |
| 6 | 2000000200 | generated | σκέφτομαι · Future: simple form · passive · αυτοί | Οι γονείς μου **θα το σκεφτούν** πριν πουν ναι. | My parents will think about it before they say yes. | Мои родители подумают, прежде чем сказать «да». |
| 7 | 2000000317 | generated | κρατάω · Subjunctive: simple form (να) · εσείς | Μπορείτε **να κρατήσετε** την τσάντα μου για ένα λεπτό; | Can you hold my bag for a minute? | Вы можете подержать мою сумку минутку? |
| 8 | 2000000372 | generated | αγαπάω · Aorist (simple past) · αυτοί | Τα παιδιά **αγάπησαν** αμέσως τον νέο σκύλο. | The children loved the new dog at once. | Дети сразу полюбили новую собаку. |
| 9 | 2000000622 | generated | προσέχω · Future: simple form · εμείς | **Θα προσέξουμε** το σπίτι σας όταν λείπετε. | We will look after your house while you're away. | Мы присмотрим за вашим домом, пока вас нет. |
| 10 | 2000000788 | generated | κοιμάμαι · Imperative: simple form · passive · εσείς | Παιδιά, **κοιμηθείτε** νωρίς, αύριο έχουμε σχολείο! | Kids, go to sleep early; tomorrow we have school! | Дети, ложитесь спать пораньше, завтра у нас школа! |
| 11 | 2000000798 | generated | ανοίγω · Present · εσείς | Εσείς **ανοίγετε** τα παράθυρα το βράδυ; | Do you open the windows in the evening? | Вы открываете окна вечером? |
| 12 | 2000000930 | generated | ακολουθώ · Aorist (simple past) · αυτοί | Οι τουρίστες **ακολούθησαν** τον οδηγό στο μουσείο. | The tourists followed the guide to the museum. | Туристы пошли за гидом в музей. |
| 13 | 2000000963 | generated | υπόσχομαι · Aorist (simple past) · passive · εμείς | **Υποσχεθήκαμε** στα παιδιά μια βόλτα στο πάρκο. | We promised the children a walk in the park. | Мы пообещали детям прогулку в парке. |
| 14 | 2000001233 | generated | μαζεύω · Future: simple form · εσύ | **Θα μαζέψεις** τα παιχνίδια σου πριν φύγουμε; | Will you pick up your toys before we leave? | Ты соберёшь свои игрушки, прежде чем мы уйдём? |
| 15 | 2000001323 | generated | προσφέρω · Imperative: simple form · εσύ | **Πρόσφερε** ένα ποτήρι νερό στον κύριο, σε παρακαλώ. | Offer the gentleman a glass of water, please. | Предложи, пожалуйста, господину стакан воды. |
| 16 | 2000001410 | generated | καλύπτω · Imperative: simple form · εσείς | **Καλύψτε** το ψωμί με μια πετσέτα. | Cover the bread with a towel. | Накройте хлеб полотенцем. |
| 17 | 2000001508 | generated | κατεβαίνω · Future: simple form · αυτοί | Το Σάββατο οι φίλοι μας **θα κατέβουν** στην Αθήνα. | On Saturday our friends will come down to Athens. | В субботу наши друзья приедут в Афины. |
| 18 | 2000001788 | generated | προτείνω · Subjunctive: simple form (να) · εσύ | Μπορείς **να προτείνεις** ένα καλό εστιατόριο; | Can you suggest a good restaurant? | Можешь посоветовать хороший ресторан? |
| 19 | 2000001844 | generated | συνδέω · Future: simple form · εμείς | Αύριο **θα συνδέσουμε** το νέο πλυντήριο. | Tomorrow we will connect the new washing machine. | Завтра мы подключим новую стиральную машину. |
| 20 | 2000001883 | generated | διασκεδάζω · Subjunctive: simple form (να) · εμείς | Πάμε στη θάλασσα **να διασκεδάσουμε** λίγο! | Let's go to the sea to have some fun! | Пойдём на море немного повеселиться! |
| 21 | 2000002011 | generated | διδάσκω · Aorist (simple past) · αυτοί | Οι δάσκαλοι **δίδαξαν** στα παιδιά ένα παλιό τραγούδι. | The teachers taught the children an old song. | Учителя научили детей старой песне. |
| 22 | 2000002120 | generated | προτιμάω · Aorist (simple past) · εσύ | Γιατί **προτίμησες** το τρένο από το αεροπλάνο; | Why did you prefer the train to the plane? | Почему ты предпочёл поезд самолёту? |
| 23 | 2000002151 | generated | ξοδεύω · Future: simple form · εσείς | Πόσα χρήματα **θα ξοδέψετε** για τα δώρα; | How much money will you spend on the presents? | Сколько денег вы потратите на подарки? |
| 24 | 2000002226 | generated | συστήνω · Imperative: simple form · εσύ | **Σύστησε** τον φίλο σου σε όλους, κανείς δεν τον ξέρει! | Introduce your friend to everyone, nobody knows him! | Представь своего друга всем, его никто не знает! |
| 25 | 2000002291 | generated | ετοιμάζομαι · Aorist (simple past) · passive · εμείς | **Ετοιμαστήκαμε** γρήγορα και φύγαμε για το θέατρο. | We got ready quickly and left for the theatre. | Мы быстро собрались и ушли в театр. |
| 26 | 2000002306 | generated | σημειώνω · Present · εσείς | **Σημειώνετε** τα γενέθλια των φίλων σας στο ημερολόγιο; | Do you note your friends' birthdays in the calendar? | Вы отмечаете дни рождения друзей в календаре? |
| 27 | 2000002355 | generated | τρελαίνομαι · Future: simple form · passive · αυτός | Η Ελένη **θα τρελαθεί** με αυτό το δώρο! | Eleni will go crazy over this present! | Элени сойдёт с ума от этого подарка! |
| 28 | 2000002472 | generated | ζωγραφίζω · Imperative: simple form · εσύ | **Ζωγράφισε** το σπίτι σου σε αυτό το χαρτί, Νίκο! | Draw your house on this paper, Nikos! | Нарисуй свой дом на этом листе бумаги, Никос! |
| 29 | 2000002738 | generated | ψωνίζω · Subjunctive: simple form (να) · αυτοί | Οι φίλες μου πήγαν στο κέντρο **να ψωνίσουν** ρούχα. | My friends went to the town centre to shop for clothes. | Мои подруги пошли в центр купить одежду. |
| 30 | 2000002964 | generated | τηγανίζω · Future: simple form · εγώ | Το βράδυ **θα τηγανίσω** πατάτες. | In the evening I will fry potatoes. | Вечером я пожарю картошку. |
| 31 | 2000003062 | generated | παντρεύω · Present · εσύ | Πότε **παντρεύεις** την κόρη σου; | When are you marrying off your daughter? | Когда ты выдаёшь дочь замуж? |
| 32 | 2000003151 | generated | σπάζω · Present · εμείς | Πρώτα **σπάζουμε** τρία αβγά και τα ανακατεύουμε με γάλα. | First we break three eggs and mix them with milk. | Сначала мы разбиваем три яйца и смешиваем их с молоком. |
| 33 | 2000003158 | generated | σπάζω · Future: simple form · εσείς | Μην παίζετε μπάλα στο σαλόνι, **θα σπάσετε** κάτι! | Do not play ball in the living room, you will break something! | Не играйте в мяч в гостиной, вы что-нибудь разобьёте! |
| 34 | 2000003186 | generated | καίω · Present · passive · εγώ | Χωρίς καπέλο **καίγομαι** στον ήλιο. | Without a hat I get burnt in the sun. | Без шляпы я сгораю на солнце. |
| 35 | 2000003243 | generated | πείθω · Aorist (simple past) · εμείς | Τελικά **πείσαμε** τον παππού να έρθει μαζί μας. | In the end we persuaded grandpa to come with us. | В итоге мы уговорили дедушку поехать с нами. |
| 36 | 2000003305 | generated | μαντεύω · Present · εμείς | Σε αυτό το παιχνίδι **μαντεύουμε** ταινίες με παντομίμα. | In this game we guess films through mime. | В этой игре мы угадываем фильмы по пантомиме. |
| 37 | 2000003333 | generated | συμπαθώ · Future: simple form · αυτοί | Είμαι σίγουρος ότι οι γονείς μου **θα σε συμπαθήσουν**. | I'm sure my parents will like you. | Я уверен, что ты понравишься моим родителям. |
| 38 | 2000003483 | generated | κλειδώνω · Subjunctive: simple form (να) · εσύ | Μην ξεχάσεις **να κλειδώσεις** το ποδήλατό σου στο σχολείο. | Don't forget to lock your bike at school. | Не забудь запереть велосипед на замок у школы. |
| 39 | 2000003544 | generated | γιορτάζω · Aorist (simple past) · αυτός | Η Μαρία **γιόρτασε** χθες τα γενέθλιά της σε μια ταβέρνα. | Maria celebrated her birthday in a tavern yesterday. | Мария вчера отпраздновала свой день рождения в таверне. |
| 40 | 2000003557 | generated | γιορτάζω · Subjunctive: simple form (να) · εσύ | Πρέπει **να γιορτάσεις** τη νέα σου δουλειά! | You have to celebrate your new job! | Ты должен отметить свою новую работу! |
| 41 | 2000003605 | generated | δηλώνω · Future: simple form · εγώ | Στη συνέντευξη **θα δηλώσω** ότι μιλάω τρεις γλώσσες. | At the interview I will state that I speak three languages. | На собеседовании я заявлю, что говорю на трёх языках. |
| 42 | 2000003723 | generated | θυμίζω · Aorist (simple past) · εγώ | **Θύμισα** στον Νίκο ότι έχει ραντεβού στις πέντε. | I reminded Nikos that he has an appointment at five. | Я напомнил Никосу, что у него встреча в пять. |
| 43 | 2000003843 | generated | ενδιαφέρω · Future: simple form · αυτοί | Νομίζω ότι αυτές οι ταινίες **θα σε ενδιαφέρουν**. | I think these films will interest you. | Думаю, эти фильмы тебя заинтересуют. |
| 44 | 2000003950 | generated | απλώνω · Future: simple form · εσείς | **Θα απλώσετε** τα ρούχα στο μπαλκόνι; | Will you hang the clothes out on the balcony? | Вы развесите бельё на балконе? |
| 45 | 2000003980 | generated | φυτεύω · Subjunctive: simple form (να) · εσείς | Ο Μάρτιος είναι ο καλύτερος μήνας για **να φυτέψετε** ντομάτες. | March is the best month for you to plant tomatoes. | Март — лучший месяц, чтобы посадить помидоры. |
| 46 | 2000003993 | generated | σκουπίζω · Aorist (simple past) · εσείς | **Σκουπίσατε** τα πόδια σας πριν μπείτε; | Did you wipe your feet before you came in? | Вы вытерли ноги, прежде чем войти? |
| 47 | 2000004055 | generated | συλλέγω · Imperative: simple form · εσείς | **Συλλέξτε** πληροφορίες για την ιστορία της πόλης σας. | Collect information about the history of your town. | Соберите информацию об истории вашего города. |
| 48 | 2000004178 | generated | φιλοξενώ · Future: simple form · εμείς | Τον Αύγουστο **θα φιλοξενήσουμε** τους ξαδέρφους μας από τον Καναδά. | In August we will host our cousins from Canada. | В августе мы примем у себя двоюродных братьев из Канады. |
| 49 | 2000004328 | generated | παρουσιάζομαι · Subjunctive: simple form (να) · passive · εσείς | Θέλω **να παρουσιαστείτε** στην τάξη σας αμέσως! | I want you to report to your classroom right away! | Я хочу, чтобы вы немедленно явились в класс! |
| 50 | 2000004443 | generated | ενδιαφέρω · Present · αυτοί | Με **ενδιαφέρουν** πολύ οι ξένες γλώσσες. | Foreign languages interest me a lot. | Меня очень интересуют иностранные языки. |
