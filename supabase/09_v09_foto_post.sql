-- V09 (2026-11-27): foto nelle domande e notizie
-- Già applicata sul progetto Supabase "app-locale" (migrazione v09_foto_post).
alter table public.posts add column if not exists photo_url text;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('post-photos','post-photos',true,4194304,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- ognuno carica e cancella solo nella propria cartella (post-photos/<id utente>/...)
create policy "carico foto dei miei post" on storage.objects for insert to authenticated
  with check (bucket_id='post-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and (select public.is_member()));
create policy "cancello foto dei miei post" on storage.objects for delete to authenticated
  using (bucket_id='post-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- create_post accetta ora p_photo_url (solo URL della propria cartella nel bucket post-photos)
drop function if exists public.create_post(text,text,text,text,double precision,double precision,int,int,text);
create or replace function public.create_post(p_kind text, p_category text, p_place_id text, p_place_label text, p_lat double precision, p_lng double precision, p_radius_m integer, p_hours integer, p_body text, p_photo_url text default null)
 returns uuid language plpgsql security definer set search_path to ''
as $function$
declare v_lat double precision; v_lng double precision; v_label text; v_id uuid;
begin
  if not public.is_member() then raise exception 'Accesso non autorizzato'; end if;
  if p_photo_url is not null and p_photo_url not like
     'https://tigxpqmedwlwthomvunb.supabase.co/storage/v1/object/public/post-photos/' || auth.uid()::text || '/%' then
    raise exception 'Foto non valida';
  end if;
  if p_place_id is not null then
    select lat, lng, name into v_lat, v_lng, v_label from public.places where id = p_place_id;
    if v_lat is null then raise exception 'Luogo sconosciuto'; end if;
  else
    if p_lat is null or p_lng is null then raise exception 'Serve la posizione'; end if;
    v_lat := round(p_lat::numeric, 3); v_lng := round(p_lng::numeric, 3); v_label := p_place_label;
  end if;
  insert into public.posts (kind, category, place_id, place_label, lat, lng, radius_m, body, author_id, expires_at, photo_url)
  values (p_kind, coalesce(p_category, 'info'), p_place_id, coalesce(v_label, 'Posizione'), v_lat, v_lng,
          coalesce(p_radius_m, 1000), trim(p_body), auth.uid(),
          now() + make_interval(hours => least(greatest(coalesce(p_hours, 3), 1), 48)), p_photo_url)
  returning id into v_id;
  return v_id;
end;
$function$;
revoke execute on function public.create_post(text,text,text,text,double precision,double precision,int,int,text,text) from public, anon;
grant execute on function public.create_post(text,text,text,text,double precision,double precision,int,int,text,text) to authenticated;
