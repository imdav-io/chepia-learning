// Genera quizzes con OpenAI/ChatGPT Vision a partir de las páginas escaneadas
// de cada libro. Build-time: corre en tu Mac, NO en runtime de la app.
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
//   node generate.mjs --book=as-it-is-book-1 --from-lesson=1 --to-lesson=10 --replace

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

if (!OPENAI_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Faltan OPENAI_API_KEY, SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en .env');
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
const SLEEP_MS = Number.parseInt(process.env.OPENAI_REQUEST_DELAY_MS ?? '1500', 10);
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

const EXPLANATION_META_PATTERNS = [
  {
    re: /\besta pregunta\s+(?:eval[uú]a|mide|practica|refuerza|comprueba|verifica|se enfoca)\b/i,
    label: 'explicación describe la pregunta en vez de justificar la respuesta',
  },
  {
    re: /\b(?:eval[uú]a|mide|practica|refuerza|comprueba|verifica)\s+(?:el|la|los|las)\s+(?:uso|comprensi[oó]n|habilidad|conocimiento|vocabulario|gram[aá]tica|estructura)\b/i,
    label: 'explicación pedagógica genérica',
  },
  {
    re: /\b(?:this question|the question)\s+(?:tests|evaluates|checks|practices|focuses on)\b/i,
    label: 'explicación meta en inglés',
  },
  {
    re: /\bseg[uú]n\s+(?:el|la|los|las)?\s*(?:vocabulario|gram[aá]tica|contenido|tema|unidad|lecci[oó]n|material)\b/i,
    label: 'explicación se apoya en el material en vez de justificar la respuesta',
  },
  {
    re: /\bcomo\s+se\s+(?:presenta|muestra|enseña|practica|trabaja|ve)\b/i,
    label: 'explicación habla de cómo aparece el contenido',
  },
];

const PERSONAL_MEMORY_PATTERNS = [
  {
    re: /\bwho\s+is\s+[A-Z][a-z]+\b/,
    label: 'pregunta de memoria sobre personaje',
  },
  {
    re: /\bwhat\s+does\s+[A-Z][a-z]+\s+(?:do|want|like|have|buy|eat|drink|need|study|say)\b/,
    label: 'pregunta sobre acciones de un personaje',
  },
  {
    re: /\bwhere\s+does\s+[A-Z][a-z]+\s+(?:live|work|go|study)\b/,
    label: 'pregunta sobre datos de un personaje',
  },
  {
    re: /\bwhat\s+is\s+[A-Z][a-z]+'s\s+(?:job|occupation|profession|name)\b/,
    label: 'pregunta sobre oficio/nombre de un personaje',
  },
  {
    re: /\b[a-zA-Z]+,\s+(?:a|an)\s+[a-z]+\s*,\s+(?:works|lives|studies|likes|wants|has)\b/i,
    label: 'mini-contexto centrado en biografía de personaje',
  },
];

const GENERIC_PROMPT_PATTERNS = [
  /^choose\s+the\s+(?:correct|best|natural)\s+(?:sentence|question|answer|word)\.?$/i,
  /^complete\s+the\s+sentence\.?$/i,
  /^choose\s+the\s+right\s+(?:sentence|question|answer|word)\.?$/i,
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
// OpenAI Vision
// ---------------------------------------------------------
const SYSTEM_PROMPT = `You are an expert English teacher (CEFR A1-C1) for Spanish-speaking learners. You will receive images with source material from a unit, but you must treat them only as internal input. First analyze useful vocabulary, examples, exercises, instructions, and grammar structures internally. Then create English knowledge exercises based on those patterns.

Critical rule: NEVER mention pages, images, scans, PDFs, books, texts, passages, or phrases like "according to the page/text/book" or "según la página/texto/libro". Do not ask who a person is, what they do, where they live, what they bought, or what a character did. Questions must assess usable English knowledge: completing sentences, choosing the correct form, choosing the natural question/answer, vocabulary, rules, and usage. If something is not legible, ignore it. Always return valid JSON with no extra text.`;

function levelPlan(level) {
  if (level === 'beginner') {
    return `Book 1 / beginner:
- Use very simple, clear English.
- Prioritize exercises such as "Complete the sentence", "Choose the correct word", "Choose the correct question", and "Choose the correct answer".
- Generate at least 6 fill_blank questions with short sentences. Style example: "This ____ an elephant."
- Use basic vocabulary from the unit and very targeted structures: a/an, this/that, is/are, am/is/are, he/she/it, plurals, basic simple present, simple questions, numbers, colors, objects, places, or basic actions as relevant.
- Avoid long mini-stories. Use one sentence per prompt whenever possible.
- Explanations must be very clear, such as: "'Is' se usa con singular y con he/she/it; por eso 'This is...' es correcto."`;
  }
  if (level === 'intermediate') {
    return `Book 2 / intermediate:
- Increase complexity slightly with more natural phrases, while still testing English knowledge.
- Combine vocabulary, collocations, prepositions, verb forms, question formation, comparatives, modals, time expressions, and structures found in examples or exercises.
- Include at least 3 fill_blank questions.
- You may use short usage contexts, but the answer must depend on vocabulary/grammar, not on remembering character facts.`;
  }
  return `Book 3 / advanced:
- Use higher complexity when the unit supports it: vocabulary nuance, verb tenses, connectors, phrasal verbs, conditionals, passive voice, reported speech, clauses, collocations, or register.
- Include at least 2 fill_blank questions and natural-usage choice questions.
- Distractors must be plausible and teach real usage differences.
- Avoid literal reading questions; assess English mastery.`;
}

function userPrompt({ level, lessonNumber, feedback }) {
  return `Internal context for difficulty calibration:
- Approximate CEFR level: ${level}
- Unit/lesson: ${lessonNumber}

You will receive images with source material from this unit. Use them only to infer:
- important vocabulary and expressions;
- practiced grammar structures;
- reusable examples, exercises, and sentence patterns.

${levelPlan(level)}

Do not tell the learner that you saw images, pages, a PDF, a book, a text, a passage, or a lesson. Do not ask visual questions or meta questions. Bad examples:
- "According to the page, what does ...?"
- "What is shown in the image?"
- "In the text, what word means ...?"
- "Según la página, ¿qué significa ...?"
- "Who is Sam?"
- "What does Sam do?"
- "What is Sam's job?"
- "Where does Ana live?"

Good examples:
- "Complete the sentence: This ____ an elephant."
- "Choose the correct question: ____ this your book?"
- "Which sentence uses 'is' correctly?"
- "Choose the best answer: Are they students?"
- "Which word means 'very tired'?"
- "Complete the sentence: She ____ to school every day."

Generate EXACTLY 15 questions mixed as follows:
- fill_blank to complete sentences with vocabulary or grammar from the unit.
- multiple_choice to choose the correct word, correct phrase, correct question, or natural answer.
- true_false only for rules or correct English usage, never for facts about characters.

Rules:
- Each multiple_choice question has 4 options with exactly ONE correct option.
- Each true_false question has 2 options ("True"/"False") with exactly ONE correct option.
- A fill_blank prompt must include "____" and the correct answer as one of 4 options.
- Questions and options MUST be in English.
- Each prompt must be self-contained and unique. Do not use repeated generic prompts like "Choose the correct sentence." without including the sentence, word, or context.
- Instead of "Choose the correct sentence.", write something specific such as "Choose the correct sentence with 'is'." or "Choose the correct question for a singular object."
- The explanation MUST be in Spanish, short (1-2 sentences), and explain WHY the correct answer is correct.
- The explanation must be didactic and concrete. Examples:
  - "'Is' se usa con singular y con he/she/it; por eso 'This is an elephant' es correcto."
  - "'Are' se usa con plural o con you/we/they; por eso 'They are students' es correcto."
  - "'An' va antes de un sonido vocálico; por eso se dice 'an apple'."
- The explanation must NOT say what the question evaluates. Forbidden: "esta pregunta evalúa...", "evalúa el uso correcto de...", "sirve para practicar...", "mide la comprensión...".
- The explanation must not rely on phrases such as "según el vocabulario", "como se presenta", "como se vio", or "en la unidad". Explain the rule, meaning, or fact directly.
- Whenever natural, start with "La respuesta correcta es..." or mention the correct option and then use "porque...".
- Good explanations:
  - "La respuesta correcta es 'peaches' porque las palabras terminadas en -ch forman el plural con -es."
  - "'Does' se usa con he/she/it en preguntas del present simple; por eso 'Does she...?' es correcto."
  - "'Tired' significa cansado; las otras opciones expresan hambre, frío o tristeza."
- If the correct answer is vocabulary, explain the meaning or nuance.
- If the correct answer is grammar, explain the concrete rule.
- If you use a mini-context, explain the language logic, not facts from a story.
- Each question must be answerable from the skill practiced in the unit, not from visual memory.
- Use plausible distractors, not absurd ones. Avoid options that are too obvious.
- Vary formats: sentence completion, natural answer selection, correct usage identification, meaning in context, and dialogue comprehension.
- Avoid generic questions that could belong to any lesson. They should feel connected to this unit's topic, vocabulary, or structure.
- Forbidden: asking for names, professions, actions, or personal facts about characters. Do not ask "Who is...?", "What does Sam do?", "What is his job?", "Where does she live?", "What does he buy?".
- Do not use prompts that depend on remembering a story. Use prompts that depend on knowing English.
- Avoid mentioning "unit", "lesson", "material", "exercise", or "source" inside questions.
- Forbidden material-reference words: page, image, picture, scan, PDF, book, text, passage, "according to", página, imagen, libro, texto, pasaje, "según".
- If you need to assess comprehension, ask directly about the situation or dialogue.
${feedback ? `\nFix these specific issues detected in a previous attempt:\n${feedback}\n` : ''}

Return ONLY JSON with this shape:
{
  "questions": [
    {
      "kind": "multiple_choice" | "true_false" | "fill_blank",
      "prompt": "string",
      "explanation": "short Spanish string",
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

function collectMetaReferenceIssues(value, location, issues) {
  if (typeof value !== 'string') return;
  for (const pattern of META_REFERENCE_PATTERNS) {
    if (pattern.re.test(value)) {
      issues.push(`${location}: ${pattern.label} -> "${value.slice(0, 120)}"`);
      break;
    }
  }
}

function collectExplanationQualityIssues(value, location, issues) {
  if (typeof value !== 'string') return;
  for (const pattern of EXPLANATION_META_PATTERNS) {
    if (pattern.re.test(value)) {
      issues.push(`${location}: ${pattern.label} -> "${value.slice(0, 120)}"`);
      break;
    }
  }
}

function collectPersonalMemoryIssues(value, location, issues) {
  if (typeof value !== 'string') return;
  for (const pattern of PERSONAL_MEMORY_PATTERNS) {
    if (pattern.re.test(value)) {
      issues.push(`${location}: ${pattern.label} -> "${value.slice(0, 120)}"`);
      break;
    }
  }
}

function collectGenericPromptIssues(question, location, issues) {
  const prompt = String(question?.prompt ?? '').trim();
  for (const pattern of GENERIC_PROMPT_PATTERNS) {
    if (pattern.test(prompt)) {
      issues.push(`${location}: prompt genérico, debe incluir oración/contexto -> "${prompt}"`);
      return;
    }
  }
}

function validateLevelShape(questions, level, issues) {
  const fillBlankCount = questions.filter((question) => question.kind === 'fill_blank').length;
  if (level === 'beginner' && fillBlankCount < 6) {
    issues.push(`beginner: se esperaban al menos 6 fill_blank y llegaron ${fillBlankCount}`);
  }
  if (level === 'intermediate' && fillBlankCount < 3) {
    issues.push(`intermediate: se esperaban al menos 3 fill_blank y llegaron ${fillBlankCount}`);
  }
  if (level === 'advanced' && fillBlankCount < 2) {
    issues.push(`advanced: se esperaban al menos 2 fill_blank y llegaron ${fillBlankCount}`);
  }
}

function validateQuestions(questions, level) {
  const issues = [];
  if (!Array.isArray(questions)) {
    throw new Error('La respuesta no contiene un arreglo de preguntas');
  }
  if (questions.length !== 15) {
    issues.push(`se esperaban 15 preguntas y llegaron ${questions.length}`);
  }
  validateLevelShape(questions, level, issues);

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
    collectExplanationQualityIssues(question.explanation, `${qLabel}.explanation`, issues);
    collectPersonalMemoryIssues(question.prompt, `${qLabel}.prompt`, issues);
    collectPersonalMemoryIssues(question.explanation, `${qLabel}.explanation`, issues);
    collectGenericPromptIssues(question, `${qLabel}.prompt`, issues);

    if (question.kind === 'fill_blank' && !String(question.prompt ?? '').includes('____')) {
      issues.push(`${qLabel}: fill_blank debe incluir "____" en el prompt`);
    }

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
      collectPersonalMemoryIssues(option?.text, `${qLabel}.option${optionIndex + 1}`, issues);
    }
  }

  if (issues.length > 0) {
    throw new Error(issues.slice(0, 10).join('; '));
  }
}

async function generateQuestionsVision({ level, lessonNumber, images, feedback }) {
  const content = [
    { type: 'input_text', text: userPrompt({ level, lessonNumber, feedback }) },
    ...images.map((img) => ({
      type: 'input_image',
      image_url: `data:${img.mime};base64,${img.base64}`,
      detail: 'low',
    })),
  ];
  const body = {
    model: OPENAI_MODEL,
    instructions: SYSTEM_PROMPT,
    input: [{ role: 'user', content }],
    max_output_tokens: 8192,
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
  if (!text) throw new Error('Sin texto en respuesta: ' + JSON.stringify(data).slice(0, 300));
  let parsed;
  try {
    parsed = extractJson(text);
  } catch (e) {
    const snippet = text.slice(-200);
    throw new Error(`JSON parse falló. Final: "...${snippet}"`);
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
      validateQuestions(questions, level);
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
      ai_model: OPENAI_MODEL,
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
  const fromLesson = args['from-lesson'] ? parseInt(args['from-lesson'], 10) : null;
  const toLesson = args['to-lesson'] ? parseInt(args['to-lesson'], 10) : null;
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
    if (!filterLessonNumber && fromLesson) lessonsQuery = lessonsQuery.gte('number', fromLesson);
    if (!filterLessonNumber && toLesson) lessonsQuery = lessonsQuery.lte('number', toLesson);
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
