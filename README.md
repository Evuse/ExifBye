# ExifBye

App personale, nativa SwiftUI, per **iPhone e iPad con iOS/iPadOS 16–18**. Seleziona foto e video, anche in massa, ricodifica e salva **nuove copie** nel rullino. Gli originali non vengono eliminati o modificati. Interfaccia in italiano, nessun account, pubblicità, analytics o libreria esterna.

Progetto impostato per **Xcode 16.2 su macOS 15.0.1**, Swift 5 e deployment target iOS 16.0. Non richiede CocoaPods, Homebrew, XcodeGen o pacchetti Swift aggiuntivi.

## Stato delle verifiche

Il progetto è stato scritto in un ambiente Linux: verificati sintassi Swift con parser, struttura del progetto Xcode, plist, schema e riproducibilità del generatore. **Compilazione con SDK Apple, test XCTest e prova sul dispositivo non sono ancora stati eseguiti**: vanno completati sul Mac seguendo la guida sotto. Il controllo di sintassi non verifica i tipi o il comportamento delle API Apple. Questa versione richiede quindi collaudo prima di affidarle file sensibili.

## Installazione sul tuo iPhone, passo per passo

1. Scarica e decomprimi `ExifBye.zip` sul Mac. Tieni la cartella in una posizione stabile, per esempio `Documenti/ExifBye`. In alternativa usa il checkout del repository che contiene questi file. Non serve caricare niente sull’App Store.
2. Apri **Xcode 16.2**, accetta le condizioni e completa l’installazione dei componenti che propone al primo avvio. Per l’iPhone fisico non serve scaricare un simulatore.
3. In **Xcode → Settings… → Accounts**, premi **+**, scegli **Apple Account/Apple ID** e accedi con il tuo account. Per uso personale va bene un account gratuito; non occorre pagare l’Apple Developer Program.
4. Apri `ExifBye.xcodeproj` dalla cartella estratta. Non aprire un singolo `.swift` e non serve un `.xcworkspace`.
5. Collega l’iPhone al Mac con un cavo USB che supporti i dati. Sbloccalo. Se richiesto, conferma **Autorizza/Trust** sul telefono e sul Mac, inserendo il codice dell’iPhone. Lascia l’iPhone sbloccato durante la prima installazione.
6. Nel navigatore a sinistra di Xcode, clicca il progetto blu **ExifBye**. Sotto **TARGETS**, scegli **ExifBye**, poi **Signing & Capabilities**.
7. Lascia attivo **Automatically manage signing**. In **Team** scegli il tuo account, solitamente indicato come **Nome Cognome (Personal Team)** per l’account gratuito. Cambia **Bundle Identifier** da `app.exifbye.personal` a uno personale e univoco, per esempio `it.tuonome.exifbye`. Non cambiare il deployment target da 16.0. Se vuoi eseguire i test anche sull’iPhone, seleziona anche il target **ExifByeTests**, scegli lo stesso Team e usa un identificatore coerente, per esempio `it.tuonome.exifbye.tests`.
8. Nella barra superiore scegli lo schema **ExifBye** e come destinazione **il tuo iPhone**, invece di un simulatore o “Any iOS Device”. Attendi che Xcode completi il pairing e la preparazione del dispositivo. Lo trovi anche in **Window → Devices and Simulators**.
9. Sull’iPhone abilita **Impostazioni → Privacy e sicurezza → Modalità sviluppatore**. Segui la richiesta di riavvio e conferma l’attivazione dopo il riavvio. Se la voce non compare, completa prima il collegamento a Xcode e prova **Product → Run**, poi ricontrolla. Ricollega e sblocca il dispositivo dopo il riavvio.
10. Premi il triangolo **Run ▶︎** in Xcode, oppure **⌘R**. Xcode compila, firma e installa l’app. La prima volta può chiedere di usare il certificato di sviluppo nel Portachiavi del Mac: autorizza la richiesta di Xcode/codesign.
11. Se sull’iPhone compare **Sviluppatore non autorizzato/Untrusted Developer**, apri **Impostazioni → Generali → VPN e gestione dispositivo**, seleziona il profilo con il tuo Apple ID e autorizzalo seguendo le indicazioni di iOS. La voce appare solo quando esiste un profilo da autorizzare. Torna su Xcode e premi nuovamente **Run** se necessario.
12. All’avvio seleziona **Seleziona foto e video**, scegli inizialmente una foto con posizione GPS e un breve video con audio e premi **Aggiungi/Add** nel selettore di sistema.
13. Premi **Pulisci e salva**. Alla richiesta di iOS consenti l’**aggiunta** alla libreria Foto. Il selettore di sistema non richiede l’accesso completo al rullino. Tieni ExifBye in primo piano fino alla fine: lo schermo viene mantenuto acceso durante il lavoro.
14. Apri **Foto → Recenti/Salvati di recente**: troverai le nuove copie con la data del nuovo salvataggio. Verifica che si aprano, che l’orientamento sia corretto e che il video abbia l’audio. Nel pannello informazioni non deve esserci la posizione originale. Per una verifica più completa dei file esportati, usa anche i passaggi sotto.
15. Terminata la prova puoi scollegare il cavo e aprire ExifBye dalla schermata Home. Le future elaborazioni non richiedono Xcode o il Mac. Se i file sono già sul dispositivo, la ricodifica avviene senza Internet; Foto può comunque scaricare o sincronizzare elementi tramite iCloud in base alle tue impostazioni.

### Scadenza della firma gratuita

Con **Personal Team gratuito**, il profilo di sviluppo dura normalmente **7 giorni**. Dopo la scadenza l’app potrebbe non aprirsi: ricollega l’iPhone, apri lo stesso progetto, scegli lo stesso Team e Bundle Identifier e premi **⌘R** per rinnovarla. Non eliminare prima l’app. Le copie già salvate in Foto restano nel rullino anche se la firma scade o disinstalli ExifBye. Per un altro tuo dispositivo ripeti collegamento, Modalità sviluppatore e Run scegliendo quel dispositivo. Un abbonamento Developer a pagamento permette profili di sviluppo più duraturi, ma non è necessario per cominciare.

### Problemi frequenti

- **“Signing requires a development team”**: scegli il tuo Personal Team nel target ExifBye. Se il problema riguarda ExifByeTests, configura anche quel target.
- **“Bundle identifier is not available”**: usa un identificatore più personale e univoco e lascia la firma automatica attiva.
- **iPhone non visibile**: sbloccalo, cambia cavo/porta, conferma Trust e controlla Window → Devices and Simulators. Il deployment target 16.0 è il minimo dell’app, non la versione da installare sul telefono.
- **Versione iOS non supportata da Xcode**: Xcode 16.2 include l’SDK iOS 18.2. Se Devices and Simulators segnala che il sistema del tuo iPhone è troppo recente, serve una versione di Xcode che lo supporti, con i relativi requisiti macOS. Non è un problema risolvibile cambiando il deployment target. Non aggiornare macOS/Xcode senza prima verificare il messaggio concreto.
- **Permesso Foto negato**: Impostazioni → App → ExifBye → Foto su iOS 18, oppure Impostazioni → ExifBye → Foto su iOS 16/17; abilita l’aggiunta, poi riprova.
- **Importazione lenta**: l’originale potrebbe essere su iCloud. Scaricalo in Foto o lascia completare il download. Interrompi annulla anche la richiesta al provider, ma la risposta di iOS può richiedere tempo.
- **File non elaborato**: il messaggio appare sotto quell’elemento. Gli altri continuano; il pulsante di ripresa ritenta solo gli elementi non salvati. Libera spazio se necessario. Non c’è un limite numerico imposto dall’app, ma dimensioni, memoria, batteria, spazio e codec supportati dal dispositivo restano vincoli reali.

## Che cosa viene rimosso e che cosa resta

“Qualsiasi informazione” non può significare letteralmente tutti i byte diversi dai pixel: un file leggibile deve descrivere dimensioni, codifica e colore; un video deve includere tempi e tracce. L’obiettivo è eliminare i **metadati descrittivi originali**, come GPS, data di scatto, marca/modello/seriale della fotocamera, autore, commenti, parole chiave e identificatori. Non è una garanzia di anonimato del contenuto.

- **Foto**: ImageIO decodifica i pixel; Core Image applica l’orientamento; una nuova immagine opaca sRGB viene codificata in JPEG al 95%, senza passare le proprietà del sorgente al codificatore. Trasparenza resa su bianco. Un controllo successivo accetta solo proprietà tecniche note e blocca il salvataggio se trova proprietà inattese.
- **Video**: AVAssetReader decodifica il video principale e, se presente, la prima traccia audio. Core Image renderizza ogni frame in un buffer nuovo, senza allegati del buffer sorgente; AVAssetWriter codifica un nuovo MP4 H.264 con audio AAC stereo a 44,1 kHz. Non vengono copiati stream compressi, tracce metadata/GPS, sottotitoli, capitoli o timecode del sorgente. L’orientamento visivo viene mantenuto. Il controllo finale blocca file con metadati asset/traccia o tracce extra.
- **Originali**: immutati, con i metadati originali ancora presenti. L’app richiede solo il permesso di aggiungere copie.
- **Nuove copie**: nome casuale `Clean-UUID`, nuova data di aggiunta in Foto, informazioni tecniche del nuovo encoding e profilo colore standard. Non vengono impostati posizione o data di scatto originali. Foto/iCloud e le app con cui condividi possono aggiungere nuove informazioni dopo il salvataggio.
- **Qualità e formati**: ricodifica con perdita, uscita SDR a 8 bit, nessuna conservazione di RAW/HDR/Dolby Vision/depth/alpha/motion. Live Photo → immagine statica; GIF/APNG animate rifiutate per evitare la perdita silenziosa dell’animazione. Le sequenze HEIF e immagini multipagina vengono ridotte all’immagine principale. Effetti, ritagli temporali e slow-motion vanno verificati sul file effettivamente restituito da Foto. File corrotti, protetti da DRM o non decodificabili/codificabili da iOS possono fallire.
- **Contenuto**: volti, targhe, scritte, watermark, voce, luoghi riconoscibili e impronte statistiche della fotocamera non vengono anonimizzati. L’app non effettua OCR, sfocatura o cancellazione sicura degli originali.

Non c’è un server dell’app, né vengono registrati nomi, URL o metadati nei log. I file intermedi stanno nella directory temporanea protetta dell’app e vengono rimossi dopo ogni elemento; al riavvio vengono ripulite le directory di staging rimaste dopo una chiusura forzata. Non si promette una cancellazione forense della memoria flash.

L’elaborazione è sequenziale per evitare di caricare l’intero batch in memoria o duplicarlo su disco. Passando in background viene richiesta l’interruzione; l’elemento corrente può completare un salvataggio già avviato. **La ripresa vale nella sessione corrente**: dopo chiusura forzata o riavvio del processo occorre selezionare di nuovo gli elementi rimasti. Le copie già salvate non vengono ritentate automaticamente nella stessa sessione.

## Test su Mac con Xcode 16.2

In Xcode scegli un simulatore iOS 18.2 e premi **⌘U** (Product → Test). Per installare il simulatore usa Xcode → Settings → Components/Platforms, secondo la schermata disponibile. Ripeti su iOS 16 e 17 se i runtime sono disponibili sul tuo Mac, oppure su dispositivi con tali versioni. I test non richiedono accesso al rullino, Apple ID o credenziali se eseguiti nel simulatore.

Da Terminale, nella cartella del progetto:

```sh
xcodebuild -version
xcodebuild -list -project ExifBye.xcodeproj
xcodebuild -showdestinations -project ExifBye.xcodeproj -scheme ExifBye
```

Scegli l’ID di un simulatore disponibile, poi esegui (sostituisci `ID_DEL_SIMULATORE`):

```sh
mkdir -p build
xcodebuild test \
  -project ExifBye.xcodeproj \
  -scheme ExifBye \
  -destination 'platform=iOS Simulator,id=ID_DEL_SIMULATORE' \
  -derivedDataPath DerivedData \
  -resultBundlePath build/ExifBye-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Usa un percorso `-resultBundlePath` nuovo per ogni esecuzione: Xcode non sovrascrive un bundle già presente. Il risultato atteso è **7 test completati, zero fallimenti e zero test saltati**, non solo “Build succeeded”. La suite verifica immagini con GPS/EXIF/IPTC e rotazione, input corrotti/animati, rifiuto di file non puliti, video con posizione e titolo, audio decodificabile, orientamento, video muti e cancellazione preventiva.

### Collaudo manuale sul dispositivo

Prima di usare l’app su file sensibili:

1. Prova JPEG e HEIC con GPS, screenshot PNG, foto ruotate, trasparenza e Live Photo. Controlla visivamente qualità e orientamento, e che gli originali siano ancora presenti.
2. Prova MOV/MP4 con audio e GPS, video muto, verticale/orizzontale, HEVC/HDR e un filmato lungo. Verifica l’intera riproduzione, la sincronizzazione audio e l’uscita SDR.
3. Seleziona un batch misto, interrompi durante un video e riprendi. Controlla conteggi, assenza di duplicati nel singolo batch e gestione di un file non supportato.
4. Prova permesso di salvataggio negato, file solo su iCloud, spazio insufficiente e passaggio in background. I fallimenti devono essere visibili e non dichiarati come successi.
5. Esporta **la copia nuova** da Foto come originale non modificato sul Mac. Se hai ExifTool (`brew install exiftool`, facoltativo), esegui `exiftool -a -u -G1 -s /percorso/alla/copia.jpg` e lo stesso sul `.mp4`. Devono mancare posizione, autore, fotocamera, seriali e date originali. Le sezioni File/System, le date della copia nuova e le strutture JPEG/ICC/MP4 non sono metadati personali originali. L’assenza della mappa nell’interfaccia Foto da sola non dimostra l’assenza di tutti gli altri campi.

## Sviluppo

Apri direttamente il progetto incluso: non servono script di installazione. Le API usate appartengono agli SDK Apple. Il progetto usa Swift 5 per evitare di richiedere la migrazione alle regole di concorrenza di Swift 6 su Xcode 16.2.

`scripts/generate_project.py` ricrea progetto e schema con Python 3 se aggiungi nuovi file Swift. Non eseguirlo dopo aver personalizzato firma/Bundle Identifier senza salvare prima tali modifiche: il generatore ripristina i valori predefiniti. I file generati sono già inclusi; **non serve eseguirlo per installare l’app**.

```sh
python3 scripts/validate_project.py
```

Questo verifica configurazione e riferimenti locali; non sostituisce `xcodebuild test`. L’ambiente cloud è isolato: usa il checkout esistente, senza creare worktree per le normali attività. Un ambiente Linux non può compilare, firmare o installare applicazioni iOS né eseguire i test che usano gli SDK Apple.
