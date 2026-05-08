// Genera situaciones de vida diaria con expresiones naturales usando
// OpenAI/ChatGPT y las persiste en Supabase.
//
// Uso:
//   npm run generate-situations
//   npm run generate-situations -- --slug=grocery-store
//   npm run generate-situations -- --limit=5
//   npm run generate-situations -- --replace

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const {
  OPENAI_API_KEY,
  OPENAI_MODEL = 'gpt-5-mini',
  OPENAI_REQUEST_DELAY_MS = '1500',
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

const SLEEP_MS = Number.parseInt(OPENAI_REQUEST_DELAY_MS, 10);
const MIN_EXPRESSIONS = 16;
const TARGET_EXPRESSIONS = 20;
const MAX_EXPRESSIONS = 24;
const DEFAULT_TECHNICAL_QUESTIONS = Number.parseInt(
  process.env.TECHNICAL_QUESTIONS ?? '30',
  10,
);
const PRACTICE_QUESTIONS = 8;
const MAX_ATTEMPTS = Number.parseInt(process.env.SITUATIONS_MAX_ATTEMPTS ?? '3', 10);
const MAX_OUTPUT_TOKENS = Number.parseInt(process.env.OPENAI_MAX_OUTPUT_TOKENS ?? '20000', 10);

function targetTechnicalQuestions(situation) {
  return Number.parseInt(args.questions ?? situation.questionCount ?? DEFAULT_TECHNICAL_QUESTIONS, 10);
}

function minTechnicalQuestions(situation) {
  const target = targetTechnicalQuestions(situation);
  return Number.parseInt(situation.minQuestions ?? Math.max(20, target - 10), 10);
}

function maxTechnicalQuestions(situation) {
  const target = targetTechnicalQuestions(situation);
  return Number.parseInt(situation.maxQuestions ?? Math.min(50, target + 20), 10);
}

const SITUATIONS = [
  {
    slug: 'grocery-store',
    titleEs: 'Ir al supermercado',
    titleEn: 'At the grocery store',
    icon: 'cart',
    sortOrder: 1,
    group: 'daily-life',
  },
  {
    slug: 'movie-theater',
    titleEs: 'Ir al cine',
    titleEn: 'At the movies',
    icon: 'movie',
    sortOrder: 2,
    group: 'daily-life',
  },
  {
    slug: 'at-home',
    titleEs: 'En la casa',
    titleEn: 'At home',
    icon: 'home',
    sortOrder: 3,
    group: 'daily-life',
  },
  {
    slug: 'gym',
    titleEs: 'Ir al gym',
    titleEn: 'At the gym',
    icon: 'gym',
    sortOrder: 4,
    group: 'daily-life',
  },
  {
    slug: 'coffee-shop',
    titleEs: 'En una cafetería',
    titleEn: 'At a coffee shop',
    icon: 'restaurant',
    sortOrder: 5,
    group: 'daily-life',
  },
  {
    slug: 'restaurant',
    titleEs: 'En un restaurante',
    titleEn: 'At a restaurant',
    icon: 'restaurant',
    sortOrder: 6,
    group: 'daily-life',
  },
  {
    slug: 'pharmacy',
    titleEs: 'En la farmacia',
    titleEn: 'At the pharmacy',
    icon: 'health',
    sortOrder: 7,
    group: 'daily-life',
  },
  {
    slug: 'doctor-visit',
    titleEs: 'Ir al doctor',
    titleEn: 'At the doctor',
    icon: 'health',
    sortOrder: 8,
    group: 'daily-life',
  },
  {
    slug: 'airport',
    titleEs: 'En el aeropuerto',
    titleEn: 'At the airport',
    icon: 'travel',
    sortOrder: 9,
    group: 'daily-life',
  },
  {
    slug: 'hotel',
    titleEs: 'En un hotel',
    titleEn: 'At a hotel',
    icon: 'travel',
    sortOrder: 10,
    group: 'daily-life',
  },
  {
    slug: 'work-small-talk',
    titleEs: 'Small talk en el trabajo',
    titleEn: 'Work small talk',
    icon: 'work',
    sortOrder: 11,
    group: 'daily-life',
  },
  {
    slug: 'asking-directions',
    titleEs: 'Pedir direcciones',
    titleEn: 'Asking for directions',
    icon: 'directions',
    sortOrder: 12,
    group: 'daily-life',
  },
  {
    slug: 'phone-calls',
    titleEs: 'Llamadas telefónicas',
    titleEn: 'Phone calls',
    icon: 'phone',
    sortOrder: 13,
    group: 'daily-life',
  },
  {
    slug: 'shopping-clothes',
    titleEs: 'Comprar ropa',
    titleEn: 'Shopping for clothes',
    icon: 'cart',
    sortOrder: 14,
    group: 'daily-life',
  },
  {
    slug: 'public-transport',
    titleEs: 'Transporte público',
    titleEn: 'Public transportation',
    icon: 'directions',
    sortOrder: 15,
    group: 'daily-life',
  },
  {
    slug: 'job-interview-general',
    titleEs: 'Entrevista de trabajo general',
    titleEn: 'General job interview',
    icon: 'work',
    sortOrder: 101,
    group: 'interviews',
    levelBand: 'B1-C1',
    questionCount: 25,
    minQuestions: 23,
    maxQuestions: 28,
    focus:
      'Preguntas comunes para cualquier puesto: tell me about yourself, strengths, weaknesses, experience, salary expectations, teamwork, conflict, availability, why this company, closing questions.',
  },
  {
    slug: 'developer-interview',
    titleEs: 'Entrevista fullstack y arquitectura',
    titleEn: 'Fullstack and architecture interview',
    icon: 'code',
    sortOrder: 102,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'Fullstack developer preparation: project explanation, architecture trade-offs, debugging, APIs, databases, testing, performance, security, CI/CD, collaboration, production support and technical decision-making.',
  },
  {
    slug: 'java-spring-interview',
    titleEs: 'Entrevista Java y Spring Boot',
    titleEn: 'Java and Spring Boot interview',
    icon: 'code',
    sortOrder: 103,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'Java 8, 11, 17, and 21; OOP; collections; generics; streams; lambdas; exceptions; concurrency basics; JVM; Spring Framework; Spring Boot; dependency injection; validation; profiles; configuration; REST controllers; transactions.',
  },
  {
    slug: 'api-security-interview',
    titleEs: 'Entrevista APIs e integración',
    titleEn: 'API design and integration interview',
    icon: 'security',
    sortOrder: 104,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'REST, SOAP, GraphQL, webhooks, JSON, XML, XSLT, API versioning, idempotency, pagination, error contracts, authentication, authorization, JWT, OAuth2, CORS, rate limiting, Postman and SOAP UI.',
  },
  {
    slug: 'sql-database-interview',
    titleEs: 'Entrevista SQL y bases relacionales',
    titleEn: 'SQL and relational database interview',
    icon: 'database',
    sortOrder: 105,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'Oracle SQL/PLSQL, PostgreSQL, MySQL, SQL Server, SQLite, joins, indexes, execution plans, query tuning, transactions, isolation, stored procedures, functions, triggers, constraints, normalization and data modeling.',
  },
  {
    slug: 'javascript-fullstack-interview',
    titleEs: 'Entrevista Node.js, JavaScript y TypeScript',
    titleEn: 'Node.js, JavaScript and TypeScript interview',
    icon: 'code',
    sortOrder: 106,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'JavaScript, TypeScript, Node.js, Express, NestJS, event loop, async/await, promises, modules, error handling, API design, validation, dependency management, testing and production troubleshooting.',
  },
  {
    slug: 'frontend-html-css-interview',
    titleEs: 'Entrevista HTML, CSS y accesibilidad',
    titleEn: 'HTML, CSS and accessibility interview',
    icon: 'web',
    sortOrder: 107,
    group: 'interviews',
    levelBand: 'B1-C1',
    questionCount: 25,
    minQuestions: 23,
    maxQuestions: 28,
    focus:
      'HTML semantics, accessibility, forms, CSS layout, flexbox, grid, responsive design, browser rendering, performance, design systems, cross-browser issues.',
  },
  {
    slug: 'cloud-aws-interview',
    titleEs: 'Entrevista AWS',
    titleEn: 'AWS interview',
    icon: 'cloud',
    sortOrder: 108,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'AWS Lambda, EC2, S3, RDS, DynamoDB, SQS, CloudWatch, API Gateway, SES, IAM, serverless, event-driven design, monitoring, scalability, cost awareness, deployments and troubleshooting.',
  },
  {
    slug: 'messaging-kafka-interview',
    titleEs: 'Entrevista microservicios, async y batch',
    titleEn: 'Microservices, async and batch processing interview',
    icon: 'queue',
    sortOrder: 109,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'Microservices, async processing, batch jobs, queues, Kafka, topics, partitions, consumers, producers, retries, dead-letter queues, ordering, idempotency, at-least-once delivery, event-driven architecture and operational trade-offs.',
  },
  {
    slug: 'python-web-interview',
    titleEs: 'Entrevista Python',
    titleEn: 'Python interview',
    icon: 'code',
    sortOrder: 110,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'Python language, data structures, OOP, decorators, generators, virtual environments, dependency management, Flask, Django, APIs, ORM basics, request lifecycle, testing and debugging.',
  },
  {
    slug: 'php-web-interview',
    titleEs: 'Entrevista PHP',
    titleEn: 'PHP interview',
    icon: 'code',
    sortOrder: 111,
    group: 'interviews',
    levelBand: 'B1-C1',
    questionCount: 25,
    minQuestions: 23,
    maxQuestions: 28,
    focus:
      'PHP web development, request handling, sessions, Composer, frameworks, database access, security basics, legacy code, debugging and refactoring.',
  },
  {
    slug: 'azure-gcp-ai-openai-interview',
    titleEs: 'Entrevista Azure y Azure DevOps',
    titleEn: 'Azure and Azure DevOps interview',
    icon: 'cloud',
    sortOrder: 112,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'Azure App Services, Azure Containers, Azure DevOps, pipelines, deployments, cloud services, monitoring, environment configuration, cloud troubleshooting and comparisons with AWS where useful.',
  },
  {
    slug: 'cpp-interview',
    titleEs: 'Entrevista C y C++',
    titleEn: 'C and C++ interview',
    icon: 'code',
    sortOrder: 113,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 25,
    minQuestions: 23,
    maxQuestions: 28,
    focus:
      'C and C++ fundamentals, pointers, memory management, references, stack vs heap, RAII, object lifetime, STL basics, performance, undefined behavior, compilation and debugging.',
  },
  {
    slug: 'frontend-react-next-interview',
    titleEs: 'Entrevista React y Next.js',
    titleEn: 'React and Next.js interview',
    icon: 'web',
    sortOrder: 114,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'React, Next.js, Gatsby, TypeScript in frontend, components, hooks, state, context, forms, SSR, SSG, CSR, hydration, routing, performance, testing and API integration.',
  },
  {
    slug: 'frontend-vue-interview',
    titleEs: 'Entrevista Vue.js',
    titleEn: 'Vue.js interview',
    icon: 'web',
    sortOrder: 115,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 25,
    minQuestions: 23,
    maxQuestions: 28,
    focus:
      'Vue.js, Composition API, Options API, reactivity, props/emits, watchers, computed values, Vue Router, state management, component design, forms and API integration.',
  },
  {
    slug: 'frontend-ui-frameworks-interview',
    titleEs: 'Entrevista UI frameworks',
    titleEn: 'UI frameworks interview',
    icon: 'web',
    sortOrder: 116,
    group: 'interviews',
    levelBand: 'B1-C1',
    questionCount: 25,
    minQuestions: 23,
    maxQuestions: 28,
    focus:
      'Material UI, Ant Design, Bootstrap, Ext.js, design systems, component libraries, theming, accessibility, responsive UI, forms, tables, modals and practical frontend trade-offs.',
  },
  {
    slug: 'nosql-cache-interview',
    titleEs: 'Entrevista NoSQL y cache',
    titleEn: 'NoSQL and cache interview',
    icon: 'database',
    sortOrder: 117,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'MongoDB, Redis, DynamoDB, document modeling, key-value data, caching patterns, TTL, indexes, consistency, transactions, query patterns, performance, cache invalidation and when to choose NoSQL vs SQL.',
  },
  {
    slug: 'devops-containers-cicd-interview',
    titleEs: 'Entrevista DevOps, containers y CI/CD',
    titleEn: 'DevOps, containers and CI/CD interview',
    icon: 'cloud',
    sortOrder: 118,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'Docker, Kubernetes, CI/CD, AWS CodePipeline, Azure DevOps, Jenkins, Git, SVN, Linux/Unix, deployment strategies, environment variables, secrets, logs, rollbacks and incident troubleshooting.',
  },
  {
    slug: 'enterprise-integration-middleware-interview',
    titleEs: 'Entrevista middleware e integración enterprise',
    titleEn: 'Enterprise integration and middleware interview',
    icon: 'queue',
    sortOrder: 119,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 25,
    minQuestions: 23,
    maxQuestions: 28,
    focus:
      'Oracle Middleware, OSB, Tuxedo, enterprise integration, service buses, SOAP services, XML, XSLT, routing, transformations, adapters, legacy integration, monitoring and troubleshooting.',
  },
  {
    slug: 'java-enterprise-legacy-interview',
    titleEs: 'Entrevista Java enterprise y legacy',
    titleEn: 'Java enterprise and legacy interview',
    icon: 'code',
    sortOrder: 120,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 25,
    minQuestions: 23,
    maxQuestions: 28,
    focus:
      'Jersey JAX-RS, EJB, Struts, Hibernate, JPA, JDBC, Servlets, legacy Java applications, ORM mapping, transactions, application servers, migration and refactoring.',
  },
  {
    slug: 'engineering-practices-interview',
    titleEs: 'Entrevista prácticas de ingeniería',
    titleEn: 'Engineering practices interview',
    icon: 'work',
    sortOrder: 121,
    group: 'interviews',
    levelBand: 'B2-C1',
    questionCount: 30,
    focus:
      'SOLID, Clean Code, code reviews, TDD, testing strategy, incident troubleshooting, technical mentoring, documentation, estimation, collaboration, ownership and communicating trade-offs in English.',
  },
];

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isTechnicalInterview(situation) {
  return situation.group === 'interviews';
}

const SYSTEM_PROMPT = `You are an English coach for Spanish-speaking learners and a technical interview trainer. For daily-life situations, generate natural expressions a native speaker would actually use. For interviews, generate real technical questions with clear, precise, defensible technical answers. Your style must be natural, useful, direct, and not sound like a textbook. Always return valid JSON with no extra text.`;

function userPrompt(situation, feedback = '') {
  if (isTechnicalInterview(situation)) {
    const targetQuestions = targetTechnicalQuestions(situation);
    const minQuestions = minTechnicalQuestions(situation);
    const maxQuestions = maxTechnicalQuestions(situation);
    return `Generate content for an English-learning app focused on technical interviews.

Situation:
- slug: ${situation.slug}
- title_es: ${situation.titleEs}
- title_en: ${situation.titleEn}
- English level: ${situation.levelBand ?? 'B2-C1'}
${situation.focus ? `- technical focus: ${situation.focus}` : ''}

Goal:
Create a bank of technical interview questions in English with technical answers. Do not generate loose phrases or generic expressions. Generate questions such as "What is OOP?", "What is S3?", "When would you use a Set instead of a List?", "What is a SQL trigger?", "What is the difference between final, finally, and finalize?" and answers the learner can study, repeat, and adapt in a real interview.

Rules:
- Return ONLY valid JSON.
- Generate ${targetQuestions} technical questions. The acceptable minimum is ${minQuestions} and the maximum is ${maxQuestions}.
- Generate exactly ${PRACTICE_QUESTIONS} quiz-style practice questions.
- Every question must be in English.
- Every main answer must be in English, with technical precision and interview-ready language.
- Include a short explanation in neutral Mexican Spanish to help understand the concept.
- Include at least 3 key points per question.
- Include follow-up questions an interviewer might ask.
- Include common mistakes the candidate should avoid.
- Cover concepts, differences, trade-offs, use cases, troubleshooting, and design decisions.
- Spread questions across junior, mid, and senior difficulty. Include practical scenario questions, not only definitions.
- Avoid soft questions like "tell me about yourself" unless the slug is job-interview-general.
- For job-interview-general, use professional and experience-based questions, with complete model answers.
- Do not invent technologies; stay within the focus.
- Answers must be useful for someone who wants to sound competent in English, not only memorize definitions.
${feedback ? `\nFix this issue from the previous attempt:\n${feedback}\n` : ''}

Return this shape:
{
  "situation": {
    "slug": "${situation.slug}",
    "title_es": "${situation.titleEs}",
    "title_en": "${situation.titleEn}",
    "description_es": "string breve",
    "level_band": "${situation.levelBand ?? 'B2-C1'}",
    "icon": "${situation.icon}",
    "content_kind": "technical_interview",
    "technical_questions": [
      {
        "question_en": "string",
        "answer_en": "string",
        "answer_es": "string",
        "sample_answer_en": "string opcional, respuesta en primera persona para entrevista",
        "category": "string",
        "difficulty": "junior | mid | senior",
        "key_points": ["string"],
        "follow_up_questions": ["string"],
        "common_mistakes": ["string"],
        "tags": ["string"]
      }
    ],
    "practice": [
      {
        "prompt": "string",
        "options": [
          { "text": "string", "is_correct": true },
          { "text": "string", "is_correct": false },
          { "text": "string", "is_correct": false },
          { "text": "string", "is_correct": false }
        ],
        "explanation_es": "string"
      }
    ]
  }
}`;
  }

  return `Generate content for an English-learning app.

Situation:
- slug: ${situation.slug}
- title_es: ${situation.titleEs}
- title_en: ${situation.titleEn}
- level: ${situation.levelBand ?? 'A2-B1'}
${situation.focus ? `- focus: ${situation.focus}` : ''}

Goal:
Create practice content with real daily-life expressions. They must be natural phrases a native speaker would use, with casual/polite variants when useful.

Rules:
- Return ONLY valid JSON.
- Ideally generate ${TARGET_EXPRESSIONS} expressions. The acceptable minimum is ${MIN_EXPRESSIONS} and the maximum is ${MAX_EXPRESSIONS}.
- Generate exactly ${PRACTICE_QUESTIONS} practice questions.
- Do not use stiff, literal, or odd phrases.
- Explanations must be in neutral Mexican Spanish.
- English phrases must be short and reusable.
- Include expressions for politeness, hesitation, asking for help, confirming, refusing, and closing a conversation when relevant.
- "tone" must be one of: casual, neutral, polite.
- "variants" must contain 1 to 3 useful variants.
- "dialogue" must contain 2 short lines with speaker A/B.
- Practice questions must have 4 options and exactly one correct answer.
${feedback ? `\nFix this issue from the previous attempt:\n${feedback}\n` : ''}

Return this shape:
{
  "situation": {
    "slug": "${situation.slug}",
    "title_es": "${situation.titleEs}",
    "title_en": "${situation.titleEn}",
    "description_es": "string breve",
    "level_band": "${situation.levelBand ?? 'A2-B1'}",
    "icon": "${situation.icon}",
    "content_kind": "expressions",
    "expressions": [
      {
        "phrase_en": "string",
        "meaning_es": "string",
        "when_to_use_es": "string",
        "tone": "casual | neutral | polite",
        "example_en": "string",
        "pronunciation": "string opcional",
        "variants": ["string"],
        "dialogue": [
          { "speaker": "A", "text": "string" },
          { "speaker": "B", "text": "string" }
        ]
      }
    ],
    "practice": [
      {
        "prompt": "string",
        "options": [
          { "text": "string", "is_correct": true },
          { "text": "string", "is_correct": false },
          { "text": "string", "is_correct": false },
          { "text": "string", "is_correct": false }
        ],
        "explanation_es": "string"
      }
    ]
  }
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
    // Intentamos extraer el objeto completo más abajo.
  }
  const match = cleaned.match(/\{[\s\S]*\}/);
  if (!match) throw new Error(`Respuesta sin JSON: ${text.slice(0, 200)}`);
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

function validatePracticeQuestions(situation) {
  const practice = situation.practice;
  if (!Array.isArray(practice) || practice.length !== PRACTICE_QUESTIONS) {
    throw new Error(`practice debe tener ${PRACTICE_QUESTIONS} preguntas`);
  }
  for (const [index, question] of practice.entries()) {
    const label = `practice${index + 1}`;
    if (typeof question?.prompt !== 'string' || question.prompt.trim().length < 8) {
      throw new Error(`${label}.prompt ausente o corto`);
    }
    const options = Array.isArray(question.options) ? question.options : [];
    if (options.length !== 4) throw new Error(`${label}: debe tener 4 opciones`);
    const correct = options.filter((option) => option?.is_correct === true).length;
    if (correct !== 1) throw new Error(`${label}: debe tener 1 opción correcta`);
  }
}

function baseSituationFromPayload(payload, expected) {
  const situation = payload?.situation;
  if (!situation || typeof situation !== 'object') {
    throw new Error('Respuesta sin objeto situation');
  }
  if (situation.slug !== expected.slug) {
    throw new Error(`slug incorrecto: ${situation.slug}`);
  }
  return situation;
}

function validateExpressionSituation(payload, expected) {
  const situation = baseSituationFromPayload(payload, expected);
  situation.content_kind = 'expressions';
  const expressions = situation.expressions;
  if (!Array.isArray(expressions)) {
    throw new Error('situation.expressions debe ser arreglo');
  }
  if (expressions.length < MIN_EXPRESSIONS || expressions.length > MAX_EXPRESSIONS) {
    throw new Error(`expresiones fuera de rango: ${expressions.length}`);
  }
  const seen = new Set();
  for (const [index, expression] of expressions.entries()) {
    const label = `expression${index + 1}`;
    for (const key of ['phrase_en', 'meaning_es', 'when_to_use_es', 'tone']) {
      if (typeof expression?.[key] !== 'string' || expression[key].trim().length < 2) {
        throw new Error(`${label}.${key} ausente o corto`);
      }
    }
    const phrase = expression.phrase_en.trim().toLowerCase();
    if (seen.has(phrase)) throw new Error(`${label}: frase duplicada "${phrase}"`);
    seen.add(phrase);
    if (!['casual', 'neutral', 'polite'].includes(expression.tone)) {
      throw new Error(`${label}.tone inválido: ${expression.tone}`);
    }
  }

  validatePracticeQuestions(situation);
  return situation;
}

function validateTechnicalSituation(payload, expected) {
  const situation = baseSituationFromPayload(payload, expected);
  situation.content_kind = 'technical_interview';
  const questions = situation.technical_questions;
  const minQuestions = minTechnicalQuestions(expected);
  const maxQuestions = maxTechnicalQuestions(expected);
  if (!Array.isArray(questions)) {
    throw new Error('situation.technical_questions debe ser arreglo');
  }
  if (questions.length < minQuestions || questions.length > maxQuestions) {
    throw new Error(`preguntas técnicas fuera de rango: ${questions.length}`);
  }

  const seen = new Set();
  for (const [index, question] of questions.entries()) {
    const label = `technical_question${index + 1}`;
    for (const key of ['question_en', 'answer_en', 'answer_es', 'difficulty']) {
      if (typeof question?.[key] !== 'string' || question[key].trim().length < 2) {
        throw new Error(`${label}.${key} ausente o corto`);
      }
    }
    if (question.question_en.trim().length < 12) {
      throw new Error(`${label}.question_en demasiado corta`);
    }
    if (question.answer_en.trim().length < 80) {
      throw new Error(`${label}.answer_en demasiado corta`);
    }
    const difficulty = question.difficulty.trim().toLowerCase();
    if (!['junior', 'mid', 'senior'].includes(difficulty)) {
      throw new Error(`${label}.difficulty inválido: ${question.difficulty}`);
    }
    question.difficulty = difficulty;

    const questionText = question.question_en.trim().toLowerCase();
    if (seen.has(questionText)) throw new Error(`${label}: pregunta duplicada`);
    seen.add(questionText);

    const keyPoints = Array.isArray(question.key_points) ? question.key_points : [];
    if (keyPoints.length < 3) throw new Error(`${label}.key_points debe tener mínimo 3`);
    const followUps = Array.isArray(question.follow_up_questions)
      ? question.follow_up_questions
      : [];
    if (followUps.length < 1) {
      throw new Error(`${label}.follow_up_questions debe tener mínimo 1`);
    }
    const mistakes = Array.isArray(question.common_mistakes) ? question.common_mistakes : [];
    if (mistakes.length < 1) throw new Error(`${label}.common_mistakes debe tener mínimo 1`);
    const tags = Array.isArray(question.tags) ? question.tags : [];
    if (tags.length < 1) throw new Error(`${label}.tags debe tener mínimo 1`);
  }

  validatePracticeQuestions(situation);
  return situation;
}

function validateSituation(payload, expected) {
  return isTechnicalInterview(expected)
    ? validateTechnicalSituation(payload, expected)
    : validateExpressionSituation(payload, expected);
}

async function generateSituationOnce(situation, feedback = '') {
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      instructions: SYSTEM_PROMPT,
      input: [{ role: 'user', content: [{ type: 'input_text', text: userPrompt(situation, feedback) }] }],
      max_output_tokens: MAX_OUTPUT_TOKENS,
    }),
  });
  if (!response.ok) {
    throw new Error(`OpenAI ${response.status}: ${(await response.text()).slice(0, 500)}`);
  }
  const data = await response.json();
  const text = extractOpenAIText(data);
  if (!text) throw new Error(`OpenAI sin texto: ${JSON.stringify(data).slice(0, 300)}`);
  return validateSituation(extractJson(text), situation);
}

async function generateSituation(situation) {
  let feedback = '';
  let lastError;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    try {
      return await generateSituationOnce(situation, feedback);
    } catch (error) {
      lastError = error;
      feedback = error.message;
      if (attempt < MAX_ATTEMPTS) {
        console.warn(`[retry] ${situation.slug}: ${error.message}`);
        await sleep(SLEEP_MS);
      }
    }
  }
  throw lastError;
}

async function existingExpressionCount(situationId) {
  const { count, error } = await supabase
    .from('daily_life_expressions')
    .select('id', { count: 'exact', head: true })
    .eq('situation_id', situationId);
  if (error) throw error;
  return count ?? 0;
}

async function existingTechnicalQuestionCount(situationId) {
  const { count, error } = await supabase
    .from('technical_interview_questions')
    .select('id', { count: 'exact', head: true })
    .eq('situation_id', situationId);
  if (error) throw error;
  return count ?? 0;
}

async function clearSituationChildren(situationId) {
  const { error: technicalError } = await supabase
    .from('technical_interview_questions')
    .delete()
    .eq('situation_id', situationId);
  if (technicalError) throw technicalError;

  const { error: expressionError } = await supabase
    .from('daily_life_expressions')
    .delete()
    .eq('situation_id', situationId);
  if (expressionError) throw expressionError;

  const { error: questionError } = await supabase
    .from('daily_life_practice_questions')
    .delete()
    .eq('situation_id', situationId);
  if (questionError) throw questionError;
}

function contentKindFor(seed, generated) {
  return generated.content_kind ?? (isTechnicalInterview(seed) ? 'technical_interview' : 'expressions');
}

function stringList(value) {
  return Array.isArray(value)
    ? value.map((item) => String(item).trim()).filter((item) => item.length > 0)
    : [];
}

async function upsertSituation(seed, generated) {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('daily_life_situations')
    .upsert(
      {
        slug: seed.slug,
        title_es: generated.title_es ?? seed.titleEs,
        title_en: generated.title_en ?? seed.titleEn,
        description_es: generated.description_es ?? null,
        level_band: generated.level_band ?? seed.levelBand ?? 'A2-B1',
        icon: generated.icon ?? seed.icon,
        content_kind: contentKindFor(seed, generated),
        sort_order: seed.sortOrder,
        generated_by_ai: true,
        ai_model: OPENAI_MODEL,
        ai_generated_at: now,
        updated_at: now,
      },
      { onConflict: 'slug' },
    )
    .select('id')
    .single();
  if (error) throw error;
  return data.id;
}

async function persistPracticeQuestions(situationId, practice, now) {
  for (const [index, question] of practice.entries()) {
    const { data: questionRow, error: questionError } = await supabase
      .from('daily_life_practice_questions')
      .insert({
        situation_id: situationId,
        prompt: question.prompt.trim(),
        explanation_es: question.explanation_es?.trim() ?? null,
        sort_order: index,
        generated_by_ai: true,
        ai_model: OPENAI_MODEL,
        ai_generated_at: now,
        updated_at: now,
      })
      .select('id')
      .single();
    if (questionError) throw questionError;

    const optionRows = question.options.map((option, optionIndex) => ({
      question_id: questionRow.id,
      text: option.text.trim(),
      is_correct: option.is_correct === true,
      sort_order: optionIndex,
    }));
    const { error: optionError } = await supabase
      .from('daily_life_practice_options')
      .insert(optionRows);
    if (optionError) throw optionError;
  }
}

async function persistExpressionSituation(seed, generated, situationId, { replace }) {
  const existing = await existingExpressionCount(situationId);
  if (existing > 0 && !replace) {
    console.log(`[skip] ${seed.slug}: ya tiene ${existing} expresiones`);
    return;
  }
  if (existing > 0 && replace) {
    await clearSituationChildren(situationId);
    console.log(`[repl] ${seed.slug}: contenido anterior eliminado`);
  }

  const now = new Date().toISOString();
  const expressionRows = generated.expressions.map((expression, index) => ({
    situation_id: situationId,
    phrase_en: expression.phrase_en.trim(),
    meaning_es: expression.meaning_es.trim(),
    when_to_use_es: expression.when_to_use_es?.trim() ?? null,
    tone: expression.tone,
    example_en: expression.example_en?.trim() ?? null,
    pronunciation: expression.pronunciation?.trim() ?? null,
    variants: Array.isArray(expression.variants) ? expression.variants : [],
    dialogue: Array.isArray(expression.dialogue) ? expression.dialogue : [],
    sort_order: index,
    generated_by_ai: true,
    ai_model: OPENAI_MODEL,
    ai_generated_at: now,
    updated_at: now,
  }));
  const { error: expressionError } = await supabase
    .from('daily_life_expressions')
    .insert(expressionRows);
  if (expressionError) throw expressionError;

  await persistPracticeQuestions(situationId, generated.practice, now);

  console.log(
    `[ok] ${seed.slug}: ${expressionRows.length} expresiones, ${generated.practice.length} preguntas`,
  );
}

async function persistTechnicalSituation(seed, generated, situationId, { replace }) {
  const existingTechnical = await existingTechnicalQuestionCount(situationId);
  const existingExpressions = await existingExpressionCount(situationId);
  if (existingTechnical > 0 && !replace) {
    console.log(`[skip] ${seed.slug}: ya tiene ${existingTechnical} preguntas técnicas`);
    return;
  }
  if (replace || existingTechnical > 0 || existingExpressions > 0) {
    await clearSituationChildren(situationId);
    console.log(`[repl] ${seed.slug}: contenido anterior eliminado`);
  }

  const now = new Date().toISOString();
  const questionRows = generated.technical_questions.map((question, index) => ({
    situation_id: situationId,
    question_en: question.question_en.trim(),
    answer_en: question.answer_en.trim(),
    answer_es: question.answer_es?.trim() ?? null,
    sample_answer_en: question.sample_answer_en?.trim() ?? null,
    category: question.category?.trim() ?? null,
    difficulty: question.difficulty,
    key_points: stringList(question.key_points),
    follow_up_questions: stringList(question.follow_up_questions),
    common_mistakes: stringList(question.common_mistakes),
    tags: stringList(question.tags),
    sort_order: index,
    generated_by_ai: true,
    ai_model: OPENAI_MODEL,
    ai_generated_at: now,
    updated_at: now,
  }));
  const { error: questionError } = await supabase
    .from('technical_interview_questions')
    .insert(questionRows);
  if (questionError) throw questionError;

  await persistPracticeQuestions(situationId, generated.practice, now);

  console.log(
    `[ok] ${seed.slug}: ${questionRows.length} preguntas técnicas, ${generated.practice.length} preguntas de práctica`,
  );
}

async function persistGeneratedSituation(seed, generated, { replace }) {
  const situationId = await upsertSituation(seed, generated);
  if (contentKindFor(seed, generated) === 'technical_interview') {
    await persistTechnicalSituation(seed, generated, situationId, { replace });
    return;
  }
  await persistExpressionSituation(seed, generated, situationId, { replace });
}

function selectedSituations() {
  let list = SITUATIONS;
  if (args.slug) {
    list = list.filter((situation) => situation.slug === args.slug);
    if (list.length === 0) throw new Error(`Situación desconocida: ${args.slug}`);
  }
  if (args.group) {
    list = list.filter((situation) => situation.group === args.group);
    if (list.length === 0) throw new Error(`Grupo desconocido o vacío: ${args.group}`);
  }
  if (args.limit) {
    list = list.slice(0, Number.parseInt(args.limit, 10));
  }
  return list;
}

async function main() {
  const replace = args.replace === true || args.replace === 'true';
  const targets = selectedSituations();
  console.log(`[info] Generando ${targets.length} situación(es) con ${OPENAI_MODEL}`);

  for (const target of targets) {
    try {
      console.log(`[gen] ${target.slug}`);
      const generated = await generateSituation(target);
      await persistGeneratedSituation(target, generated, { replace });
      await sleep(SLEEP_MS);
    } catch (error) {
      console.error(`[err] ${target.slug}: ${error.message}`);
    }
  }
  console.log('[DONE]');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
