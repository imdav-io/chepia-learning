// Sube páginas ya renderizadas a Supabase Storage y crea un manifest.
//
// Usa las imágenes generadas por scripts/convert-pdf-to-images.sh:
//   out/pages/<book-slug>/page-001.jpg ...
//   out/study-guides/<book-slug>/page-001.jpg ...
//
// Uso:
//   cd scripts/quiz_generator
//   node upload-page-images.mjs --book=as-it-is-book-1
//   node upload-page-images.mjs --book=as-it-is-book-2
//   node upload-page-images.mjs --book=as-it-is-book-3
//   node upload-page-images.mjs --book=as-it-is-book-1 --kind=study-guide
//   node upload-page-images.mjs --book=as-it-is-book-2 --kind=study-guide

import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createClient } from '@supabase/supabase-js';
import sharp from 'sharp';

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = process.env;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en .env.');
  process.exit(1);
}

const args = Object.fromEntries(
  process.argv
    .slice(2)
    .filter((a) => a.startsWith('--'))
    .map((a) => {
      const [k, v] = a.replace(/^--/, '').split('=');
      return [k, v ?? true];
    }),
);

const BOOK_SLUG = args.book ?? 'as-it-is-book-1';
const KIND = args.kind ?? 'pages'; // 'pages' | 'study-guide'
if (!['pages', 'study-guide'].includes(KIND)) {
  console.error(`--kind debe ser 'pages' o 'study-guide' (recibí "${KIND}")`);
  process.exit(1);
}
const LOCAL_SUBDIR = KIND === 'study-guide' ? 'study-guides' : 'pages';
const REMOTE_KIND_SEGMENT = KIND === 'study-guide' ? 'study-guide' : 'pages';
const PAGES_DIR = path.resolve('./out', LOCAL_SUBDIR, BOOK_SLUG);
const REMOTE_DIR = `books/${BOOK_SLUG}/${REMOTE_KIND_SEGMENT}/v1`;
const BUCKET = 'content';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

async function imageDimensions(buffer) {
  try {
    const meta = await sharp(buffer).metadata();
    return { width: meta.width ?? 0, height: meta.height ?? 0 };
  } catch {
    return { width: 0, height: 0 };
  }
}

const MIME_BY_EXT = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.png': 'image/png',
};

async function upload(remotePath, buffer, contentType) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const { error } = await supabase.storage.from(BUCKET).upload(remotePath, buffer, {
      contentType,
      upsert: true,
    });
    if (!error) return;
    lastError = error;
    await new Promise((resolve) => setTimeout(resolve, attempt * 1000));
  }
  const detail = lastError?.message || lastError?.error || JSON.stringify(lastError);
  throw new Error(`${remotePath}: ${detail}`);
}

async function main() {
  const entries = await fs.readdir(PAGES_DIR);
  const pageFiles = entries
    .map((file) => {
      const match = file.match(/^page-(\d+)\.(jpe?g|webp|png)$/i);
      if (!match) return null;
      return {
        file,
        number: Number.parseInt(match[1], 10),
        ext: `.${match[2].toLowerCase()}`,
      };
    })
    .filter(Boolean)
    .sort((a, b) => a.number - b.number);

  if (pageFiles.length === 0) {
    throw new Error(
      `No encontré páginas en ${PAGES_DIR} (acepto .jpg/.jpeg/.webp/.png)`,
    );
  }

  const formats = new Set(pageFiles.map((p) => p.ext.replace('.', '')));
  if (formats.size > 1) {
    throw new Error(
      `Mezcla de formatos en ${PAGES_DIR}: ${[...formats].join(', ')}. ` +
        'Convierte todo al mismo formato antes de subir.',
    );
  }
  const format = pageFiles[0].ext.replace('.', '');
  const mime = MIME_BY_EXT[pageFiles[0].ext] ?? 'application/octet-stream';

  const pages = [];
  let totalBytes = 0;
  console.log(
    `Subiendo ${pageFiles.length} páginas (${format}) de ${BOOK_SLUG}...`,
  );

  for (const page of pageFiles) {
    const localPath = path.join(PAGES_DIR, page.file);
    const buffer = await fs.readFile(localPath);
    const size = await imageDimensions(buffer);
    const remotePath = `${REMOTE_DIR}/${page.file}`;
    await upload(remotePath, buffer, mime);
    totalBytes += buffer.byteLength;
    pages.push({
      pageNumber: page.number,
      storagePath: remotePath,
      width: size.width,
      height: size.height,
      sizeBytes: buffer.byteLength,
      mimeType: mime,
    });
    if (page.number % 20 === 0 || page.number === pageFiles.length) {
      console.log(`[ok] ${page.number}/${pageFiles.length}`);
    }
  }

  const manifest = {
    version: 1,
    bookSlug: BOOK_SLUG,
    kind: KIND,
    generatedAt: new Date().toISOString(),
    pageCount: pages.length,
    totalBytes,
    format,
    pages,
  };
  await upload(
    `${REMOTE_DIR}/manifest.json`,
    Buffer.from(JSON.stringify(manifest)),
    'application/json',
  );

  console.log(`[done] ${REMOTE_DIR}/manifest.json`);
  console.log(`[size] ${(totalBytes / 1024 / 1024).toFixed(1)} MB`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
