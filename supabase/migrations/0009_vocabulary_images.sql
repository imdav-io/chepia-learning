-- Imágenes para vocabulario curado.
-- Se llenan opcionalmente desde scripts/quiz_generator/generate-vocab-images.mjs
-- usando OpenAI Images / Pexels y guardando la URL pública (CDN o Supabase Storage).

alter table public.lesson_vocabulary
  add column if not exists image_url text,
  add column if not exists image_alt text;

-- También sumamos image_url al vocabulario personal del usuario, por si la
-- pantalla de flashcards quiere mostrar imágenes en términos guardados.
alter table public.user_vocabulary
  add column if not exists image_url text;
