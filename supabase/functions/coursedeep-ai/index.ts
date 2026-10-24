// CourseDeep AI — Supabase Edge Function (Deno)
// Streams answers (NDJSON), races up to 11 providers with hedged fallback,
// remembers which providers are rate-limited, searches the web with Tavily.
//
// Deploy:  supabase functions deploy coursedeep-ai --no-verify-jwt
// Optional secrets:  APP_SHARED_SECRET (client must send header x-app-key)
//                    MODEL_GROQ / MODEL_DEEPSEEK / MODEL_MISTRAL ... (override model ids without code changes)

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-app-key',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}
const enc = new TextEncoder()
const env = (k: string) => Deno.env.get(k) || ''

// ───────────────────────── types ─────────────────────────
interface FilePart { name: string; mime: string; data: string }
interface InMsg { role: string; content?: string; fileText?: string; images?: string[]; image?: string; files?: FilePart[] }
interface Msg { role: 'user' | 'assistant'; text: string; images: string[]; files: FilePart[] }
interface Src { title: string; url: string; snippet?: string }
type Emit = (o: Record<string, unknown>) => void

interface Provider {
  id: string; name: string; kind: 'openai' | 'gemini' | 'cf'
  url: string; key: string; model: string
  vision: boolean; pdf?: boolean; ctx: number; headers?: Record<string, string>
}
interface Cand { id: string; name: string; open: (s: AbortSignal) => AsyncGenerator<string> }

class HttpErr extends Error { constructor(public status: number, m: string) { super(m) } }

// ───────────────────────── providers ─────────────────────────
function buildProviders(): Provider[] {
  const L: Provider[] = []
  const oa = (id: string, name: string, url: string, key: string, model: string, vision: boolean, ctx = 100000, headers?: Record<string, string>) => {
    if (key) L.push({ id: id + ':' + model, name, kind: 'openai', url, key, model, vision, ctx, headers })
  }
  oa('groq', 'Groq', 'https://api.groq.com/openai/v1/chat/completions', env('GROQ_API_KEY'), env('MODEL_GROQ') || 'openai/gpt-oss-120b', false)
  // Gemini: newest first, each older model is a separate fallback entry
  if (env('GEMINI_API_KEY')) {
    const models = (env('MODEL_GEMINI') || 'gemini-3.8-flash,gemini-3.6-flash,gemini-3.1-flash-lite').split(',').map((s) => s.trim()).filter(Boolean)
    models.forEach((m, i) => L.push({
      id: 'gemini:' + m, name: i === 0 ? 'Gemini' : 'Gemini ' + m.replace('gemini-', ''), kind: 'gemini',
      url: `https://generativelanguage.googleapis.com/v1beta/models/${m}:streamGenerateContent?alt=sse`,
      key: env('GEMINI_API_KEY'), model: m, vision: true, pdf: true, ctx: 400000,
    }))
  }
  oa('deepseek', 'DeepSeek', 'https://api.deepseek.com/chat/completions', env('DEEPSEEK_API_KEY'), env('MODEL_DEEPSEEK') || 'deepseek-chat', false, 100000)
  oa('samba', 'SambaNova', 'https://api.sambanova.ai/v1/chat/completions', env('SAMBANOVA_API_KEY'), env('MODEL_SAMBANOVA') || 'Meta-Llama-3.3-70B-Instruct', false, 60000)
  oa('nvidia', 'NVIDIA NIM', 'https://integrate.api.nvidia.com/v1/chat/completions', env('NVIDIA_API_KEY'), env('MODEL_NVIDIA') || 'meta/llama-3.1-70b-instruct', false, 60000)
  oa('nvidia-v', 'NVIDIA Vision', 'https://integrate.api.nvidia.com/v1/chat/completions', env('NVIDIA_API_KEY'), env('MODEL_NVIDIA_VISION') || 'meta/llama-3.2-90b-vision-instruct', true, 40000)
  oa('mistral', 'Mistral', 'https://api.mistral.ai/v1/chat/completions', env('MISTRAL_API_KEY'), env('MODEL_MISTRAL') || 'mistral-small-latest', false, 80000)
  oa('mistral-v', 'Mistral Vision', 'https://api.mistral.ai/v1/chat/completions', env('MISTRAL_API_KEY'), env('MODEL_MISTRAL_VISION') || 'pixtral-12b-2409', true, 60000)
  oa('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1/chat/completions', env('OPENROUTER_API_KEY'), env('MODEL_OPENROUTER') || 'meta-llama/llama-3.1-8b-instruct:free', false, 40000, { 'HTTP-Referer': 'https://coursedeep.app', 'X-Title': 'CourseDeep' })
  oa('openrouter-v', 'OpenRouter Vision', 'https://openrouter.ai/api/v1/chat/completions', env('OPENROUTER_API_KEY'), env('MODEL_OPENROUTER_VISION') || 'google/gemma-4-26b-a4b-it:free', true, 40000, { 'HTTP-Referer': 'https://coursedeep.app', 'X-Title': 'CourseDeep' })
  // Hugging Face: the old api-inference.huggingface.co endpoint is retired -> OpenAI-compatible router
  oa('hf', 'Hugging Face', 'https://router.huggingface.co/v1/chat/completions', env('HUGGINGFACE_API_KEY'), env('MODEL_HF') || 'meta-llama/Llama-3.3-70B-Instruct', false, 40000)
  oa('hf-v', 'Hugging Face Vision', 'https://router.huggingface.co/v1/chat/completions', env('HUGGINGFACE_API_KEY'), env('MODEL_HF_VISION') || 'meta-llama/Llama-3.2-11B-Vision-Instruct', true, 30000)
  if (env('CLOUDFLARE_ACCOUNT_ID') && env('CLOUDFLARE_API_TOKEN')) {
    const m = env('MODEL_CF') || '@cf/meta/llama-3.1-8b-instruct'
    L.push({ id: 'cf:' + m, name: 'Cloudflare', kind: 'cf', url: `https://api.cloudflare.com/client/v4/accounts/${env('CLOUDFLARE_ACCOUNT_ID')}/ai/run/${m}`, key: env('CLOUDFLARE_API_TOKEN'), model: m, vision: false, ctx: 14000 })
  }
  return L
}

// ───────────────────────── health memory (per warm instance) ─────────────────────────
const cooldown = new Map<string, number>()
function markFail(id: string, e: unknown) {
  const s = e instanceof HttpErr ? e.status : 0
  const ms = s === 429 ? 60_000 : s === 401 || s === 403 ? 900_000 : s === 404 ? 600_000 : s === 400 ? 120_000 : 15_000
  cooldown.set(id, Date.now() + ms)
}
const healthy = (p: { id: string }) => (cooldown.get(p.id) ?? 0) < Date.now()

// ───────────────────────── message prep ─────────────────────────
function sanitize(raw: InMsg[]): Msg[] {
  const out: Msg[] = []
  for (const m of raw.slice(-12)) {
    if (!m || (m.role !== 'user' && m.role !== 'assistant')) continue
    let text = String(m.content ?? '')
    if (m.fileText) text += `\n\n${String(m.fileText)}`
    const images = [...(m.images ?? []), ...(m.image ? [m.image] : [])].filter((x) => typeof x === 'string' && x.length > 20).slice(0, 4)
    const files = (m.files ?? []).filter((f) => f && f.data && f.mime).slice(0, 3)
    if (!text.trim() && !images.length && !files.length) continue
    const last = out[out.length - 1]
    if (last && last.role === m.role) { // providers require alternating roles
      last.text += '\n\n' + text; last.images.push(...images); last.files.push(...files)
    } else out.push({ role: m.role, text, images, files })
  }
  while (out.length && out[0].role !== 'user') out.shift()
  return out
}

function fit(msgs: Msg[], maxChars: number): Msg[] {
  const res: Msg[] = []
  let left = maxChars
  for (let i = msgs.length - 1; i >= 0 && left > 500; i--) {
    const m = msgs[i]
    let t = m.text
    if (t.length > left) t = t.slice(0, left) + '\n…[truncated to fit this model]'
    left -= t.length
    res.unshift({ ...m, text: t })
  }
  while (res.length && res[0].role !== 'user') res.shift()
  return res
}

function buildSystem(hasSources: boolean, hasBinary: boolean): string {
  const date = new Date().toUTCString().slice(0, 16)
  return `You are CourseDeep, a fast, friendly and accurate AI assistant. Today is ${date}.
Reply in the same language the user writes in. Be clear and well structured; use Markdown (short headings, lists, tables, fenced code blocks with a language tag). Be concise unless the user wants depth. Say so honestly when unsure.
${hasBinary ? 'You can see attached images and documents — describe and analyse them carefully and concretely.' : ''}
${hasSources ? 'Web search results are provided below. Use them for current facts and cite them inline as [1], [2] matching the source numbers. Never invent sources.' : ''}
FILE CREATION: when the user asks you to create/export/generate a file (txt, md, csv, json, html, code, svg, yaml, a project as zip, …) output EACH file exactly like this and nothing else inside:
<<<FILE: folder/name.ext>>>
file content here
<<<END FILE>>>
Use several FILE blocks for several files (the app lets the user download them, or bundle them into a ZIP). Put a short explanation outside the blocks. Only use this for real files the user asked for. You cannot produce binary formats (png, pdf, docx) — offer a text-based alternative (svg, html, markdown, csv).`
}

// ───────────────────────── web search ─────────────────────────
const SKIP = /^(hi|hello|hey|thanks|thank you|ok|okay|yo|test|ping|good (morning|night|evening))\b/i
function wantsSearch(q: string, flag: unknown, hasFile: boolean): boolean {
  if (flag === false || hasFile) return false
  const t = q.trim()
  if (t.length < 8 || SKIP.test(t)) return false
  if (/^(write|create|generate|make|translate|rewrite|fix|debug|refactor|convert|summari[sz]e)\b/i.test(t) && !/\b(latest|today|news|current|202\d)\b/i.test(t)) return false
  return true
}

async function tavily(query: string): Promise<Src[]> {
  const key = env('TAVILY_API_KEY')
  if (!key) return []
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), 4500)
  try {
    const r = await fetch('https://api.tavily.com/search', {
      method: 'POST', signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({ api_key: key, query: query.slice(0, 380), search_depth: 'basic', max_results: 5 }),
    })
    if (!r.ok) return []
    const d = await r.json()
    return (d.results ?? []).filter((x: any) => x?.url).map((x: any) => ({ title: String(x.title || x.url).slice(0, 140), url: String(x.url), snippet: String(x.content || '').slice(0, 500) }))
  } catch { return [] } finally { clearTimeout(t) }
}

// ───────────────────────── provider streaming ─────────────────────────
async function* sse(res: Response): AsyncGenerator<string> {
  const reader = res.body!.getReader()
  const dec = new TextDecoder()
  let buf = ''
  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      buf += dec.decode(value, { stream: true })
      let i: number
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1)
        if (line.startsWith('data:')) yield line.slice(5).trim()
      }
    }
  } finally { try { reader.releaseLock() } catch { /* ignore */ } }
}

function openaiMsgs(p: Provider, system: string, msgs: Msg[]) {
  const out: any[] = [{ role: 'system', content: system }]
  msgs.forEach((m, i) => {
    const last = i === msgs.length - 1
    if (p.vision && last && m.images.length) {
      out.push({ role: m.role, content: [{ type: 'text', text: m.text || 'Describe and analyse this.' }, ...m.images.map((b) => ({ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${b}` } }))] })
    } else {
      let t = m.text
      if (last && (m.images.length || m.files.length)) t += `\n\n[Note: ${m.images.length + m.files.length} attachment(s) could not be read by this model.]`
      out.push({ role: m.role, content: t })
    }
  })
  return out
}

function geminiContents(msgs: Msg[]) {
  return msgs.map((m, i) => {
    const last = i === msgs.length - 1
    const parts: any[] = [{ text: m.text || (m.images.length || m.files.length ? 'Analyse the attachment(s).' : ' ') }]
    if (last) {
      m.images.forEach((b) => parts.push({ inlineData: { mimeType: 'image/jpeg', data: b } }))
      m.files.forEach((f) => parts.push({ inlineData: { mimeType: f.mime, data: f.data } }))
    }
    return { role: m.role === 'assistant' ? 'model' : 'user', parts }
  })
}

function candidate(p: Provider, system: string, all: Msg[]): Cand {
  return {
    id: p.id, name: p.name,
    async *open(signal: AbortSignal) {
      const msgs = fit(all, p.ctx)
      let res: Response
      if (p.kind === 'gemini') {
        res = await fetch(p.url, {
          method: 'POST', signal, headers: { 'Content-Type': 'application/json', 'x-goog-api-key': p.key },
          body: JSON.stringify({ systemInstruction: { parts: [{ text: system }] }, contents: geminiContents(msgs), generationConfig: { maxOutputTokens: 5000 } }),
        })
      } else if (p.kind === 'cf') {
        res = await fetch(p.url, {
          method: 'POST', signal, headers: { Authorization: `Bearer ${p.key}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ stream: true, max_tokens: 5000, messages: openaiMsgs(p, system, msgs) }),
        })
      } else {
        res = await fetch(p.url, {
          method: 'POST', signal, headers: { Authorization: `Bearer ${p.key}`, 'Content-Type': 'application/json', ...(p.headers ?? {}) },
          body: JSON.stringify({ model: p.model, stream: true, max_tokens: 5000, messages: openaiMsgs(p, system, msgs) }),
        })
      }
      if (!res.ok) throw new HttpErr(res.status, (await res.text().catch(() => '')).slice(0, 160))
      for await (const data of sse(res)) {
        if (data === '[DONE]') return
        let j: any
        try { j = JSON.parse(data) } catch { continue }
        let d = ''
        if (p.kind === 'gemini') d = (j.candidates?.[0]?.content?.parts ?? []).filter((x: any) => !x.thought).map((x: any) => x.text ?? '').join('')
        else if (p.kind === 'cf') d = j.response ?? ''
        else d = j.choices?.[0]?.delta?.content ?? ''
        if (typeof d === 'string' && d) yield d
      }
    },
  }
}

// Hedged race: start the best provider; if it has not produced a token after hedgeMs
// (or fails) start the next one in parallel. First token wins, the rest are aborted.
function race(cands: Cand[], hedgeMs: number, firstTokenMs: number, log: string[]) {
  return new Promise<{ name: string; first: string; gen: AsyncGenerator<string>; abort: () => void }>((resolve, reject) => {
    let next = 0, active = 0, done = false
    let timer: ReturnType<typeof setTimeout> | undefined
    const ctrls: AbortController[] = []
    const launch = () => {
      if (done) return
      if (next >= cands.length) {
        if (active === 0) { done = true; reject(new Error(log.join(' | ') || 'no provider available')) }
        return
      }
      const c = cands[next++]
      const ctrl = new AbortController(); ctrls.push(ctrl); active++
      clearTimeout(timer); timer = setTimeout(launch, hedgeMs)
      const ft = setTimeout(() => ctrl.abort(), firstTokenMs)
      ;(async () => {
        try {
          const gen = c.open(ctrl.signal)
          let r = await gen.next()
          while (!r.done && !r.value) r = await gen.next()
          clearTimeout(ft)
          if (r.done) throw new Error('empty reply')
          if (done) { ctrl.abort(); return }
          done = true; clearTimeout(timer)
          ctrls.forEach((x) => { if (x !== ctrl) x.abort() })
          resolve({ name: c.name, first: r.value, gen, abort: () => ctrl.abort() })
        } catch (e) {
          clearTimeout(ft)
          if (done) return
          markFail(c.id, e)
          const m = e instanceof HttpErr ? `HTTP ${e.status}` : ctrl.signal.aborted ? 'timeout' : String((e as Error).message).slice(0, 60)
          log.push(`${c.name}: ${m}`)
          active--; launch()
        }
      })()
    }
    launch()
  })
}

// ───────────────────────── pipeline ─────────────────────────
async function run(body: any, emit: Emit, signal?: AbortSignal) {
  const t0 = Date.now()
  const rawList: InMsg[] = Array.isArray(body.messages) ? body.messages : []
  const msgs = sanitize(rawList)
  const lastUser = [...msgs].reverse().find((m) => m.role === 'user')
  if (!lastUser) throw new Error('No message to answer.')

  const rawLast = [...rawList].reverse().find((m) => m?.role === 'user')
  const query = String(rawLast?.content ?? '').trim() || lastUser.text.slice(0, 200)
  const hasBinary = msgs.some((m) => m.images.length || m.files.length)
  const hasFileText = !!rawLast?.fileText

  // 1) web search
  let sources: Src[] = []
  if (wantsSearch(query, body.search, hasFileText || hasBinary)) {
    emit({ t: 'status', s: 'searching', text: 'Searching the web' })
    sources = await tavily(query)
    if (sources.length) {
      emit({ t: 'sources', sources: sources.map(({ title, url }) => ({ title, url })) })
      emit({ t: 'status', s: 'reading', text: `Reading ${sources.length} sources` })
    }
  }
  if (signal?.aborted) return

  // 2) system prompt (+ search context)
  let system = buildSystem(sources.length > 0, hasBinary)
  if (sources.length) system += '\n\nSEARCH RESULTS:\n' + sources.map((s, i) => `[${i + 1}] ${s.title}\n${s.url}\n${s.snippet ?? ''}`).join('\n\n')

  // 3) choose providers
  const all = buildProviders()
  const needVision = msgs.some((m) => m.images.length)
  const needPdf = msgs.some((m) => m.files.length)
  let pool: Provider[]
  if (needPdf) pool = all.filter((p) => p.pdf).concat(all.filter((p) => !p.pdf && (needVision ? p.vision : !p.vision)))
  else if (needVision) pool = all.filter((p) => p.vision)
  else pool = all.filter((p) => !p.vision || p.kind === 'gemini') // vision-only models are not used for plain text
  const ok = pool.filter(healthy)
  const cands = (ok.length ? ok : pool).map((p) => candidate(p, system, msgs))
  if (!cands.length) throw new Error('No AI provider is configured. Add API keys to Supabase secrets.')

  emit({ t: 'status', s: 'thinking', text: needVision ? 'Looking at your image' : 'Thinking' })
  const log: string[] = []
  const win = await race(cands, 3500, 14000, log)
  if (signal?.aborted) { win.abort(); return }
  emit({ t: 'status', s: 'writing', text: 'Writing' })
  emit({ t: 'delta', d: win.first })
  try {
    for await (const d of win.gen) {
      if (signal?.aborted) { win.abort(); return }
      emit({ t: 'delta', d })
    }
  } catch {
    if (!signal?.aborted) emit({ t: 'delta', d: '\n\n_…the connection to the model was interrupted._' })
  }
  emit({ t: 'done', provider: win.name, ms: Date.now() - t0 })
}

// ───────────────────────── abuse protection ─────────────────────────
const hits = new Map<string, { n: number; reset: number }>()
function limited(ip: string): boolean {
  const now = Date.now()
  const h = hits.get(ip)
  if (!h || h.reset < now) { hits.set(ip, { n: 1, reset: now + 60_000 }); return false }
  h.n++
  if (hits.size > 5000) for (const [k, v] of hits) if (v.reset < now) hits.delete(k)
  return h.n > 40
}

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } })

function friendly(m: string): string {
  return `All AI providers are busy right now. Please try again in a moment.\n(${m.slice(0, 300)})`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method === 'GET') return json({ ok: true, providers: buildProviders().length })

  const secret = env('APP_SHARED_SECRET')
  if (secret && req.headers.get('x-app-key') !== secret) return json({ error: 'Unauthorized' }, 401)
  const ip = (req.headers.get('x-forwarded-for') || 'anon').split(',')[0].trim()
  if (limited(ip)) return json({ error: 'Too many requests — please wait a minute.' }, 429)

  let body: any
  try {
    const raw = await req.text()
    if (raw.length > 14_000_000) return json({ error: 'Attachments are too large (max ~10 MB).' }, 413)
    body = JSON.parse(raw)
  } catch { return json({ error: 'Invalid request.' }, 400) }

  if (body.ping) return json({ ok: true }) // warm-up: costs no API quota

  // non-streaming mode (PHP gateway / simple clients)
  if (body.stream === false) {
    let reply = '', provider = '', sources: Src[] = []
    try {
      await run(body, (o) => {
        if (o.t === 'delta') reply += o.d
        else if (o.t === 'sources') sources = o.sources as Src[]
        else if (o.t === 'done') provider = String(o.provider)
      })
      return json({ reply, sources, provider })
    } catch (e) { return json({ error: friendly((e as Error).message) }, 502) }
  }

  const ac = new AbortController()
  const stream = new ReadableStream({
    async start(c) {
      const emit: Emit = (o) => { try { c.enqueue(enc.encode(JSON.stringify(o) + '\n')) } catch { ac.abort() } }
      try { await run(body, emit, ac.signal) } catch (e) { emit({ t: 'error', message: friendly((e as Error).message) }) }
      try { c.close() } catch { /* already closed */ }
    },
    cancel() { ac.abort() },
  })
  return new Response(stream, { headers: { ...CORS, 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no' } })
})
