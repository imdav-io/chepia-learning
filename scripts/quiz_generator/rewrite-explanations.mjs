// Reescribe explanations existentes sin cambiar preguntas, opciones ni intentos.
//
// Uso:
//   cd scripts/quiz_generator
//   node rewrite-explanations.mjs
//   node rewrite-explanations.mjs --book=as-it-is-book-1
//   node rewrite-explanations.mjs --book=as-it-is-book-1 --lesson=1
//   node rewrite-explanations.mjs --book=as-it-is-book-1 --from-lesson=7

import 'dotenv/config';
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
  process.argv
    .slice(2)
    .filter((a) => a.startsWith('--'))
    .map((a) => {
      const [key, value] = a.replace(/^--/, '').split('=');
      return [key, value ?? true];
    }),
);

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const DEFAULT_BOOK_SLUGS = ['as-it-is-book-1', 'as-it-is-book-2', 'as-it-is-book-3'];
const SLEEP_MS = Number.parseInt(process.env.OPENAI_REQUEST_DELAY_MS ?? '1500', 10);
const MAX_ATTEMPTS = Number.parseInt(process.env.REWRITE_EXPLANATIONS_MAX_ATTEMPTS ?? '3', 10);

const EXPLANATION_META_PATTERNS = [
  /\besta pregunta\s+(?:eval[uú]a|mide|practica|refuerza|comprueba|verifica|se enfoca)\b/i,
  /\b(?:eval[uú]a|mide|practica|refuerza|comprueba|verifica)\s+(?:el|la|los|las)\s+(?:uso|comprensi[oó]n|habilidad|conocimiento|vocabulario|gram[aá]tica|estructura)\b/i,
  /\b(?:this question|the question)\s+(?:tests|evaluates|checks|practices|focuses on)\b/i,
  /\bseg[uú]n\s+(?:la|el|las|los)?\s*(?:p[aá]gina|imagen|libro|texto|lecci[oó]n|unidad|ejercicio|material|fuente|pdf|vocabulario|gram[aá]tica|contenido|tema)\b/i,
  /\b(?:en|de)\s+(?:la|el|las|los)\s+(?:p[aá]gina|imagen|libro|texto|lecci[oó]n|unidad|ejercicio|material|fuente|pdf)\b/i,
  /\b(?:according to|based on|shown in|seen in|from)\s+(?:the\s+)?(?:page|pages|image|images|picture|pictures|book|text|passage|lesson|unit|exercise|material|source|pdf)\b/i,
  /\bcomo\s+se\s+(?:presenta|muestra|enseña|practica|trabaja|ve|vio)\b/i,
];

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function extractJson(text) {
  const cleaned = text.replace(/```json\s*|```/g, '').trim();
  const match = cleaned.match(/\{[\s\S]*\}/);
  return JSON.parse(match ? match[0] : cleaned);
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

function cleanExplanation(value) {
  return String(value ?? '')
    .trim()
    .replace(
      /^\s*(?:seg[uú]n|de acuerdo con)\s+(?:el|la|los|las)?\s*(?:contexto|informaci[oó]n|descripci[oó]n|contenido|vocabulario|gram[aá]tica)\s+(?:de\s+(?:la|el)\s+)?(?:lecci[oó]n|unidad|material|texto|libro)?\s*,\s*/i,
      '',
    )
    .replace(
      /\s*,?\s*(?:seg[uú]n|de acuerdo con)\s+(?:el|la|los|las)?\s*(?:contexto|informaci[oó]n|descripci[oó]n|contenido|vocabulario|gram[aá]tica)\s+(?:de\s+(?:la|el)\s+)?(?:lecci[oó]n|unidad|material|texto|libro)?\s*\.?$/i,
      '.',
    )
    .replace(
      /\b(?:en|dentro de)\s+(?:el|la)\s+(?:contexto|contenido)\s+de\s+(?:la|el)\s+(?:lecci[oó]n|unidad|material)\b/gi,
      'en esta situacion',
    )
    .replace(/\b(?:de|en)\s+(?:la|el)\s+lecci[oó]n\b/gi, '')
    .replace(/\s{2,}/g, ' ')
    .replace(/\s+\./g, '.');
}

function validateRewrites(rewrites, questionCount) {
  if (!Array.isArray(rewrites)) {
    throw new Error('La respuesta no contiene explanations[]');
  }
  if (rewrites.length !== questionCount) {
    throw new Error(`Se esperaban ${questionCount} explicaciones y llegaron ${rewrites.length}`);
  }

  const seen = new Set();
  for (const rewrite of rewrites) {
    const number = Number.parseInt(rewrite.number, 10);
    if (!Number.isInteger(number) || number < 1 || number > questionCount) {
      throw new Error(`numero de pregunta desconocido: ${rewrite.number}`);
    }
    if (seen.has(number)) {
      throw new Error(`numero de pregunta duplicado: ${number}`);
    }
    seen.add(number);

    const explanation = cleanExplanation(rewrite.explanation);
    rewrite.explanation = explanation;
    if (explanation.length < 18) {
      throw new Error(`explicacion demasiado corta para pregunta ${number}`);
    }
    for (const pattern of EXPLANATION_META_PATTERNS) {
      if (pattern.test(explanation)) {
        throw new Error(`explicacion meta para pregunta ${number}: ${explanation}`);
      }
    }
  }
}

function promptForQuiz({ bookSlug, lessonNumber, questions }) {
  const payload = questions.map((question, index) => ({
    number: index + 1,
    question_id: question.id,
    kind: question.kind,
    prompt: question.prompt,
    correct_option: question.options.find((option) => option.is_correct)?.text,
    incorrect_options: question.options
      .filter((option) => !option.is_correct)
      .map((option) => option.text),
  }));

  return `Rewrite ONLY the explanations for these English questions.

Internal ordering reference:
- Book: ${bookSlug}
- Lesson: ${lessonNumber}

Mandatory rules:
- Return one Spanish explanation for each question_id.
- The explanation must explain WHY the correct option is correct.
- Do NOT explain what the question evaluates.
- Do NOT use phrases such as "esta pregunta evalua", "evalua el uso correcto de", "sirve para practicar", "mide la comprension", "segun el vocabulario", "segun la leccion", "segun el contexto", "como se presenta", "como se vio", "en la pagina", "en el libro", "en el texto", or similar phrases.
- If you need to mention context, use "en esta situacion" or "en el dialogo"; never use "en la leccion" or "segun el material".
- If it is vocabulary, explain the meaning or nuance of the correct word.
- If it is grammar, explain the concrete rule.
- If it is comprehension, explain the logic of the situation or dialogue.
- Keep 1 or 2 short sentences.
- Do not change questions, options, or ids.
- Respond using each question's "number" field. Do not copy or invent UUIDs.

Good examples:
- "La respuesta correcta es 'peaches' porque las palabras terminadas en -ch forman el plural con -es."
- "'Does' se usa con he/she/it en preguntas del present simple; por eso 'Does she...?' es correcto."
- "'Tired' significa cansado; las otras opciones hablan de hambre, frio o tristeza."

Questions:
${JSON.stringify(payload, null, 2)}

Return ONLY JSON:
{
  "explanations": [
    { "number": 1, "explanation": "explicacion en espanol" }
  ]
}`;
}

async function rewriteQuiz(quiz) {
  let lastError;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        instructions:
          'You are an expert English teacher for Spanish-speaking learners. You rewrite brief, useful, concrete feedback. Always return valid JSON with no extra text.',
        input: [{ role: 'user', content: [{ type: 'input_text', text: promptForQuiz(quiz) }] }],
        max_output_tokens: 8192,
      }),
    });

    if (!response.ok) {
      throw new Error(`OpenAI ${response.status}: ${(await response.text()).slice(0, 500)}`);
    }

    const data = await response.json();
    const text = extractOpenAIText(data);
    if (!text) {
      throw new Error(`OpenAI sin texto: ${JSON.stringify(data).slice(0, 300)}`);
    }

    try {
      const parsed = extractJson(text);
      const rewrites = parsed.explanations;
      validateRewrites(rewrites, quiz.questions.length);
      return rewrites.map((rewrite) => ({
        question_id: quiz.questions[Number.parseInt(rewrite.number, 10) - 1].id,
        explanation: String(rewrite.explanation).trim(),
      }));
    } catch (error) {
      lastError = error;
      if (attempt < MAX_ATTEMPTS) {
        console.warn(`[retry] ${quiz.bookSlug} L${quiz.lessonNumber}: ${error.message}`);
        await sleep(SLEEP_MS);
      }
    }
  }

  throw lastError;
}

async function fetchBooks() {
  let query = supabase.from('books').select('id, slug').order('slug');
  if (args.book) {
    query = query.eq('slug', args.book);
  } else {
    query = query.in('slug', DEFAULT_BOOK_SLUGS);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

async function fetchLessons(bookId) {
  let query = supabase
    .from('lessons')
    .select('id, number')
    .eq('book_id', bookId)
    .order('number');
  if (args.lesson) {
    query = query.eq('number', Number.parseInt(args.lesson, 10));
  } else {
    if (args['from-lesson']) {
      query = query.gte('number', Number.parseInt(args['from-lesson'], 10));
    }
    if (args['to-lesson']) {
      query = query.lte('number', Number.parseInt(args['to-lesson'], 10));
    }
  }

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

async function fetchQuizPayload({ book, lesson }) {
  const { data: quiz, error: quizError } = await supabase
    .from('quizzes')
    .select('id')
    .eq('lesson_id', lesson.id)
    .eq('kind', 'lesson')
    .maybeSingle();
  if (quizError) throw quizError;
  if (!quiz) return null;

  const { data: questions, error: questionsError } = await supabase
    .from('questions')
    .select('id, kind, prompt, explanation, sort_order')
    .eq('quiz_id', quiz.id)
    .order('sort_order');
  if (questionsError) throw questionsError;
  if (!questions?.length) return null;

  const { data: options, error: optionsError } = await supabase
    .from('options')
    .select('question_id, text, is_correct, sort_order')
    .in(
      'question_id',
      questions.map((question) => question.id),
    )
    .order('sort_order');
  if (optionsError) throw optionsError;

  const optionsByQuestion = new Map();
  for (const option of options ?? []) {
    const list = optionsByQuestion.get(option.question_id) ?? [];
    list.push(option);
    optionsByQuestion.set(option.question_id, list);
  }

  return {
    bookSlug: book.slug,
    lessonNumber: lesson.number,
    questions: questions.map((question) => ({
      ...question,
      options: optionsByQuestion.get(question.id) ?? [],
    })),
  };
}

async function main() {
  let updatedQuestions = 0;
  let processedQuizzes = 0;

  const books = await fetchBooks();
  for (const book of books) {
    const lessons = await fetchLessons(book.id);
    for (const lesson of lessons) {
      const quiz = await fetchQuizPayload({ book, lesson });
      if (!quiz) continue;

      console.log(`[rewrite] ${book.slug} L${lesson.number} (${quiz.questions.length} preguntas)`);
      const rewrites = await rewriteQuiz(quiz);

      for (const rewrite of rewrites) {
        const { error } = await supabase
          .from('questions')
          .update({ explanation: rewrite.explanation })
          .eq('id', rewrite.question_id);
        if (error) throw error;
      }

      processedQuizzes += 1;
      updatedQuestions += rewrites.length;
      console.log(`[ok] ${book.slug} L${lesson.number}: ${rewrites.length} explicaciones`);
      await sleep(SLEEP_MS);
    }
  }

  console.log(`[DONE] ${processedQuizzes} quizzes, ${updatedQuestions} explicaciones actualizadas`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
