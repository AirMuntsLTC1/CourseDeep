// CourseDeep AI backend - Cloudflare Worker (free, no bot-check pages).
// Set the secret GROQ_API_KEY in the Worker settings (never put it in the app).

const SYSTEM_PROMPT =
  "You are CourseDeep, a helpful, friendly and accurate AI assistant. " +
  "Answer clearly, use short paragraphs or lists when they help, and be honest when unsure.";
const MODEL = "openai/gpt-oss-120b";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    if (request.method !== "POST") return json({ error: "Use POST" }, 405);
    if (!env.GROQ_API_KEY) return json({ error: "GROQ_API_KEY secret is not set" }, 500);

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    const history = (Array.isArray(body.messages) ? body.messages : [])
      .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
      .slice(-30);

    if (history.length === 0) return json({ error: "No messages provided" }, 400);

    const upstream = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GROQ_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [{ role: "system", content: SYSTEM_PROMPT }, ...history],
      }),
    });

    const data = await upstream.json().catch(() => null);
    if (!upstream.ok || !data) {
      const msg = data?.error?.message || `AI service error (HTTP ${upstream.status})`;
      return json({ error: msg }, 502);
    }

    const reply = data.choices?.[0]?.message?.content;
    if (!reply) return json({ error: "The model returned no answer" }, 502);

    return json({ reply });
  },
};
