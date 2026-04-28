# Chepia Learning - Project Context

## Project Overview
Chepia Learning is a mobile application (iOS + Android) designed for English language learning. It features a curriculum based on PDFs and audio lessons, complemented by AI-generated quizzes.

### Core Tech Stack
- **Framework:** Flutter 3.41+ (Dart 3.11+)
- **State Management:** Riverpod 2 (with code generation)
- **Routing:** go_router (Stateful Shell for bottom navigation)
- **Backend:** Supabase (Auth, PostgreSQL, Storage)
- **Local Persistence:** Hive (for large data) & shared_preferences (for settings)
- **Media:** pdfx (PDF rendering) & just_audio (Audio playback with background support)
- **i18n:** Flutter Localizations with `.arb` files (English and Spanish)

### Architecture
The project follows a **Feature-First Clean Architecture** pattern located in `lib/features/`:
- `data/`: Repositories and Data Sources (Supabase, Hive).
- `domain/`: Entities and Abstract Repositories.
- `presentation/`: Screens, Widgets, and Riverpod Controllers.

Global shared logic is located in `lib/core/` (config, logging, errors) and `lib/shared/` (theme, common widgets, services).

---

## Building and Running

### Prerequisites
- Flutter SDK 3.41.0+
- Node.js 20+ (for build-time scripts)
- ffmpeg (`brew install ffmpeg`) for audio conversion
- Supabase project and credentials

### Initial Setup
1.  **Dependencies:** `flutter pub get`
2.  **Environment:** Copy `.env.example` to `.env` and fill in Supabase credentials.
3.  **Localizations:** `flutter gen-l10n`
4.  **Code Generation:** `dart run build_runner build --delete-conflicting-outputs`
5.  **Run:** `flutter run`

### Backend Setup
- Migrations are located in `supabase/migrations/`.
- Storage bucket named `content` (private) is required in Supabase.

### AI Quiz Generation (Build-time)
Quizzes are generated once using Anthropic's Claude.
- Scripts are in `scripts/quiz_generator/`.
- Requires `ANTHROPIC_API_KEY` in the script's `.env`.

---

## Development Conventions

### Coding Standards
- **Linting:** Uses `very_good_analysis` and `flutter_lints`.
- **Formatting:** 
  - Prefer single quotes (`'`) for strings.
  - Mandatory trailing commas for parameters and lists.
  - No `print` statements; use `AppLogger` from `lib/core/logging/`.
- **Naming:** Follow standard Dart PascalCase for classes and camelCase for methods/variables.

### State Management & Logic
- Use **Riverpod** with the `@riverpod` annotation for code generation.
- Logic should reside in Controllers/Notifiers within the `presentation` layer.
- Domain entities should be immutable, preferably using **Freezed**.

### Navigation
- Defined in `lib/app/router.dart`.
- Uses `StatefulShellRoute` to maintain state across bottom navigation tabs.
- Auth guards are implemented via `redirect` in the router.

### Localization
- Add strings to `lib/l10n/app_en.arb` and `app_es.arb`.
- Access via `AppLocalizations.of(context)!`.

---

## Key Directories
- `lib/features/`: Feature-specific implementation.
- `lib/core/`: Application-wide configuration and utilities.
- `lib/shared/`: Reusable widgets, themes, and services.
- `supabase/`: Database schema and migrations.
- `scripts/`: Maintenance and build-time content generation scripts.
- `assets/`: Fonts, icons, and static images.
