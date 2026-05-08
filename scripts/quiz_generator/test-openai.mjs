// Smoke test del modelo y la API key antes de correr generación masiva.
//
// Uso:
//   node test-openai.mjs
//   node test-openai.mjs gpt-5-mini

import 'dotenv/config';

const model = process.argv[2] ?? process.env.OPENAI_MODEL ?? 'gpt-5-mini';
const { OPENAI_API_KEY } = process.env;

if (!OPENAI_API_KEY) {
  console.error('Falta OPENAI_API_KEY en .env');
  process.exit(1);
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

console.log(`Probando OpenAI model="${model}" ...`);

try {
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      instructions: 'Always return valid JSON with no extra text.',
      input: 'Return ONLY this JSON: {"ok": true, "provider": "openai"}',
      max_output_tokens: 200,
    }),
  });

  if (!response.ok) {
    throw new Error(`OpenAI ${response.status}: ${(await response.text()).slice(0, 500)}`);
  }

  const data = await response.json();
  const text = extractOpenAIText(data);
  console.log('OK. Respuesta cruda:');
  console.log(text);
  console.log('\nUsage:', data.usage ?? 'sin usage');
} catch (error) {
  console.error('FALLO:', error.message);
  process.exit(1);
}
