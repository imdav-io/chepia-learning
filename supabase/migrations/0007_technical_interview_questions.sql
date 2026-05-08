-- Preguntas y respuestas técnicas para preparación de entrevistas en inglés.
-- Complementa daily_life_situations sin mezclarlo con expresiones cotidianas.

alter table public.daily_life_situations
  add column if not exists content_kind text not null default 'expressions';

alter table public.daily_life_situations
  drop constraint if exists daily_life_situations_content_kind_check;

alter table public.daily_life_situations
  add constraint daily_life_situations_content_kind_check
  check (content_kind in ('expressions', 'technical_interview'));

create table if not exists public.technical_interview_questions (
  id uuid primary key default uuid_generate_v4(),
  situation_id uuid not null references public.daily_life_situations(id) on delete cascade,
  question_en text not null,
  answer_en text not null,
  answer_es text,
  sample_answer_en text,
  category text,
  difficulty text not null default 'mid',
  key_points jsonb not null default '[]'::jsonb,
  follow_up_questions jsonb not null default '[]'::jsonb,
  common_mistakes jsonb not null default '[]'::jsonb,
  tags jsonb not null default '[]'::jsonb,
  sort_order int not null default 0,
  generated_by_ai boolean not null default false,
  ai_model text,
  ai_generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint technical_interview_question_not_blank check (length(trim(question_en)) > 0),
  constraint technical_interview_answer_not_blank check (length(trim(answer_en)) > 0),
  constraint technical_interview_unique_question unique (situation_id, question_en)
);

alter table public.technical_interview_questions
  drop constraint if exists technical_interview_difficulty_check;

alter table public.technical_interview_questions
  add constraint technical_interview_difficulty_check
  check (difficulty in ('junior', 'mid', 'senior'));

create index if not exists technical_interview_questions_situation_idx
  on public.technical_interview_questions (situation_id, sort_order);

alter table public.technical_interview_questions enable row level security;

drop policy if exists "auth read technical interview questions" on public.technical_interview_questions;
create policy "auth read technical interview questions" on public.technical_interview_questions
  for select to authenticated using (true);
