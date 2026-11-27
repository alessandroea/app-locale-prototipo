-- App Locale – V08 – posizione condivisa SOLO con gli amici, SOLO se la persona la attiva,
-- con durata (1 ora, 8 ore, finché non la spengo) e precisione (esatta o zona ~1 km) scelte da lei.
create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.friendships f where f.status = 'accepted'
    and ((f.requester_id = a and f.addressee_id = b) or (f.requester_id = b and f.addressee_id = a)));
$$;

create table public.locations (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  lat         double precision not null,
  lng         double precision not null,
  accuracy_m  int,
  precision   text not null default 'exact' check (precision in ('exact', 'area')),
  share_until timestamptz,             -- null = finché non la spengo
  updated_at  timestamptz not null default now()
);
alter table public.locations enable row level security;
create policy "posizione mia o di amici che la condividono" on public.locations for select to authenticated
  using ((select public.is_member()) and (
    user_id = (select auth.uid())
    or ((share_until is null or share_until > now()) and public.are_friends((select auth.uid()), user_id))
  ));
revoke insert, update, delete on public.locations from authenticated, anon;

create or replace function public.share_location(p_lat double precision, p_lng double precision, p_accuracy int,
  p_precision text, p_hours int)
returns void language plpgsql security definer set search_path = '' as $$
declare v_lat double precision := p_lat; v_lng double precision := p_lng; v_prec text := coalesce(p_precision, 'exact');
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  if v_prec not in ('exact', 'area') then v_prec := 'exact'; end if;
  if v_prec = 'area' then v_lat := round(p_lat::numeric, 2); v_lng := round(p_lng::numeric, 2); end if;
  insert into public.locations (user_id, lat, lng, accuracy_m, precision, share_until, updated_at)
  values (auth.uid(), v_lat, v_lng, case when v_prec = 'area' then 1000 else p_accuracy end, v_prec,
          case when p_hours is null or p_hours <= 0 then null else now() + make_interval(hours => least(p_hours, 168)) end, now())
  on conflict (user_id) do update set lat = excluded.lat, lng = excluded.lng, accuracy_m = excluded.accuracy_m,
    precision = excluded.precision, share_until = case when p_hours = -1 then public.locations.share_until else excluded.share_until end,
    updated_at = now();
end;
$$;

create or replace function public.stop_sharing_location()
returns void language sql security definer set search_path = '' as $$
  delete from public.locations where user_id = auth.uid();
$$;

create or replace function public.profile_stats(p_user uuid)
returns table (posts int, answers int, helpful int, best int, since timestamptz)
language sql stable security definer set search_path = '' as $$
  select
    (select count(*)::int from public.posts where author_id = p_user),
    (select count(*)::int from public.answers where author_id = p_user),
    (select count(*)::int from public.votes v join public.answers a on a.id = v.answer_id where a.author_id = p_user)
      + (select count(*)::int from public.votes v join public.posts p on p.id = v.post_id where p.author_id = p_user),
    (select count(*)::int from public.posts p join public.answers a on a.id = p.best_answer_id where a.author_id = p_user),
    (select created_at from public.profiles where id = p_user)
  where public.is_member();
$$;

revoke execute on function public.share_location(double precision, double precision, int, text, int),
  public.stop_sharing_location(), public.profile_stats(uuid), public.are_friends(uuid, uuid) from public, anon;
grant execute on function public.share_location(double precision, double precision, int, text, int),
  public.stop_sharing_location(), public.profile_stats(uuid), public.are_friends(uuid, uuid) to authenticated;

alter publication supabase_realtime add table public.locations;
