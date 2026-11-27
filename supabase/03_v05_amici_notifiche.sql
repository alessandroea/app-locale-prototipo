-- App Locale – V05 – amicizie, avvisi salvati nel database e notifiche push
-- Le chiavi delle notifiche push sono nel Vault di Supabase (non in questo file).

create extension if not exists pg_net with schema extensions;

-- ---------- amicizie ----------
create table public.friendships (
  id           bigint generated always as identity primary key,
  requester_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending','accepted')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);
create unique index friendships_pair_uq on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_addressee_idx on public.friendships (addressee_id);
alter table public.friendships enable row level security;

create policy "vedo le mie amicizie" on public.friendships for select to authenticated
  using ((select public.is_member()) and (requester_id = (select auth.uid()) or addressee_id = (select auth.uid())));
create policy "chiedo l'amicizia" on public.friendships for insert to authenticated
  with check ((select public.is_member()) and requester_id = (select auth.uid()) and status = 'pending');
create policy "accetto l'amicizia" on public.friendships for update to authenticated
  using ((select public.is_member()) and addressee_id = (select auth.uid()))
  with check (addressee_id = (select auth.uid()) and status = 'accepted');
create policy "tolgo l'amicizia" on public.friendships for delete to authenticated
  using ((select public.is_member()) and (requester_id = (select auth.uid()) or addressee_id = (select auth.uid())));
revoke update on public.friendships from authenticated, anon;
grant update (status, responded_at) on public.friendships to authenticated;

-- ---------- avvisi (sezione Attività) ----------
create table public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  actor_id   uuid references public.profiles(id) on delete set null,
  kind       text not null check (kind in ('answer','answer_also','best','friend_request','friend_accept','post_new')),
  post_id    uuid references public.posts(id) on delete cascade,
  body       text not null,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_actor_idx on public.notifications (actor_id);
create index notifications_post_idx on public.notifications (post_id);
alter table public.notifications enable row level security;

create policy "leggo i miei avvisi" on public.notifications for select to authenticated
  using ((select public.is_member()) and user_id = (select auth.uid()));
create policy "segno letti i miei avvisi" on public.notifications for update to authenticated
  using ((select public.is_member()) and user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "cancello i miei avvisi" on public.notifications for delete to authenticated
  using ((select public.is_member()) and user_id = (select auth.uid()));
revoke insert, update on public.notifications from authenticated, anon;
grant update (read_at) on public.notifications to authenticated;

-- ---------- telefoni registrati per le notifiche push ----------
create table public.push_subscriptions (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  endpoint   text not null unique,
  p256dh     text not null,
  auth       text not null,
  user_agent text,
  created_at timestamptz not null default now()
);
create index push_subscriptions_user_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;
create policy "vedo i miei telefoni" on public.push_subscriptions for select to authenticated
  using ((select public.is_member()) and user_id = (select auth.uid()));
create policy "tolgo i miei telefoni" on public.push_subscriptions for delete to authenticated
  using ((select public.is_member()) and user_id = (select auth.uid()));

create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(p_user_agent, 200))
  on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
    user_agent = excluded.user_agent, created_at = now();
end;
$$;

-- chiave pubblica per iscriversi alle push (non segreta)
create or replace function public.push_public_key()
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public' and public.is_member();
$$;

-- ---------- creazione degli avvisi ----------
create or replace function public.notify(p_user uuid, p_actor uuid, p_kind text, p_post uuid, p_body text)
returns void language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, actor_id, kind, post_id, body)
  select p_user, p_actor, p_kind, p_post, p_body
  where p_user is not null and p_user is distinct from p_actor;
$$;

create or replace function public.trg_answer_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_post public.posts%rowtype; v_name text; v_q text; r record;
begin
  if new.is_demo or new.author_id is null then return new; end if;
  select * into v_post from public.posts where id = new.post_id;
  select display_name into v_name from public.profiles where id = new.author_id;
  v_q := left(v_post.body, 60) || case when char_length(v_post.body) > 60 then '…' else '' end;
  -- a chi ha fatto la domanda
  perform public.notify(v_post.author_id, new.author_id, 'answer', v_post.id,
    coalesce(v_name, 'Qualcuno') || ' ha risposto alla tua domanda: “' || v_q || '”');
  -- a chi aveva già risposto alla stessa domanda
  for r in select distinct a.author_id from public.answers a
           where a.post_id = new.post_id and a.author_id is not null and a.id <> new.id
             and a.author_id <> new.author_id and a.author_id is distinct from v_post.author_id loop
    perform public.notify(r.author_id, new.author_id, 'answer_also', v_post.id,
      coalesce(v_name, 'Qualcuno') || ' ha risposto anche a: “' || v_q || '”');
  end loop;
  return new;
end;
$$;
create trigger answers_notify after insert on public.answers for each row execute function public.trg_answer_notify();

create or replace function public.trg_post_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text; r record;
begin
  if new.is_demo or new.author_id is null then return new; end if;
  select display_name into v_name from public.profiles where id = new.author_id;
  -- per ora siete in pochi: ogni nuova domanda o notizia avvisa tutti gli altri membri
  for r in select p.id from public.profiles p join auth.users u on u.id = p.id
           join public.members m on lower(m.email) = lower(u.email) where p.id <> new.author_id loop
    perform public.notify(r.id, new.author_id, 'post_new', new.id,
      coalesce(v_name, 'Qualcuno') || case when new.kind = 'n' then ' ha pubblicato una notizia' else ' ha chiesto' end
      || ' su ' || new.place_label || ': “' || left(new.body, 60) || case when char_length(new.body) > 60 then '…' else '' end || '”');
  end loop;
  return new;
end;
$$;
create trigger posts_notify after insert on public.posts for each row execute function public.trg_post_notify();

create or replace function public.trg_best_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_author uuid; v_name text;
begin
  if new.best_answer_id is null or new.best_answer_id is not distinct from old.best_answer_id then return new; end if;
  select author_id into v_author from public.answers where id = new.best_answer_id;
  select display_name into v_name from public.profiles where id = new.author_id;
  perform public.notify(v_author, new.author_id, 'best', new.id,
    coalesce(v_name, 'Qualcuno') || ' ha scelto la tua risposta come migliore: +15 punti');
  return new;
end;
$$;
create trigger posts_best_notify after update of best_answer_id on public.posts for each row execute function public.trg_best_notify();

create or replace function public.trg_friend_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text;
begin
  if tg_op = 'INSERT' then
    select display_name into v_name from public.profiles where id = new.requester_id;
    perform public.notify(new.addressee_id, new.requester_id, 'friend_request', null,
      coalesce(v_name, 'Qualcuno') || ' vuole essere tuo amico');
  elsif new.status = 'accepted' and old.status <> 'accepted' then
    select display_name into v_name from public.profiles where id = new.addressee_id;
    perform public.notify(new.requester_id, new.addressee_id, 'friend_accept', null,
      coalesce(v_name, 'Qualcuno') || ' ha accettato la tua richiesta di amicizia');
  end if;
  return new;
end;
$$;
create trigger friendships_notify after insert or update of status on public.friendships for each row execute function public.trg_friend_notify();

-- ---------- invio push: ogni nuovo avviso chiama la funzione send-push ----------
create or replace function public.trg_push_send()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_secret text;
begin
  if not exists (select 1 from public.push_subscriptions where user_id = new.user_id) then return new; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_secret';
  perform net.http_post(
    url := 'https://tigxpqmedwlwthomvunb.supabase.co/functions/v1/send-push',
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 10000);
  return new;
end;
$$;
create trigger notifications_push after insert on public.notifications for each row execute function public.trg_push_send();

-- ---------- permessi delle funzioni ----------
revoke execute on function public.notify(uuid,uuid,text,uuid,text), public.trg_answer_notify(), public.trg_post_notify(),
  public.trg_best_notify(), public.trg_friend_notify(), public.trg_push_send() from public, anon, authenticated;
revoke execute on function public.save_push_subscription(text,text,text,text), public.push_public_key() from public, anon;
grant execute on function public.save_push_subscription(text,text,text,text), public.push_public_key() to authenticated;

-- ---------- tempo reale ----------
alter publication supabase_realtime add table public.friendships, public.notifications;
