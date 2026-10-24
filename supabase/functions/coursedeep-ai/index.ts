import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { messages } = await req.json()
    const GROQ_API_KEY = Deno.env.get('GROQ_API_KEY')
    const TAVILY_API_KEY = Deno.env.get('TAVILY_API_KEY')

    if (!GROQ_API_KEY) throw new Error("GROQ_API_KEY is missing")
    if (!TAVILY_API_KEY) throw new Error("TAVILY_API_KEY is missing")

    const recentMessages = messages.slice(-10);
    const userQuery = recentMessages[recentMessages.length - 1].content

    let context = ""
    let sources = []
    let debugError = ""

    // 1. Direct Fetch to Tavily with strict error checking
    try {
      const tavilyRes = await fetch("https://api.tavily.com/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          api_key: TAVILY_API_KEY,
          query: userQuery,
          search_depth: "basic",
          max_results: 3
        })
      })

      if (!tavilyRes.ok) {
        const errorText = await tavilyRes.text();
        throw new Error(`Tavily HTTP ${tavilyRes.status}: ${errorText}`);
      }

      const tavilyData = await tavilyRes.json()
      
      if (tavilyData.results && tavilyData.results.length > 0) {
        sources = tavilyData.results
        context = tavilyData.results.map((r: any) => `Source: ${r.title}\nURL: ${r.url}\nContent: ${r.content.substring(0, 500)}`).join("\n\n")
      } else {
        throw new Error("Tavily returned 0 results");
      }
    } catch (e: any) {
      debugError = e.message;
      console.error("Tavily Error:", e.message);
    }

    // 2. Force the AI to read the context
    let systemPrompt = 'You are CourseDeep, a helpful AI assistant. Today is October 2026.';
    if (context) {
      systemPrompt = `You are CourseDeep. You MUST use the following real-time web search results to answer the user's question. DO NOT say you don't have access to real-time information. Today is October 2026.\n\nSearch Results:\n${context}`;
    }

    const finalMessages = [{ role: 'system', content: systemPrompt }, ...recentMessages];

    const finalRes = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${GROQ_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ 
        model: 'openai/gpt-oss-120b', 
        messages: finalMessages,
        max_tokens: 2048 
      }),
    })
    
    const finalData = await finalRes.json()
    if (!finalData.choices || !finalData.choices[0]) {
        throw new Error(`Groq Error: ${JSON.stringify(finalData)}`)
    }

    const reply = finalData.choices[0].message.content

    // Return debugError so you can see it in Termux
    return new Response(JSON.stringify({ reply, sources, debugError }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})