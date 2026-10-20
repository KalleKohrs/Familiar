-- 0006_avatars_storage
-- Privater Storage-Bucket „avatars“ für Profilbilder.
--
-- Genau ein Bild pro Person unter {user_id}/avatar.jpg; ein neues Bild überschreibt das alte
-- (Upload mit upsert braucht laut Supabase-Doku INSERT, SELECT und UPDATE).
-- Lesen: eigenes Bild und Bilder von Personen aus gemeinsamen Familien; angezeigt wird über
-- signierte URLs. Kein Löschen durch Clients: „Bild entfernen“ setzt nur
-- profiles.avatar_path = null (update_profile); die Datei räumt später die Kontolöschung auf.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 1048576, array['image/jpeg']);

create policy avatars_select_own_and_co_members
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (storage.foldername(name))[1] = any (array (select m::text from private.co_member_ids() as m))
    )
  );

create policy avatars_insert_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and name = (select auth.uid())::text || '/avatar.jpg'
  );

create policy avatars_update_own
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and name = (select auth.uid())::text || '/avatar.jpg'
  )
  with check (
    bucket_id = 'avatars'
    and name = (select auth.uid())::text || '/avatar.jpg'
  );
