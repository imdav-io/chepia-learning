// Supabase Edge Function: vocabulary-tts
//
// Generates OpenAI TTS audio once for curated lesson vocabulary, stores it in
// Supabase Storage, and returns a signed URL. Subsequent calls reuse the stored
// object and do not call OpenAI again.
//
// Required Supabase secrets:
//   OPENAI_API_KEY
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY
//
// Optional Supabase secrets:
//   OPENAI_TTS_MODEL  (default gpt-4o-mini-tts)
//   OPENAI_TTS_VOICE  (default marin)

// deno-lint-ignore-file no-explicit-any
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const OPENAI_SPEECH_URL = 'https://api.openai.com/v1/audio/speech';
const BUCKET = 'vocab-audio';
const SIGNED_URL_TTL_SECONDS = 60 * 60 * 24;
const DEFAULT_MODEL = 'gpt-4o-mini-tts';
const DEFAULT_VOICE = 'marin';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type SpeechUsage = 'term' | 'example';

interface SpeechRequest {
  lessonVocabularyId?: string;
  usage?: SpeechUsage;
}

interface LessonVocabularyRow {
  id: string;
  term: string;
  example_en: string | null;
  audio_storage_path: string | null;
}

function json(data: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}

function normalizeUsage(value: unknown): SpeechUsage {
  return value === 'example' ? 'example' : 'term';
}

async function hashText(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value.trim().toLowerCase()),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .slice(0, 16);
}

function buildInstructions({
  usage,
  example,
}: {
  usage: SpeechUsage;
  example: string | null;
}): string {
  const base =
    'Speak in clear, natural American English for an English learner. Use a calm, friendly tone and precise pronunciation. Read only the target text, with no extra words.';
  if (usage === 'example') return `${base} Keep the sentence natural.`;
  if (!example?.trim()) return `${base} Pronounce the word or phrase naturally.`;
  return `${base} Use this context only to choose pronunciation, but do not read it aloud: "${example.trim()}".`;
}

async function objectExists(storage: any, path: string): Promise<boolean> {
  const { error } = await storage.from(BUCKET).download(path);
  return !error;
}

async function signedUrl(storage: any, path: string): Promise<string> {
  const { data, error } = await storage
    .from(BUCKET)
    .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
  if (error || !data?.signedUrl) {
    throw new Error(`signed_url_failed:${error?.message ?? 'unknown'}`);
  }
  return data.signedUrl;
}

async function generateSpeech({
  text,
  usage,
  example,
  model,
  voice,
  apiKey,
}: {
  text: string;
  usage: SpeechUsage;
  example: string | null;
  model: string;
  voice: string;
  apiKey: string;
}): Promise<ArrayBuffer> {
  const upstream = await fetch(OPENAI_SPEECH_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      voice,
      input: text,
      instructions: buildInstructions({ usage, example }),
      response_format: 'mp3',
    }),
  });

  if (!upstream.ok) {
    const detail = await upstream.text();
    throw new Error(`openai_${upstream.status}:${detail.slice(0, 500)}`);
  }

  return upstream.arrayBuffer();
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  let env;
  try {
    env = {
      openaiApiKey: requireEnv('OPENAI_API_KEY'),
      supabaseUrl: requireEnv('SUPABASE_URL'),
      supabaseAnonKey: requireEnv('SUPABASE_ANON_KEY'),
      supabaseServiceRoleKey: requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
      model: Deno.env.get('OPENAI_TTS_MODEL') ?? DEFAULT_MODEL,
      voice: Deno.env.get('OPENAI_TTS_VOICE') ?? DEFAULT_VOICE,
    };
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : 'missing_env' }, 500);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'auth_required' }, 401);

  const userClient = createClient(env.supabaseUrl, env.supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: 'auth_required' }, 401);

  let payload: SpeechRequest;
  try {
    payload = (await req.json()) as SpeechRequest;
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  const lessonVocabularyId = String(payload.lessonVocabularyId ?? '').trim();
  if (!lessonVocabularyId) return json({ error: 'lesson_vocabulary_id_required' }, 400);

  const usage = normalizeUsage(payload.usage);
  const serviceClient = createClient(
    env.supabaseUrl,
    env.supabaseServiceRoleKey,
    { auth: { persistSession: false } },
  );

  const { data: rowData, error: rowError } = await serviceClient
    .from('lesson_vocabulary')
    .select('id, term, example_en, audio_storage_path')
    .eq('id', lessonVocabularyId)
    .single();

  const row = rowData as LessonVocabularyRow | null;
  if (rowError || !row) return json({ error: 'lesson_vocabulary_not_found' }, 404);

  const text = usage === 'example' ? row.example_en?.trim() : row.term.trim();
  if (!text) return json({ error: 'speech_text_required' }, 400);

  const hash = await hashText(`${usage}:${text}`);
  const storagePath = `lesson-vocabulary/${row.id}/${usage}-${hash}.mp3`;
  const storage = serviceClient.storage;

  try {
    if (usage === 'term' && row.audio_storage_path === storagePath) {
      return json({
        signedUrl: await signedUrl(storage, storagePath),
        storagePath,
        cached: true,
      });
    }

    if (await objectExists(storage, storagePath)) {
      if (usage === 'term' && row.audio_storage_path !== storagePath) {
        await serviceClient
          .from('lesson_vocabulary')
          .update({
            audio_storage_path: storagePath,
            audio_model: env.model,
            audio_voice: env.voice,
          })
          .eq('id', row.id);
      }
      return json({
        signedUrl: await signedUrl(storage, storagePath),
        storagePath,
        cached: true,
      });
    }

    const audio = await generateSpeech({
      text,
      usage,
      example: row.example_en,
      model: env.model,
      voice: env.voice,
      apiKey: env.openaiApiKey,
    });

    const { error: uploadError } = await storage.from(BUCKET).upload(
      storagePath,
      audio,
      {
        contentType: 'audio/mpeg',
        upsert: true,
      },
    );
    if (uploadError) throw new Error(`upload_failed:${uploadError.message}`);

    if (usage === 'term') {
      await serviceClient
        .from('lesson_vocabulary')
        .update({
          audio_storage_path: storagePath,
          audio_model: env.model,
          audio_voice: env.voice,
          audio_generated_at: new Date().toISOString(),
        })
        .eq('id', row.id);
    }

    return json({
      signedUrl: await signedUrl(storage, storagePath),
      storagePath,
      cached: false,
    });
  } catch (e) {
    return json(
      {
        error: 'speech_generation_failed',
        detail: e instanceof Error ? e.message : String(e),
      },
      500,
    );
  }
});
