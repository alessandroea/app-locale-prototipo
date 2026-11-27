-- App Locale – V10 (2026-11-27)
-- 1. Avvisi a chi è in zona  2. Foto nelle risposte  3. Zone seguite  4. Gruppi veri
-- Già applicata sul progetto Supabase "app-locale" (migrazione v10_zone_gruppi).

-- ---------- 1. Avvisi a chi è in zona ----------
alter table public.profiles
  add column if not exists alerts_nearby boolean not null default true,
  add column if not exists alert_radius_m int not null default 1000 check (alert_radius_m between 300 and 10000);
grant update (alerts_nearby, alert_radius_m) on public.profiles to authenticated;

-- Ultima zona della persona, usata SOLO dal database per mandare gli avvisi.
-- Nessuno la può leggere (nemmeno gli amici): niente policy, solo funzioni del server.
create table if not exists public.alert_positions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  location extensions.geography(point, 4326) not null,
  updated_at timestamptz not null default now()
);
create index if not exists alert_positions_gix on public.alert_positions using gist (location);
alter table public.alert_positions enable row level security;
revoke all on public.alert_positions from anon, authenticated;

create or replace function public.set_alert_position(p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  if not coalesce((select alerts_nearby from public.profiles where id = auth.uid()), true) then
    delete from public.alert_positions where user_id = auth.uid();
    return;
  end if;
  insert into public.alert_positions (user_id, location, updated_at)
  values (auth.uid(),
          extensions.st_setsrid(extensions.st_makepoint(round(p_lng::numeric, 3)::float8, round(p_lat::numeric, 3)::float8), 4326)::extensions.geography,
          now())
  on conflict (user_id) do update set location = excluded.location, updated_at = excluded.updated_at;
end $$;

create or replace function public.clear_alert_position()
returns void language sql security definer set search_path = '' as $$
  delete from public.alert_positions where user_id = auth.uid();
$$;

revoke execute on function public.set_alert_position(double precision, double precision) from public, anon;
revoke execute on function public.clear_alert_position() from public, anon;
grant execute on function public.set_alert_position(double precision, double precision) to authenticated;
grant execute on function public.clear_alert_position() to authenticated;

-- ---------- 3. Zone seguite ----------
create table if not exists public.followed_zones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  radius_m int not null default 2000 check (radius_m between 300 and 20000),
  location extensions.geography(point, 4326)
    generated always as (extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography) stored,
  created_at timestamptz not null default now()
);
create index if not exists followed_zones_user_idx on public.followed_zones (user_id);
create index if not exists followed_zones_gix on public.followed_zones using gist (location);
alter table public.followed_zones enable row level security;
create policy "vedo le mie zone" on public.followed_zones for select to authenticated
  using (user_id = (select auth.uid()) and (select public.is_member()));
create policy "aggiungo le mie zone" on public.followed_zones for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.is_member()));
create policy "modifico le mie zone" on public.followed_zones for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "tolgo le mie zone" on public.followed_zones for delete to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.trg_zone_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.followed_zones where user_id = new.user_id) >= 10 then
    raise exception 'Puoi seguire al massimo 10 zone';
  end if;
  return new;
end $$;
create trigger followed_zones_limit before insert on public.followed_zones
  for each row execute function public.trg_zone_limit();

-- ---------- 2. Foto nelle risposte ----------
alter table public.answers add column if not exists photo_url text;
drop function if exists public.add_answer(uuid, text, double precision, double precision);
create or replace function public.add_answer(p_post_id uuid, p_body text, p_lat double precision, p_lng double precision,
                                             p_photo_url text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_dist int; v_id uuid;
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  if p_photo_url is not null and p_photo_url not like
     'https://tigxpqmedwlwthomvunb.supabase.co/storage/v1/object/public/post-photos/' || auth.uid()::text || '/%' then
    raise exception 'Foto non valida';
  end if;
  if p_lat is not null and p_lng is not null then
    select round(extensions.st_distance(p.location,
             extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography))::int
      into v_dist from public.posts p where p.id = p_post_id;
  end if;
  insert into public.answers (post_id, body, distance_m, author_id, photo_url)
  values (p_post_id, trim(p_body), v_dist, auth.uid(), p_photo_url)
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.add_answer(uuid, text, double precision, double precision, text) from public, anon;
grant execute on function public.add_answer(uuid, text, double precision, double precision, text) to authenticated;

-- ---------- 4. Gruppi veri ----------
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 3 and 50),
  description text not null default '' check (char_length(description) <= 200),
  color text not null default '#2f6fe4' check (color ~ '^#[0-9a-fA-F]{6}$'),
  place_label text check (char_length(place_label) <= 80),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists groups_name_uidx on public.groups (lower(trim(name)));

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists group_members_user_idx on public.group_members (user_id);

create table if not exists public.group_posts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  parent_id uuid references public.group_posts(id) on delete cascade,  -- null = discussione, altrimenti risposta
  author_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 500),
  photo_url text,
  created_at timestamptz not null default now()
);
create index if not exists group_posts_group_idx on public.group_posts (group_id, created_at desc);
create index if not exists group_posts_parent_idx on public.group_posts (parent_id);
create index if not exists group_posts_author_idx on public.group_posts (author_id);

create or replace function public.is_group_member(p_group uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_members where group_id = p_group and user_id = auth.uid());
$$;
create or replace function public.is_group_owner(p_group uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_members where group_id = p_group and user_id = auth.uid() and role = 'owner');
$$;
revoke execute on function public.is_group_member(uuid) from public, anon;
revoke execute on function public.is_group_owner(uuid) from public, anon;
grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_owner(uuid) to authenticated;

alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_posts enable row level security;

-- I gruppi sono aperti: tutti i membri dell'app li vedono e li leggono; per scrivere bisogna unirsi.
create policy "membri vedono i gruppi" on public.groups for select to authenticated using ((select public.is_member()));
create policy "chi crea modifica il gruppo" on public.groups for update to authenticated
  using ((select public.is_group_owner(id))) with check ((select public.is_group_owner(id)));
create policy "chi crea elimina il gruppo" on public.groups for delete to authenticated
  using ((select public.is_group_owner(id)));
revoke insert on public.groups from authenticated, anon;   -- si crea solo con create_group()
revoke update on public.groups from authenticated, anon;
grant update (name, description, color, place_label) on public.groups to authenticated;

create policy "membri vedono chi è nei gruppi" on public.group_members for select to authenticated using ((select public.is_member()));
create policy "mi unisco a un gruppo" on public.group_members for insert to authenticated
  with check (user_id = (select auth.uid()) and role = 'member' and (select public.is_member()));
create policy "esco da un gruppo" on public.group_members for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.is_group_owner(group_id)));
revoke update on public.group_members from authenticated, anon;

create policy "membri leggono i gruppi" on public.group_posts for select to authenticated using ((select public.is_member()));
create policy "scrivo nei miei gruppi" on public.group_posts for insert to authenticated
  with check (author_id = (select auth.uid()) and (select public.is_member()) and public.is_group_member(group_id)
    and (photo_url is null or photo_url like
      'https://tigxpqmedwlwthomvunb.supabase.co/storage/v1/object/public/post-photos/' || (select auth.uid())::text || '/%'));
create policy "elimino i miei post o modero il mio gruppo" on public.group_posts for delete to authenticated
  using (author_id = (select auth.uid()) or (select public.is_group_owner(group_id)));
revoke update on public.group_posts from authenticated, anon;

create or replace function public.create_group(p_name text, p_description text, p_color text, p_place_label text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  if (select count(*) from public.groups where created_by = auth.uid()) >= 10 then
    raise exception 'Puoi creare al massimo 10 gruppi';
  end if;
  if exists (select 1 from public.groups where lower(trim(name)) = lower(trim(p_name))) then
    raise exception 'Esiste già un gruppo con questo nome';
  end if;
  insert into public.groups (name, description, color, place_label, created_by)
  values (trim(p_name), coalesce(trim(p_description), ''), coalesce(p_color, '#2f6fe4'), nullif(trim(p_place_label), ''), auth.uid())
  returning id into v_id;
  insert into public.group_members (group_id, user_id, role) values (v_id, auth.uid(), 'owner');
  return v_id;
end $$;
revoke execute on function public.create_group(text, text, text, text) from public, anon;
grant execute on function public.create_group(text, text, text, text) to authenticated;

-- ---------- Avvisi ----------
alter table public.notifications add column if not exists group_id uuid references public.groups(id) on delete cascade;
create index if not exists notifications_group_idx on public.notifications (group_id);
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in (
  'answer', 'answer_also', 'best', 'friend_request', 'friend_accept', 'post_new', 'confirm', 'resolved',
  'nearby', 'zone', 'group_post', 'group_reply'));

-- Nuova domanda o notizia: avviso a chi è vicino (entro il raggio scelto da chi chiede E da chi riceve,
-- posizione degli ultimi 3 giorni), a chi segue quella zona e agli amici. Una sola notifica a persona.
-- Prima (V05–V09) l'avviso arrivava a tutti i membri.
create or replace function public.trg_post_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text; v_text text; r record;
begin
  if new.is_demo or new.author_id is null then return new; end if;
  select display_name into v_name from public.profiles where id = new.author_id;
  v_text := '“' || left(new.body, 60) || case when char_length(new.body) > 60 then '…' else '' end || '”';
  for r in
    with membri as (
      select p.id, p.alerts_nearby, p.alert_radius_m from public.profiles p
      join auth.users u on u.id = p.id
      join public.members m on lower(m.email) = lower(u.email)
      where p.id <> new.author_id
    ), cand as (
      select m.id, 1 as pri, 'nearby' as kind, null::text as zone,
             round(extensions.st_distance(a.location, new.location))::int as d
      from membri m join public.alert_positions a on a.user_id = m.id
      where m.alerts_nearby and a.updated_at > now() - interval '3 days'
        and extensions.st_dwithin(a.location, new.location, least(new.radius_m, m.alert_radius_m))
      union all
      select z.user_id, 2, 'zone', z.name, null
      from public.followed_zones z join membri m on m.id = z.user_id
      where extensions.st_dwithin(z.location, new.location, z.radius_m)
      union all
      select m.id, 3, 'post_new', null, null
      from membri m where public.are_friends(new.author_id, m.id)
    )
    select distinct on (id) id, kind, zone, d from cand order by id, pri, zone
  loop
    perform public.notify(r.id, new.author_id, r.kind, new.id,
      case r.kind
        when 'nearby' then case when new.kind = 'n' then 'Notizia' else 'Domanda' end
             || ' vicino a te (' || case when r.d < 1000 then r.d || ' m' else round(r.d / 1000.0, 1) || ' km' end || '), '
             || coalesce(v_name, 'qualcuno') || ' su ' || new.place_label || ': ' || v_text
        when 'zone' then 'Novità in ' || r.zone || ': ' || coalesce(v_name, 'qualcuno')
             || case when new.kind = 'n' then ' ha pubblicato una notizia' else ' chiede' end || ' su ' || new.place_label || ': ' || v_text
        else coalesce(v_name, 'Qualcuno') || case when new.kind = 'n' then ' ha pubblicato una notizia' else ' ha chiesto' end
             || ' su ' || new.place_label || ': ' || v_text
      end);
  end loop;
  return new;
end $$;

create or replace function public.trg_group_post_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text; v_group text; v_parent public.group_posts%rowtype; v_text text; r record;
begin
  select display_name into v_name from public.profiles where id = new.author_id;
  select name into v_group from public.groups where id = new.group_id;
  v_text := '“' || left(new.body, 60) || case when char_length(new.body) > 60 then '…' else '' end || '”';
  if new.parent_id is null then
    for r in select user_id from public.group_members where group_id = new.group_id and user_id <> new.author_id loop
      insert into public.notifications (user_id, actor_id, kind, group_id, body)
      values (r.user_id, new.author_id, 'group_post', new.group_id,
              coalesce(v_name, 'Qualcuno') || ' in ' || v_group || ': ' || v_text);
    end loop;
  else
    select * into v_parent from public.group_posts where id = new.parent_id;
    for r in select distinct x.uid from (
               select v_parent.author_id as uid
               union select author_id from public.group_posts where parent_id = new.parent_id) x
             where x.uid is not null and x.uid <> new.author_id loop
      insert into public.notifications (user_id, actor_id, kind, group_id, body)
      values (r.uid, new.author_id, 'group_reply', new.group_id,
              coalesce(v_name, 'Qualcuno') || ' ha risposto in ' || v_group || ': ' || v_text);
    end loop;
  end if;
  return new;
end $$;
create trigger group_posts_notify after insert on public.group_posts
  for each row execute function public.trg_group_post_notify();

revoke execute on function public.trg_group_post_notify() from public, anon, authenticated;
revoke execute on function public.trg_zone_limit() from public, anon, authenticated;

-- Aggiornamenti in tempo reale
alter publication supabase_realtime add table public.groups, public.group_members, public.group_posts;

-- Tre gruppi di partenza (vuoti, senza proprietario)
insert into public.groups (name, description, color, place_label) values
  ('Richmond e dintorni', 'Cosa succede tra Richmond, Kew, Twickenham e Putney: consigli, eventi, novità.', '#30a46c', 'Richmond, Londra'),
  ('Italiani a Londra', 'Consigli, ritrovi ed eventi per italiani a Londra.', '#2f6fe4', 'Londra'),
  ('Bergamo e provincia', 'Traffico, eventi e novità tra Bergamo e la provincia.', '#e5484d', 'Bergamo')
on conflict do nothing;
