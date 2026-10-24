import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// STRICT 3-SECOND TIMEOUT
async function fetchWithTimeout(url: string, options: any) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), 3000); // 3 seconds max per provider
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(id);
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { messages } = await req.json()
    const recentMessages = messages.slice(-6); // Keep history short for speed
    const userQuery = recentMessages[recentMessages.length - 1].content

    const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
    const GROQ_API_KEY = Deno.env.get('GROQ_API_KEY')
    const CF_ACCOUNT_ID = Deno.env.get('CLOUDFLARE_ACCOUNT_ID')
    const CF_API_TOKEN = Deno.env.get('CLOUDFLARE_API_TOKEN')
    const OPENROUTER_API_KEY = Deno.env.get('OPENROUTER_API_KEY')
    const TAVILY_API_KEY = Deno.env.get('TAVILY_API_KEY')

    let reply = ""
    let sources = []
    let providerUsed = "None"

    // --- STEP 1: TAVILY SEARCH (Fast Mode) ---
    let context = "";
    if (TAVILY_API_KEY) {
      try {
        const tavilyRes = await fetchWithTimeout("https://api.tavily.com/search", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ 
            api_key: TAVILY_API_KEY, 
            query: userQuery, 
            search_depth: "basic", // "basic" is much faster than "advanced"
            max_results: 3 
          })
        })
        const tavilyData = await tavilyRes.json()
        if (tavilyData.results) {
          sources = tavilyData.results;
          context = tavilyData.results.map((r: any) => `Source: ${r.title}\nURL: ${r.url}\nContent: ${r.content.substring(0, 400)}`).join("\n\n");
        }
      } catch (e) { console.error("Tavily timeout") }
    }

    let systemPrompt = 'You are CourseDeep, a helpful AI assistant. Today is October 2026. Keep answers concise.';
    if (context) {
      systemPrompt = `You are CourseDeep. Use this search context to answer concisely:\n\n${context}`;
    }

    // --- TIER 1: Groq (Fastest LLM on Earth - ~300ms) ---
    if (GROQ_API_KEY && !reply) {
      try {
        const res = await fetchWithTimeout('https://api.groq.com/openai/v1/chat/completions', {
          method: 'POST', 
          headers: { 'Authorization': `Bearer ${GROQ_API_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ 
            model: 'openai/gpt-oss-120b', 
            messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], 
            max_tokens: 1024 // Reduced from 2048 for speed
          }),
        })
        const data = await res.json()
        if (res.ok && data.choices?.[0]?.message?.content) {
          reply = data.choices[0].message.content; providerUsed = "Groq";
        }
      } catch (e) { console.error("Groq timeout/fail") }
    }

    // --- TIER 2: Google Gemini ---
    if (GEMINI_API_KEY && !reply) {
      try {
        const geminiContents = recentMessages.map((m: any) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }));
        const res = await fetchWithTimeout(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent`, {
          method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
          body: JSON.stringify({ 
            systemInstruction: { parts: [{ text: systemPrompt }] }, 
            contents: geminiContents, 
            generationConfig: { maxOutputTokens: 1024 } // Reduced from 4096
          }),
        })
        const data = await res.json()
        if (res.ok && data.candidates?.[0]?.content?.parts?.[0]?.text) {
          reply = data.candidates[0].content.parts[0].text; providerUsed = "Gemini";
        }
      } catch (e) { console.error("Gemini timeout/fail") }
    }

    // --- TIER 3: Cloudflare ---
    if (CF_ACCOUNT_ID && CF_API_TOKEN && !reply) {
      try {
        const res = await fetchWithTimeout(`https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/ai/run/@cf/meta/llama-3.1-8b-instruct`, {
          method: 'POST', headers: { 'Authorization': `Bearer ${CF_API_TOKEN}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ messages: [{ role: 'system', content: systemPrompt }, ...recentMessages] }),
        })
        const data = await res.json()
        if (res.ok && data.result?.response) {
          reply = data.result.response; providerUsed = "Cloudflare";
        }
      } catch (e) { console.error("CF timeout/fail") }
    }

    // --- TIER 4: OpenRouter ---
    if (OPENROUTER_API_KEY && !reply) {
      try {
        const res = await fetchWithTimeout('https://openrouter.ai/api/v1/chat/completions', {
          method: 'POST', headers: { 
            'Authorization': `Bearer ${OPENROUTER_API_KEY}`, 
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://coursedeep.app',
            'X-Title': 'CourseDeep'
          },
          body: JSON.stringify({ model: 'meta-llama/llama-3.1-8b-instruct:free', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages] }),
        })
        const data = await res.json()
        if (res.ok && data.choices?.[0]?.message?.content) {
          reply = data.choices[0].message.content; providerUsed = "OpenRouter";
        }
      } catch (e) { console.error("OpenRouter timeout/fail") }
    }

    if (!reply) throw new Error(`All providers timed out or failed.`)

    return new Response(JSON.stringify({ reply, sources, provider: providerUsed }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})