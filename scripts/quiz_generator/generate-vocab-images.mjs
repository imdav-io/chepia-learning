// Genera ilustraciones para vocabulario curado y las sube a Supabase Storage.
// Llena la columna `image_url` de `lesson_vocabulary` (migración 0009).
//
// Uso:
//   cd scripts/quiz_generator
//   node generate-vocab-images.mjs --book=as-it-is-book-1 --max=50
//   node generate-vocab-images.mjs --lesson=<lesson_uuid>
//   node generate-vocab-images.mjs --replace        # regenera incluso si ya hay url
//
// Requiere en .env:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   OPENAI_API_KEY (DALL-E 3 / gpt-image-1)
//   OPENAI_IMAGE_MODEL (opcional, default: gpt-image-1)
//
// Sube las imágenes al bucket `vocab-images`. Crea el bucket público en Supabase
// antes de la primera corrida (Supabase Studio > Storage > New bucket > Public).

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const args = parseArgs(process.argv.slice(2));
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false } },
);

const BUCKET = 'vocab-images';
const IMAGE_MODEL = process.env.OPENAI_IMAGE_MODEL || 'gpt-image-1';
const MAX_TERMS = Number(args.max) || 50;
const SHOULD_REPLACE = args.replace === true || args.replace === 'true';

if (!process.env.OPENAI_API_KEY) {
  console.error('Falta OPENAI_API_KEY en .env');
  process.exit(1);
}

await ensureBucket();

const terms = await loadTerms();
console.log(`[info] ${terms.length} término(s) candidatos. Procesando hasta ${MAX_TERMS}.`);

let done = 0;
let failed = 0;
for (const term of terms.slice(0, MAX_TERMS)) {
  try {
    const url = await generateAndUpload(term);
    await supabase
      .from('lesson_vocabulary')
      .update({ image_url: url, image_alt: `Illustration of ${term.term}` })
      .eq('id', term.id);
    console.log(`[ok ] ${term.term} -> ${url}`);
    done++;
  } catch (e) {
    failed++;
    console.warn(`[fail] ${term.term}: ${e.message}`);
  }
}
console.log(`[done] ${done} ilustradas, ${failed} fallidas.`);

// ----------------------------------------------------------------------

async function loadTerms() {
  let query = supabase
    .from('lesson_vocabulary')
    .select('id, lesson_id, term, meaning_es, lessons:lesson_id(book_id, books:book_id(slug))')
    .order('sort_order', { ascending: true });

  if (!SHOULD_REPLACE) {
    query = query.is('image_url', null);
  }
  if (args.lesson) {
    query = query.eq('lesson_id', args.lesson);
  }
  const { data, error } = await query;
  if (error) throw error;
  if (args.book) {
    return (data || []).filter((t) => t.lessons?.books?.slug === args.book);
  }
  return data || [];
}

async function ensureBucket() {
  const { data: list } = await supabase.storage.listBuckets();
  if ((list || []).some((b) => b.name === BUCKET)) return;
  console.log(`[info] creando bucket público "${BUCKET}"`);
  const { error } = await supabase.storage.createBucket(BUCKET, { public: true });
  if (error) throw error;
}

async function generateAndUpload(term) {
  const prompt = buildPrompt(term);
  const res = await fetch('https://api.openai.com/v1/images/generations', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: IMAGE_MODEL,
      prompt,
      n: 1,
      size: '1024x1024',
    }),
  });
  if (!res.ok) {
    throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  }
  const json = await res.json();
  const b64 = json?.data?.[0]?.b64_json;
  const remoteUrl = json?.data?.[0]?.url;
  let bytes;
  if (b64) {
    bytes = Buffer.from(b64, 'base64');
  } else if (remoteUrl) {
    const r = await fetch(remoteUrl);
    bytes = Buffer.from(await r.arrayBuffer());
  } else {
    throw new Error('OpenAI no devolvió imagen.');
  }
  const path = `${term.lesson_id}/${term.id}.png`;
  const upload = await supabase.storage
    .from(BUCKET)
    .upload(path, bytes, {
      contentType: 'image/png',
      upsert: true,
    });
  if (upload.error) throw upload.error;
  const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
  return data.publicUrl;
}

function buildPrompt(term) {
  const word = term.term;
  const meaning = term.meaning_es || '';
  return [
    `A simple, friendly flat illustration that represents the meaning of the English word "${word}".`,
    meaning ? `In Spanish it means: "${meaning}".` : '',
    'Style: minimal, clean vector art, soft pastel colors, white background, no text, no letters, child-friendly.',
    'Composition: subject centered, clear silhouette, easy to recognize at thumbnail size.',
  ]
    .filter(Boolean)
    .join(' ');
}

function parseArgs(list) {
  const out = {};
  for (const a of list) {
    if (!a.startsWith('--')) continue;
    const [k, v] = a.replace(/^--/, '').split('=');
    out[k] = v ?? true;
  }
  return out;
}
