# Chepia Learning

Chepia Learning es una app Flutter para aprender ingles con libros por nivel,
lectura en PDF, audios sincronizados, progreso, quizzes y vocabulario. La app
usa Supabase como backend y esta preparada para correr en web y dispositivos
moviles.

## Estado actual

- Inicio de sesion con Supabase Auth y Google OAuth.
- Catalogo de niveles, libros y lecciones.
- Lectura de PDF con visor integrado, cache local y soporte offline.
- Audios por leccion ordenados de primero a ultimo.
- Reproductor de audio persistente con pausa/limpieza al salir del nivel.
- Pantallas de carga animadas con estilo visual oscuro/neon.
- Progreso por libro, leccion y actividad.
- Quizzes por leccion y resultados guardados.
- Flashcards y vocabulario asociado a lecciones.
- Dashboard de progreso con accion para continuar lectura.

## Stack

- Flutter 3.x
- Riverpod para estado
- GoRouter para navegacion
- Supabase Auth, Database y Storage
- `pdfx` para lectura de PDF
- `just_audio` para reproduccion de audio
- Node.js para scripts de contenido y generacion de quizzes
- `ffmpeg` para normalizacion de audio

## Estructura principal

```text
lib/
  app/                     Navegacion, shell y configuracion global
  core/                    Configuracion, errores, logging y utilidades
  features/
    auth/                  Inicio de sesion
    catalog/               Niveles, libros y lecciones
    lesson/                Lector, audio y experiencia de estudio
    onboarding/            Splash y carga inicial
    profile/               Perfil del usuario
    progress/              Progreso y continuidad
    quiz/                  Quizzes
    vocabulary/            Flashcards y vocabulario
  shared/
    ai/                    Servicios compartidos de IA
    services/              Cache y servicios compartidos
    theme/                 Colores y tema visual
    widgets/               Widgets reutilizables
  l10n/                    Localizacion y archivos generados
scripts/
  convert-audio.sh         Conversion de audios WMA a MP3
  convert-pdf-to-images.sh Conversion de PDFs a imagenes por pagina
  quiz_generator/          Upload, registro, quizzes y vocabulario con IA
supabase/
  migrations/              Esquema, seeds y politicas
```

## Variables de entorno

Crea un archivo `.env` en la raiz tomando como base `.env.example`:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=your-ios-client-id.apps.googleusercontent.com
APP_ENV=development
```

Para los scripts de quizzes, crea `scripts/quiz_generator/.env` desde
`scripts/quiz_generator/.env.example`:

```env
AI_PROVIDER=gemini
GEMINI_API_KEY=your-gemini-key
ANTHROPIC_API_KEY=your-anthropic-key
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
CONTENT_DIR=/path/to/content
```

Nunca subas archivos `.env`, llaves de servicio, dumps privados ni contenido
con derechos no autorizados al repositorio.

## Setup local

1. Instala dependencias de Flutter:

```bash
flutter pub get
```

2. Genera localizaciones:

```bash
flutter gen-l10n
```

3. Corre la app en web:

```bash
flutter run -d chrome --web-port 5050
```

4. Corre la app en macOS, iOS o Android segun tu ambiente:

```bash
flutter run
```

## Supabase

Aplica las migraciones en orden:

```text
supabase/migrations/0001_initial_schema.sql
supabase/migrations/0002_seed_demo.sql
supabase/migrations/0002_user_vocabulary.sql
supabase/migrations/0003_storage_policies.sql
supabase/migrations/0004_lesson_vocabulary.sql
```

Despues configura:

- Auth providers para Google OAuth.
- Storage buckets para PDFs, audios y assets optimizados.
- Politicas de lectura/escritura segun el ambiente.
- Redirect URLs de OAuth para localhost y dominios de produccion.

## Pipeline de contenido

Los scripts de `scripts/` y `scripts/quiz_generator/` ayudan a procesar libros,
audios, imagenes de pagina, quizzes y vocabulario. Ejecutalos solo con contenido
que tengas permitido usar y distribuir.

Ejemplos:

```bash
CONTENT_DIR="/path/to/As it is" bash scripts/convert-audio.sh
CONTENT_DIR="/path/to/As it is" DPI=120 bash scripts/convert-pdf-to-images.sh
```

Para quizzes:

```bash
cd scripts/quiz_generator
npm install
npm run upload-content
npm run extract
npm run generate
```

Comandos utiles adicionales:

```bash
node register-content.mjs
node upload-page-images.mjs
node generate-vocabulary.mjs
```

La carpeta `scripts/quiz_generator/out/` es salida generada y no debe subirse.

## Verificacion antes de subir

Antes de subir cambios a GitHub, corre:

```bash
dart format lib test
flutter analyze
flutter test
flutter build web --debug
git status --short
```

El `.gitignore` ya excluye builds, archivos generados, `.env`, llaves locales y
salida de scripts. Aun asi, revisa siempre `git status --short` antes de hacer
commit.

El build web puede mostrar advertencias de `pdfx` durante el dry-run de WASM.
Mientras el comando termine con `Built build/web`, el build actual es valido.

## Subir a GitHub

Si el repo aun no esta inicializado:

```bash
git init
git add .
git commit -m "Initial Chepia Learning app"
git branch -M main
git remote add origin git@github.com:USER/REPO.git
git push -u origin main
```

Si el repo ya existe:

```bash
git remote -v
git status --short
git add .
git commit -m "Update Chepia Learning app"
git push
```

Antes de hacer publico el repositorio, revisa:

- `.env` y llaves secretas no deben estar versionadas.
- El contenido PDF/audio debe tener permiso de distribucion.
- El README debe apuntar a instrucciones reales de setup.
- El repositorio debe tener licencia solo si puedes licenciar todo el contenido.
- Para produccion, configura reglas de rama y CI en GitHub Actions.

## Build web y deploy

Build de desarrollo:

```bash
flutter build web --debug
```

Build de produccion:

```bash
flutter build web --release
```

Si vas a publicar en GitHub Pages bajo un subpath, usa:

```bash
flutter build web --release --base-href /REPO/
```

El contenido generado queda en `build/web`.

## Flujos importantes

### Lectura y audio

- Las lecciones se muestran en orden ascendente.
- Los audios aparecen de primero a ultimo.
- El reproductor se pausa al salir de la experiencia de nivel.
- El cache local permite seguir leyendo contenido previamente descargado.

### Progreso

- El progreso se calcula por libro, leccion y actividad.
- La pantalla de progreso muestra estadisticas generales y una accion para
  continuar la lectura pendiente.

### Vocabulario y quizzes

- Cada leccion puede tener palabras asociadas.
- Las flashcards ayudan a repasar vocabulario.
- Los quizzes se pueden generar y sincronizar desde los scripts.

## Troubleshooting

### Google OAuth no funciona en localhost

Agrega las URLs locales en Google Cloud Console y Supabase Auth:

```text
http://localhost:5050
http://localhost:5050/auth/callback
```

### PDFs no cargan en web

Verifica que el archivo exista en Supabase Storage, que las politicas permitan
lectura y que el bucket tenga CORS configurado para el dominio de la app.

### Audio no reproduce

Confirma que el archivo este en un formato soportado por web. Para archivos WMA
u otros formatos antiguos, convierte a MP3 o AAC con `ffmpeg`.

### El build web muestra warnings de `pdfx`

Son advertencias del dry-run de WASM relacionadas con interop web. Si el comando
termina correctamente, no bloquean el build actual.

## Roadmap sugerido

- CI en GitHub Actions con format, analyze, tests y build web.
- Pruebas end-to-end para flujos de lectura, audio y progreso.
- Panel administrativo para cargar contenido sin scripts manuales.
- Hosting de produccion y configuracion de dominios.
- Politicas de privacidad, terminos y preparacion para tiendas moviles.
