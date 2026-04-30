#!/usr/bin/env bash
# Convierte cada PDF principal a una secuencia de JPEGs (uno por página) en
# scripts/quiz_generator/out/pages/<book-slug>/page-NNN.jpg. Las usa el
# pipeline de generación de quizzes con Gemini Vision (los PDFs son escaneos
# de imagen, no tienen texto seleccionable).
#
# Requiere: poppler (`brew install poppler`).
# Uso:      bash scripts/convert-pdf-to-images.sh

set -euo pipefail

CONTENT_DIR="${CONTENT_DIR:-$HOME/Downloads/As it is}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/quiz_generator/out/pages"
DPI="${DPI:-120}"

if ! command -v pdftoppm >/dev/null 2>&1; then
  echo "[error] pdftoppm no está instalado. brew install poppler" >&2
  exit 127
fi

convert_book() {
  local folder="$1"
  local slug="$2"
  local book_root="$CONTENT_DIR/$folder/Book"
  local pdf=""

  # Busca el PDF principal (orden de preferencia)
  for candidate in "main.pdf" "As it is - Book 1.pdf" "As it is - Book 2.pdf" "As it is - Book 3.pdf"; do
    if [ -f "$book_root/$candidate" ]; then
      pdf="$book_root/$candidate"
      break
    fi
  done

  if [ -z "$pdf" ]; then
    echo "[warn] PDF no encontrado para $folder en $book_root"
    return
  fi

  local out="$OUT_DIR/$slug"
  mkdir -p "$out"

  if compgen -G "$out/page-*.jpg" >/dev/null; then
    local existing
    existing=$(find "$out" -name "page-*.jpg" | wc -l | tr -d ' ')
    echo "[skip] $slug: ya hay $existing imágenes en $out"
    return
  fi

  echo "[conv] $pdf -> $out/page-*.jpg (DPI $DPI, JPEG q70)"
  pdftoppm -jpeg -jpegopt quality=70 -r "$DPI" "$pdf" "$out/page"
  local count
  count=$(find "$out" -name "page-*.jpg" | wc -l | tr -d ' ')
  echo "       $count páginas convertidas"
}

convert_book "Book 1" "as-it-is-book-1"
convert_book "Book 2" "as-it-is-book-2"
convert_book "Book 3" "as-it-is-book-3"

echo "[DONE]"
