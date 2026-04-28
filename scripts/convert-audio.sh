#!/usr/bin/env bash
# Convierte todos los WMA de Book 1, Book 2 y Book 3 a MP3 96kbps mono.
# Requiere ffmpeg (brew install ffmpeg).
#
# Uso:
#   bash scripts/convert-audio.sh

set -euo pipefail

CONTENT_DIR="${CONTENT_DIR:-$HOME/Downloads/As it is}"
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"

if ! command -v "$FFMPEG_BIN" >/dev/null 2>&1; then
  echo "[error] ffmpeg no está instalado o no está en PATH." >&2
  echo "        Instálalo con: brew install ffmpeg" >&2
  exit 127
fi

output_name() {
  local input="$1"
  local base="${input%.*}"
  # Compatible con bash 3.2 (macOS default): usar tr en vez de ${var,,}.
  local lower
  lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')

  if [[ "$lower" =~ lesson[[:space:]_-]+0*([0-9]+) ]]; then
    echo "Lesson ${BASH_REMATCH[1]}.mp3"
    return
  fi

  if [[ "$lower" =~ ap+p?endix[[:space:]_-]+0*([0-9]+) ]]; then
    echo "Appendix ${BASH_REMATCH[1]}.mp3"
    return
  fi

  echo "$base.mp3"
}

convert_book() {
  local book="$1"
  local audio_root="$CONTENT_DIR/$book/Audios"
  local src=""
  local dst="$audio_root/mp3"

  for candidate in "$audio_root/WMA" "$audio_root/wma"; do
    if [ -d "$candidate" ]; then
      src="$candidate"
      break
    fi
  done

  if [ -z "$src" ]; then
    echo "[warn] no se encontró carpeta WMA para $book: $audio_root"
    return
  fi

  mkdir -p "$dst"

  local found=0
  while IFS= read -r -d '' f; do
    found=1
    local name
    name=$(basename "$f")
    local out="$dst/$(output_name "$name")"
    if [ -f "$out" ]; then
      echo "[skip] $out"
      continue
    fi
    echo "[conv] $f -> $out"
    "$FFMPEG_BIN" -y -i "$f" -codec:a libmp3lame -b:a 96k -ac 1 "$out" </dev/null >/dev/null 2>&1
  done < <(find "$src" -maxdepth 1 -type f -iname "*.wma" -print0)

  if [ "$found" -eq 0 ]; then
    echo "[warn] no hay archivos WMA en $src"
  fi
}

convert_book "Book 1"
convert_book "Book 2"
convert_book "Book 3"

echo "[DONE]"
