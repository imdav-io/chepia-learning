// Sube páginas ya renderizadas a Supabase Storage y crea un manifest.
//
// Fase 1: Book 1. Usa las imágenes generadas por scripts/convert-pdf-to-images.sh:
//   out/pages/as-it-is-book-1/page-001.jpg ...
//
// Uso:
//   cd scripts/quiz_generator
//   node upload-page-images.mjs --book=as-it-is-book-1

import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createClient } from '@supabase/supabase-js';

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
const PAGES_DIR = path.resolve('./out/pages', BOOK_SLUG);
const REMOTE_DIR = `books/${BOOK_SLUG}/pages/v1`;
const BUCKET = 'content';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function jpegSize(buf) {
  let i = 2;
  while (i < buf.length) {
    if (buf[i] !== 0xff) break;
    const marker = buf[i + 1];
    const len = buf.readUInt16BE(i + 2);
    if (
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf)
    ) {
      return {
        height: buf.readUInt16BE(i + 5),
        width: buf.readUInt16BE(i + 7),
      };
    }
    i += 2 + len;
  }
  return { width: 0, height: 0 };
}

async function upload(remotePath, buffer, contentType) {
  const { error } = await supabase.storage.from(BUCKET).upload(remotePath, buffer, {
    contentType,
    upsert: true,
  });
  if (error) throw new Error(`${remotePath}: ${error.message}`);
}

async function main() {
  const entries = await fs.readdir(PAGES_DIR);
  const pageFiles = entries
    .filter((f) => /^page-\d+\.jpg$/i.test(f))
    .map((file) => ({
      file,
      number: Number.parseInt(file.match(/^page-(\d+)\.jpg$/i)[1], 10),
    }))
    .sort((a, b) => a.number - b.number);

  if (pageFiles.length === 0) {
    throw new Error(`No encontré páginas en ${PAGES_DIR}`);
  }

  const pages = [];
  let totalBytes = 0;
  console.log(`Subiendo ${pageFiles.length} páginas de ${BOOK_SLUG}...`);

  for (const page of pageFiles) {
    const localPath = path.join(PAGES_DIR, page.file);
    const buffer = await fs.readFile(localPath);
    const size = jpegSize(buffer);
    const remotePath = `${REMOTE_DIR}/${page.file}`;
    await upload(remotePath, buffer, 'image/jpeg');
    totalBytes += buffer.byteLength;
    pages.push({
      pageNumber: page.number,
      storagePath: remotePath,
      width: size.width,
      height: size.height,
      sizeBytes: buffer.byteLength,
      mimeType: 'image/jpeg',
    });
    if (page.number % 20 === 0 || page.number === pageFiles.length) {
      console.log(`[ok] ${page.number}/${pageFiles.length}`);
    }
  }

  const manifest = {
    version: 1,
    bookSlug: BOOK_SLUG,
    generatedAt: new Date().toISOString(),
    pageCount: pages.length,
    totalBytes,
    format: 'jpg',
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
