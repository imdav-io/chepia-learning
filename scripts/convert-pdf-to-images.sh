#!/usr/bin/env bash
# Convierte cada PDF principal a una secuencia de imágenes (uno por página) en
# scripts/quiz_generator/out/pages/<book-slug>/page-NNN.<ext>. Las usa el
# pipeline de generación de quizzes con Vision (los PDFs son escaneos de
# imagen, no tienen texto seleccionable) y la app Flutter como fuente de
# páginas optimizadas.
#
# Formatos soportados:
#   FORMAT=webp (default, recomendado)  PDF -> PNG -> WEBP q90 (lossless intermedio)
#   FORMAT=jpeg                          PDF -> JPEG q70 (legacy)
#
# Requiere:
#   - poppler  (brew install poppler)
#   - libwebp  (brew install webp)   solo si FORMAT=webp
#
# Uso:
#   bash scripts/convert-pdf-to-images.sh
#   FORMAT=jpeg bash scripts/convert-pdf-to-images.sh
#   DPI=150 bash scripts/convert-pdf-to-images.sh

set -euo pipefail

CONTENT_DIR="${CONTENT_DIR:-$HOME/Downloads/As it is}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/quiz_generator/out/pages"
SG_OUT_DIR="$SCRIPT_DIR/quiz_generator/out/study-guides"
DPI="${DPI:-120}"
FORMAT="${FORMAT:-webp}"
WEBP_QUALITY="${WEBP_QUALITY:-90}"
JPEG_QUALITY="${JPEG_QUALITY:-70}"

if ! command -v pdftoppm >/dev/null 2>&1; then
  echo "[error] pdftoppm no está instalado. brew install poppler" >&2
  exit 127
fi

case "$FORMAT" in
  webp)
    if ! command -v cwebp >/dev/null 2>&1; then
      echo "[error] cwebp no está instalado. brew install webp" >&2
      exit 127
    fi
    EXT="webp"
    ;;
  jpeg|jpg)
    FORMAT="jpeg"
    EXT="jpg"
    ;;
  *)
    echo "[error] FORMAT debe ser webp o jpeg (recibí '$FORMAT')." >&2
    exit 2
    ;;
esac

# Renderiza un PDF a una carpeta de imágenes en el formato seleccionado.
# Si FORMAT=webp: pdftoppm emite PNG temporales que cwebp convierte a WEBP
# con calidad alta y luego elimina. PNG intermedio es lossless, así que el
# WEBP final viene del raster real, no de un JPEG re-comprimido.
render_pdf_to_images() {
  local pdf="$1"
  local out="$2"

  mkdir -p "$out"

  if [ "$FORMAT" = "jpeg" ]; then
    pdftoppm -jpeg -jpegopt "quality=$JPEG_QUALITY" -r "$DPI" "$pdf" "$out/page"
    return
  fi

  # FORMAT=webp: render a PNG, convert to WEBP, drop PNG.
  pdftoppm -png -r "$DPI" "$pdf" "$out/page"

  local total=0
  local converted=0
  for png in "$out"/page-*.png; do
    [ -e "$png" ] || continue
    total=$((total + 1))
    local webp="${png%.png}.webp"
    if cwebp -q "$WEBP_QUALITY" -quiet "$png" -o "$webp" 2>/dev/null; then
      rm -f "$png"
      converted=$((converted + 1))
    else
      echo "[warn] cwebp falló: $png (lo dejo como PNG)"
    fi
  done
  if [ "$total" -gt 0 ]; then
    echo "       $converted/$total páginas convertidas a webp q$WEBP_QUALITY"
  fi
}

# Salta si la carpeta destino ya tiene imágenes del formato actual.
already_rendered() {
  local out="$1"
  if compgen -G "$out/page-*.$EXT" >/dev/null; then
    local existing
    existing=$(find "$out" -name "page-*.$EXT" | wc -l | tr -d ' ')
    echo "$existing"
    return 0
  fi
  return 1
}

convert_book() {
  local folder="$1"
  local slug="$2"
  local book_root="$CONTENT_DIR/$folder/Book"
  local pdf=""

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
  if existing=$(already_rendered "$out"); then
    echo "[skip] $slug: ya hay $existing imágenes .$EXT en $out"
    return
  fi

  echo "[conv] $pdf -> $out/page-*.$EXT (DPI $DPI, $FORMAT)"
  render_pdf_to_images "$pdf" "$out"
  local count
  count=$(find "$out" -name "page-*.$EXT" | wc -l | tr -d ' ')
  echo "       $count páginas en total"
}

convert_study_guide() {
  local folder="$1"
  local slug="$2"
  local book_root="$CONTENT_DIR/$folder/Book"
  local pdf=""

  for candidate in "study_guide.pdf" "Study Guide.pdf"; do
    if [ -f "$book_root/$candidate" ]; then
      pdf="$book_root/$candidate"
      break
    fi
  done
  if [ -z "$pdf" ]; then
    pdf="$(find "$book_root" -maxdepth 1 -type f -iname "*study*guide*.pdf" -print -quit 2>/dev/null || true)"
  fi

  if [ -z "$pdf" ]; then
    echo "[skip-sg] Study guide no encontrado para $folder"
    return
  fi

  local out="$SG_OUT_DIR/$slug"
  if existing=$(already_rendered "$out"); then
    echo "[skip-sg] $slug: ya hay $existing imágenes .$EXT en $out"
    return
  fi

  echo "[conv-sg] $pdf -> $out/page-*.$EXT (DPI $DPI, $FORMAT)"
  render_pdf_to_images "$pdf" "$out"
  local count
  count=$(find "$out" -name "page-*.$EXT" | wc -l | tr -d ' ')
  echo "          $count páginas en total"
}

convert_book "Book 1" "as-it-is-book-1"
convert_book "Book 2" "as-it-is-book-2"
convert_book "Book 3" "as-it-is-book-3"

convert_study_guide "Book 1" "as-it-is-book-1"
convert_study_guide "Book 2" "as-it-is-book-2"
convert_study_guide "Book 3" "as-it-is-book-3"

echo "[DONE]"
