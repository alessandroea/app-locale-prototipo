# App Locale – prototipo

Prototipo web dell'app basata sulla posizione di Alessandro e Giovanni.

**Ultima: V07**
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
Versioni precedenti: [/v06/](https://alessandroea.github.io/app-locale-prototipo/v06/) · [/v05/](https://alessandroea.github.io/app-locale-prototipo/v05/) · [/v04/](https://alessandroea.github.io/app-locale-prototipo/v04/) · [/v03/](https://alessandroea.github.io/app-locale-prototipo/v03/)

## Database (Supabase)

- Progetto `app-locale` nell'organizzazione "Local Intelligence", regione Francoforte (UE), piano gratuito.
- `supabase/01_schema.sql`: tabelle, PostGIS, regole di accesso (RLS) e funzioni.
- `supabase/02_seed_demo.sql`: membri ammessi e dati di esempio di V03 (Richmond).
- `supabase/03_v05_amici_notifiche.sql`: amicizie, avvisi, telefoni per le push, trigger.
- `supabase/04_v06_foto_conferme.sql`: foto profilo (bucket avatars), Confermo/Risolto, avvisi relativi.
- `supabase/05_registrazione_aperta.sql`: registrazione aperta con interruttore.
- `supabase/06_v07_nome_utente.sql`: nome utente unico.
- `supabase/functions/send-push`: funzione che manda le notifiche push; le chiavi VAPID sono nel Vault di Supabase.
- Possono entrare solo le email nella tabella `members`. Per aggiungere una persona:
  `insert into public.members (email, name, color) values ('email@esempio.com', 'Nome', '#8e4ec6');`
- Privacy: le coordinate di un post libero sono arrotondate a ~100 m; di chi risponde si salva solo la distanza dal posto.
- La chiave nel codice è quella pubblica (publishable): i dati sono protetti dalle regole RLS.
