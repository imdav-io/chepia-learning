-- Permite a cualquier usuario autenticado leer objetos del bucket "content"
-- (incluye crear signed URLs). Sin esta policy, Supabase Storage responde
-- "Object not found" aunque el archivo exista.
--
-- Las escrituras quedan limitadas al service_role (lo usa upload-content.mjs).

drop policy if exists "auth read content" on storage.objects;

create policy "auth read content"
on storage.objects
for select
to authenticated
using (bucket_id = 'content');
