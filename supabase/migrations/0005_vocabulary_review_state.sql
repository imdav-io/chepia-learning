-- Estado de repaso espaciado para vocabulario guardado por usuario.

alter table public.user_vocabulary
  add column if not exists review_state text not null default 'new',
  add column if not exists review_count int not null default 0,
  add column if not exists interval_days int not null default 0,
  add column if not exists due_at timestamptz not null default now(),
  add column if not exists last_reviewed_at timestamptz;

alter table public.user_vocabulary
  drop constraint if exists user_vocabulary_review_state_check;

alter table public.user_vocabulary
  add constraint user_vocabulary_review_state_check
  check (review_state in ('new', 'learning', 'mastered'));

create index if not exists user_vocabulary_due_idx
  on public.user_vocabulary (user_id, due_at, review_state);
