-- Chepia Learning · perfiles enriquecidos
-- Guarda email separado de display_name, agrega avatar/provider/locale,
-- y mantiene los datos sincronizados cuando el usuario actualiza su sesión.
--
-- Correr en SQL Editor de Supabase.

alter table public.profiles
  add column if not exists email text,
  add column if not exists full_name text,
  add column if not exists given_name text,
  add column if not exists family_name text,
  add column if not exists avatar_url text,
  add column if not exists provider text,
  add column if not exists email_verified boolean default false,
  add column if not exists locale text,
  add column if not exists last_sign_in_at timestamptz;

-- Trigger que ejecuta al insertarse un nuevo usuario en auth.users.
-- Extrae email + metadatos de Google/Apple/email-password.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  app_meta jsonb := coalesce(new.raw_app_meta_data, '{}'::jsonb);
  v_full_name text := nullif(meta->>'full_name', '');
  v_name text := nullif(meta->>'name', '');
  v_given text := nullif(meta->>'given_name', '');
  v_family text := nullif(meta->>'family_name', '');
  v_avatar text := coalesce(nullif(meta->>'avatar_url', ''), nullif(meta->>'picture', ''));
  v_locale text := nullif(meta->>'locale', '');
  v_provider text := coalesce(nullif(app_meta->>'provider', ''), 'email');
  v_email_verified boolean := coalesce((meta->>'email_verified')::boolean, false);
  v_resolved_full_name text := coalesce(v_full_name, v_name);
  v_display text := coalesce(v_resolved_full_name, new.email);
begin
  insert into public.profiles (
    id, email, full_name, given_name, family_name,
    avatar_url, provider, email_verified, locale,
    display_name, last_sign_in_at
  )
  values (
    new.id, new.email, v_resolved_full_name, v_given, v_family,
    v_avatar, v_provider, v_email_verified, v_locale,
    v_display, new.last_sign_in_at
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    given_name = coalesce(excluded.given_name, public.profiles.given_name),
    family_name = coalesce(excluded.family_name, public.profiles.family_name),
    avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url),
    provider = coalesce(excluded.provider, public.profiles.provider),
    email_verified = excluded.email_verified,
    locale = coalesce(excluded.locale, public.profiles.locale),
    display_name = coalesce(public.profiles.display_name, excluded.display_name),
    last_sign_in_at = excluded.last_sign_in_at,
    updated_at = now();
  return new;
end;
$$;

-- Trigger que mantiene perfil sincronizado en cada login subsecuente.
-- auth.users se actualiza al refrescarse la sesión y trae avatar/last_sign_in_at frescos.
create or replace function public.handle_user_updated()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  app_meta jsonb := coalesce(new.raw_app_meta_data, '{}'::jsonb);
  v_full_name text := coalesce(nullif(meta->>'full_name', ''), nullif(meta->>'name', ''));
  v_avatar text := coalesce(nullif(meta->>'avatar_url', ''), nullif(meta->>'picture', ''));
  v_provider text := coalesce(nullif(app_meta->>'provider', ''), 'email');
  v_email_verified boolean := coalesce((meta->>'email_verified')::boolean, false);
  v_locale text := nullif(meta->>'locale', '');
  v_given text := nullif(meta->>'given_name', '');
  v_family text := nullif(meta->>'family_name', '');
begin
  update public.profiles
  set
    email = new.email,
    full_name = coalesce(v_full_name, public.profiles.full_name),
    given_name = coalesce(v_given, public.profiles.given_name),
    family_name = coalesce(v_family, public.profiles.family_name),
    avatar_url = coalesce(v_avatar, public.profiles.avatar_url),
    provider = coalesce(v_provider, public.profiles.provider),
    email_verified = v_email_verified,
    locale = coalesce(v_locale, public.profiles.locale),
    last_sign_in_at = coalesce(new.last_sign_in_at, public.profiles.last_sign_in_at),
    updated_at = now()
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update on auth.users
  for each row execute function public.handle_user_updated();

-- Backfill de usuarios existentes: copia email + metadatos a profiles.
-- Sólo rellena campos vacíos para no sobreescribir display_name personalizados.
update public.profiles p
set
  email = coalesce(p.email, u.email),
  full_name = coalesce(
    p.full_name,
    nullif(u.raw_user_meta_data->>'full_name', ''),
    nullif(u.raw_user_meta_data->>'name', '')
  ),
  given_name = coalesce(p.given_name, nullif(u.raw_user_meta_data->>'given_name', '')),
  family_name = coalesce(p.family_name, nullif(u.raw_user_meta_data->>'family_name', '')),
  avatar_url = coalesce(
    p.avatar_url,
    nullif(u.raw_user_meta_data->>'avatar_url', ''),
    nullif(u.raw_user_meta_data->>'picture', '')
  ),
  provider = coalesce(p.provider, nullif(u.raw_app_meta_data->>'provider', ''), 'email'),
  email_verified = coalesce(
    p.email_verified,
    (u.raw_user_meta_data->>'email_verified')::boolean,
    false
  ),
  locale = coalesce(p.locale, nullif(u.raw_user_meta_data->>'locale', '')),
  last_sign_in_at = coalesce(p.last_sign_in_at, u.last_sign_in_at)
from auth.users u
where u.id = p.id;
