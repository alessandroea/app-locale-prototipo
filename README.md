# App Locale – prototipo

Prototipo web dell'app basata sulla posizione di Alessandro e Giovanni.

**Ultima: V05**
- Ricerca dei posti in tutto il mondo (OpenStreetMap): cerchi "Bergamo" o "Trescore Balneario" e puoi fare una domanda su quel posto anche se non sei lì.
- Amicizie salvate nel database: richiesta, accetta, rimuovi; filtro "Amici" nel feed.
- Avvisi salvati nel database (sezione Attività): risposte alle tue domande, risposte dove hai risposto anche tu, nuove domande, risposta migliore, amicizie.
- Notifiche push sul telefono (anche ad app chiusa). Su iPhone: Condividi → "Aggiungi alla schermata Home", apri l'app dall'icona, accedi, Profilo → Notifiche sul telefono → Attiva.

Prova: https://alessandroea.github.io/app-locale-prototipo/
Versioni precedenti: [/v04/](https://alessandroea.github.io/app-locale-prototipo/v04/) · [/v03/](https://alessandroea.github.io/app-locale-prototipo/v03/)

## Database (Supabase)

- Progetto `app-locale` nell'organizzazione "Local Intelligence", regione Francoforte (UE), piano gratuito.
- `supabase/01_schema.sql`: tabelle, PostGIS, regole di accesso (RLS) e funzioni.
- `supabase/02_seed_demo.sql`: membri ammessi e dati di esempio di V03 (Richmond).
- `supabase/03_v05_amici_notifiche.sql`: amicizie, avvisi, telefoni per le push, trigger.
- `supabase/functions/send-push`: funzione che manda le notifiche push; le chiavi VAPID sono nel Vault di Supabase.
- Possono entrare solo le email nella tabella `members`. Per aggiungere una persona:
  `insert into public.members (email, name, color) values ('email@esempio.com', 'Nome', '#8e4ec6');`
- Privacy: le coordinate di un post libero sono arrotondate a ~100 m; di chi risponde si salva solo la distanza dal posto.
- La chiave nel codice è quella pubblica (publishable): i dati sono protetti dalle regole RLS.
