// Genera flashcards de vocabulario por lección usando OpenAI/ChatGPT Vision
// sobre las imágenes de las páginas de cada lección. Lo persiste en
// public.lesson_vocabulary y la app lo muestra como deck principal de
// flashcards para esa lección.
//
// Pipeline previo (igual que generate.mjs):
//   1) bash scripts/convert-pdf-to-images.sh
//   2) node upload-content.mjs / register-content.mjs
//   3) npm run generate-vocabulary -- [--book=<slug>] [--lesson=<n>] [--replace]
//
// Idempotente: si una lección ya tiene vocabulario, la omite. Usa --replace
// para regenerar y sobrescribir.
//
// Uso:
//   npm run generate-vocabulary                                # todas las lecciones
//   npm run generate-vocabulary -- --book=as-it-is-book-1      # solo un libro
//   npm run generate-vocabulary -- --book=as-it-is-book-1 --lesson=1
//   npm run generate-vocabulary -- --book=as-it-is-book-1 --from-lesson=1 --to-lesson=10
//   npm run generate-vocabulary -- --book=as-it-is-book-1 --replace
//
// Nota: este script requiere que la migración 0004_lesson_vocabulary.sql ya
// esté aplicada en Supabase (SQL Editor → pegar el archivo → Run).

import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createClient } from '@supabase/supabase-js';

const {
  OPENAI_API_KEY,
  OPENAI_MODEL = 'gpt-5-mini',
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
} = process.env;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en .env');
  process.exit(1);
}

if (!OPENAI_API_KEY) {
  console.error('Falta OPENAI_API_KEY en .env');
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

const PAGES_DIR = path.resolve('./out/pages');
const SLEEP_MS = Number.parseInt(process.env.OPENAI_REQUEST_DELAY_MS ?? '1500', 10);
const INTRO_OFFSET = 10; // primeras N páginas asumidas como portada/índice
const MAX_ATTEMPTS = Number.parseInt(process.env.GENERATE_MAX_ATTEMPTS ?? '3', 10);
const MIN_TERMS = 8;
const MAX_TERMS = 12;

const BOOKS_META = {
  'as-it-is-book-1': { level: 'beginner', title: 'As it is — Book 1' },
  'as-it-is-book-2': { level: 'intermediate', title: 'As it is — Book 2' },
  'as-it-is-book-3': { level: 'advanced', title: 'As it is — Book 3' },
};

const META_REFERENCE_PATTERNS = [
  /\b(?:according to|based on|shown in|seen in|from)\s+(?:the\s+)?(?:page|pages|image|images|picture|pictures|book|text|passage|lesson|unit|exercise|material|source|pdf)\b/i,
  /\b(?:in|on)\s+(?:the|this|these)\s+(?:page|pages|image|images|picture|pictures|book|text|passage|lesson|unit|exercise|material|source|pdf)\b/i,
  /\b(?:this|the)\s+(?:page|image|picture|book|text|passage|lesson|unit|exercise|material|source|pdf)\s+(?:shows|says|states|mentions|explains|contains|describes|practices|teaches)\b/i,
  /\bseg[uú]n\s+(?:la|el|las|los)?\s*(?:p[aá]gina|imagen|libro|texto|lecci[oó]n|unidad|ejercicio|material|fuente|pdf)\b/i,
  /\b(?:en|de)\s+(?:la|el|las|los)\s+(?:p[aá]gina|imagen|libro|texto|lecci[oó]n|unidad|ejercicio|material|fuente|pdf)\b/i,
  /\b(?:como se vio|lo que se vio|as we saw|in this lesson|in the unit)\b/i,
];

function levelPlan(level) {
  if (level === 'beginner') {
    return `Book 1 / beginner:
- Extract very basic, useful vocabulary: objects, animals, food, places, simple actions, common adjectives, and short expressions.
- If the unit focuses on a basic structure such as this/that, is/are, a/an, plurals, or simple questions, include those forms only when they work as clear flashcards.
- Keep English examples very short, such as "This is an apple." or "The dog is big."`;
  }
  if (level === 'intermediate') {
    return `Book 2 / intermediate:
- Include vocabulary, verbs, collocations, prepositions, functional expressions, and short natural phrases.
- Examples may be slightly fuller sentences, but they must stay clear.`;
  }
  return `Book 3 / advanced:
- Include terms, expressions, collocations, phrasal verbs, connectors, academic verbs, or nuanced vocabulary when present.
- Examples should teach real usage, not only translate the word.`;
}

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
const SYSTEM_PROMPT = `You are an expert English teacher (CEFR A1-C1) for Spanish-speaking learners. You will receive images with source material from a unit. Treat those images only as internal input: your job is to extract the most important words and expressions for flashcard practice.

Critical rules:
- Always return valid JSON with no extra text.
- Never mention pages, images, scans, PDFs, books, texts, passages, or meta phrases such as "according to the page", "in the text", or "based on the material".
- The meaning must be a short, clear Spanish translation/definition, without meta phrases.
- The English example must use the word/expression naturally in a short, self-contained sentence, without generic references such as "as we saw before".`;

function userPrompt({ level, lessonNumber }) {
  return `Internal context (do not cite it):
- Approximate CEFR level: ${level}
- Unit/lesson: ${lessonNumber}

From the images, extract between ${MIN_TERMS} and ${MAX_TERMS} KEY vocabulary entries that a learner should master after the unit. Prioritize:
- New or central vocabulary from the unit: nouns, verbs, adjectives, and expressions.
- Words that appear several times or in important examples.
- Useful phrasal verbs and collocations, if present.

${levelPlan(level)}

Avoid:
- Obvious function words (the, of, is, are...) unless they are the focus of the unit.
- Repeated words with the same root if one form is already covered.
- Expressions that do not support the communicative goal of the unit.

For each entry return:
- "term": English word or expression, lowercase except proper nouns.
- "meaning_es": clear, short Spanish meaning (3-12 words). If the word has several meanings, choose the one that fits the unit.
- "example_en": a short English sentence that uses the word naturally. It must make sense by itself and not depend on the unit context.
- "pronunciation": simple phonetic hint for Spanish speakers, such as "ka-RI-er" for "career". Optional; omit it when not useful.

Good examples:
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

Bad examples (do not do this):
- "meaning_es": "esta palabra significa cansado" -> too meta.
- "example_en": "As we saw in the text, this word means tired." -> refers to the material.
- "term": "the" -> obvious function word.

Return ONLY JSON with this shape:
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
    for (const key of ['term', 'meaning_es', 'example_en', 'pronunciation']) {
      const value = entry?.[key];
      if (typeof value !== 'string') continue;
      if (META_REFERENCE_PATTERNS.some((pattern) => pattern.test(value))) {
        issues.push(`${label}.${key}: referencia meta prohibida`);
      }
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

async function generateVocabularyWithOpenAI({ level, lessonNumber, images }) {
  const content = [
    { type: 'input_text', text: userPrompt({ level, lessonNumber }) },
    ...images.map((img) => ({
      type: 'input_image',
      image_url: `data:${img.mediaType};base64,${img.base64}`,
      detail: 'low',
    })),
  ];
  const body = {
    model: OPENAI_MODEL,
    instructions: SYSTEM_PROMPT,
    input: [{ role: 'user', content }],
    max_output_tokens: 4096,
  };
  const res = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`OpenAI ${res.status}: ${errText.slice(0, 500)}`);
  }
  const data = await res.json();
  const text = extractOpenAIText(data);
  if (!text) {
    throw new Error('Sin texto en respuesta de OpenAI: ' + JSON.stringify(data).slice(0, 400));
  }
  const parsed = extractJson(text);
  const vocab = Array.isArray(parsed) ? parsed : parsed.vocabulary;
  if (!Array.isArray(vocab) || vocab.length === 0) {
    throw new Error('Respuesta sin entradas de vocabulary');
  }
  return vocab;
}

function extractOpenAIText(data) {
  if (typeof data.output_text === 'string') return data.output_text;
  const chunks = [];
  for (const item of data.output ?? []) {
    for (const part of item.content ?? []) {
      if (part.type === 'output_text' && typeof part.text === 'string') {
        chunks.push(part.text);
      }
      if (part.type === 'text' && typeof part.text === 'string') {
        chunks.push(part.text);
      }
    }
  }
  return chunks.join('\n').trim();
}

async function generateVocabulary({ level, lessonNumber, images }) {
  return generateVocabularyWithOpenAI({ level, lessonNumber, images });
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
    ai_model: OPENAI_MODEL,
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
  const fromLesson = args['from-lesson'] ? Number.parseInt(args['from-lesson'], 10) : null;
  const toLesson = args['to-lesson'] ? Number.parseInt(args['to-lesson'], 10) : null;
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
    if (!filterLessonNumber && fromLesson) lessonsQuery = lessonsQuery.gte('number', fromLesson);
    if (!filterLessonNumber && toLesson) lessonsQuery = lessonsQuery.lte('number', toLesson);
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
