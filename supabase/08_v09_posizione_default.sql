-- App Locale – V09 (richiesta di Alessandro): posizione per gli amici attiva di default; ognuno può spegnerla dal Profilo.
-- Resta visibile solo agli amici (regole di public.locations invariate).
alter table public.profiles add column if not exists share_location boolean not null default true;
alter table public.profiles add column if not exists share_precision text not null default 'exact';
alter table public.profiles add constraint profiles_share_precision_chk check (share_precision in ('exact', 'area'));
revoke update on public.profiles from authenticated, anon;
grant update (display_name, color, avatar_url, username, onboarded_at, share_location, share_precision) on public.profiles to authenticated;
