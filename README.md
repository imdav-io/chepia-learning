# Chepia Learning

App Flutter para estudiar inglés con libros en PDF, audios por lección,
progreso sincronizado y quizzes guardados en Supabase.

La idea central es simple: el estudiante abre un libro, lee el PDF, escucha el
audio de la lección activa, cambia entre libro y study guide, y retoma después
desde la misma página y segundo de audio donde se quedó.

## Estado actual

El proyecto ya tiene un MVP funcional:

- Login con email/password y Google OAuth.
- Catálogo por niveles, libros y lecciones desde Supabase.
- Visor PDF con dos pestañas: `Libro` y `Study guide`.
- Cache de PDF para web y mobile.
- Player de audio con play/pause, saltos de 10s, slider y velocidad.
- Persistencia de progreso de lectura y audio.
- Restauración de última página leída y último segundo escuchado.
- Marcado de completado al superar el 90% de lectura o audio.
- Quizzes reales por lección, con feedback inmediato y registro de intentos.
- Dashboard de progreso por libro: porcentaje, última lección, páginas leídas,
  minutos escuchados y quizzes aprobados.

## Stack

- Flutter / Dart
- Riverpod
- GoRouter
- Supabase Auth, Postgres, RLS y Storage
- pdfx para PDF
- just_audio y just_audio_background para audio
- Node.js para pipeline de contenido y quizzes
- ffmpeg para convertir WMA a MP3

## Estructura

```txt
lib/
  app/                  Router, shell principal y MaterialApp
  core/                 Configuración, errores y logging
  features/
    auth/               Login y sesión
    catalog/            Niveles, libros, lecciones y assets
    lesson/             Reader PDF, study guide, audio player y lista
    progress/           Progreso agregado por libro
    quiz/               Quizzes, intentos y resultados
    profile/            Perfil
    onboarding/         Splash/onboarding
  shared/
    services/           Cache de assets
    theme/              Tema visual
  l10n/                 Localización es/en

scripts/
  convert-audio.sh      Convierte WMA a MP3
  quiz_generator/       Upload, registro, extracción PDF y generación IA

supabase/
  migrations/           Schema, seed demo y políticas de Storage
```

## Variables de entorno

El app carga `.env` desde la raíz del proyecto.

```bash
cp .env.example .env
```

Variables principales:

```env
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=your_anon_key_here

GOOGLE_WEB_CLIENT_ID=your_google_web_client_id.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=your_google_ios_client_id.apps.googleusercontent.com

APP_ENV=development
```

Los scripts de contenido usan su propio archivo:

```bash
cp scripts/quiz_generator/.env.example scripts/quiz_generator/.env
```

Variables principales de scripts:

```env
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
CONTENT_DIR=/ruta/a/tu/carpeta/As it is

AI_PROVIDER=gemini
GEMINI_API_KEY=your_gemini_key
```

También se puede usar Claude:

```env
AI_PROVIDER=claude
ANTHROPIC_API_KEY=your_anthropic_key
```

## Setup local

Requisitos:

- Flutter compatible con `pubspec.yaml`
- Dart compatible con `pubspec.yaml`
- Node.js 20+
- ffmpeg, si vas a convertir WMA
- Proyecto de Supabase

Instalación:

```bash
flutter pub get
flutter gen-l10n
```

Correr en web:

```bash
flutter run -d chrome --web-port 5050
```

Correr en iOS o Android:

```bash
flutter run
```

## Supabase

Ejecuta las migraciones desde el SQL Editor de Supabase:

```txt
supabase/migrations/0001_initial_schema.sql
supabase/migrations/0002_seed_demo.sql
supabase/migrations/0003_storage_policies.sql
```

Después crea el bucket privado:

```txt
content
```

El schema contiene:

- `profiles`
- `levels`
- `books`
- `lessons`
- `assets`
- `reading_progress`
- `audio_progress`
- `quizzes`
- `questions`
- `options`
- `quiz_attempts`
- `quiz_answers`
- `user_streaks`

Las tablas con datos del usuario usan Row Level Security para que cada usuario
solo vea y modifique su propio progreso e intentos.

## Pipeline de contenido

La app espera esta estructura local por defecto:

```txt
CONTENT_DIR/
  Book 1/
    Book/
      As it is - Book 1.pdf
      English. AS IT IS. Study Guide [Book 1].pdf
    Audios/
      WMA/
      mp3/
  Book 2/
    Book/
    Audios/
  Book 3/
    Book/
    Audios/
```

Convertir WMA a MP3:

```bash
CONTENT_DIR="/ruta/a/As it is" bash scripts/convert-audio.sh
```

Instalar dependencias de scripts:

```bash
cd scripts/quiz_generator
npm install
```

Subir PDFs y audios:

```bash
node upload-content.mjs
```

Registrar libros, lecciones y assets en Postgres:

```bash
node register-content.mjs
```

Extraer texto de PDFs:

```bash
node extract-pdf-text.mjs
```

Generar quizzes con IA:

```bash
node generate.mjs
```

`generate.mjs` es idempotente: si una lección ya tiene quiz generado, la omite.

## Flujos principales

### Lectura y audio

1. El usuario inicia sesión.
2. Selecciona nivel y libro.
3. El reader abre el PDF principal en la pestaña `Libro`.
4. La pestaña `Study guide` abre la guía del mismo libro, si existe.
5. La lista lateral permite cambiar de lección/audio sin reiniciar el PDF.
6. La app guarda página leída y posición de audio.
7. Al reabrir, restaura la última página y el último segundo de audio.

### Progreso

El dashboard calcula:

- porcentaje general
- porcentaje por libro
- última lección con actividad
- páginas leídas
- minutos escuchados
- quizzes aprobados
- lecciones leídas y audios completados

El porcentaje combina lectura, audio y quizzes. Si un libro no tiene quizzes
generados, los quizzes no penalizan su porcentaje.

### Quizzes

Cada quiz:

- carga preguntas desde Supabase
- crea un intento antes de permitir responder
- registra respuestas
- muestra feedback inmediato
- finaliza con score, total y aprobado/reprobado

## Testing y calidad

Comandos útiles:

```bash
dart format lib test
flutter analyze
flutter test
flutter build web --debug
```

Antes de entregar cambios conviene correr al menos:

```bash
flutter analyze
flutter test
```

## Notas de release

Para subir a App Store o Google Play todavía faltan pasos de producto y release:

- configurar signing release de Android
- configurar bundle id, signing y capabilities de iOS
- revisar iconos, splash y screenshots
- agregar política de privacidad y términos
- preparar cuenta demo para revisión
- declarar uso de datos en App Store Connect y Play Console
- validar derechos/licencias de PDFs y audios
- correr pruebas en dispositivos reales
- revisar que no queden textos técnicos visibles para usuarios finales

## Troubleshooting

### OAuth redirige a localhost incorrecto

En web, la URL de redirección debe estar permitida en Supabase Auth. Agrega las
URLs locales que uses, por ejemplo:

```txt
http://localhost:5050
http://127.0.0.1:5050
```

### PDF falla al cambiar entre Libro y Study guide

El visor PDF usa una copia fresca de bytes al abrir el documento para evitar el
error web de `detached ArrayBuffer`. Si ya tenías la app abierta, haz refresh
completo del navegador después de compilar.

### No convierte WMA

Instala ffmpeg:

```bash
brew install ffmpeg
```

Y asegúrate de que `CONTENT_DIR` apunte a la carpeta que contiene `Book 1`,
`Book 2` y `Book 3`.

### Quizzes no aparecen

Verifica:

- que `extract-pdf-text.mjs` haya generado datos
- que `generate.mjs` tenga `GEMINI_API_KEY` o `ANTHROPIC_API_KEY`
- que `SUPABASE_SERVICE_ROLE_KEY` sea la service role key, no la anon key
- que existan filas en `quizzes`, `questions` y `options`

## Roadmap sugerido

- Descarga offline explícita por libro.
- Bookmarks y notas por página.
- Flashcards por lección.
- Repetición espaciada de vocabulario.
- Dictados cortos usando los audios.
- Práctica de speaking con grabación y feedback.
- Mejor dashboard de racha y hábitos.
- Panel admin para subir contenido sin scripts locales.
