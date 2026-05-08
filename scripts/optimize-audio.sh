#!/usr/bin/env bash
# Optimiza MP3 manteniendo calidad alta para audios de aprendizaje (voz).
# Reencode con libmp3lame VBR `-q:a 2` (~190 kbps), mono, 44.1 kHz.
# - VBR de calidad alta: la voz se siente natural sin perder definición.
# - Mono: los audios son narrados, estéreo no aporta nada y duplica peso.
# - Sample rate 44.1 kHz: estándar consistente, evita resamplings raros.
#
# Uso:
#   # Modo local (recomendado, no toca Supabase):
#   bash scripts/optimize-audio.sh --src=/path/to/audios --out=/path/to/audios-optimized
#
#   # Sobre la carpeta del pipeline:
#   CONTENT_DIR="$HOME/Downloads/As it is" bash scripts/optimize-audio.sh
#
# Requiere ffmpeg (brew install ffmpeg).

set -euo pipefail

FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
SRC=""
OUT=""
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --src=*) SRC="${arg#--src=}" ;;
    --out=*) OUT="${arg#--out=}" ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *) echo "[warn] argumento ignorado: $arg" ;;
  esac
done

if ! command -v "$FFMPEG_BIN" >/dev/null 2>&1; then
  echo "[error] ffmpeg no está instalado o no está en PATH." >&2
  echo "        Instálalo con: brew install ffmpeg" >&2
  exit 127
fi

# Tamaño humano (KB / MB) sin depender de GNU coreutils.
human_size() {
  local bytes="$1"
  if [ "$bytes" -ge 1048576 ]; then
    awk -v b="$bytes" 'BEGIN{printf "%.1f MB", b/1048576}'
  elif [ "$bytes" -ge 1024 ]; then
    awk -v b="$bytes" 'BEGIN{printf "%.1f KB", b/1024}'
  else
    echo "${bytes} B"
  fi
}

file_size() {
  if stat --version >/dev/null 2>&1; then
    stat -c '%s' "$1"
  else
    stat -f '%z' "$1"
  fi
}

optimize_one() {
  local input="$1"
  local output="$2"
  mkdir -p "$(dirname "$output")"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry ] $input -> $output"
    return
  fi

  if [ -f "$output" ] && [ "$output" -nt "$input" ]; then
    echo "[skip] $output (más nuevo que el origen)"
    return
  fi

  "$FFMPEG_BIN" -y -i "$input" \
    -codec:a libmp3lame -q:a 2 -ac 1 -ar 44100 \
    -map_metadata 0 -id3v2_version 3 \
    "$output" </dev/null >/dev/null 2>&1

  local before after pct
  before=$(file_size "$input")
  after=$(file_size "$output")
  pct=$(awk -v a="$after" -v b="$before" 'BEGIN{ if (b==0) print "0"; else printf "%.0f", (a*100/b) }')
  echo "[ok  ] $(basename "$input"): $(human_size "$before") -> $(human_size "$after") (${pct}%)"
}

run_local() {
  local src="$1"
  local out="$2"

  if [ ! -d "$src" ]; then
    echo "[error] carpeta de origen no existe: $src" >&2
    exit 1
  fi

  local total_before=0
  local total_after=0
  local count=0

  while IFS= read -r -d '' f; do
    rel="${f#$src/}"
    target="$out/$rel"
    optimize_one "$f" "$target"
    if [ -f "$target" ]; then
      total_before=$((total_before + $(file_size "$f")))
      total_after=$((total_after + $(file_size "$target")))
      count=$((count + 1))
    fi
  done < <(find "$src" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.wav" \) -print0)

  if [ "$count" -eq 0 ]; then
    echo "[warn] no se encontraron audios en $src"
    return
  fi

  echo
  echo "[total] $count archivos: $(human_size "$total_before") -> $(human_size "$total_after")"
}

run_default_pipeline() {
  local content_dir="${CONTENT_DIR:-$HOME/Downloads/As it is}"
  if [ ! -d "$content_dir" ]; then
    echo "[error] CONTENT_DIR no existe: $content_dir" >&2
    echo "        Pasa --src=... y --out=... o exporta CONTENT_DIR." >&2
    exit 1
  fi
  for book in "Book 1" "Book 2" "Book 3"; do
    local src="$content_dir/$book/Audios/mp3"
    local out="$content_dir/$book/Audios/mp3-optimized"
    if [ ! -d "$src" ]; then
      echo "[skip] $book: no hay carpeta $src"
      continue
    fi
    echo "=== $book ==="
    run_local "$src" "$out"
  done
}

if [ -n "$SRC" ] && [ -n "$OUT" ]; then
  run_local "$SRC" "$OUT"
elif [ -n "$SRC" ] || [ -n "$OUT" ]; then
  echo "[error] Debes pasar --src y --out juntos (o ninguno para usar CONTENT_DIR)." >&2
  exit 2
else
  run_default_pipeline
fi

echo "[DONE]"
