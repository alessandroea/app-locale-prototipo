-- App Locale – V04 – schema database (Supabase / Postgres + PostGIS)
-- Accesso privato: solo le email in public.members vedono e scrivono i dati.

create extension if not exists postgis with schema extensions;

-- ---------- membri ammessi (sezione privata) ----------
create table public.members (
  email      text primary key,
  name       text not null,
  color      text not null default '#14202b',
  created_at timestamptz not null default now()
);
alter table public.members enable row level security;
-- nessuna policy: la tabella non è leggibile dalle app

create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.members m
    where lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- ---------- profili ----------
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  color        text not null default '#14202b',
  created_at   timestamptz not null default now()
);
alter table public.profiles enable row level security;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare m public.members%rowtype;
begin
  select * into m from public.members where lower(email) = lower(new.email);
  insert into public.profiles (id, display_name, color)
  values (
    new.id,
    coalesce(m.name, new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    coalesce(m.color, '#14202b')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- luoghi ----------
create table public.places (
  id         text primary key,
  name       text not null,
  category   text not null,
  lat        double precision not null,
  lng        double precision not null,
  location   extensions.geography(Point, 4326)
             generated always as (extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography) stored,
  info       jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index places_location_idx on public.places using gist (location);
alter table public.places enable row level security;

-- ---------- stato live dei luoghi ----------
create table public.place_reports (
  id              bigint generated always as identity primary key,
  place_id        text not null references public.places(id) on delete cascade,
  author_id       uuid references public.profiles(id) on delete set null default auth.uid(),
  status          text not null check (status in ('tranquillo','affollato','coda','evento','ritardi','chiuso')),
  is_demo         boolean not null default false,
  demo_offset_min int,
  created_at      timestamptz not null default now()
);
create index place_reports_place_idx on public.place_reports (place_id, created_at desc);
alter table public.place_reports enable row level security;

-- ---------- domande e notizie ----------
create table public.posts (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null check (kind in ('q','n')),           -- q = domanda, n = notizia
  category        text not null default 'info',
  place_id        text references public.places(id) on delete set null,
  place_label     text not null,
  lat             double precision not null,                          -- mai la posizione esatta: arrotondata a ~100 m
  lng             double precision not null,
  location        extensions.geography(Point, 4326)
                  generated always as (extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography) stored,
  radius_m        int not null default 1000 check (radius_m between 100 and 50000),
  body            text not null check (char_length(body) between 1 and 280),
  author_id       uuid references public.profiles(id) on delete cascade default auth.uid(),
  demo_author     text,                                               -- utenti di esempio (Giulia R., Mark TW10…)
  is_demo         boolean not null default false,
  demo_offset_min int,                                                -- i dati demo restano sempre "live"
  base_votes      int not null default 0,
  best_answer_id  uuid,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  check (author_id is not null or is_demo)
);
create index posts_location_idx on public.posts using gist (location);
create index posts_expires_idx on public.posts (expires_at);
create index posts_author_idx on public.posts (author_id);
create index posts_place_idx on public.posts (place_id);
alter table public.posts enable row level security;

-- ---------- risposte ----------
create table public.answers (
  id              uuid primary key default gen_random_uuid(),
  post_id         uuid not null references public.posts(id) on delete cascade,
  body            text not null check (char_length(body) between 1 and 280),
  distance_m      int,                                                -- distanza dal posto, la posizione non viene salvata
  author_id       uuid references public.profiles(id) on delete cascade default auth.uid(),
  demo_author     text,
  is_demo         boolean not null default false,
  demo_offset_min int,
  base_votes      int not null default 0,
  created_at      timestamptz not null default now(),
  check (author_id is not null or is_demo)
);
create index answers_post_idx on public.answers (post_id);
create index answers_author_idx on public.answers (author_id);
alter table public.answers enable row level security;

alter table public.posts
  add constraint posts_best_answer_fk foreign key (best_answer_id) references public.answers(id) on delete set null;
create index posts_best_answer_idx on public.posts (best_answer_id);

-- ---------- voti "Utile" ----------
create table public.votes (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  post_id    uuid references public.posts(id) on delete cascade,
  answer_id  uuid references public.answers(id) on delete cascade,
  created_at timestamptz not null default now(),
  check ((post_id is null) <> (answer_id is null))
);
create unique index votes_post_uq   on public.votes (user_id, post_id)   where post_id is not null;
create unique index votes_answer_uq on public.votes (user_id, answer_id) where answer_id is not null;
create index votes_answer_idx on public.votes (answer_id);
create index votes_post_idx on public.votes (post_id);
create index place_reports_author_idx on public.place_reports (author_id);
alter table public.votes enable row level security;

-- ---------- regole di accesso (RLS) ----------
create policy "membri leggono i profili" on public.profiles for select to authenticated using ((select public.is_member()));
create policy "aggiorno il mio profilo"  on public.profiles for update to authenticated
  using (id = (select auth.uid()) and (select public.is_member())) with check (id = (select auth.uid()));

create policy "membri leggono i luoghi" on public.places for select to authenticated using ((select public.is_member()));

create policy "membri leggono lo stato" on public.place_reports for select to authenticated using ((select public.is_member()));
create policy "membri segnalano lo stato" on public.place_reports for insert to authenticated
  with check ((select public.is_member()) and author_id = (select auth.uid()) and not is_demo);

create policy "membri leggono i post" on public.posts for select to authenticated using ((select public.is_member()));
create policy "elimino i miei post"   on public.posts for delete to authenticated
  using (author_id = (select auth.uid()) and (select public.is_member()));

create policy "membri leggono le risposte" on public.answers for select to authenticated using ((select public.is_member()));
create policy "elimino le mie risposte"    on public.answers for delete to authenticated
  using (author_id = (select auth.uid()) and (select public.is_member()));

create policy "membri leggono i voti" on public.votes for select to authenticated using ((select public.is_member()));
create policy "voto"                  on public.votes for insert to authenticated
  with check ((select public.is_member()) and user_id = (select auth.uid()));
create policy "tolgo il mio voto"     on public.votes for delete to authenticated
  using (user_id = (select auth.uid()) and (select public.is_member()));

-- ---------- funzioni per l'app ----------
-- Nuova domanda/notizia: se è su un luogo usa le sue coordinate, altrimenti arrotonda a ~100 m.
create or replace function public.create_post(
  p_kind text, p_category text, p_place_id text, p_place_label text,
  p_lat double precision, p_lng double precision, p_radius_m int, p_hours int, p_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_lat double precision; v_lng double precision; v_label text; v_id uuid;
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  if p_place_id is not null then
    select lat, lng, name into v_lat, v_lng, v_label from public.places where id = p_place_id;
    if v_lat is null then raise exception 'Luogo sconosciuto'; end if;
  else
    if p_lat is null or p_lng is null then raise exception 'Serve la posizione'; end if;
    v_lat := round(p_lat::numeric, 3); v_lng := round(p_lng::numeric, 3); v_label := p_place_label;
  end if;
  insert into public.posts (kind, category, place_id, place_label, lat, lng, radius_m, body, author_id, expires_at)
  values (p_kind, coalesce(p_category, 'info'), p_place_id, coalesce(v_label, 'Posizione'), v_lat, v_lng,
          coalesce(p_radius_m, 1000), trim(p_body), auth.uid(),
          now() + make_interval(hours => least(greatest(coalesce(p_hours, 3), 1), 48)))
  returning id into v_id;
  return v_id;
end;
$$;

-- Nuova risposta: calcola la distanza dal posto lato server, senza salvare la posizione di chi risponde.
create or replace function public.add_answer(p_post_id uuid, p_body text, p_lat double precision, p_lng double precision)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_dist int; v_id uuid;
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  if p_lat is not null and p_lng is not null then
    select round(extensions.st_distance(p.location,
             extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography))::int
      into v_dist from public.posts p where p.id = p_post_id;
  end if;
  insert into public.answers (post_id, body, distance_m, author_id)
  values (p_post_id, trim(p_body), v_dist, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- Risposta migliore: solo chi ha fatto la domanda.
create or replace function public.set_best_answer(p_post_id uuid, p_answer_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  update public.posts set best_answer_id = p_answer_id
   where id = p_post_id and author_id = auth.uid()
     and exists (select 1 from public.answers a where a.id = p_answer_id and a.post_id = p_post_id);
  if not found then raise exception 'Solo chi ha fatto la domanda può scegliere la risposta migliore'; end if;
end;
$$;

-- Domande attive vicino a un punto (per la versione successiva e per l'app iPhone).
create or replace function public.nearby_posts(p_lat double precision, p_lng double precision, p_radius_m int default 5000)
returns table (id uuid, distance_m int)
language sql stable security definer set search_path = '' as $$
  select p.id,
         round(extensions.st_distance(p.location, extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography))::int
    from public.posts p
   where public.is_member()
     and (p.is_demo or p.expires_at > now())
     and extensions.st_dwithin(p.location, extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography, p_radius_m)
   order by 2;
$$;

revoke execute on function public.is_member(), public.create_post(text,text,text,text,double precision,double precision,int,int,text),
  public.add_answer(uuid,text,double precision,double precision), public.set_best_answer(uuid,uuid),
  public.nearby_posts(double precision,double precision,int), public.handle_new_user() from public, anon;
grant execute on function public.is_member(), public.create_post(text,text,text,text,double precision,double precision,int,int,text),
  public.add_answer(uuid,text,double precision,double precision), public.set_best_answer(uuid,uuid),
  public.nearby_posts(double precision,double precision,int) to authenticated;

-- ---------- tempo reale ----------
alter publication supabase_realtime add table public.posts, public.answers, public.votes, public.place_reports;

-- la funzione dei nuovi utenti è solo per il trigger
revoke execute on function public.handle_new_user() from authenticated;
