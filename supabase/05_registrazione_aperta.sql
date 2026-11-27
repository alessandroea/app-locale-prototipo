-- App Locale – registrazione aperta ai tester (richiesta di Alessandro, 27/11/2026)
-- Con open_signup = true ogni nuovo account (email confermata o Google) diventa membro da solo.
-- Per richiudere:  update public.app_settings set value = 'false'::jsonb, updated_at = now() where key = 'open_signup';
-- Per togliere l'accesso a una persona:  delete from public.members where email = 'email@esempio.com';
create table if not exists public.app_settings (
  key   text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
insert into public.app_settings (key, value) values ('open_signup', 'true'::jsonb)
on conflict (key) do update set value = excluded.value, updated_at = now();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare m public.members%rowtype; v_open boolean; v_name text;
begin
  select coalesce((select value::text::boolean from public.app_settings where key = 'open_signup'), false) into v_open;
  v_name := coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), nullif(trim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email, '@', 1));
  if v_open and new.email is not null then
    insert into public.members (email, name, color)
    values (lower(new.email), left(v_name, 40), (array['#3150F5','#1F9D63','#E08A00','#8E4EC6','#E5484D','#12A594'])[1 + floor(random() * 6)::int])
    on conflict (email) do nothing;
  end if;
  select * into m from public.members where lower(email) = lower(new.email);
  insert into public.profiles (id, display_name, color)
  values (new.id, left(coalesce(m.name, v_name), 40), coalesce(m.color, '#3150F5'))
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
