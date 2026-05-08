-- Cached OpenAI TTS audio for curated lesson vocabulary.
-- Audio is generated once by the vocabulary-tts Edge Function, stored in a
-- private Supabase Storage bucket, and reused through signed URLs.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'vocab-audio',
  'vocab-audio',
  false,
  5242880,
  array['audio/mpeg']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "auth read vocab audio" on storage.objects;

create policy "auth read vocab audio"
on storage.objects
for select
to authenticated
using (bucket_id = 'vocab-audio');

alter table public.lesson_vocabulary
  add column if not exists audio_storage_path text,
  add column if not exists audio_model text,
  add column if not exists audio_voice text,
  add column if not exists audio_generated_at timestamptz;

create index if not exists lesson_vocabulary_audio_storage_path_idx
  on public.lesson_vocabulary (audio_storage_path)
  where audio_storage_path is not null;
