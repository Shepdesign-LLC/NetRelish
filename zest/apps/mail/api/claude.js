// Vercel serverless function — the key never leaves the server.
// Set ANTHROPIC_API_KEY in Vercel → Project → Settings → Environment Variables.
// Optional: set MAILPRESS_TOKEN and enter the same value in the app's "Proxy token" field
// so random visitors can't spend your credits through /api/claude.
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (process.env.MAILPRESS_TOKEN && req.headers['x-mailpress-token'] !== process.env.MAILPRESS_TOKEN) return res.status(401).json({ error: 'Bad proxy token' });
  if (!process.env.ANTHROPIC_API_KEY) return res.status(500).json({ error: 'ANTHROPIC_API_KEY is not set on the server' });
  const { model, max_tokens, system, messages } = req.body || {};
  if (!model || !messages) return res.status(400).json({ error: 'model and messages are required' });
  const upstream = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-api-key': process.env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({ model, max_tokens: Math.min(max_tokens || 8000, 16000), system, messages })
  });
  const data = await upstream.json().catch(() => ({ error: 'Upstream returned a non-JSON response' }));
  res.status(upstream.status).json(data);
}
