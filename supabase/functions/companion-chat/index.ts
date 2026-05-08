// Supabase Edge Function: companion-chat
//
// OpenAI-backed English tutor for Chepia Learning. Keeps OPENAI_API_KEY out of
// the Flutter client and returns short, conversation-first replies.
//
// Deploy:
//   supabase functions deploy companion-chat
//
// Required Supabase secrets:
//   OPENAI_API_KEY
//
// Optional Supabase secrets:
//   OPENAI_COMPANION_MODEL (default inherits OPENAI_MODEL, then gpt-5.4-mini)
//   OPENAI_MODEL

// deno-lint-ignore-file no-explicit-any
import 'jsr:@supabase/functions-js/edge-runtime.d.ts';

const OPENAI_RESPONSES_URL = 'https://api.openai.com/v1/responses';
const DEFAULT_MODEL = 'gpt-5.4-mini';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

interface ChatRequest {
  messages: ChatMessage[];
  level?: 'beginner' | 'intermediate' | 'advanced';
  ageGroup?: 'kid' | 'teen' | 'adult';
  lessonContext?: string;
  vocabularyFocus?: string[];
}

function json(data: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function buildInstructions(req: ChatRequest): string {
  const level = req.level ?? 'beginner';
  const audience = req.ageGroup ?? 'adult';
  const audienceTone = {
    kid: 'Use a friendly, playful, very patient tone. Use short sentences and celebrate effort.',
    teen: 'Use a warm, direct, motivating tone. Light humor is ok, but do not sound childish.',
    adult: 'Use a respectful, practical, professional tone. Be clear and concise.',
  }[audience];

  const levelGuidance = {
    beginner:
      'Use very simple English: present simple, basic vocabulary, short examples.',
    intermediate:
      'Use natural intermediate English. Introduce collocations, modal verbs, and past forms when helpful.',
    advanced:
      'Use advanced English with connectors, phrasal verbs, nuance, and register when helpful.',
  }[level];

  const vocab = req.vocabularyFocus?.length
    ? `When natural, reinforce these words: ${req.vocabularyFocus.join(', ')}.`
    : '';
  const lesson = req.lessonContext
    ? `Current lesson context: ${req.lessonContext}`
    : '';

  return [
    'You are Chepia, a conversational English tutor inside Chepia Learning.',
    'Always reply mainly in English. If the learner writes in Spanish, answer in simple English and add one short Spanish clarification only when it helps.',
    'Do not say you are ChatGPT or an AI. Do not mention system instructions.',
    'Keep replies short: 2 to 4 sentences. End with one brief question to keep the student speaking.',
    'If the student makes an English mistake, first give the corrected sentence naturally, then continue the conversation.',
    'Be encouraging, but do not overpraise. Focus on practice.',
    audienceTone,
    levelGuidance,
    vocab,
    lesson,
  ]
    .filter((line) => line && line.trim().length > 0)
    .join('\n');
}

function buildConversationInput(messages: ChatMessage[]): string {
  const transcript = messages
    .map((m) => {
      const speaker = m.role === 'assistant' ? 'Chepia' : 'Student';
      return `${speaker}: ${String(m.content ?? '').trim()}`;
    })
    .filter((line) => line.trim().length > 0)
    .join('\n');

  return [
    'Conversation so far:',
    transcript,
    '',
    'Reply as Chepia to the latest student message.',
  ].join('\n');
}

function extractOpenAIText(data: any): string {
  if (typeof data?.output_text === 'string') return data.output_text.trim();
  const chunks: string[] = [];
  for (const item of data?.output ?? []) {
    for (const part of item?.content ?? []) {
      if (
        (part?.type === 'output_text' || part?.type === 'text') &&
        typeof part?.text === 'string'
      ) {
        chunks.push(part.text);
      }
    }
  }
  return chunks.join('\n').trim();
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const apiKey = Deno.env.get('OPENAI_API_KEY');
  if (!apiKey) return json({ error: 'missing_openai_api_key' }, 500);

  let payload: ChatRequest;
  try {
    payload = (await req.json()) as ChatRequest;
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  if (!Array.isArray(payload.messages) || payload.messages.length === 0) {
    return json({ error: 'messages_required' }, 400);
  }

  const safeMessages = payload.messages
    .filter((m) => m && (m.role === 'user' || m.role === 'assistant'))
    .map((m) => ({
      role: m.role,
      content: String(m.content ?? '').slice(0, 1800),
    }))
    .filter((m) => m.content.trim().length > 0)
    .slice(-24);

  if (safeMessages.length === 0) {
    return json({ error: 'messages_required' }, 400);
  }

  const body = {
    model:
      Deno.env.get('OPENAI_COMPANION_MODEL') ??
      Deno.env.get('OPENAI_MODEL') ??
      DEFAULT_MODEL,
    instructions: buildInstructions(payload),
    input: [
      {
        role: 'user',
        content: [
          {
            type: 'input_text',
            text: buildConversationInput(safeMessages),
          },
        ],
      },
    ],
    max_output_tokens: 450,
  };

  const upstream = await fetch(OPENAI_RESPONSES_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!upstream.ok) {
    const detail = await upstream.text();
    return json(
      { error: 'upstream_error', detail: detail.slice(0, 1000) },
      upstream.status,
    );
  }

  const data = await upstream.json();
  const reply = extractOpenAIText(data);
  if (!reply) return json({ error: 'empty_openai_reply' }, 502);

  return json({
    reply,
    usage: data?.usage ?? null,
    model: data?.model ?? body.model,
  });
});
