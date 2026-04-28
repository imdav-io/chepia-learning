// Extrae texto de los PDFs del curso "As it is" y lo guarda en JSON
// para que el generador de quizzes lo use sin re-parsear los PDFs.
//
// Uso: pnpm install && node extract-pdf-text.mjs
//
// Salida: ./out/lessons.json

import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const pdfParse = require('pdf-parse');

const CONTENT_DIR = process.env.CONTENT_DIR;
if (!CONTENT_DIR) {
  console.error('Falta CONTENT_DIR en .env');
  process.exit(1);
}

const BOOKS = [
  {
    slug: 'as-it-is-book-1',
    level: 'beginner',
    folder: 'Book 1',
    files: ['main.pdf', 'As it is - Book 1.pdf'],
  },
  {
    slug: 'as-it-is-book-2',
    level: 'intermediate',
    folder: 'Book 2',
    files: ['As it is - Book 2.pdf', 'main.pdf'],
  },
  {
    slug: 'as-it-is-book-3',
    level: 'advanced',
    folder: 'Book 3',
    files: ['As it is - Book 3.pdf', 'main.pdf'],
  },
];

async function firstExisting(baseDir, candidates, label) {
  for (const candidate of candidates) {
    const fullPath = path.join(baseDir, candidate);
    try {
      await fs.access(fullPath);
      return fullPath;
    } catch (_) {
      // Try the next known filename.
    }
  }
  throw new Error(`${label} no encontrado. Busqué: ${candidates.join(', ')}`);
}

async function main() {
  const out = [];

  for (const book of BOOKS) {
    const pdfPath = await firstExisting(
      path.join(CONTENT_DIR, book.folder, 'Book'),
      book.files,
      `${book.folder} PDF principal`,
    );
    console.log(`[*] Leyendo ${pdfPath}`);
    const buffer = await fs.readFile(pdfPath);
    const data = await pdfParse(buffer);

    out.push({
      slug: book.slug,
      level: book.level,
      title: path.basename(pdfPath, '.pdf'),
      pages: data.numpages,
      // Texto completo. Después se segmenta por lección heurísticamente
      // (por ahora dejamos el texto crudo y el generador ubica "Lesson N").
      rawText: data.text,
    });
    console.log(`    ${data.numpages} páginas, ${data.text.length} caracteres`);
  }

  await fs.mkdir('./out', { recursive: true });
  await fs.writeFile('./out/lessons-raw.json', JSON.stringify(out, null, 2));
  console.log('[OK] Guardado en ./out/lessons-raw.json');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
