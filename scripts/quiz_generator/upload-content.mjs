// Sube los PDFs y audios convertidos a Supabase Storage (bucket "content"
// privado). NO subir WMA: convertir antes con scripts/convert-audio.sh.
//
// Uso: node upload-content.mjs

import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createClient } from '@supabase/supabase-js';

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CONTENT_DIR } = process.env;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !CONTENT_DIR) {
  console.error('Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o CONTENT_DIR.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const BUCKET = 'content';

const BOOKS = [
  {
    slug: 'as-it-is-book-1',
    folder: 'Book 1',
    pdf: {
      localCandidates: ['Book/main.pdf', 'Book/As it is - Book 1.pdf'],
      remote: 'books/as-it-is-book-1/pdf/v1/main.pdf',
    },
    studyGuide: {
      localCandidates: [
        'Book/study_guide.pdf',
        'Book/English. AS IT IS. Study Guide [Book 1].pdf',
      ],
      remote: 'books/as-it-is-book-1/pdf/v1/study_guide.pdf',
    },
    audioDir: 'Audios/mp3',
    audioRemoteDir: 'books/as-it-is-book-1/audio/v1',
  },
  {
    slug: 'as-it-is-book-2',
    folder: 'Book 2',
    pdf: {
      localCandidates: ['Book/As it is - Book 2.pdf', 'Book/main.pdf'],
      remote: 'books/as-it-is-book-2/pdf/v1/main.pdf',
    },
    studyGuide: {
      localCandidates: [
        'Book/English. AS IT IS. Study Guide [Book 2].pdf',
        'Book/study_guide.pdf',
      ],
      remote: 'books/as-it-is-book-2/pdf/v1/study_guide.pdf',
    },
    audioDir: 'Audios/mp3',
    audioRemoteDir: 'books/as-it-is-book-2/audio/v1',
  },
  {
    slug: 'as-it-is-book-3',
    folder: 'Book 3',
    pdf: {
      localCandidates: ['Book/As it is - Book 3.pdf', 'Book/main.pdf'],
      remote: 'books/as-it-is-book-3/pdf/v1/main.pdf',
    },
    audioDir: 'Audios/mp3',
    audioRemoteDir: 'books/as-it-is-book-3/audio/v1',
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

async function uploadFile(localPath, remotePath, contentType) {
  const buffer = await fs.readFile(localPath);
  const { error } = await supabase.storage.from(BUCKET).upload(remotePath, buffer, {
    contentType,
    upsert: true,
  });
  if (error) throw new Error(`upload ${remotePath}: ${error.message}`);
  console.log(`[ok] ${remotePath} (${(buffer.byteLength / 1024 / 1024).toFixed(1)} MB)`);
}

async function main() {
  for (const book of BOOKS) {
    console.log(`\n=== ${book.folder} ===`);

    const bookRoot = path.join(CONTENT_DIR, book.folder);
    const pdfPath = await firstExisting(
      bookRoot,
      book.pdf.localCandidates,
      `${book.folder} PDF principal`,
    );
    await uploadFile(pdfPath, book.pdf.remote, 'application/pdf');

    if (book.studyGuide) {
      try {
        const sgPath = await firstExisting(
          bookRoot,
          book.studyGuide.localCandidates,
          `${book.folder} study guide`,
        );
        await uploadFile(sgPath, book.studyGuide.remote, 'application/pdf');
      } catch (e) {
        console.warn(`[warn] sin study guide: ${e.message}`);
      }
    }

    const audioDir = path.join(CONTENT_DIR, book.folder, book.audioDir);
    let entries;
    try {
      entries = await fs.readdir(audioDir);
    } catch (e) {
      console.warn(`[warn] sin carpeta de audio (${audioDir}). Convierte WMA a MP3 primero.`);
      continue;
    }
    const mp3s = entries.filter((f) => f.toLowerCase().endsWith('.mp3'));
    for (const f of mp3s) {
      const local = path.join(audioDir, f);
      const remote = `${book.audioRemoteDir}/${f.replace(/\s+/g, '_').toLowerCase()}`;
      await uploadFile(local, remote, 'audio/mpeg');
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
