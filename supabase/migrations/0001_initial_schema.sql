-- Chepia Learning · schema inicial
-- Correr en SQL Editor de Supabase (proyecto > SQL Editor > New query > pegar > Run).

-- =========================================================
-- Extensiones útiles
-- =========================================================
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
-- create extension if not exists vector; -- futuro: RAG con pgvector

-- =========================================================
-- Perfiles (sobre auth.users)
-- =========================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  preferred_language text default 'es' check (preferred_language in ('es','en')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =========================================================
-- Catálogo
-- =========================================================
create table if not exists public.levels (
  id uuid primary key default uuid_generate_v4(),
  code text unique not null check (code in ('beginner','intermediate','advanced')),
  name text not null,
  sort_order int not null
);

insert into public.levels (code, name, sort_order)
values
  ('beginner','Beginner',1),
  ('intermediate','Intermediate',2),
  ('advanced','Advanced',3)
on conflict (code) do nothing;

create table if not exists public.books (
  id uuid primary key default uuid_generate_v4(),
  level_id uuid references public.levels(id) on delete restrict,
  title text not null,
  slug text unique not null,
  cover_url text,
  description text,
  language text default 'en',
  sort_order int default 1,
  created_at timestamptz default now()
);

create table if not exists public.lessons (
  id uuid primary key default uuid_generate_v4(),
  book_id uuid references public.books(id) on delete cascade,
  number int not null,
  title text not null,
  pdf_start_page int,
  pdf_end_page int,
  created_at timestamptz default now(),
  unique (book_id, number)
);

create table if not exists public.assets (
  id uuid primary key default uuid_generate_v4(),
  lesson_id uuid references public.lessons(id) on delete cascade,
  book_id uuid references public.books(id) on delete cascade,
  kind text not null check (kind in ('pdf','audio','study_guide')),
  storage_path text not null,
  mime_type text,
  size_bytes bigint,
  duration_sec int,
  pages int,
  version int not null default 1,
  content_hash text,
  created_at timestamptz default now()
);

-- =========================================================
-- Progreso del usuario
-- =========================================================
create table if not exists public.reading_progress (
  user_id uuid references public.profiles(id) on delete cascade,
  lesson_id uuid references public.lessons(id) on delete cascade,
  last_page int default 1,
  is_completed boolean default false,
  updated_at timestamptz default now(),
  primary key (user_id, lesson_id)
);

create table if not exists public.audio_progress (
  user_id uuid references public.profiles(id) on delete cascade,
  lesson_id uuid references public.lessons(id) on delete cascade,
  last_position_sec int default 0,
  is_completed boolean default false,
  updated_at timestamptz default now(),
  primary key (user_id, lesson_id)
);

-- =========================================================
-- Quizzes
-- =========================================================
create table if not exists public.quizzes (
  id uuid primary key default uuid_generate_v4(),
  lesson_id uuid references public.lessons(id) on delete cascade,
  kind text not null check (kind in ('lesson','review_5')),
  passing_score int default 70,
  generated_by_ai boolean default false,
  ai_model text,
  ai_generated_at timestamptz,
  created_at timestamptz default now()
);

create table if not exists public.questions (
  id uuid primary key default uuid_generate_v4(),
  quiz_id uuid references public.quizzes(id) on delete cascade,
  prompt text not null,
  kind text not null check (kind in ('multiple_choice','true_false','fill_blank','listening')),
  audio_asset_id uuid references public.assets(id),
  explanation text,
  sort_order int default 0
);

create table if not exists public.options (
  id uuid primary key default uuid_generate_v4(),
  question_id uuid references public.questions(id) on delete cascade,
  text text not null,
  is_correct boolean not null default false,
  sort_order int default 0
);

create table if not exists public.quiz_attempts (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id) on delete cascade,
  quiz_id uuid references public.quizzes(id) on delete cascade,
  score int default 0,
  total int default 0,
  passed boolean default false,
  started_at timestamptz default now(),
  finished_at timestamptz
);

create table if not exists public.quiz_answers (
  attempt_id uuid references public.quiz_attempts(id) on delete cascade,
  question_id uuid references public.questions(id),
  option_id uuid references public.options(id),
  text_answer text,
  is_correct boolean default false,
  primary key (attempt_id, question_id)
);

-- =========================================================
-- Streaks (futuro)
-- =========================================================
create table if not exists public.user_streaks (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  current_days int default 0,
  longest_days int default 0,
  last_activity_at date
);

-- =========================================================
-- Row Level Security
-- =========================================================
alter table public.profiles enable row level security;
alter table public.reading_progress enable row level security;
alter table public.audio_progress enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.quiz_answers enable row level security;
alter table public.user_streaks enable row level security;

-- Catálogo: lectura pública para usuarios autenticados.
alter table public.levels enable row level security;
alter table public.books enable row level security;
alter table public.lessons enable row level security;
alter table public.assets enable row level security;
alter table public.quizzes enable row level security;
alter table public.questions enable row level security;
alter table public.options enable row level security;

create policy "auth read levels" on public.levels for select to authenticated using (true);
create policy "auth read books" on public.books for select to authenticated using (true);
create policy "auth read lessons" on public.lessons for select to authenticated using (true);
create policy "auth read assets" on public.assets for select to authenticated using (true);
create policy "auth read quizzes" on public.quizzes for select to authenticated using (true);
create policy "auth read questions" on public.questions for select to authenticated using (true);
create policy "auth read options" on public.options for select to authenticated using (true);

-- Profiles: cada usuario su propio registro.
create policy "own profile read" on public.profiles for select using (auth.uid() = id);
create policy "own profile update" on public.profiles for update using (auth.uid() = id);

-- Reading/audio progress: cada usuario lo suyo.
create policy "own reading progress" on public.reading_progress for all using (auth.uid() = user_id);
create policy "own audio progress" on public.audio_progress for all using (auth.uid() = user_id);
create policy "own quiz attempts" on public.quiz_attempts for all using (auth.uid() = user_id);
create policy "own quiz answers" on public.quiz_answers for all using (
  exists (select 1 from public.quiz_attempts qa where qa.id = attempt_id and qa.user_id = auth.uid())
);
create policy "own streaks" on public.user_streaks for all using (auth.uid() = user_id);

-- =========================================================
-- Storage bucket privado: 'content' (crear desde dashboard o API)
-- =========================================================
-- Crear bucket "content" como privado y aplicar políticas:
-- 1. Allow SELECT to authenticated (servirá vía signed URLs).
-- 2. Disallow INSERT/UPDATE/DELETE excepto al service_role (lo subes tú).

-- Si prefieres SQL, puedes agregar después algo como:
-- insert into storage.buckets (id, name, public) values ('content','content', false)
-- on conflict (id) do nothing;
