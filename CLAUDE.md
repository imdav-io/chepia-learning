# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Chepia Learning is a Flutter app for studying English with PDF books, per-lesson audio, synced progress and AI-generated quizzes backed by Supabase. README and onboarding docs (including code comments) are written in Spanish; keep new docs/UI strings consistent with that.

## Commands

Flutter app:

```bash
flutter pub get
flutter gen-l10n                                          # generate AppLocalizations from lib/l10n/*.arb
dart run build_runner build --delete-conflicting-outputs  # Riverpod, Freezed, json_serializable codegen
flutter analyze
flutter test
flutter test test/path/to/file_test.dart                  # single test file
flutter test --name "test name substring"                 # single test by name
flutter run -d chrome --web-port 5050                     # web dev (port matches Supabase OAuth allowlist)
flutter run                                               # iOS / Android
flutter build web --debug --no-wasm-dry-run               # CI-equivalent web build
dart format lib test
```

`.env` (loaded as a Flutter asset by `flutter_dotenv`) must exist before `flutter run` — CI copies `.env.example` to `.env`. The bundled assets list in [pubspec.yaml](pubspec.yaml) includes `.env`, so missing it breaks the build.

Content pipeline (`scripts/quiz_generator/`, Node 20+):

```bash
cd scripts/quiz_generator && npm install
node upload-content.mjs       # upload PDFs + MP3s to Supabase Storage bucket `content`
node register-content.mjs     # register books/lessons/assets rows in Postgres
node extract-pdf-text.mjs     # extract per-lesson text into out/
node generate.mjs             # AI quiz generation; idempotent (skips lessons that already have a quiz)
```

These scripts use a separate `.env` in `scripts/quiz_generator/` and require `SUPABASE_SERVICE_ROLE_KEY` (not anon). `AI_PROVIDER=gemini|claude` switches between `GEMINI_API_KEY` and `ANTHROPIC_API_KEY`.

Audio conversion (one-off): `CONTENT_DIR="/path/to/As it is" bash scripts/convert-audio.sh` (requires `ffmpeg`).

## Architecture

**Feature-first clean architecture under `lib/features/<feature>/{data,domain,presentation}`**: `data/` holds Supabase/Hive datasources, models and repository impls; `domain/` holds entities and abstract repositories; `presentation/` holds screens, widgets and Riverpod controllers. Features: `auth`, `catalog`, `lesson`, `progress`, `quiz`, `vocabulary`, `profile`, `onboarding`. Cross-cutting code lives in `lib/core/` (config, errors, logging, network, utils, widgets) and `lib/shared/` (theme, services like `asset_cache`, AI helpers, common widgets). App wiring (router, shell, MaterialApp) is in `lib/app/`.

**State + DI**: Riverpod 2 with `@riverpod` codegen — generators produce `*.g.dart` files, so re-run build_runner after editing providers. Domain entities are immutable, generally Freezed. The single root is `ProviderScope` in [lib/main.dart](lib/main.dart).

**Routing**: [lib/app/router.dart](lib/app/router.dart) defines a `goRouterProvider` whose redirect uses `authRepositoryProvider.currentUser` and a refresh notifier wired to `authRepo.authStateChanges()`. A `StatefulShellRoute.indexedStack` powers bottom nav (Learn / Progress / Profile) so each tab keeps its own navigator stack. Full-screen routes (`/book/:bookSlug`, `/quiz/...`, `/flashcards/...`) attach to the root navigator to escape the shell. Auth flow: `/splash` → `/sign-in` or `/`.

**Backend (Supabase)**: schema and RLS in [supabase/migrations/](supabase/migrations/). User-data tables (`reading_progress`, `audio_progress`, `quiz_attempts`, `quiz_answers`, `user_streaks`, `profiles`) are gated by RLS so each user only sees their own rows. Catalog tables (`levels`, `books`, `lessons`, `assets`, `quizzes`, `questions`, `options`) are read-mostly. PDFs and MP3s live in a private Storage bucket named `content`; the Flutter app downloads via signed URLs and caches with `asset_cache` in `lib/shared/services/`.

**Reader/audio coupling**: the book reader uses `pdfx` with a tab toggle between book PDF and study guide. To avoid the web `detached ArrayBuffer` error, the viewer always opens from a fresh copy of the cached bytes — preserve that pattern when touching PDF code. Audio uses `just_audio` plus `just_audio_background` (initialized in [lib/main.dart](lib/main.dart) only on non-web). Reading page and audio second are persisted per lesson and restored on reopen; the 90% threshold marks lessons completed.

**Progress aggregation**: `features/progress` combines reading %, audio %, and quiz pass rate per book. Books without generated quizzes do not penalize the score — keep that branch when changing the formula.

## Conventions

- Lints: `flutter_lints` + custom rules in [analysis_options.yaml](analysis_options.yaml) — `prefer_single_quotes`, `require_trailing_commas`, `avoid_print`. Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/generated/**`) are excluded.
- Logging: never `print` in production code paths — use `AppLogger` in `lib/core/logging/`. (The router currently has one debug `print` behind an `// ignore:` comment; don't add more.)
- Localization: add strings to both `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb` and re-run `flutter gen-l10n`. Access via `AppLocalizations.of(context)!`.
- Env access: use `Env` from `lib/core/config/env.dart`; `Env.assertConfigured()` runs at startup.

## CI

[.github/workflows/flutter.yml](.github/workflows/flutter.yml) runs on push to `main` and on PRs: `flutter pub get` → `flutter gen-l10n` → `flutter analyze` → `flutter test` → `flutter build web --debug --no-wasm-dry-run`. Run these locally before pushing. A separate `deploy-web.yml` handles web deploys.
