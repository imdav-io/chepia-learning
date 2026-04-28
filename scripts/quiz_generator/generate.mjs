// Genera quizzes con un LLM (Gemini o Claude) para cada lección de cada libro
// y los persiste en Supabase. Build-time: corre en tu Mac, NO en runtime.
//
// Provider seleccionable:
//   AI_PROVIDER=gemini   (default — gratis con free tier de Google AI Studio)
//   AI_PROVIDER=claude   (Anthropic — requiere ANTHROPIC_API_KEY válida)
//
// Uso:
//   1) cp .env.example .env y llena las claves (mínimo: GEMINI_API_KEY o ANTHROPIC_API_KEY)
//   2) node extract-pdf-text.mjs    (genera ./out/lessons-raw.json)
//   3) node generate.mjs             (genera quizzes y los inserta en Supabase)
//
// Idempotente: si una lección ya tiene quiz generado por IA, se omite.

import 'dotenv/config';
import fs from 'node:fs/promises';
import { createClient } from '@supabase/supabase-js';

const {
  AI_PROVIDER = 'gemini',
  GEMINI_API_KEY,
  GEMINI_MODEL = 'gemini-2.0-flash',
  ANTHROPIC_API_KEY,
  ANTHROPIC_MODEL = 'claude-sonnet-4-5',
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
} = process.env;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en .env.');
  process.exit(1);
}

const provider = AI_PROVIDER.toLowerCase();
if (provider === 'gemini' && !GEMINI_API_KEY) {
  console.error('Falta GEMINI_API_KEY en .env. Consíguela gratis en https://aistudio.google.com/app/apikey');
  process.exit(1);
}
if (provider === 'claude' && !ANTHROPIC_API_KEY) {
  console.error('Falta ANTHROPIC_API_KEY en .env.');
  process.exit(1);
}

console.log(`Provider: ${provider} | model: ${provider === 'gemini' ? GEMINI_MODEL : ANTHROPIC_MODEL}`);

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// ---------------------------------------------------------
// Heurística para segmentar el texto crudo por "Lesson N"
// ---------------------------------------------------------
function splitIntoLessons(rawText) {
  const lessons = [];
  const re = /Lesson\s+(\d+)\b([\s\S]*?)(?=Lesson\s+\d+\b|Appendix\b|$)/gi;
  let match;
  while ((match = re.exec(rawText)) !== null) {
    lessons.push({
      number: parseInt(match[1], 10),
      text: match[2].trim().slice(0, 8000),
    });
  }
  const byNum = new Map();
  for (const l of lessons) {
    const prev = byNum.get(l.number);
    if (!prev || prev.text.length < l.text.length) byNum.set(l.number, l);
  }
  return [...byNum.values()].sort((a, b) => a.number - b.number);
}

// ---------------------------------------------------------
// Prompts
// ---------------------------------------------------------
const SYSTEM_PROMPT = `Eres un teacher experto de inglés (CEFR A1-C1). Generas preguntas de comprensión, vocabulario y gramática para alumnos hispanohablantes basándote ÚNICAMENTE en el texto provisto. Devuelves JSON válido sin texto adicional.`;

function userPrompt({ bookTitle, level, lessonNumber, lessonText }) {
  return `Libro: ${bookTitle}
Nivel CEFR aproximado: ${level}
Lección ${lessonNumber}.

Texto de la lección:
"""
${lessonText}
"""

Genera EXACTAMENTE 15 preguntas mezcladas con esta distribución:
- 4 multiple_choice de comprehension/lectura
- 4 multiple_choice de vocabulary
- 4 multiple_choice de grammar
- 2 true_false
- 1 fill_blank

Cada multiple_choice tiene 4 opciones con UNA sola correcta.
Cada true_false tiene 2 opciones ("True"/"False") con UNA correcta.
Cada fill_blank deja el espacio como "____" en el prompt y la respuesta correcta como una de las 4 opciones.

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
  // Limpia fences markdown ```json ... ``` que algunos modelos meten.
  const cleaned = text.replace(/```json\s*|```/g, '').trim();
  const match = cleaned.match(/\{[\s\S]*\}/);
  if (!match) throw new Error('Respuesta sin JSON: ' + text.slice(0, 200));
  return JSON.parse(match[0]);
}

// ---------------------------------------------------------
// Provider: Gemini (Google AI Studio)
// ---------------------------------------------------------
async function generateWithGemini({ bookTitle, level, lessonNumber, lessonText }) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const body = {
    systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
    contents: [
      {
        role: 'user',
        parts: [{ text: userPrompt({ bookTitle, level, lessonNumber, lessonText }) }],
      },
    ],
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: 4096,
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
    throw new Error(`Gemini ${res.status}: ${errText.slice(0, 300)}`);
  }
  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error('Gemini sin contenido en respuesta');
  return extractJson(text);
}

// ---------------------------------------------------------
// Provider: Claude (Anthropic)
// ---------------------------------------------------------
async function generateWithClaude({ bookTitle, level, lessonNumber, lessonText }) {
  // Import dinámico para no requerir instalado si usa Gemini.
  const { default: Anthropic } = await import('@anthropic-ai/sdk');
  const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

  const res = await anthropic.messages.create({
    model: ANTHROPIC_MODEL,
    max_tokens: 4000,
    system: SYSTEM_PROMPT,
    messages: [
      { role: 'user', content: userPrompt({ bookTitle, level, lessonNumber, lessonText }) },
    ],
  });

  const text = res.content
    .filter((c) => c.type === 'text')
    .map((c) => c.text)
    .join('\n');
  return extractJson(text);
}

// ---------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------
async function generateQuestions(args) {
  const parsed = provider === 'claude'
    ? await generateWithClaude(args)
    : await generateWithGemini(args);
  if (!Array.isArray(parsed.questions) || parsed.questions.length === 0) {
    throw new Error('Sin preguntas en respuesta');
  }
  return parsed.questions;
}

// ---------------------------------------------------------
// Persistencia
// ---------------------------------------------------------
async function ensureBookAndLesson({ bookSlug, level, bookTitle, lessonNumber }) {
  const { data: levelRow } = await supabase
    .from('levels')
    .select('id')
    .eq('code', level)
    .single();
  if (!levelRow) throw new Error(`Nivel ${level} no existe en tabla levels`);

  let { data: book } = await supabase
    .from('books')
    .select('id')
    .eq('slug', bookSlug)
    .maybeSingle();
  if (!book) {
    const insert = await supabase
      .from('books')
      .insert({ slug: bookSlug, title: bookTitle, level_id: levelRow.id, language: 'en' })
      .select('id')
      .single();
    book = insert.data;
  }

  let { data: lesson } = await supabase
    .from('lessons')
    .select('id')
    .eq('book_id', book.id)
    .eq('number', lessonNumber)
    .maybeSingle();
  if (!lesson) {
    const insert = await supabase
      .from('lessons')
      .insert({ book_id: book.id, number: lessonNumber, title: `Lesson ${lessonNumber}` })
      .select('id')
      .single();
    lesson = insert.data;
  }
  return { bookId: book.id, lessonId: lesson.id };
}

async function quizExists(lessonId) {
  const { data } = await supabase
    .from('quizzes')
    .select('id')
    .eq('lesson_id', lessonId)
    .eq('kind', 'lesson')
    .maybeSingle();
  return !!data;
}

async function persistQuiz({ lessonId, questions }) {
  const aiModel = provider === 'claude' ? ANTHROPIC_MODEL : GEMINI_MODEL;
  const { data: quiz, error } = await supabase
    .from('quizzes')
    .insert({
      lesson_id: lessonId,
      kind: 'lesson',
      generated_by_ai: true,
      ai_model: aiModel,
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

// ---------------------------------------------------------
// Main
// ---------------------------------------------------------
async function main() {
  const raw = JSON.parse(await fs.readFile('./out/lessons-raw.json', 'utf8'));

  for (const book of raw) {
    const lessons = splitIntoLessons(book.rawText);
    console.log(`\n=== ${book.title} (${lessons.length} lecciones detectadas) ===`);

    for (const lesson of lessons) {
      try {
        const { lessonId } = await ensureBookAndLesson({
          bookSlug: book.slug,
          level: book.level,
          bookTitle: book.title,
          lessonNumber: lesson.number,
        });

        if (await quizExists(lessonId)) {
          console.log(`[skip] Lesson ${lesson.number} ya tiene quiz`);
          continue;
        }

        console.log(`[gen ] Lesson ${lesson.number} ...`);
        const questions = await generateQuestions({
          bookTitle: book.title,
          level: book.level,
          lessonNumber: lesson.number,
          lessonText: lesson.text,
        });
        await persistQuiz({ lessonId, questions });
        console.log(`[ok  ] Lesson ${lesson.number}: ${questions.length} preguntas`);
      } catch (e) {
        console.error(`[err ] Lesson ${lesson.number}:`, e.message);
      }
    }
  }
  console.log('\n[DONE]');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
