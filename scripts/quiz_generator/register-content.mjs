// Registra en Supabase los libros, lecciones y assets reales después de
// subir los archivos al bucket "content" con upload-content.mjs.
//
// Idempotente: usa upsert por slug/(book,number)/path.
//
// Uso:
//   1) bash scripts/convert-audio.sh        (WMA -> MP3 si aplica)
//   2) node upload-content.mjs               (sube PDFs y MP3s al Storage)
//   3) node register-content.mjs             (registra/actualiza en BD)
//
// Cuando lo corras eliminará los assets demo (que apuntan a URLs http://...
// públicas) y los reemplazará por los storage_path reales del bucket.

import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createClient } from '@supabase/supabase-js';

const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CONTENT_DIR } = process.env;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !CONTENT_DIR) {
  console.error('Faltan SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY o CONTENT_DIR en .env.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// Estructura del contenido. Ajusta los paths si cambiaste la organización local.
const BOOKS = [
  {
    slug: 'as-it-is-book-1',
    level: 'beginner',
    title: 'As it is — Book 1',
    folder: 'Book 1',
    pdfRemote: 'books/as-it-is-book-1/pdf/v1/main.pdf',
    studyGuideRemote: 'books/as-it-is-book-1/pdf/v1/study_guide.pdf',
    audioDir: 'Audios/mp3',
    audioRemoteDir: 'books/as-it-is-book-1/audio/v1',
  },
  {
    slug: 'as-it-is-book-2',
    level: 'intermediate',
    title: 'As it is — Book 2',
    folder: 'Book 2',
    pdfRemote: 'books/as-it-is-book-2/pdf/v1/main.pdf',
    studyGuideRemote: 'books/as-it-is-book-2/pdf/v1/study_guide.pdf',
    audioDir: 'Audios/mp3',
    audioRemoteDir: 'books/as-it-is-book-2/audio/v1',
  },
  {
    slug: 'as-it-is-book-3',
    level: 'advanced',
    title: 'As it is — Book 3',
    folder: 'Book 3',
    pdfRemote: 'books/as-it-is-book-3/pdf/v1/main.pdf',
    audioDir: 'Audios/mp3',
    audioRemoteDir: 'books/as-it-is-book-3/audio/v1',
  },
];

async function ensureBook(book) {
  const { data: levelRow } = await supabase
    .from('levels')
    .select('id')
    .eq('code', book.level)
    .single();
  if (!levelRow) throw new Error(`Nivel ${book.level} no existe`);

  const { data: existing } = await supabase
    .from('books')
    .select('id')
    .eq('slug', book.slug)
    .maybeSingle();
  if (existing) return existing.id;

  const { data, error } = await supabase
    .from('books')
    .insert({
      slug: book.slug,
      title: book.title,
      level_id: levelRow.id,
      language: 'en',
    })
    .select('id')
    .single();
  if (error) throw error;
  return data.id;
}

async function ensureLesson(bookId, number, title) {
  const { data: existing } = await supabase
    .from('lessons')
    .select('id')
    .eq('book_id', bookId)
    .eq('number', number)
    .maybeSingle();
  if (existing) return existing.id;

  const { data, error } = await supabase
    .from('lessons')
    .insert({ book_id: bookId, number, title })
    .select('id')
    .single();
  if (error) throw error;
  return data.id;
}

/** Borra cualquier asset previo (incluye demos) y crea uno nuevo. */
async function upsertAsset({ kind, lessonId, bookId, storagePath, mimeType, durationSec, pages }) {
  // Limpia previos del mismo (kind, lesson_id, book_id) para idempotencia.
  let q = supabase.from('assets').delete().eq('kind', kind);
  if (lessonId) q = q.eq('lesson_id', lessonId);
  else q = q.is('lesson_id', null).eq('book_id', bookId);
  await q;

  const { error } = await supabase.from('assets').insert({
    kind,
    lesson_id: lessonId ?? null,
    book_id: bookId,
    storage_path: storagePath,
    mime_type: mimeType,
    duration_sec: durationSec ?? null,
    pages: pages ?? null,
    version: 1,
  });
  if (error) throw error;
}

function parseLessonNumber(filename) {
  // Acepta "Lesson 1.mp3", "lesson_01.mp3", "lesson-1.mp3", etc.
  const m = filename.toLowerCase().match(/lesson[\s_-]+(\d+)/);
  if (m) return parseInt(m[1], 10);
  return null;
}

async function main() {
  for (const book of BOOKS) {
    console.log(`\n=== ${book.title} ===`);
    const bookId = await ensureBook(book);

    // PDF principal
    upsertAsset.bookSlug = book.slug;
    await upsertAsset({
      kind: 'pdf',
      bookId,
      storagePath: book.pdfRemote,
      mimeType: 'application/pdf',
    });
    console.log(`[pdf] ${book.pdfRemote}`);

    // Study guide opcional
    if (book.studyGuideRemote) {
      try {
        await upsertAsset({
          kind: 'study_guide',
          bookId,
          storagePath: book.studyGuideRemote,
          mimeType: 'application/pdf',
        });
        console.log(`[study_guide] ${book.studyGuideRemote}`);
      } catch (e) {
        console.warn(`[warn] sin study_guide: ${e.message}`);
      }
    }

    // Audios por lección. Los descubrimos del filesystem local.
    const localAudioDir = path.join(CONTENT_DIR, book.folder, book.audioDir);
    let entries = [];
    try {
      entries = await fs.readdir(localAudioDir);
    } catch (_) {
      console.warn(`[warn] no se encontró ${localAudioDir}. Convierte WMA→MP3 y vuelve a correr.`);
      continue;
    }

    const mp3s = entries.filter((f) => f.toLowerCase().endsWith('.mp3'));
    for (const f of mp3s) {
      const number = parseLessonNumber(f);
      if (!number) {
        console.log(`[skip] ${f} (no es Lesson N.mp3)`);
        continue;
      }
      const lessonId = await ensureLesson(bookId, number, `Lesson ${number}`);
      // remote path debe coincidir con upload-content.mjs (lo replicamos):
      const remoteName = f.replace(/\s+/g, '_').toLowerCase();
      const storagePath = `${book.audioRemoteDir}/${remoteName}`;
      await upsertAsset({
        kind: 'audio',
        bookId,
        lessonId,
        storagePath,
        mimeType: 'audio/mpeg',
      });
      console.log(`[audio] Lesson ${number} -> ${storagePath}`);
    }
  }

  console.log('\n[DONE]');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
