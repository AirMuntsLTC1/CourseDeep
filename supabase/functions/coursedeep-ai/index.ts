import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

async function fetchWithTimeout(url: string, options: any, timeoutMs = 15000) {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  try { return await fetch(url, { ...options, signal: controller.signal }); } 
  finally { clearTimeout(id); }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { messages } = await req.json()
    if (!messages || messages.length === 0) throw new Error("No messages provided");
    
    const recentMessages = messages.slice(-4);
    const latestMsg = recentMessages[recentMessages.length - 1];
    const userQuery = latestMsg.content || "What is in this image?";
    const imageBase64 = latestMsg.image;

    const GROQ_API_KEY = Deno.env.get('GROQ_API_KEY')
    const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
    const CF_ACCOUNT_ID = Deno.env.get('CLOUDFLARE_ACCOUNT_ID')
    const CF_API_TOKEN = Deno.env.get('CLOUDFLARE_API_TOKEN')
    const OPENROUTER_API_KEY = Deno.env.get('OPENROUTER_API_KEY')
    const TAVILY_API_KEY = Deno.env.get('TAVILY_API_KEY')
    const NVIDIA_API_KEY = Deno.env.get('NVIDIA_API_KEY')
    const SAMBANOVA_API_KEY = Deno.env.get('SAMBANOVA_API_KEY')
    const DEEPSEEK_API_KEY = Deno.env.get('DEEPSEEK_API_KEY')
    const MISTRAL_API_KEY = Deno.env.get('MISTRAL_API_KEY')
    const HUGGINGFACE_API_KEY = Deno.env.get('HUGGINGFACE_API_KEY')

    let reply = ""
    let sources = []
    let providerUsed = "None"
    let debugLog = []

    // ==========================================
    // ROUTE 1: VISION (Image Analysis)
    // ==========================================
    if (imageBase64) {
      // V1: Gemini Vision
      if (GEMINI_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent`, {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
            body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: userQuery }, { inlineData: { mimeType: 'image/jpeg', data: imageBase64 } }] }], generationConfig: { maxOutputTokens: 2048 } }),
          }, 30000) // 30s for images
          const data = await res.json()
          if (res.ok && data.candidates?.[0]?.content?.parts?.[0]?.text) { reply = data.candidates[0].content.parts[0].text; providerUsed = "Gemini Vision"; }
          else { debugLog.push("Gemini Vision failed") }
        } catch (e) { debugLog.push("Gemini Vision timeout") }
      }

      // V2: Mistral Vision (Pixtral)
      if (MISTRAL_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api.mistral.ai/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${MISTRAL_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'pixtral-12b-2409', messages: [{ role: 'user', content: [{ type: 'text', text: userQuery }, { type: 'image_url', image_url: `data:image/jpeg;base64,${imageBase64}` }] }], max_tokens: 2048 }),
          }, 30000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "Mistral Vision"; }
          else { debugLog.push("Mistral Vision failed") }
        } catch (e) { debugLog.push("Mistral Vision timeout") }
      }

      // V3: Hugging Face Vision (Llama 3.2)
      if (HUGGINGFACE_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api-inference.huggingface.co/models/meta-llama/Llama-3.2-11B-Vision-Instruct', {
            method: 'POST', headers: { 'Authorization': `Bearer ${HUGGINGFACE_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ inputs: userQuery, parameters: { image: imageBase64 } }),
          }, 30000)
          const data = await res.json()
          if (res.ok && data[0]?.generated_text) { reply = data[0].generated_text; providerUsed = "HuggingFace Vision"; }
          else { debugLog.push("HuggingFace Vision failed") }
        } catch (e) { debugLog.push("HuggingFace Vision timeout") }
      }

      // V4: OpenRouter Vision (Gemma 4)
      if (OPENROUTER_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${OPENROUTER_API_KEY}`, 'Content-Type': 'application/json', 'HTTP-Referer': 'https://coursedeep.app' },
            body: JSON.stringify({ model: 'google/gemma-4-26b-a4b-it:free', messages: [{ role: 'user', content: [{ type: 'text', text: userQuery }, { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}` } }] }] }),
          }, 30000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "OpenRouter Vision"; }
          else { debugLog.push("OpenRouter Vision failed") }
        } catch (e) { debugLog.push("OpenRouter Vision timeout") }
      }

      if (!reply) throw new Error(`Vision failed. Debug: ${debugLog.join(" | ")}`)
    } 
    // ==========================================
    // ROUTE 2: TEXT (Recycling Method)
    // ==========================================
    else {
      // 1. TAVILY SEARCH
      let context = "";
      if (TAVILY_API_KEY) {
        try {
          const tavilyRes = await fetchWithTimeout("https://api.tavily.com/search", {
            method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ api_key: TAVILY_API_KEY, query: userQuery, search_depth: "basic", max_results: 2 })
          }, 5000)
          const tavilyData = await tavilyRes.json()
          if (tavilyData.results) {
            sources = tavilyData.results;
            context = tavilyData.results.map((r: any) => `Source: ${r.title}\nURL: ${r.url}\nContent: ${r.content.substring(0, 250)}`).join("\n\n");
          }
        } catch (e) { debugLog.push("Tavily timeout") }
      }

      let systemPrompt = 'You are CourseDeep, a helpful AI assistant. Today is October 2026. Keep answers concise.';
      if (context) systemPrompt = `You are CourseDeep. Use this search context to answer concisely:\n\n${context}`;

      // TEXT 1: Groq
      if (GROQ_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api.groq.com/openai/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${GROQ_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'openai/gpt-oss-120b', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 2048 }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "Groq"; }
          else { debugLog.push("Groq failed") }
        } catch (e) { debugLog.push("Groq timeout") }
      }

      // TEXT 2: DeepSeek
      if (DEEPSEEK_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api.deepseek.com/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${DEEPSEEK_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'deepseek-chat', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 2048 }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "DeepSeek"; }
          else { debugLog.push("DeepSeek failed") }
        } catch (e) { debugLog.push("DeepSeek timeout") }
      }

      // TEXT 3: Gemini
      if (GEMINI_API_KEY && !reply) {
        try {
          const geminiContents = recentMessages.map((m: any) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }));
          const res = await fetchWithTimeout(`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent`, {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
            body: JSON.stringify({ systemInstruction: { parts: [{ text: systemPrompt }] }, contents: geminiContents, generationConfig: { maxOutputTokens: 2048 } }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data.candidates?.[0]?.content?.parts?.[0]?.text) { reply = data.candidates[0].content.parts[0].text; providerUsed = "Gemini"; }
          else { debugLog.push("Gemini failed") }
        } catch (e) { debugLog.push("Gemini timeout") }
      }

      // TEXT 4: NVIDIA
      if (NVIDIA_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://integrate.api.nvidia.com/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${NVIDIA_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'meta/llama-3.1-70b-instruct', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 2048 }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "NVIDIA NIM"; }
          else { debugLog.push("NVIDIA failed") }
        } catch (e) { debugLog.push("NVIDIA timeout") }
      }

      // TEXT 5: SambaNova
      if (SAMBANOVA_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api.sambanova.ai/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${SAMBANOVA_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'Meta-Llama-3.3-70B-Instruct', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 2048 }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "SambaNova"; }
          else { debugLog.push("SambaNova failed") }
        } catch (e) { debugLog.push("SambaNova timeout") }
      }

      // TEXT 6: Mistral
      if (MISTRAL_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api.mistral.ai/v1/chat/completions', {
            method: 'POST', headers: { 'Authorization': `Bearer ${MISTRAL_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: 'open-mistral-7b', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 2048 }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "Mistral"; }
          else { debugLog.push("Mistral failed") }
        } catch (e) { debugLog.push("Mistral timeout") }
      }

      // TEXT 7: Cloudflare
      if (CF_ACCOUNT_ID && CF_API_TOKEN && !reply) {
        try {
          const res = await fetchWithTimeout(`https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/ai/run/@cf/meta/llama-3.1-8b-instruct`, {
            method: 'POST', headers: { 'Authorization': `Bearer ${CF_API_TOKEN}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ messages: [{ role: 'system', content: systemPrompt }, ...recentMessages] }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data.result?.response) { reply = data.result.response; providerUsed = "Cloudflare"; }
          else { debugLog.push("Cloudflare failed") }
        } catch (e) { debugLog.push("Cloudflare timeout") }
      }

      // TEXT 8: OpenRouter
      if (OPENROUTER_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST', headers: { 
              'Authorization': `Bearer ${OPENROUTER_API_KEY}`, 'Content-Type': 'application/json',
              'HTTP-Referer': 'https://coursedeep.app', 'X-Title': 'CourseDeep'
            },
            body: JSON.stringify({ model: 'meta-llama/llama-3.1-8b-instruct:free', messages: [{ role: 'system', content: systemPrompt }, ...recentMessages], max_tokens: 2048 }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data.choices?.[0]?.message?.content) { reply = data.choices[0].message.content; providerUsed = "OpenRouter"; }
          else { debugLog.push("OpenRouter failed") }
        } catch (e) { debugLog.push("OpenRouter timeout") }
      }

      // TEXT 9: Hugging Face
      if (HUGGINGFACE_API_KEY && !reply) {
        try {
          const res = await fetchWithTimeout('https://api-inference.huggingface.co/models/mistralai/Mistral-7B-Instruct-v0.2', {
            method: 'POST', headers: { 'Authorization': `Bearer ${HUGGINGFACE_API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ inputs: `${systemPrompt}\n\nUser: ${userQuery}\nAssistant:` }),
          }, 8000)
          const data = await res.json()
          if (res.ok && data[0]?.generated_text) { reply = data[0].generated_text; providerUsed = "HuggingFace"; }
          else { debugLog.push("HuggingFace failed") }
        } catch (e) { debugLog.push("HuggingFace timeout") }
      }

      if (!reply) throw new Error(`All 9 text AI providers failed. Debug: ${debugLog.join(" | ")}`)
    }

    return new Response(JSON.stringify({ reply, sources, provider: providerUsed }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error: any) {
    // ALWAYS return a valid JSON response, even for errors!
    return new Response(JSON.stringify({ error: error.message || "Unknown Error" }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})