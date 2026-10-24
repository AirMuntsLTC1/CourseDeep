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
    const userQuery = messages[messages.length - 1].content

    // 1. Ask the model if it needs to search
    const decisionRes = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${GROQ_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'openai/gpt-oss-120b',
        messages: [
          { role: 'system', content: 'Decide if this query needs real-time web search. Reply ONLY with "SEARCH: <query>" or "DIRECT".' },
          { role: 'user', content: userQuery }
        ],
        temperature: 0,
      }),
    })
    const decisionData = await decisionRes.json()
    const decision = decisionData.choices[0].message.content

    // 2. Perform search if needed
    let context = ""
    if (decision.startsWith("SEARCH:")) {
      const searchQuery = decision.replace("SEARCH:", "").trim()
      try {
        const searchRes = await tvly.search(searchQuery, { searchDepth: "basic" })
        context = searchRes.results.map((r: any) => `- ${r.title}: ${r.content}`).join("\n\n")
      } catch (e) {
        console.error("Tavily search failed:", e)
      }
    }

    // 3. Generate final answer
    const finalMessages = context
      ? [{ role: 'system', content: `You are CourseDeep. Use this web search context to answer:\n\n${context}` }, ...messages]
      : [{ role: 'system', content: 'You are CourseDeep, a helpful AI assistant.' }, ...messages]

    const finalRes = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${GROQ_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'openai/gpt-oss-120b', messages: finalMessages }),
    })
    const finalData = await finalRes.json()
    const reply = finalData.choices[0].message.content

    return new Response(JSON.stringify({ reply }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message || String(error) }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})