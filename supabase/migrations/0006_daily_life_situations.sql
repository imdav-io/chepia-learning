-- Situaciones de vida diaria: expresiones naturales por contexto.
-- Contenido read-only para usuarios autenticados; se alimenta con
-- scripts/quiz_generator/generate-situations.mjs usando service role.

create table if not exists public.daily_life_situations (
  id uuid primary key default uuid_generate_v4(),
  slug text not null unique,
  title_es text not null,
  title_en text not null,
  description_es text,
  level_band text not null default 'A2-B1',
  icon text not null default 'chat',
  sort_order int not null default 0,
  generated_by_ai boolean not null default false,
  ai_model text,
  ai_generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_life_situations_slug_not_blank check (length(trim(slug)) > 0),
  constraint daily_life_situations_title_es_not_blank check (length(trim(title_es)) > 0),
  constraint daily_life_situations_title_en_not_blank check (length(trim(title_en)) > 0)
);

create table if not exists public.daily_life_expressions (
  id uuid primary key default uuid_generate_v4(),
  situation_id uuid not null references public.daily_life_situations(id) on delete cascade,
  phrase_en text not null,
  meaning_es text not null,
  when_to_use_es text,
  tone text not null default 'neutral',
  example_en text,
  pronunciation text,
  variants jsonb not null default '[]'::jsonb,
  dialogue jsonb not null default '[]'::jsonb,
  sort_order int not null default 0,
  generated_by_ai boolean not null default false,
  ai_model text,
  ai_generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_life_expressions_phrase_not_blank check (length(trim(phrase_en)) > 0),
  constraint daily_life_expressions_meaning_not_blank check (length(trim(meaning_es)) > 0),
  constraint daily_life_expressions_unique_phrase unique (situation_id, phrase_en)
);

create table if not exists public.daily_life_practice_questions (
  id uuid primary key default uuid_generate_v4(),
  situation_id uuid not null references public.daily_life_situations(id) on delete cascade,
  prompt text not null,
  explanation_es text,
  sort_order int not null default 0,
  generated_by_ai boolean not null default false,
  ai_model text,
  ai_generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_life_practice_prompt_not_blank check (length(trim(prompt)) > 0)
);

create table if not exists public.daily_life_practice_options (
  id uuid primary key default uuid_generate_v4(),
  question_id uuid not null references public.daily_life_practice_questions(id) on delete cascade,
  text text not null,
  is_correct boolean not null default false,
  sort_order int not null default 0,
  constraint daily_life_practice_option_not_blank check (length(trim(text)) > 0)
);

create index if not exists daily_life_situations_sort_idx
  on public.daily_life_situations (sort_order, title_es);

create index if not exists daily_life_expressions_situation_idx
  on public.daily_life_expressions (situation_id, sort_order);

create index if not exists daily_life_practice_questions_situation_idx
  on public.daily_life_practice_questions (situation_id, sort_order);

create index if not exists daily_life_practice_options_question_idx
  on public.daily_life_practice_options (question_id, sort_order);

alter table public.daily_life_situations enable row level security;
alter table public.daily_life_expressions enable row level security;
alter table public.daily_life_practice_questions enable row level security;
alter table public.daily_life_practice_options enable row level security;

drop policy if exists "auth read daily life situations" on public.daily_life_situations;
create policy "auth read daily life situations" on public.daily_life_situations
  for select to authenticated using (true);

drop policy if exists "auth read daily life expressions" on public.daily_life_expressions;
create policy "auth read daily life expressions" on public.daily_life_expressions
  for select to authenticated using (true);

drop policy if exists "auth read daily life practice questions" on public.daily_life_practice_questions;
create policy "auth read daily life practice questions" on public.daily_life_practice_questions
  for select to authenticated using (true);

drop policy if exists "auth read daily life practice options" on public.daily_life_practice_options;
create policy "auth read daily life practice options" on public.daily_life_practice_options
  for select to authenticated using (true);
