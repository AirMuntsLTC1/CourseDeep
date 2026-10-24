import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { tavily } from "npm:@tavily/core"

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

    if (!GROQ_API_KEY) throw new Error("GROQ_API_KEY is not set")
    if (!TAVILY_API_KEY) throw new Error("TAVILY_API_KEY is not set")

    const tvly = tavily({ apiKey: TAVILY_API_KEY })
    const recentMessages = messages.slice(-10);
    const userQuery = recentMessages[recentMessages.length - 1].content

    // 1. Ask the model if it needs to search
    const decisionRes = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${GROQ_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'openai/gpt-oss-120b',
        messages: [
          { role: 'system', content: 'Analyze the user query. If it asks for current events, news, weather, or real-time data, reply exactly with: SEARCH: <optimized search query>. Otherwise, reply exactly with: DIRECT.' },
          { role: 'user', content: userQuery }
        ],
        temperature: 0,
        max_tokens: 50
      }),
    })
    
    const decisionData = await decisionRes.json()
    if (!decisionData.choices || !decisionData.choices[0] || !decisionData.choices[0].message) {
        throw new Error("Failed to get decision from AI")
    }
    
    const decision = decisionData.choices[0].message.content || ""
    let context = ""
    let sources = []

    // 2. Perform search if needed (Using robust parsing)
    const decisionUpper = decision.toUpperCase();
    if (decisionUpper.includes("SEARCH:")) {
      const searchQuery = decision.substring(decisionUpper.indexOf("SEARCH:") + 7).replace(/["'*]/g, '').trim();
      if (searchQuery.length > 0) {
        try {
          const searchRes = await tvly.search(searchQuery, { searchDepth: "basic" })
          sources = searchRes.results
          context = searchRes.results.map((r: any) => `- ${r.title}: ${r.content.substring(0, 300)}...`).join("\n\n")
        } catch (e) {
          console.error("Tavily search failed:", e)
        }
      }
    }

    // 3. Generate final answer (Forcing the AI to use the context)
    let systemPrompt = 'You are CourseDeep, a helpful AI assistant.';
    if (context) {
      systemPrompt = `You are CourseDeep, a helpful AI assistant. You have been provided with the following real-time web search results. Use them to answer the user's question accurately. DO NOT say you don't have access to real-time information because you DO have the search results below.\n\nSearch Results:\n${context}`;
    }

    const finalMessages = [
        { role: 'system', content: systemPrompt }, 
        ...recentMessages
    ];

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
    if (!finalData.choices || !finalData.choices[0] || !finalData.choices[0].message) {
        throw new Error("Failed to get final response from AI")
    }

    const reply = finalData.choices[0].message.content

    return new Response(JSON.stringify({ reply, sources }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error: any) {
    console.error("Function error:", error);
    return new Response(JSON.stringify({ error: error.message || String(error) }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})