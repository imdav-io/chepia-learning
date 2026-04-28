-- Seed de demo para validar el flujo end-to-end ANTES de subir tu contenido real.
-- Apunta a un PDF y un audio públicos. Cuando uses upload-content.mjs,
-- cambia las URLs en `assets` por los `storage_path` reales en el bucket "content".
--
-- Correr en SQL Editor de Supabase tras la migración 0001.

-- 3 libros (uno por nivel)
insert into public.books (slug, level_id, title, description, language, sort_order, cover_url)
select 'as-it-is-book-1', l.id, 'As it is — Book 1', 'Curso básico de inglés.', 'en', 1, null
from public.levels l where l.code = 'beginner'
on conflict (slug) do nothing;

insert into public.books (slug, level_id, title, description, language, sort_order, cover_url)
select 'as-it-is-book-2', l.id, 'As it is — Book 2', 'Curso intermedio de inglés.', 'en', 1, null
from public.levels l where l.code = 'intermediate'
on conflict (slug) do nothing;

insert into public.books (slug, level_id, title, description, language, sort_order, cover_url)
select 'as-it-is-book-3', l.id, 'As it is — Book 3', 'Curso avanzado de inglés.', 'en', 1, null
from public.levels l where l.code = 'advanced'
on conflict (slug) do nothing;

-- 5 lecciones del Book 1 para validar el flujo
insert into public.lessons (book_id, number, title, pdf_start_page, pdf_end_page)
select b.id, n, 'Lesson ' || n, (n - 1) * 8 + 1, n * 8
from public.books b, generate_series(1, 5) as n
where b.slug = 'as-it-is-book-1'
on conflict (book_id, number) do nothing;

-- Assets DEMO: usa un PDF público y un audio público para validar UX.
-- Reemplaza estos `storage_path` por los reales (ej: 'books/as-it-is-book-1/audio/v1/lesson_1.mp3')
-- cuando subas con upload-content.mjs.
do $$
declare
  l_id uuid;
  b_id uuid;
begin
  select b.id into b_id from public.books b where b.slug = 'as-it-is-book-1';

  -- PDF del libro (un solo asset por libro)
  insert into public.assets (book_id, kind, storage_path, mime_type, version, pages)
  values (b_id, 'pdf', 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf', 'application/pdf', 1, null)
  on conflict do nothing;

  -- Audio por lección (lecciones 1..5)
  for n in 1..5 loop
    select id into l_id from public.lessons where book_id = b_id and number = n;
    insert into public.assets (lesson_id, book_id, kind, storage_path, mime_type, duration_sec, version)
    values (l_id, b_id, 'audio',
            'https://www.kozco.com/tech/piano2-CoolEdit.mp3', -- demo audio público
            'audio/mpeg', 60, 1)
    on conflict do nothing;
  end loop;
end $$;
