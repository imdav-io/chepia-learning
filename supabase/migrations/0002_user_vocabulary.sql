-- Vocabulario guardado por usuario.

create table if not exists public.user_vocabulary (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  book_id uuid not null references public.books(id) on delete cascade,
  lesson_id uuid references public.lessons(id) on delete cascade,
  term text not null,
  normalized_term text not null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_vocabulary_term_not_blank check (length(trim(term)) > 0),
  constraint user_vocabulary_unique_term unique (
    user_id,
    book_id,
    lesson_id,
    normalized_term
  )
);

create index if not exists user_vocabulary_user_book_idx
  on public.user_vocabulary (user_id, book_id, updated_at desc);

create index if not exists user_vocabulary_user_lesson_idx
  on public.user_vocabulary (user_id, lesson_id, updated_at desc);

alter table public.user_vocabulary enable row level security;

drop policy if exists "own vocabulary" on public.user_vocabulary;
create policy "own vocabulary" on public.user_vocabulary
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
