// App Locale – V05 – funzione send-push
// Chiamata dal database (trigger su public.notifications) per ogni nuovo avviso.
// Legge chiavi e telefoni registrati direttamente dal database e manda la notifica push (Web Push).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import webpush from "npm:web-push@3.6.7";
import postgres from "npm:postgres@3.4.5";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { prepare: false, max: 1 });

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const secrets = await sql<{ name: string; decrypted_secret: string }[]>`
    select name, decrypted_secret from vault.decrypted_secrets
    where name in ('push_secret', 'vapid_public', 'vapid_private', 'vapid_subject')`;
  const s = Object.fromEntries(secrets.map((r) => [r.name, r.decrypted_secret]));
  if (!s.push_secret || req.headers.get("x-push-secret") !== s.push_secret) return json({ error: "forbidden" }, 403);

  const { notification_id } = await req.json().catch(() => ({}));
  if (!notification_id) return json({ error: "notification_id mancante" }, 400);

  const [n] = await sql<{ user_id: string; body: string; post_id: string | null; kind: string }[]>`
    select user_id, body, post_id, kind from public.notifications where id = ${notification_id}`;
  if (!n) return json({ error: "avviso non trovato" }, 404);

  const subs = await sql<{ id: number; endpoint: string; p256dh: string; auth: string }[]>`
    select id, endpoint, p256dh, auth from public.push_subscriptions where user_id = ${n.user_id}`;

  const [{ unread }] = await sql<{ unread: number }[]>`
    select count(*)::int as unread from public.notifications where user_id = ${n.user_id} and read_at is null`;

  webpush.setVapidDetails(s.vapid_subject, s.vapid_public, s.vapid_private);
  const url = n.post_id ? `./#post=${n.post_id}` : n.kind.startsWith("friend") ? "./#tab=me" : "./#tab=act";
  const payload = JSON.stringify({ title: "App Locale", body: n.body, url, tag: `n${notification_id}`, badge: unread });

  let sent = 0;
  const gone: number[] = [];
  for (const sub of subs) {
    try {
      await webpush.sendNotification({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } }, payload, {
        TTL: 3600,
        urgency: "high",
      });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) gone.push(sub.id); // telefono non più registrato
      console.error("push non inviata", code, (e as Error).message);
    }
  }
  if (gone.length) await sql`delete from public.push_subscriptions where id in ${sql(gone)}`;
  return json({ sent, removed: gone.length });
});
