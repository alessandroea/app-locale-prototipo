-- App Locale – V06 – foto profilo, nome modificabile, "Confermo" / "Risolto"

-- ---------- foto profilo ----------
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add constraint profiles_name_len check (char_length(trim(display_name)) between 1 and 40);
-- dal profilo si cambiano solo nome, colore e foto
revoke update on public.profiles from authenticated, anon;
grant update (display_name, color, avatar_url) on public.profiles to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- ogni membro scrive solo nella propria cartella avatars/<id utente>/...
create policy "carico la mia foto" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_member()));
create policy "sostituisco la mia foto" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_member()));
create policy "cancello la mia foto" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_member()));

-- ---------- Confermo / Risolto ----------
create table public.post_reactions (
  post_id    uuid not null references public.posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  kind       text not null check (kind in ('confirm', 'resolved')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id, kind)
);
create index post_reactions_user_idx on public.post_reactions (user_id);
alter table public.post_reactions enable row level security;
create policy "membri leggono le conferme" on public.post_reactions for select to authenticated using ((select public.is_member()));
create policy "confermo" on public.post_reactions for insert to authenticated
  with check ((select public.is_member()) and user_id = (select auth.uid()));
create policy "tolgo la mia conferma" on public.post_reactions for delete to authenticated
  using ((select public.is_member()) and user_id = (select auth.uid()));

-- conferme di esempio sui post demo (non sono utenti veri)
alter table public.posts add column if not exists base_confirms int not null default 0;
update public.posts set base_confirms = case kind when 'n' then 2 + (base_votes % 4) else base_votes % 3 end where is_demo;

-- ---------- avvisi per Confermo / Risolto ----------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('answer','answer_also','best','friend_request','friend_accept','post_new','confirm','resolved'));

create or replace function public.trg_reaction_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_post public.posts%rowtype; v_name text; v_q text;
begin
  select * into v_post from public.posts where id = new.post_id;
  if v_post.author_id is null then return new; end if;
  select display_name into v_name from public.profiles where id = new.user_id;
  v_q := left(v_post.body, 60) || case when char_length(v_post.body) > 60 then '…' else '' end;
  perform public.notify(v_post.author_id, new.user_id, new.kind, v_post.id,
    coalesce(v_name, 'Qualcuno') || case new.kind when 'confirm' then ' conferma: “' else ' dice che è risolto: “' end || v_q || '”');
  return new;
end;
$$;
create trigger post_reactions_notify after insert on public.post_reactions for each row execute function public.trg_reaction_notify();
revoke execute on function public.trg_reaction_notify() from public, anon, authenticated;

alter publication supabase_realtime add table public.post_reactions;

-- le modifiche ai profili (nome, foto) arrivano in tempo reale
alter publication supabase_realtime add table public.profiles;
