# App Locale – prototipo

Prototipo web dell'app basata sulla posizione di Alessandro e Giovanni.

**Ultima: V10**
- Avvisi a chi è in zona: quando arriva una domanda o notizia, la notifica va a chi è vicino (entro il raggio scelto da chi chiede e da chi riceve), a chi segue quella zona e agli amici; non più a tutti. Il database tiene solo la zona di ognuno (~100 m) in una tabella che nessuno può leggere; si spegne da Profilo → Notifiche.
- Foto nelle risposte: chi è sul posto risponde con la prova.
- Zone seguite (fino a 10): casa, lavoro, il tuo paese; dal Profilo o dalla ricerca ("Segui questa zona"). Cerchi tratteggiati sulla mappa e filtro "Le mie zone" nel feed.
- Gruppi veri nel database: crea, unisciti, discussioni e risposte con foto, avvisi ai membri, chi crea il gruppo può togliere i messaggi. Tre gruppi di partenza.

V09:
- Posizione per gli amici accesa di default (è il senso dell'app): si spegne in un tocco da Profilo → "Posizione per gli amici", e al benvenuto c'è già l'interruttore. Precisione esatta o zona ~1 km. Si aggiorna da sola mentre l'app è aperta.
- Foto nelle domande e notizie (ridotta a 1280 px prima del caricamento, bucket `post-photos`).
- Pulsante "Condividi" in ogni conversazione: link che apre direttamente quella domanda.
- Filtri rapidi sulla mappa: Tutto, Urgenti, Amici.

V08:
- Profilo di ogni persona apribile toccando foto o nome (statistiche, amicizia, domande attive).
- Posizione condivisa con gli amici: solo se la attivi tu, solo con gli amici, con precisione (esatta o zona ~1 km) e durata (1 ora, 8 ore, finché la spegni). Pin degli amici sulla mappa e fila "Amici sulla mappa"; live se aggiornata negli ultimi 5 minuti, altrimenti ultima posizione.
- Usabilità: pannello in basso che scorre tutto insieme e si allarga, risposta fissa in fondo alla conversazione, ricerca delle persone.
- Benvenuto: nome vuoto e nome utente suggerito dalla parte prima della @.

V07:
- Al primo accesso ognuno sceglie nome e nome utente unico (@nome), con controllo in tempo reale; foto facoltativa. Nome e nome utente si cambiano dal Profilo.
- Registrazione aperta ai tester (interruttore `open_signup` in `app_settings`).

V06:
- Nuova grafica: mappa a tutto schermo, barra di ricerca, pin "a segnale" colorati per urgenza che pulsano quando la notizia è fresca, tema scuro automatico, barra laterale su computer e iPad.
- Foto profilo (ritagliata e ridotta prima del caricamento) e nome modificabile.
- "Confermo" e "Risolto" su domande e notizie, con avviso a chi le ha pubblicate; un post è risolto se lo dice l'autore o almeno due persone.
- Urgenza dalla categoria: rosso emergenza, giallo viabilità e servizi, verde vita locale; filtro "Urgenti" nel feed.
- Scadenza fino a 48 ore; nuova icona dell'app.

V05: ricerca dei posti nel mondo, amicizie, avvisi e notifiche push (su iPhone: Condividi → "Aggiungi alla schermata Home", poi Profilo → Notifiche sul telefono → Attiva).

Prova: https://alessandroea.github.io/app-locale-prototipo/
Versioni precedenti: [/v09/](https://alessandroea.github.io/app-locale-prototipo/v09/) · [/v08/](https://alessandroea.github.io/app-locale-prototipo/v08/) · [/v07/](https://alessandroea.github.io/app-locale-prototipo/v07/) · [/v06/](https://alessandroea.github.io/app-locale-prototipo/v06/) · [/v05/](https://alessandroea.github.io/app-locale-prototipo/v05/) · [/v04/](https://alessandroea.github.io/app-locale-prototipo/v04/) · [/v03/](https://alessandroea.github.io/app-locale-prototipo/v03/)

## Database (Supabase)

- Progetto `app-locale` nell'organizzazione "Local Intelligence", regione Francoforte (UE), piano gratuito.
- `supabase/01_schema.sql`: tabelle, PostGIS, regole di accesso (RLS) e funzioni.
- `supabase/02_seed_demo.sql`: membri ammessi e dati di esempio di V03 (Richmond).
- `supabase/03_v05_amici_notifiche.sql`: amicizie, avvisi, telefoni per le push, trigger.
- `supabase/04_v06_foto_conferme.sql`: foto profilo (bucket avatars), Confermo/Risolto, avvisi relativi.
- `supabase/05_registrazione_aperta.sql`: registrazione aperta con interruttore.
- `supabase/06_v07_nome_utente.sql`: nome utente unico.
- `supabase/07_v08_posizione_amici.sql`: posizione condivisa solo con gli amici, statistiche del profilo.
- `supabase/08_v09_posizione_default.sql`: posizione per gli amici accesa di default, spegnibile dal profilo.
- `supabase/09_v09_foto_post.sql`: foto nelle domande e notizie (bucket `post-photos`).
- `supabase/10_v10_zone_gruppi.sql`: avvisi a chi è in zona, zone seguite, foto nelle risposte, gruppi.
- `supabase/functions/send-push`: funzione che manda le notifiche push; le chiavi VAPID sono nel Vault di Supabase.
- Possono entrare solo le email nella tabella `members`. Per aggiungere una persona:
  `insert into public.members (email, name, color) values ('email@esempio.com', 'Nome', '#8e4ec6');`
- Privacy: le coordinate di un post libero sono arrotondate a ~100 m; di chi risponde si salva solo la distanza dal posto.
- La chiave nel codice è quella pubblica (publishable): i dati sono protetti dalle regole RLS.
