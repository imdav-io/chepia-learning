// Genera quizzes con Gemini Vision a partir de las páginas escaneadas de cada
// libro. Build-time: corre en tu Mac, NO en runtime de la app.
//
// Pipeline previo:
//   1) bash scripts/convert-audio.sh                     (WMA -> MP3 si aplica)
//   2) bash scripts/convert-pdf-to-images.sh             (PDF -> JPEG por página)
//   3) node upload-content.mjs                            (sube PDFs/MP3 al Storage)
//   4) node register-content.mjs                          (registra books/lessons/assets)
//   5) node generate.mjs [--book=<slug>] [--lesson=<n>] [--replace]
//      (este script)
//
// Idempotente: si una lección ya tiene quiz, la omite. Usa --replace para
// regenerar y sobrescribir quizzes existentes después de validar la respuesta.
//
// Uso:
//   node generate.mjs                       # todas las lecciones de los 3 libros
//   node generate.mjs --book=as-it-is-book-1   # solo un libro
//   node generate.mjs --book=as-it-is-book-1 --lesson=1   # 1 sola lección (smoke test)
//   node generate.mjs --book=as-it-is-book-1 --lesson=1 --replace

import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createClient } from '@supabase/supabase-js';

const {
  GEMINI_API_KEY,
  GEMINI_MODEL = 'gemini-2.5-flash',
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
} = process.env;

if (!GEMINI_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Faltan GEMINI_API_KEY, SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en .env');
  process.exit(1);
}

const args = Object.fromEntries(
  process.argv.slice(2)
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
const RPM = 15; // gemini-2.5-flash free tier
const SLEEP_MS = Math.ceil(60_000 / RPM); // 4 seg entre requests
const INTRO_OFFSET = 10; // primeras N páginas asumidas como portada/índice
const MAX_ATTEMPTS = Number.parseInt(process.env.GENERATE_MAX_ATTEMPTS ?? '3', 10);

const ALLOWED_KINDS = new Set(['multiple_choice', 'true_false', 'fill_blank']);

const META_REFERENCE_PATTERNS = [
  {
    re: /\b(?:according to|based on|shown in|seen in|from)\s+(?:the\s+)?(?:page|pages|image|images|picture|pictures|book|text|passage|lesson|unit|exercise|material|source|pdf)\b/i,
    label: 'referencia meta en inglés',
  },
  {
    re: /\b(?:in|on)\s+(?:the|this|these)\s+(?:page|pages|image|images|picture|pictures|book|text|passage|lesson|unit|exercise|material|source|pdf)\b/i,
    label: 'referencia a página/imagen/texto en inglés',
  },
  {
    re: /\b(?:this|the)\s+(?:page|image|picture|book|text|passage|lesson|unit|exercise|material|source|pdf)\s+(?:shows|says|states|mentions|explains|contains|describes|practices|teaches)\b/i,
    label: 'la pregunta habla del material, no del contenido',
  },
  {
    re: /\bseg[uú]n\s+(?:la|el|las|los)?\s*(?:p[aá]gina|imagen|libro|texto|lecci[oó]n|unidad|ejercicio|material|fuente|pdf)\b/i,
    label: 'referencia meta en español',
  },
  {
    re: /\b(?:en|de)\s+(?:la|el|las|los)\s+(?:p[aá]gina|imagen|libro|texto|lecci[oó]n|unidad|ejercicio|material|fuente|pdf)\b/i,
    label: 'referencia a página/imagen/texto en español',
  },
  {
    re: /\b(?:la|el)\s+(?:p[aá]gina|imagen|libro|texto|lecci[oó]n|unidad|ejercicio|material|fuente|pdf)\s+(?:dice|muestra|explica|menciona|contiene|describe|practica|enseña)\b/i,
    label: 'la explicación habla del material, no del contenido',
  },
  { re: /\blo que se vio\b/i, label: 'frase meta "lo que se vio"' },
  { re: /\bcomo se vio\b/i, label: 'frase meta "como se vio"' },
];

const BOOKS_META = {
  'as-it-is-book-1': { level: 'beginner', title: 'As it is — Book 1' },
  'as-it-is-book-2': { level: 'intermediate', title: 'As it is — Book 2' },
  'as-it-is-book-3': { level: 'advanced', title: 'As it is — Book 3' },
};

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// ---------------------------------------------------------
// Páginas / imágenes
// ---------------------------------------------------------
async function listPagesForBook(bookSlug) {
  const dir = path.join(PAGES_DIR, bookSlug);
  let files;
  try {
    files = await fs.readdir(dir);
  } catch (_) {
    throw new Error(`No hay imágenes para ${bookSlug}. Corre scripts/convert-pdf-to-images.sh primero.`);
  }
  const pages = files
    .filter((f) => /^page-\d+\.jpg$/.test(f))
    .map((f) => {
      const num = parseInt(f.match(/^page-(\d+)\.jpg$/)[1], 10);
      return { num, path: path.join(dir, f) };
    })
    .sort((a, b) => a.num - b.num);
  return pages;
}

function rangeFor(totalPages, numLessons, lessonNumber) {
  const usable = Math.max(numLessons, totalPages - INTRO_OFFSET);
  const perLesson = Math.max(1, Math.floor(usable / numLessons));
  const start = INTRO_OFFSET + (lessonNumber - 1) * perLesson + 1;
  const end = lessonNumber === numLessons
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
      mime: 'image/jpeg',
      base64: buf.toString('base64'),
      sizeBytes: buf.length,
    });
  }
  return result;
}

// ---------------------------------------------------------
// Gemini Vision
// ---------------------------------------------------------
const SYSTEM_PROMPT = `Eres un teacher experto de inglés (CEFR A1-C1) para alumnos hispanohablantes. Recibirás imágenes que contienen el material fuente de una unidad, pero debes tratarlas solo como insumo interno. Primero analiza internamente el objetivo comunicativo, vocabulario útil, diálogos, ejemplos, instrucciones y estructuras gramaticales. Después crea ejercicios naturales para el estudiante, como si hubieras preparado una clase práctica basada en esa unidad.

Regla crítica: NUNCA menciones páginas, imágenes, escaneos, PDF, libro, texto, pasaje ni frases como "according to the page/text/book" o "según la página/texto/libro". Las preguntas deben evaluar comprensión, uso de vocabulario y control gramatical, no la existencia del material. Si algo no es legible, ignóralo. Devuelve siempre JSON válido sin texto adicional.`;

function userPrompt({ level, lessonNumber, feedback }) {
  return `Contexto interno para calibrar dificultad:
- Nivel CEFR aproximado: ${level}
- Unidad/lección: ${lessonNumber}

Vas a recibir imágenes con el material fuente de esta unidad. Úsalas únicamente para inferir:
- el tema principal de comunicación;
- vocabulario y expresiones importantes;
- estructuras gramaticales practicadas;
- situaciones, diálogos, ejemplos y ejercicios reutilizables.

No menciones al estudiante que viste imágenes, páginas, PDF, libro, texto, pasaje o lección. No hagas preguntas visuales ni meta-preguntas. Malos ejemplos:
- "According to the page, what does ...?"
- "What is shown in the image?"
- "In the text, what word means ...?"
- "Según la página, ¿qué significa ...?"

Buenos ejemplos:
- "Which sentence uses the simple present correctly?"
- "What does Maria want to buy?"
- "Which word means 'very tired'?"
- "Complete the sentence: She ____ to school every day."

Genera EXACTAMENTE 15 preguntas mezcladas con esta distribución:
- 4 multiple_choice de comprehension sobre situaciones, diálogos, instrucciones o mini-contextos de la unidad
- 4 multiple_choice de vocabulary sobre significado, uso, colocación o sinónimo de palabras/expresiones importantes de la unidad
- 4 multiple_choice de grammar sobre estructuras practicadas en la unidad, con frases completas y naturales
- 2 true_false sobre hechos, diálogos, reglas o uso correcto practicado
- 1 fill_blank usando una oración natural basada en patrones de la unidad

Reglas:
- Cada multiple_choice tiene 4 opciones con UNA sola correcta.
- Cada true_false tiene 2 opciones ("True"/"False") con UNA correcta.
- fill_blank deja "____" en el prompt y la respuesta correcta como una de 4 opciones.
- Las preguntas y opciones DEBEN estar en inglés.
- La explicación DEBE estar en español, breve (1-2 oraciones).
- Cada pregunta debe poder contestarse desde la habilidad practicada en la unidad, no desde memoria visual.
- Usa distractores plausibles, no absurdos. Evita opciones demasiado obvias.
- Varía formatos: completar oración, elegir respuesta natural, identificar uso correcto, significado en contexto y comprensión de diálogos.
- Evita preguntas genéricas que podrían pertenecer a cualquier lección. Deben sentirse conectadas al tema, vocabulario o estructura de esta unidad.
- Evita mencionar "unit", "lesson", "material", "exercise" o "source" dentro de las preguntas.
- Prohibido usar estas palabras como referencia al material: page, image, picture, scan, PDF, book, text, passage, "according to", página, imagen, libro, texto, pasaje, "según".
- Si necesitas evaluar comprensión, pregunta directamente por la situación o diálogo.
${feedback ? `\nCorrige específicamente estos problemas detectados en un intento anterior:\n${feedback}\n` : ''}

Responde SOLO con un JSON con la forma:
{
  "questions": [
    {
      "kind": "multiple_choice" | "true_false" | "fill_blank",
      "prompt": "string",
      "explanation": "string corta en español",
      "options": [
        { "text": "string", "is_correct": true | false }
      ]
    }
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
    // Si no era JSON directo, intentamos extraer el objeto más abajo.
  }
  const match = cleaned.match(/\{[\s\S]*\}/);
  if (!match) throw new Error('Respuesta sin JSON: ' + text.slice(0, 200));
  return JSON.parse(match[0]);
}

function collectMetaReferenceIssues(value, location, issues) {
  if (typeof value !== 'string') return;
  for (const pattern of META_REFERENCE_PATTERNS) {
    if (pattern.re.test(value)) {
      issues.push(`${location}: ${pattern.label} -> "${value.slice(0, 120)}"`);
      break;
    }
  }
}

function validateQuestions(questions) {
  const issues = [];
  if (!Array.isArray(questions)) {
    throw new Error('La respuesta no contiene un arreglo de preguntas');
  }
  if (questions.length !== 15) {
    issues.push(`se esperaban 15 preguntas y llegaron ${questions.length}`);
  }

  const seenPrompts = new Set();
  for (const [i, question] of questions.entries()) {
    const qLabel = `q${i + 1}`;
    if (!ALLOWED_KINDS.has(question.kind)) {
      issues.push(`${qLabel}: kind inválido "${question.kind}"`);
    }
    if (typeof question.prompt !== 'string' || question.prompt.trim().length < 8) {
      issues.push(`${qLabel}: prompt ausente o demasiado corto`);
    }
    if (typeof question.explanation !== 'string' || question.explanation.trim().length < 8) {
      issues.push(`${qLabel}: explanation ausente o demasiado corta`);
    }
    collectMetaReferenceIssues(question.prompt, `${qLabel}.prompt`, issues);
    collectMetaReferenceIssues(question.explanation, `${qLabel}.explanation`, issues);

    const promptKey = String(question.prompt ?? '').trim().toLowerCase();
    if (promptKey) {
      if (seenPrompts.has(promptKey)) {
        issues.push(`${qLabel}: prompt duplicado`);
      }
      seenPrompts.add(promptKey);
    }

    const options = Array.isArray(question.options) ? question.options : [];
    const expectedOptions = question.kind === 'true_false' ? 2 : 4;
    if (options.length !== expectedOptions) {
      issues.push(`${qLabel}: esperaba ${expectedOptions} opciones y llegaron ${options.length}`);
    }
    const correctCount = options.filter((option) => option?.is_correct === true).length;
    if (correctCount !== 1) {
      issues.push(`${qLabel}: debe tener exactamente 1 opción correcta, tiene ${correctCount}`);
    }
    for (const [optionIndex, option] of options.entries()) {
      if (typeof option?.text !== 'string' || option.text.trim().length === 0) {
        issues.push(`${qLabel}.option${optionIndex + 1}: texto ausente`);
      }
      collectMetaReferenceIssues(option?.text, `${qLabel}.option${optionIndex + 1}`, issues);
    }
  }

  if (issues.length > 0) {
    throw new Error(issues.slice(0, 10).join('; '));
  }
}

async function generateQuestionsVision({ level, lessonNumber, images, feedback }) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const parts = [
    { text: userPrompt({ level, lessonNumber, feedback }) },
    ...images.map((img) => ({ inline_data: { mime_type: img.mime, data: img.base64 } })),
  ];
  const body = {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [{ role: 'user', parts }],
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 8192,
      responseMimeType: 'application/json',
    },
  };
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gemini ${res.status}: ${errText.slice(0, 400)}`);
  }
  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  const finishReason = data?.candidates?.[0]?.finishReason;
  if (!text) throw new Error('Sin texto en respuesta: ' + JSON.stringify(data).slice(0, 300));
  let parsed;
  try {
    parsed = extractJson(text);
  } catch (e) {
    // Diagnóstico útil: muchos JSON parse fail por trunco (MAX_TOKENS).
    const snippet = text.slice(-200);
    throw new Error(`JSON parse falló (finishReason=${finishReason}). Final: "...${snippet}"`);
  }
  if (!Array.isArray(parsed.questions) || parsed.questions.length === 0) {
    throw new Error('Sin preguntas en respuesta');
  }
  return parsed.questions;
}

async function generateValidatedQuestionsVision({ level, lessonNumber, images }) {
  let feedback = '';
  let lastError;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    const questions = await generateQuestionsVision({
      level,
      lessonNumber,
      images,
      feedback,
    });
    try {
      validateQuestions(questions);
      return questions;
    } catch (e) {
      lastError = e;
      feedback = e.message;
      if (attempt < MAX_ATTEMPTS) {
        console.warn(`[retry] L${lessonNumber}: validación falló (${e.message})`);
        await sleep(SLEEP_MS);
      }
    }
  }
  throw new Error(`La respuesta no pasó validación después de ${MAX_ATTEMPTS} intentos: ${lastError.message}`);
}

// ---------------------------------------------------------
// Persistencia (igual que antes)
// ---------------------------------------------------------
async function existingQuizId(lessonId) {
  const { data } = await supabase
    .from('quizzes')
    .select('id')
    .eq('lesson_id', lessonId)
    .eq('kind', 'lesson')
    .maybeSingle();
  return data?.id ?? null;
}

async function deleteQuiz(quizId) {
  const { data: questionRows, error: questionError } = await supabase
    .from('questions')
    .select('id')
    .eq('quiz_id', quizId);
  if (questionError) throw questionError;

  const questionIds = (questionRows ?? []).map((row) => row.id);
  if (questionIds.length > 0) {
    const { error: answerByQuestionError } = await supabase
      .from('quiz_answers')
      .delete()
      .in('question_id', questionIds);
    if (answerByQuestionError) throw answerByQuestionError;
  }

  const { data: attemptRows, error: attemptError } = await supabase
    .from('quiz_attempts')
    .select('id')
    .eq('quiz_id', quizId);
  if (attemptError) throw attemptError;

  const attemptIds = (attemptRows ?? []).map((row) => row.id);
  if (attemptIds.length > 0) {
    const { error: answerByAttemptError } = await supabase
      .from('quiz_answers')
      .delete()
      .in('attempt_id', attemptIds);
    if (answerByAttemptError) throw answerByAttemptError;

    const { error: attemptsDeleteError } = await supabase
      .from('quiz_attempts')
      .delete()
      .in('id', attemptIds);
    if (attemptsDeleteError) throw attemptsDeleteError;
  }

  const { error } = await supabase.from('quizzes').delete().eq('id', quizId);
  if (error) throw error;
}

async function persistQuiz({ lessonId, questions }) {
  const { data: quiz, error } = await supabase
    .from('quizzes')
    .insert({
      lesson_id: lessonId,
      kind: 'lesson',
      generated_by_ai: true,
      ai_model: GEMINI_MODEL,
      ai_generated_at: new Date().toISOString(),
    })
    .select('id')
    .single();
  if (error) throw error;

  for (const [i, q] of questions.entries()) {
    const { data: qRow, error: qErr } = await supabase
      .from('questions')
      .insert({
        quiz_id: quiz.id,
        kind: q.kind,
        prompt: q.prompt,
        explanation: q.explanation,
        sort_order: i,
      })
      .select('id')
      .single();
    if (qErr) throw qErr;
    const opts = (q.options ?? []).map((o, idx) => ({
      question_id: qRow.id,
      text: o.text,
      is_correct: !!o.is_correct,
      sort_order: idx,
    }));
    if (opts.length > 0) {
      const { error: oErr } = await supabase.from('options').insert(opts);
      if (oErr) throw oErr;
    }
  }
}

async function maybeBackfillRange(lessonId, start, end) {
  // Si la lección no tenía rangos, los persistimos para que el reader del PDF
  // pueda saltar a la página correcta.
  await supabase
    .from('lessons')
    .update({ pdf_start_page: start, pdf_end_page: end })
    .eq('id', lessonId)
    .is('pdf_start_page', null);
}

// ---------------------------------------------------------
// Main
// ---------------------------------------------------------
async function main() {
  const filterBookSlug = args.book;
  const filterLessonNumber = args.lesson ? parseInt(args.lesson, 10) : null;
  const replaceExisting = args.replace === true || args.replace === 'true';

  if (replaceExisting) {
    console.warn('[warn] --replace activo: los quizzes existentes se reemplazarán solo después de generar una versión válida.');
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
        const quizId = await existingQuizId(lesson.id);
        if (quizId && !replaceExisting) {
          console.log(`[skip] L${lesson.number}: ya tiene quiz`);
          continue;
        }

        const range = (lesson.pdf_start_page && lesson.pdf_end_page)
          ? { start: lesson.pdf_start_page, end: Math.min(lesson.pdf_end_page, totalPages) }
          : rangeFor(totalPages, lessons.length, lesson.number);

        const images = await loadImagesInRange(pages, range.start, range.end);
        if (images.length === 0) {
          console.warn(`[skip] L${lesson.number}: sin imágenes en pp ${range.start}-${range.end}`);
          continue;
        }
        const totalKB = Math.round(images.reduce((s, i) => s + i.sizeBytes, 0) / 1024);
        console.log(`[gen ] L${lesson.number} pp ${range.start}-${range.end} (${images.length} imgs, ${totalKB}KB)`);

        const questions = await generateValidatedQuestionsVision({
          level: meta.level,
          lessonNumber: lesson.number,
          images,
        });
        if (quizId && replaceExisting) {
          await deleteQuiz(quizId);
          console.log(`[repl] L${lesson.number}: quiz anterior eliminado`);
        }
        await persistQuiz({ lessonId: lesson.id, questions });
        await maybeBackfillRange(lesson.id, range.start, range.end);
        console.log(`[ok  ] L${lesson.number}: ${questions.length} preguntas`);

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
