-- App Locale – V07 – nome utente unico (@nome), scelto da ogni persona al primo accesso
create extension if not exists citext with schema extensions;
alter table public.profiles add column if not exists username extensions.citext;
alter table public.profiles add column if not exists onboarded_at timestamptz;
alter table public.profiles add constraint profiles_username_format check (username is null or username ~ '^[a-z0-9._]{3,20}$');
create unique index if not exists profiles_username_uq on public.profiles (username);
revoke update on public.profiles from authenticated, anon;
grant update (display_name, color, avatar_url, username, onboarded_at) on public.profiles to authenticated;

create or replace function public.username_available(p_username text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_member()
     and lower(p_username) ~ '^[a-z0-9._]{3,20}$'
     and not exists (select 1 from public.profiles where username = lower(p_username)::extensions.citext and id <> auth.uid());
$$;
revoke execute on function public.username_available(text) from public, anon;
grant execute on function public.username_available(text) to authenticated;
