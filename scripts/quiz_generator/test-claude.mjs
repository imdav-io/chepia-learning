// Smoke test del modelo y la API key antes de correr generate.mjs sobre 80
// lecciones. Una sola llamada cuesta ~$0.01 y confirma:
//   1. Que ANTHROPIC_API_KEY funciona
//   2. Que el `model` ID es válido
//   3. Que el JSON parse no se rompe con la respuesta real
//
// Uso: node test-claude.mjs [model_id]
//   model_id default: claude-sonnet-4-5

import 'dotenv/config';
import Anthropic from '@anthropic-ai/sdk';

const model = process.argv[2] ?? 'claude-sonnet-4-5';
const { ANTHROPIC_API_KEY } = process.env;
if (!ANTHROPIC_API_KEY) {
  console.error('Falta ANTHROPIC_API_KEY en .env');
  process.exit(1);
}

const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

console.log(`Probando model="${model}" ...`);
try {
  const res = await anthropic.messages.create({
    model,
    max_tokens: 200,
    messages: [
      {
        role: 'user',
        content:
          'Responde SOLO con un JSON: {"ok": true, "model_used": "<el model id que estás usando>"}',
      },
    ],
  });
  const text = res.content
    .filter((c) => c.type === 'text')
    .map((c) => c.text)
    .join('\n');
  console.log('OK. Respuesta cruda:');
  console.log(text);
  console.log('\nUsage:', res.usage);
} catch (e) {
  console.error('FALLÓ:', e.status, e.message);
  console.error('Sugerencia: prueba con "claude-sonnet-4-7", "claude-sonnet-4-5", o un id dated.');
  process.exit(1);
}
