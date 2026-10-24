import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Custom timeout helper
async function fetchWithTimeout(url: string, options: any, timeoutMs: number) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
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
    const recentMessages = messages.slice(-4);
    const latestMsg = recentMessages[recentMessages.length - 1];
    const userQuery = latestMsg.content || "What is in this image?";
    const imageBase64 = latestMsg.image;

    // Load ALL secrets
    const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
    const GROQ_API_KEY = Deno.env.get('GROQ_API_KEY')
    const CF_ACCOUNT_ID = Deno.env.get('CLOUDFLARE_ACCOUNT_ID')
    const CF_API_TOKEN = Deno.env.get('CLOUDFLARE_API_TOKEN')
    const OPENROUTER_API_KEY = Deno.env.get('OPENROUTER_API_KEY')
    const TAVILY_API_KEY = Deno.env.get('TAVILY_API_KEY')
    const NVIDIA_API_KEY = Deno.env.get('NVIDIA_API_KEY')
    const SAMBANOVA_API_KEY = Deno.env.get('SAMBANOVA_API_KEY')
    const DEEPSEEK_API_KEY = Deno.env.get('DEEPSEEK_API_KEY')

    let reply = ""
    let sources = []
    let providerUsed = "None"
    let debugLog = []

    // ==========================================
    // ROUTE 1: VISION (Image Analysis)
    // ==========================================
    if (imageBase64) {
      
      // TIER 1: Gemini Vision (Best for images)
      if (GEMINI_API_KEY && !reply) {
        try {
          const geminiContents = [{
            role: 'user',
            parts: [
              { text: userQuery },
              { inlineData: { mimeType: 'image/jpeg', data: imageBase64 } }
            ]
          }];
          const res = await fetchWithTimeout(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent`, {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
            body: JSON.stringify({ contents: geminiContents, generationConfig: { maxOutputTokens: 1024 } }),
          }, 30000) // 30s for vision
          const data = await res.json()
          if (res.ok && data.candidates?.[0]?.content?.parts?.[0]?.text) { 
            reply = data.candidates[0].content.parts[0].text; providerUsed = "Gemini Vision"; 
          } else { debugLog.push(`Gemini Vision failed: ${data.error?.message}`) }
        } catch (e: any) { debugLog.push("Gemini Vision timeout") }
      }

      // TIER 2: OpenRouter Vision (Free Qwen VL Model)
      if (OPENROUTER_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST', headers: { 
              'Authorization': `Bearer ${OPENROUTER_API_KEY}`, 'Content-Type': 'application/json',
              'HTTP-Referer': 'https://coursedeep.app'
            },
            body: JSON.stringify({ 
              model: 'google/gemma-4-26b-a4b-it:free',
              messages: [{ role: 'user', content: [
                { type: 'text', text: userQuery },
                { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } }
              ]}],
            }),
          }, 15000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { 
            reply = data.choices[0].message.content; providerUsed = "OpenRouter Vision"; 
          } else { debugLog.push(`OpenRouter Vision failed: ${data.error?.message}`) }
        } catch (e: any) { debugLog.push("OpenRouter Vision timeout") }
      }

      if (!reply) throw new Error(`Vision analysis failed. Debug: ${debugLog.join(" | ")}`)

    } 
    // ==========================================
    // ROUTE 2: TEXT (7-Tier Fallback + Tavily)
    // ==========================================
    else {
      // 1. TAVILY SEARCH (Fast Mode)
      let context = "";
      if (TAVILY_API_KEY) {
        try {
          const tavilyRes = await fetchWithTimeout("https://api.tavily.com/search", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ 
              api_key: TAVILY_API_KEY, 
              query: userQuery, 
              search_depth: "basic", 
              max_results: 2 
            })
          }, 3000)
          const tavilyData = await tavilyRes.json()
          if (tavilyData.results) {
            sources = tavilyData.results;
            context = tavilyData.results.map((r: any) => `Source: ${r.title}\nURL: ${r.url}\nContent: ${r.content.substring(0, 250)}`).join("\n\n");
          }
        } catch (e) { debugLog.push("Tavily timeout") }
      }

      let systemPrompt = 'You are CourseDeep, a helpful AI assistant. Today is October 2026. Keep answers concise.';
      if (context) systemPrompt = `You are CourseDeep. Use this search context to answer concisely:\n\n${context}`;

      // TIER 1: Groq (Fastest)
      if (GROQ_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api.groq.com/openai/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${GROQ_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'openai/gpt-oss-120b', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 512 }),
          }, 3000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "Groq"; }
          else { debugLog.push("Groq failed") }
        } catch (e) { debugLog.push("Groq timeout") }
      }

      // TIER 2: DeepSeek
      if (DEEPSEEK_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api.deepseek.com/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${DEEPSEEK_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'deepseek-chat', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 512 }),
          }, 3000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "DeepSeek"; }
          else { debugLog.push("DeepSeek failed") }
        } catch (e) { debugLog.push("DeepSeek timeout") }
      }

      // TIER 3: Google Gemini (Text)
      if (GEMINI_API_KEY && !reply) {
        try {
          const geminiContents = recentMessages.map((m: any) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }));
          const res = await fetchWithTimeout(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent`, {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
            body: JSON.stringify({ systemInstruction: { parts: [{ text: systemPrompt }] }, contents: geminiContents, generationConfig: { maxOutputTokens: 512 } }),
          }, 3000)
          const data = await res.json()
          if (res.ok && data.candidates?.[0]?.content?.parts?.[0]?.text) { reply = data.candidates[0].content.parts[0].text; providerUsed = "Gemini"; }
          else { debugLog.push("Gemini failed") }
        } catch (e) { debugLog.push("Gemini timeout") }
      }

      // TIER 4: NVIDIA NIM
      if (NVIDIA_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://integrate.api.nvidia.com/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${NVIDIA_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'meta/llama-3.1-70b-instruct', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 512 }),
          }, 3000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "NVIDIA"; }
          else { debugLog.push("NVIDIA failed") }
        } catch (e) { debugLog.push("NVIDIA timeout") }
      }

      // TIER 5: SambaNova
      if (SAMBANOVA_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api.sambanova.ai/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${SAMBANOVA_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'Meta-Llama-3.3-70B-Instruct', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 512 }),
          }, 3000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "SambaNova"; }
          else { debugLog.push("SambaNova failed") }
        } catch (e) { debugLog.push("SambaNova timeout") }
      }

      // TIER 6: Cloudflare
      if (CF_ACCOUNT_ID && CF_API_TOKEN && !reply) {
        try {
          const res = await fetchWithTimeout(`https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/ai/run/@cf/meta/llama-3.1-8b-instruct`, {
            method: 'POST', headers: { 'Authorization': `Bearer ${CF_API_TOKEN}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ messages: [{ role: 'system', content: systemPrompt }, ...recentMessages] }),
          }, 3000)
          const data = await res.json()
          if (res.ok && data.result?.response) { reply = data.result.response; providerUsed = "Cloudflare"; }
          else { debugLog.push("Cloudflare failed") }
        } catch (e) { debugLog.push("Cloudflare timeout") }
      }

      // TIER 7: OpenRouter (Text)
      if (OPENROUTER_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST', headers: { 
              'Authorization': `Bearer ${OPENROUTER_API_KEY}`, 'Content-Type': 'application/json',
              'HTTP-Referer': 'https://coursedeep.app', 'X-Title': 'CourseDeep'
            },
            body: JSON.stringify({ model: 'meta-llama/llama-3.1-8b-instruct:free', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 512 }),
          }, 3000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "OpenRouter"; }
          else { debugLog.push("OpenRouter failed") }
        } catch (e) { debugLog.push("OpenRouter timeout") }
      }

      if (!reply) throw new Error(`All 7 text AI providers failed. Debug: ${debugLog.join(" | ")}`)
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