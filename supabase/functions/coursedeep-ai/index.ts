import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { messages } = await req.json()
    const recentMessages = messages.slice(-10);
    const userQuery = recentMessages[recentMessages.length - 1].content

    // Load all keys from Supabase Secrets
    const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
    const GROQ_API_KEY = Deno.env.get('GROQ_API_KEY')
    const CF_ACCOUNT_ID = Deno.env.get('CLOUDFLARE_ACCOUNT_ID')
    const CF_API_TOKEN = Deno.env.get('CLOUDFLARE_API_TOKEN')
    const OPENROUTER_API_KEY = Deno.env.get('OPENROUTER_API_KEY')
    const TAVILY_API_KEY = Deno.env.get('TAVILY_API_KEY')

    let reply = ""
    let sources = []
    let providerUsed = "None"
    let debugLog = []

    // --- STEP 1: ALWAYS SEARCH WITH TAVILY FIRST ---
    let context = "";
    if (TAVILY_API_KEY) {
      try {
        const tavilyRes = await fetch("https://api.tavily.com/search", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ api_key: TAVILY_API_KEY, query: userQuery, max_results: 3 })
        })
        const tavilyData = await tavilyRes.json()
        if (tavilyData.results) {
          sources = tavilyData.results;
          context = tavilyData.results.map((r: any) => `Source: ${r.title}\nURL: ${r.url}\nContent: ${r.content.substring(0, 500)}`).join("\n\n");
        }
      } catch (e: any) { debugLog.push(`Tavily failed: ${e.message}`) }
    }

    // Base prompt
    let systemPrompt = 'You are CourseDeep, a helpful AI assistant. Today is October 2026.';
    if (context) {
      systemPrompt = `You are CourseDeep. You MUST use the following real-time web search results to answer the user's question. DO NOT say you don't have access to real-time information.\n\nSearch Results:\n${context}`;
    }

    // --- TIER 1: Google Gemini ---
    if (GEMINI_API_KEY && !reply) {
      try {
        const geminiContents = recentMessages.map((m: any) => ({ 
            role: m.role === 'assistant' ? 'model' : 'user', 
            parts: [{ text: m.content }] 
        }));
        const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent`, {
          method: 'POST', 
          headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
          body: JSON.stringify({ 
            systemInstruction: { parts: [{ text: systemPrompt }] }, 
            contents: geminiContents, 
            generationConfig: { maxOutputTokens: 4096 } 
          }),
        })
        const data = await res.json()
        if (res.ok && data.candidates?.[0]?.content?.parts?.[0]?.text) {
          reply = data.candidates[0].content.parts[0].text; 
          providerUsed = "Gemini";
        } else { 
          debugLog.push(`Gemini failed: ${data.error?.message || 'Unknown'}`) 
        }
      } catch (e: any) { debugLog.push(`Gemini catch: ${e.message}`) }
    }

    // --- TIER 2: Groq ---
    if (GROQ_API_KEY && !reply) {
      try {
        const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
          method: 'POST', 
          headers: { 'Authorization': `Bearer ${GROQ_API_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ 
            model: 'openai/gpt-oss-120b', 
            messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], 
            max_tokens: 2048 
          }),
        })
        const data = await res.json()
        if (res.ok && data.choices?.[0]?.message?.content) {
          reply = data.choices[0].message.content; 
          providerUsed = "Groq";
        } else { 
          debugLog.push(`Groq failed: ${data.error?.message || 'Unknown'}`) 
        }
      } catch (e: any) { debugLog.push(`Groq catch: ${e.message}`) }
    }

    // --- TIER 3: Cloudflare Workers AI ---
    if (CF_ACCOUNT_ID && CF_API_TOKEN && !reply) {
      try {
        const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/ai/run/@cf/meta/llama-3.1-8b-instruct`, {
          method: 'POST', 
          headers: { 'Authorization': `Bearer ${CF_API_TOKEN}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ 
            messages: [{ role: 'system', content: systemPrompt }, ...recentMessages] 
          }),
        })
        const data = await res.json()
        if (res.ok && data.result?.response) {
          reply = data.result.response; 
          providerUsed = "Cloudflare";
        } else { 
          debugLog.push(`Cloudflare failed: ${JSON.stringify(data.errors)}`) 
        }
      } catch (e: any) { debugLog.push(`Cloudflare catch: ${e.message}`) }
    }

    // --- TIER 4: OpenRouter (Free Model) ---
    if (OPENROUTER_API_KEY && !reply) {
      try {
        const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
          method: 'POST', 
          headers: { 
            'Authorization': `Bearer ${OPENROUTER_API_KEY}`, 
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://coursedeep.app', // Required by OpenRouter
            'X-Title': 'CourseDeep'
          },
          body: JSON.stringify({ 
            model: 'meta-llama/llama-3.1-8b-instruct:free', 
            messages: [{ role: 'system', content: systemPrompt }, ...recentMessages] 
          }),
        })
        const data = await res.json()
        if (res.ok && data.choices?.[0]?.message?.content) {
          reply = data.choices[0].message.content; 
          providerUsed = "OpenRouter";
        } else { 
          debugLog.push(`OpenRouter failed: ${data.error?.message || 'Unknown'}`) 
        }
      } catch (e: any) { debugLog.push(`OpenRouter catch: ${e.message}`) }
    }

    // If all 4 failed
    if (!reply) {
      throw new Error(`All AI providers failed. Debug log: ${debugLog.join(" | ")}`)
    }

    return new Response(JSON.stringify({ reply, sources, provider: providerUsed }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})