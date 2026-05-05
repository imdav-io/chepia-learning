-- Vocabulario curado por lección (catálogo, generado por IA o curado a mano).
-- Read-only para usuarios autenticados; lo alimentamos via service role desde
-- scripts/quiz_generator/generate-vocabulary.mjs.

create table if not exists public.lesson_vocabulary (
  id uuid primary key default uuid_generate_v4(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  term text not null,
  meaning_es text not null,
  example_en text,
  pronunciation text,
  sort_order int not null default 0,
  generated_by_ai boolean not null default false,
  ai_model text,
  ai_generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lesson_vocabulary_term_not_blank check (length(trim(term)) > 0),
  constraint lesson_vocabulary_meaning_not_blank check (length(trim(meaning_es)) > 0),
  constraint lesson_vocabulary_unique_term unique (lesson_id, term)
);

create index if not exists lesson_vocabulary_lesson_idx
  on public.lesson_vocabulary (lesson_id, sort_order);

alter table public.lesson_vocabulary enable row level security;

drop policy if exists "auth read lesson vocabulary" on public.lesson_vocabulary;
create policy "auth read lesson vocabulary" on public.lesson_vocabulary
  for select to authenticated using (true);
