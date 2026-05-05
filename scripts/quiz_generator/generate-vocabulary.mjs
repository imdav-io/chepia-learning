// Genera vocabulario curado por lección usando Claude Vision sobre las
// imágenes de las páginas de cada lección. Lo persiste en
// public.lesson_vocabulary y la app lo muestra como flashcards por defecto.
//
// Pipeline previo (igual que generate.mjs):
//   1) bash scripts/convert-pdf-to-images.sh
//   2) node upload-content.mjs / register-content.mjs
//   3) node generate-vocabulary.mjs [--book=<slug>] [--lesson=<n>] [--replace]
//
// Idempotente: si una lección ya tiene vocabulario, la omite. Usa --replace
// para regenerar y sobrescribir.
//
// Uso:
//   node generate-vocabulary.mjs                                # todas las lecciones
//   node generate-vocabulary.mjs --book=as-it-is-book-1         # solo un libro
//   node generate-vocabulary.mjs --book=as-it-is-book-1 --lesson=1
//   node generate-vocabulary.mjs --book=as-it-is-book-1 --replace
//
// Nota: este script requiere que la migración 0004_lesson_vocabulary.sql ya
// esté aplicada en Supabase (SQL Editor → pegar el archivo → Run).

import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createClient } from '@supabase/supabase-js';
import Anthropic from '@anthropic-ai/sdk';

const {
  ANTHROPIC_API_KEY,
  ANTHROPIC_MODEL = 'claude-sonnet-4-5',
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
} = process.env;

if (!ANTHROPIC_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Faltan ANTHROPIC_API_KEY, SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en .env');
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

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

const PAGES_DIR = path.resolve('./out/pages');
const SLEEP_MS = 1500; // throttle conservador para no saturar la API
const INTRO_OFFSET = 10; // primeras N páginas asumidas como portada/índice
const MAX_ATTEMPTS = Number.parseInt(process.env.GENERATE_MAX_ATTEMPTS ?? '3', 10);
const MIN_TERMS = 8;
const MAX_TERMS = 12;

const BOOKS_META = {
  'as-it-is-book-1': { level: 'beginner', title: 'As it is — Book 1' },
  'as-it-is-book-2': { level: 'intermediate', title: 'As it is — Book 2' },
  'as-it-is-book-3': { level: 'advanced', title: 'As it is — Book 3' },
};

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// ---------------------------------------------------------
// Páginas / imágenes (mismo patrón que generate.mjs)
// ---------------------------------------------------------
async function listPagesForBook(bookSlug) {
  const dir = path.join(PAGES_DIR, bookSlug);
  let files;
  try {
    files = await fs.readdir(dir);
  } catch (_) {
    throw new Error(`No hay imágenes para ${bookSlug}. Corre scripts/convert-pdf-to-images.sh primero.`);
  }
  return files
    .filter((f) => /^page-\d+\.jpg$/.test(f))
    .map((f) => ({
      num: Number.parseInt(f.match(/^page-(\d+)\.jpg$/)[1], 10),
      path: path.join(dir, f),
    }))
    .sort((a, b) => a.num - b.num);
}

function rangeFor(totalPages, numLessons, lessonNumber) {
  const usable = Math.max(numLessons, totalPages - INTRO_OFFSET);
  const perLesson = Math.max(1, Math.floor(usable / numLessons));
  const start = INTRO_OFFSET + (lessonNumber - 1) * perLesson + 1;
  const end =
    lessonNumber === numLessons
      ? totalPages
      : Math.min(INTRO_OFFSET + lessonNumber * perLesson, totalPages);
  return { start: Math.max(1, start), end: Math.max(start, end) };
}

async function loadImagesInRange(pages, startPage, endPage) {
  const result = [];
  for (const p of pages) {
    if (p.num < startPage || p.num > endPage) continue;
    const buf = await fs.readFile(p.path);
    result.push({
      mediaType: 'image/jpeg',
      base64: buf.toString('base64'),
      sizeBytes: buf.length,
    });
  }
  return result;
}

// ---------------------------------------------------------
// Prompt + generación
// ---------------------------------------------------------
const SYSTEM_PROMPT = `Eres un teacher experto de inglés (CEFR A1-C1) para alumnos hispanohablantes. Recibirás imágenes con el material fuente de una unidad. Trátalas solo como insumo: tu trabajo es extraer las palabras y expresiones más importantes para que el estudiante las practique como flashcards.

Reglas críticas:
- Devuelve SIEMPRE JSON válido sin texto adicional.
- NUNCA menciones páginas, imágenes, escaneos, PDF, libro, texto, pasaje, ni frases meta del tipo "según la página", "in the text", "según el material".
- El significado debe ser una traducción/definición clara en español, breve, sin meta-frases.
- El ejemplo en inglés debe usar la palabra/expresión naturalmente, en una oración corta y autosuficiente (sin diálogos genéricos tipo "as we saw before").`;

function userPrompt({ level, lessonNumber }) {
  return `Contexto interno (no lo cites):
- Nivel CEFR aproximado: ${level}
- Unidad/lección: ${lessonNumber}

A partir de las imágenes, extrae entre ${MIN_TERMS} y ${MAX_TERMS} entradas de vocabulario CLAVE (las que un estudiante debería dominar al terminar la unidad). Prioriza:
- Vocabulario nuevo o central de la unidad (sustantivos, verbos, adjetivos, expresiones).
- Palabras que aparecen varias veces o en ejemplos importantes.
- Phrasal verbs y colocaciones útiles si los hay.

Evita:
- Palabras función obvias (the, of, is, are…) salvo que sean foco de la unidad.
- Palabras repetidas con misma raíz si ya cubriste una forma.
- Expresiones que no aporten al objetivo comunicativo de la unidad.

Para cada entrada devuelve:
- "term": palabra o expresión en inglés, en minúsculas salvo nombres propios.
- "meaning_es": significado en español, claro y breve (3-12 palabras). Si la palabra tiene varias acepciones, elige la que aplica en la unidad.
- "example_en": una oración corta en inglés que use la palabra naturalmente. Que tenga sentido por sí sola, no dependa del contexto de la unidad.
- "pronunciation": pista fonética simple para hispanohablantes (ej. "ka-RI-er" para "career"). Opcional, omite el campo si no aplica.

Buenos ejemplos:
{
  "term": "tired",
  "meaning_es": "cansado",
  "example_en": "I'm tired after work.",
  "pronunciation": "TAI-erd"
}
{
  "term": "to look for",
  "meaning_es": "buscar",
  "example_en": "She is looking for her keys."
}

Malos ejemplos (NO hacer):
- "meaning_es": "esta palabra significa cansado" → demasiado meta.
- "example_en": "As we saw in the text, this word means tired." → habla del material.
- "term": "the" → palabra función obvia.

Responde SOLO con un JSON con la forma:
{
  "vocabulary": [
    { "term": "...", "meaning_es": "...", "example_en": "...", "pronunciation": "..." }
  ]
}`;
}

function extractJson(text) {
  let cleaned = text.replace(/```json\s*|```/g, '').trim();
  try {
    const parsed = JSON.parse(cleaned);
    if (typeof parsed === 'string') {
      cleaned = parsed.trim();
    } else {
      return parsed;
    }
  } catch (_) {
    // fall through al regex
  }
  const match = cleaned.match(/\{[\s\S]*\}/);
  if (!match) throw new Error('Respuesta sin JSON: ' + text.slice(0, 200));
  return JSON.parse(match[0]);
}

function validateVocabulary(items) {
  const issues = [];
  if (!Array.isArray(items)) {
    throw new Error('La respuesta no contiene un arreglo de vocabulary');
  }
  if (items.length < MIN_TERMS || items.length > MAX_TERMS) {
    issues.push(`se esperaban entre ${MIN_TERMS} y ${MAX_TERMS} entradas, llegaron ${items.length}`);
  }
  const seen = new Set();
  for (const [i, entry] of items.entries()) {
    const label = `entry${i + 1}`;
    if (typeof entry?.term !== 'string' || entry.term.trim().length < 2) {
      issues.push(`${label}: term ausente o demasiado corto`);
    }
    if (typeof entry?.meaning_es !== 'string' || entry.meaning_es.trim().length < 2) {
      issues.push(`${label}: meaning_es ausente o demasiado corto`);
    }
    if (entry?.example_en !== undefined && typeof entry.example_en !== 'string') {
      issues.push(`${label}: example_en debe ser string`);
    }
    if (entry?.pronunciation !== undefined && typeof entry.pronunciation !== 'string') {
      issues.push(`${label}: pronunciation debe ser string`);
    }
    const key = String(entry?.term ?? '').trim().toLowerCase();
    if (key) {
      if (seen.has(key)) issues.push(`${label}: term duplicado ("${key}")`);
      seen.add(key);
    }
  }
  if (issues.length > 0) {
    throw new Error(issues.slice(0, 8).join('; '));
  }
}

async function generateVocabulary({ level, lessonNumber, images }) {
  const content = [
    { type: 'text', text: userPrompt({ level, lessonNumber }) },
    ...images.map((img) => ({
      type: 'image',
      source: { type: 'base64', media_type: img.mediaType, data: img.base64 },
    })),
  ];
  const res = await anthropic.messages.create({
    model: ANTHROPIC_MODEL,
    max_tokens: 4096,
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content }],
  });
  const text = res.content
    .filter((c) => c.type === 'text')
    .map((c) => c.text)
    .join('\n');
  if (!text) {
    throw new Error('Sin texto en respuesta de Claude: ' + JSON.stringify(res).slice(0, 300));
  }
  const parsed = extractJson(text);
  const vocab = Array.isArray(parsed) ? parsed : parsed.vocabulary;
  if (!Array.isArray(vocab) || vocab.length === 0) {
    throw new Error('Respuesta sin entradas de vocabulary');
  }
  return vocab;
}

async function generateValidatedVocabulary({ level, lessonNumber, images }) {
  let lastError;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      const items = await generateVocabulary({ level, lessonNumber, images });
      validateVocabulary(items);
      return items;
    } catch (e) {
      lastError = e;
      if (attempt < MAX_ATTEMPTS) {
        console.warn(`[retry] L${lessonNumber}: ${e.message}`);
        await sleep(SLEEP_MS);
      }
    }
  }
  throw new Error(
    `La respuesta no pasó validación después de ${MAX_ATTEMPTS} intentos: ${lastError.message}`,
  );
}

// ---------------------------------------------------------
// Persistencia
// ---------------------------------------------------------
async function existingVocabularyCount(lessonId) {
  const { count, error } = await supabase
    .from('lesson_vocabulary')
    .select('id', { count: 'exact', head: true })
    .eq('lesson_id', lessonId);
  if (error) throw error;
  return count ?? 0;
}

async function deleteVocabulary(lessonId) {
  const { error } = await supabase
    .from('lesson_vocabulary')
    .delete()
    .eq('lesson_id', lessonId);
  if (error) throw error;
}

async function persistVocabulary({ lessonId, items }) {
  const now = new Date().toISOString();
  const rows = items.map((item, idx) => ({
    lesson_id: lessonId,
    term: String(item.term).trim(),
    meaning_es: String(item.meaning_es).trim(),
    example_en: item.example_en ? String(item.example_en).trim() : null,
    pronunciation: item.pronunciation ? String(item.pronunciation).trim() : null,
    sort_order: idx,
    generated_by_ai: true,
    ai_model: ANTHROPIC_MODEL,
    ai_generated_at: now,
    updated_at: now,
  }));
  const { error } = await supabase.from('lesson_vocabulary').insert(rows);
  if (error) throw error;
}

// ---------------------------------------------------------
// Main
// ---------------------------------------------------------
async function main() {
  const filterBookSlug = args.book;
  const filterLessonNumber = args.lesson ? Number.parseInt(args.lesson, 10) : null;
  const replaceExisting = args.replace === true || args.replace === 'true';

  if (replaceExisting) {
    console.warn('[warn] --replace activo: el vocabulario existente se reemplazará tras generar una versión válida.');
  }

  let booksQuery = supabase.from('books').select('id, slug').order('slug');
  if (filterBookSlug) booksQuery = booksQuery.eq('slug', filterBookSlug);
  const { data: books, error: be } = await booksQuery;
  if (be) throw be;

  for (const book of books) {
    const meta = BOOKS_META[book.slug];
    if (!meta) {
      console.warn(`[skip book] ${book.slug}: sin metadata`);
      continue;
    }
    const pages = await listPagesForBook(book.slug);
    const totalPages = pages.length;

    let lessonsQuery = supabase
      .from('lessons')
      .select('id, number, pdf_start_page, pdf_end_page')
      .eq('book_id', book.id)
      .order('number');
    if (filterLessonNumber) lessonsQuery = lessonsQuery.eq('number', filterLessonNumber);
    const { data: lessons, error: le } = await lessonsQuery;
    if (le) throw le;

    console.log(`\n=== ${book.slug} (${totalPages} pp, ${lessons.length} lessons) ===`);

    for (const lesson of lessons) {
      try {
        const existing = await existingVocabularyCount(lesson.id);
        if (existing > 0 && !replaceExisting) {
          console.log(`[skip] L${lesson.number}: ya tiene ${existing} entradas`);
          continue;
        }

        const range =
          lesson.pdf_start_page && lesson.pdf_end_page
            ? { start: lesson.pdf_start_page, end: Math.min(lesson.pdf_end_page, totalPages) }
            : rangeFor(totalPages, lessons.length, lesson.number);

        const images = await loadImagesInRange(pages, range.start, range.end);
        if (images.length === 0) {
          console.warn(`[skip] L${lesson.number}: sin imágenes en pp ${range.start}-${range.end}`);
          continue;
        }
        const totalKB = Math.round(images.reduce((s, i) => s + i.sizeBytes, 0) / 1024);
        console.log(`[gen ] L${lesson.number} pp ${range.start}-${range.end} (${images.length} imgs, ${totalKB}KB)`);

        const items = await generateValidatedVocabulary({
          level: meta.level,
          lessonNumber: lesson.number,
          images,
        });
        if (existing > 0 && replaceExisting) {
          await deleteVocabulary(lesson.id);
          console.log(`[repl] L${lesson.number}: vocabulario anterior eliminado`);
        }
        await persistVocabulary({ lessonId: lesson.id, items });
        console.log(`[ok  ] L${lesson.number}: ${items.length} entradas`);

        await sleep(SLEEP_MS);
      } catch (e) {
        console.error(`[err ] L${lesson.number}: ${e.message}`);
      }
    }
  }
  console.log('\n[DONE]');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
