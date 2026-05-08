// Convierte imágenes (PNG/JPG/JPEG) a WEBP con calidad 90 manteniendo
// nombres relativos. Sirve para optimizar páginas del libro o ilustraciones
// de vocabulario sin pérdida visible. Reporta tamaño antes/después.
//
// Uso:
//   cd scripts/quiz_generator
//   npm install     # instala sharp si no está
//
//   # Carpeta arbitraria:
//   node convert-to-webp.mjs --src=./out/pages/as-it-is-book-1 --out=./out/pages-webp/as-it-is-book-1
//
//   # Con calidad personalizada (default 90):
//   node convert-to-webp.mjs --src=./in --out=./out --quality=85
//
//   # Sobrescribe la carpeta de origen (cuidado, requiere --in-place):
//   node convert-to-webp.mjs --src=./out/pages/as-it-is-book-1 --in-place
//
// Notas:
// - Mantiene la subestructura de directorios.
// - Salta archivos que no son PNG/JPG/JPEG.
// - Si el WEBP destino existe y es más nuevo que el origen, lo respeta
//   (re-corre seguro).

import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';

const args = parseArgs(process.argv.slice(2));
const SRC = args.src;
const OUT = args.out;
const IN_PLACE = args['in-place'] === true || args['in-place'] === 'true';
const QUALITY = Number(args.quality ?? 90);

if (!SRC) {
  console.error('Falta --src=<carpeta>. Usa --help para ver el detalle.');
  process.exit(1);
}
if (!IN_PLACE && !OUT) {
  console.error('Falta --out=<carpeta> (o usa --in-place para sobrescribir).');
  process.exit(1);
}
if (Number.isNaN(QUALITY) || QUALITY < 1 || QUALITY > 100) {
  console.error(`--quality debe estar entre 1 y 100 (recibí "${args.quality}").`);
  process.exit(1);
}

const targetRoot = IN_PLACE ? SRC : OUT;
await fs.mkdir(targetRoot, { recursive: true });

const stats = { converted: 0, skipped: 0, failed: 0, before: 0, after: 0 };

await walk(SRC);
report();

// --------------------------------------------------------------------------

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const abs = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await walk(abs);
      continue;
    }
    if (!entry.isFile()) continue;
    if (!/\.(png|jpe?g)$/i.test(entry.name)) continue;
    await convertOne(abs);
  }
}

async function convertOne(absInput) {
  const rel = path.relative(SRC, absInput);
  const base = rel.replace(/\.(png|jpe?g)$/i, '');
  const target = path.join(targetRoot, `${base}.webp`);

  await fs.mkdir(path.dirname(target), { recursive: true });

  const inputStat = await fs.stat(absInput);
  if (fsSync.existsSync(target)) {
    const targetStat = await fs.stat(target);
    if (targetStat.mtimeMs >= inputStat.mtimeMs) {
      stats.skipped += 1;
      console.log(`[skip] ${rel}`);
      return;
    }
  }

  try {
    await sharp(absInput)
      .webp({ quality: QUALITY, effort: 4 })
      .toFile(target);
    const outStat = await fs.stat(target);
    stats.converted += 1;
    stats.before += inputStat.size;
    stats.after += outStat.size;
    const pct = ((outStat.size / inputStat.size) * 100).toFixed(0);
    console.log(
      `[ok  ] ${rel} -> ${path.relative(targetRoot, target)} ` +
        `(${human(inputStat.size)} -> ${human(outStat.size)}, ${pct}%)`,
    );
    if (IN_PLACE) {
      await fs.unlink(absInput);
    }
  } catch (e) {
    stats.failed += 1;
    console.warn(`[fail] ${rel}: ${e.message}`);
  }
}

function report() {
  console.log();
  const pct = stats.before === 0
    ? '-'
    : `${((stats.after / stats.before) * 100).toFixed(0)}%`;
  console.log(
    `[total] convertidos: ${stats.converted}, ` +
      `omitidos: ${stats.skipped}, fallidos: ${stats.failed}`,
  );
  console.log(`[size]  ${human(stats.before)} -> ${human(stats.after)} (${pct})`);
}

function human(bytes) {
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(1)} MB`;
  if (bytes >= 1_024) return `${(bytes / 1_024).toFixed(1)} KB`;
  return `${bytes} B`;
}

function parseArgs(list) {
  const out = {};
  for (const a of list) {
    if (a === '-h' || a === '--help') {
      console.log(
        'Uso: node convert-to-webp.mjs --src=<dir> --out=<dir> [--quality=90] [--in-place]',
      );
      process.exit(0);
    }
    if (!a.startsWith('--')) continue;
    const [k, v] = a.replace(/^--/, '').split('=');
    out[k] = v ?? true;
  }
  return out;
}
