
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

class HttpErr extends Error { constructor(public status: number, m: string, public retryMs = 0) { super(m) } }

// ───────────────────────── providers ─────────────────────────
function buildProviders(): Provider[] {
  const L: Provider[] = []
  const oa = (id: string, name: string, url: string, key: string, model: string, vision: boolean, ctx = 100000, headers?: Record<string, string>) => {
    if (key) L.push({ id: id + ':' + model, name, kind: 'openai', url, key, model, vision, ctx, headers })
  }
  // Groq: each model has its own rate limit, so every one is a separate fallback slot
  ;(env('MODEL_GROQ') || 'openai/gpt-oss-120b,llama-3.3-70b-versatile,openai/gpt-oss-20b').split(',').map((x) => x.trim()).filter(Boolean).forEach((m, i) =>
    oa('groq', i === 0 ? 'Groq' : 'Groq ' + m.split('/').pop(), 'https://api.groq.com/openai/v1/chat/completions', env('GROQ_API_KEY'), m, false))
  // Gemini: newest first, each older model is a separate fallback entry
  if (env('GEMINI_API_KEY')) {
    const models = (env('MODEL_GEMINI') || 'gemini-3.8-flash,gemini-3.6-flash,gemini-3.1-flash-lite,gemini-2.5-flash,gemini-2.5-flash-lite').split(',').map((s) => s.trim()).filter(Boolean)
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
const cooldown = new Map<string, number>() // temporarily out (quota / rate limit / error)
const dead = new Map<string, number>() // key or model rejected (401/403/404): skip for a long time
function markFail(id: string, e: unknown) {
  const s = e instanceof HttpErr ? e.status : 0
  const retry = e instanceof HttpErr ? e.retryMs : 0
  if (s === 401 || s === 403 || s === 404) dead.set(id, Date.now() + 900_000)
  // 429 = rate/quota limit, 402 = no credit. Respect the provider's own Retry-After when it sends one.
  const ms = s === 429 ? Math.min(Math.max(retry, 45_000), 6 * 3600_000)
    : s === 402 ? Math.min(Math.max(retry, 600_000), 6 * 3600_000)
    : s === 401 || s === 403 ? 900_000 : s === 404 ? 600_000 : s === 400 || s === 413 ? 120_000 : 15_000
  cooldown.set(id, Date.now() + ms)
}
const healthy = (p: { id: string }) => (cooldown.get(p.id) ?? 0) < Date.now()
const alive = (p: { id: string }) => (dead.get(p.id) ?? 0) < Date.now()
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

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

function buildSystem(hasSources: boolean, hasBinary: boolean, lang = '', think = false): string {
  const date = new Date().toUTCString().slice(0, 16)
  return `You are CourseDeep, a fast, friendly and accurate AI assistant. Today is ${date}.
${lang && lang !== 'English' ? `Always reply in ${lang} unless the user clearly writes in another language.` : 'Reply in the same language the user writes in.'}\n${think ? 'DEEP THINK MODE: reason carefully step by step before answering. Start with a short section titled "**Thinking**" (max 8 lines) where you plan and double-check, then a line with --- and the final answer.' : ''} Be clear and well structured; use Markdown (short headings, lists, tables, fenced code blocks with a language tag). Be concise unless the user wants depth. Say so honestly when unsure.
${hasBinary ? 'You can see attached images and documents — describe and analyse them carefully and concretely.' : ''}
${hasSources ? 'Web search results are provided below. Use them for current facts and cite them inline as [1], [2] matching the source numbers. Never invent sources.' : ''}
FILE CREATION: when the user asks you to create/export/generate a file (txt, md, csv, json, html, code, svg, yaml, a project as zip, …) output EACH file exactly like this and nothing else inside:
<<<FILE: folder/name.ext>>>
file content here
<<<END FILE>>>
Use several FILE blocks for several files (the app lets the user download them, or bundle them into a ZIP). Put a short explanation outside the blocks. Only use this for real files the user asked for. You cannot write binary formats (pdf, docx) yourself — offer a text-based alternative (html, markdown, csv). Pictures, photos, logos and artwork are created by the app's built-in image generator when the user asks to generate/draw/create an image, so never answer such requests with SVG code unless the user explicitly asks for SVG or vector code. You can read web pages: when the user pastes a link, its text is provided to you as a numbered source.`
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
      if (!res.ok) {
        const ra = Number(res.headers.get('retry-after'))
        throw new HttpErr(res.status, (await res.text().catch(() => '')).slice(0, 160), Number.isFinite(ra) && ra > 0 ? ra * 1000 : 0)
      }
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
function race(cands: Cand[], hedgeMs: number, firstTokenMs: number, log: string[], onFail?: (name: string) => void) {
  return new Promise<{ id: string; name: string; first: string; gen: AsyncGenerator<string>; abort: () => void }>((resolve, reject) => {
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
          resolve({ id: c.id, name: c.name, first: r.value, gen, abort: () => ctrl.abort() })
        } catch (e) {
          clearTimeout(ft)
          if (done) return
          markFail(c.id, e)
          const m = e instanceof HttpErr ? `HTTP ${e.status}` : ctrl.signal.aborted ? 'timeout' : String((e as Error).message).slice(0, 60)
          log.push(`${c.name}: ${m}`)
          onFail?.(c.name)
          active--; launch()
        }
      })()
    }
    launch()
  })
}


// ───────────────────────── image generation (real PNG/JPEG, with automatic recycling) ─────────────────────────
// Order: Gemini image -> Cloudflare FLUX -> Hugging Face FLUX -> Pollinations FLUX.
// If one is out of quota / errors, the next one starts immediately (same recycling idea as the text AIs).
const IMG_VERB = '(?:generate|create|make|draw|paint|design|render|produce|give me|show me|imagine|illustrate|sketch)'
const IMG_NOUN = '(?:image|images|picture|pictures|photo|photos|illustration|artwork|wallpaper|portrait|poster|logo|banner|thumbnail|avatar|icon|painting|drawing|render|cover art|background)'
const RE_IMG1 = new RegExp(`\\b${IMG_VERB}\\b[^.\\n]{0,40}\\b${IMG_NOUN}\\b`, 'i')
const RE_IMG2 = /^\s*(draw|paint|sketch|illustrate)\b/i
const RE_IMG_TEXT = /\b(svg|vector code|html|css|canvas|code|script|python|javascript|react|flutter|explain|how to|tutorial|prompt for)\b/i
function wantsImage(t: string): boolean {
  const q = t.trim()
  if (q.length < 6 || q.length > 900) return false
  if (RE_IMG_TEXT.test(q)) return false
  return RE_IMG1.test(q) || RE_IMG2.test(q)
}

function polishPrompt(raw: string): string {
  let t = raw.trim().replace(/\s+/g, ' ')
  t = t.replace(/^(can|could|would|will) you (please )?/i, '').replace(/^please\s+/i, '')
  t = t.replace(new RegExp(`^${IMG_VERB}\\s+(me\\s+)?(an?\\s+|the\\s+)?(${IMG_NOUN})?\\s*(of|for|with|about|that|showing)?\\s*`, 'i'), (m) => m.length < t.length ? '' : m)
  if (t.length < 3) t = raw
  const logo = /\blogo|icon|emblem|brand/i.test(raw)
  const style = logo
    ? 'professional modern logo design, clean minimal shapes, balanced composition, centered, crisp edges, on a plain background, high resolution'
    : 'ultra detailed, high quality, professional, sharp focus, cinematic lighting, rich colors, 4k'
  return `${t}, ${style}`.slice(0, 1500)
}

function toBase64(buf: Uint8Array): string {
  let s = ''
  const CH = 0x8000
  for (let i = 0; i < buf.length; i += CH) s += String.fromCharCode(...buf.subarray(i, i + CH))
  return btoa(s)
}

interface Img { data: string; mime: string }
interface ImgProv { id: string; name: string; run: (prompt: string, signal: AbortSignal) => Promise<Img> }

async function okImg(res: Response): Promise<Img> {
  if (!res.ok) {
    const ra = Number(res.headers.get('retry-after'))
    throw new HttpErr(res.status, (await res.text().catch(() => '')).slice(0, 160), Number.isFinite(ra) && ra > 0 ? ra * 1000 : 0)
  }
  const mime = (res.headers.get('content-type') || '').split(';')[0].trim()
  if (!mime.startsWith('image/')) throw new HttpErr(502, 'not an image: ' + mime)
  const bytes = new Uint8Array(await res.arrayBuffer())
  if (bytes.length < 2000) throw new HttpErr(502, 'image too small')
  return { data: toBase64(bytes), mime }
}

function imageProviders(): ImgProv[] {
  const L: ImgProv[] = []
  if (env('GEMINI_API_KEY')) {
    const m = env('MODEL_GEMINI_IMAGE') || 'gemini-2.5-flash-image'
    L.push({
      id: 'img-gemini:' + m, name: 'Gemini Image',
      run: async (prompt, signal) => {
        const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent`, {
          method: 'POST', signal, headers: { 'Content-Type': 'application/json', 'x-goog-api-key': env('GEMINI_API_KEY') },
          body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], generationConfig: { responseModalities: ['TEXT', 'IMAGE'] } }),
        })
        if (!res.ok) throw new HttpErr(res.status, (await res.text().catch(() => '')).slice(0, 160))
        const j = await res.json()
        const part = (j.candidates?.[0]?.content?.parts ?? []).find((x: any) => x.inlineData?.data || x.inline_data?.data)
        const d = part?.inlineData ?? part?.inline_data
        if (!d?.data) throw new HttpErr(502, 'no image in reply')
        return { data: d.data, mime: d.mimeType || d.mime_type || 'image/png' }
      },
    })
  }
  if (env('CLOUDFLARE_ACCOUNT_ID') && env('CLOUDFLARE_API_TOKEN')) {
    const m = env('MODEL_CF_IMAGE') || '@cf/black-forest-labs/flux-1-schnell'
    L.push({
      id: 'img-cf:' + m, name: 'Cloudflare FLUX',
      run: async (prompt, signal) => {
        const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${env('CLOUDFLARE_ACCOUNT_ID')}/ai/run/${m}`, {
          method: 'POST', signal, headers: { Authorization: `Bearer ${env('CLOUDFLARE_API_TOKEN')}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ prompt: prompt.slice(0, 2000), steps: 8 }),
        })
        if (!res.ok) throw new HttpErr(res.status, (await res.text().catch(() => '')).slice(0, 160))
        const j = await res.json()
        const b64 = j?.result?.image
        if (!b64) throw new HttpErr(502, 'no image in reply')
        return { data: b64, mime: 'image/jpeg' }
      },
    })
  }
  if (env('HUGGINGFACE_API_KEY')) {
    const m = env('MODEL_HF_IMAGE') || 'black-forest-labs/FLUX.1-schnell'
    L.push({
      id: 'img-hf:' + m, name: 'Hugging Face FLUX',
      run: async (prompt, signal) =>
        okImg(await fetch(`https://router.huggingface.co/hf-inference/models/${m}`, {
          method: 'POST', signal, headers: { Authorization: `Bearer ${env('HUGGINGFACE_API_KEY')}`, 'Content-Type': 'application/json', Accept: 'image/png' },
          body: JSON.stringify({ inputs: prompt }),
        })),
    })
  }
  // keyless last resort
  L.push({
    id: 'img-pollinations', name: 'Pollinations FLUX',
    run: async (prompt, signal) =>
      okImg(await fetch(`https://image.pollinations.ai/prompt/${encodeURIComponent(prompt)}?width=1024&height=1024&model=flux&nologo=true&enhance=true&seed=${Math.floor(Math.random() * 1e6)}`, { signal })),
  })
  return L
}

async function makeImage(userText: string, emit: Emit, signal?: AbortSignal): Promise<{ img: Img; by: string; failed: number }> {
  const prompt = polishPrompt(userText)
  const all = imageProviders().filter(alive)
  const order = [...all.filter(healthy), ...all.filter((p) => !healthy(p))]
  let failed = 0
  const log: string[] = []
  for (const p of order) {
    if (signal?.aborted) throw new Error('cancelled')
    emit({ t: 'status', s: 'image', text: failed ? `Switching image AI - trying ${p.name}` : `Creating your image with ${p.name}` })
    const ac = new AbortController()
    const timer = setTimeout(() => ac.abort(), 38_000)
    try {
      const img = await p.run(prompt, ac.signal)
      clearTimeout(timer)
      return { img, by: p.name, failed }
    } catch (e) {
      clearTimeout(timer)
      markFail(p.id, e)
      failed++
      log.push(`${p.name}: ${e instanceof HttpErr ? 'HTTP ' + e.status : ac.signal.aborted ? 'timeout' : String((e as Error).message).slice(0, 50)}`)
    }
  }
  throw new Error(log.join(' | ') || 'no image provider available')
}

// ───────────────────────── reading links + extra search ─────────────────────────
const PRIVATE_HOST = /^(localhost|0\.0\.0\.0|127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|\[?::1|.*\.internal$|.*\.local$)/i
async function readPage(url: string): Promise<Src | null> {
  try {
    const u = new URL(url)
    if (!/^https?:$/.test(u.protocol) || PRIVATE_HOST.test(u.hostname)) return null
    const ctrl = new AbortController()
    const t = setTimeout(() => ctrl.abort(), 6000)
    try {
      const r = await fetch(u.toString(), { signal: ctrl.signal, redirect: 'follow', headers: { 'User-Agent': 'Mozilla/5.0 (compatible; CourseDeepBot/1.0)', Accept: 'text/html,text/plain' } })
      if (!r.ok) return null
      const ct = r.headers.get('content-type') || ''
      if (!/text\/|json|xml/.test(ct)) return null
      const html = (await r.text()).slice(0, 400_000)
      const title = (html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || u.hostname).replace(/\s+/g, ' ').trim().slice(0, 140)
      const text = html.replace(/<(script|style|noscript|svg|head)[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ')
        .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim()
      return { title, url: u.toString(), snippet: text.slice(0, 2500) }
    } finally { clearTimeout(t) }
  } catch { return null }
}

// Fallback web search (no key) when Tavily is missing, out of quota or returns nothing.
async function ddg(query: string): Promise<Src[]> {
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), 5000)
  try {
    const r = await fetch('https://html.duckduckgo.com/html/?q=' + encodeURIComponent(query.slice(0, 300)), {
      signal: ctrl.signal, headers: { 'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130 Mobile Safari/537.36' },
    })
    if (!r.ok) return []
    const html = await r.text()
    const out: Src[] = []
    const re = /<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>[\s\S]*?<a[^>]+class="result__snippet"[^>]*>([\s\S]*?)<\/a>/g
    let m: RegExpExecArray | null
    while ((m = re.exec(html)) && out.length < 5) {
      let href = m[1].replace(/&amp;/g, '&')
      const q = href.match(/[?&]uddg=([^&]+)/)
      if (q) href = decodeURIComponent(q[1])
      if (href.startsWith('//')) href = 'https:' + href
      if (!/^https?:\/\//.test(href)) continue
      const clean = (x: string) => x.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&#x27;|&#39;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim()
      out.push({ title: clean(m[2]).slice(0, 140) || href, url: href, snippet: clean(m[3]).slice(0, 500) })
    }
    return out
  } catch { return [] } finally { clearTimeout(t) }
}

// ───────────────────────── pipeline ─────────────────────────
async function run(body: any, emit: Emit, signal?: AbortSignal) {
  const t0 = Date.now()
  const rawList: InMsg[] = Array.isArray(body.messages) ? body.messages : []
  const msgs = sanitize(rawList)
  
  // IMAGE GENERATION: real raster image (JPEG/PNG) sent as one event; the app saves it and shows a Download button.
  const lastUserMsg = msgs.filter((m) => m.role === 'user').pop()
  if (lastUserMsg && !lastUserMsg.images.length && !lastUserMsg.files.length && wantsImage(String(([...rawList].reverse().find((m) => m?.role === 'user')?.content) ?? lastUserMsg.text))) {
    const userText = String(([...rawList].reverse().find((m) => m?.role === 'user')?.content) ?? lastUserMsg.text)
    emit({ t: 'status', s: 'image', text: 'Creating your image' })
    try {
      const { img, by, failed } = await makeImage(userText, emit, signal)
      const ext = img.mime.includes('png') ? 'png' : img.mime.includes('webp') ? 'webp' : 'jpg'
      emit({ t: 'image', name: `coursedeep-${Date.now()}.${ext}`, mime: img.mime, data: img.data })
      emit({ t: 'delta', d: 'Here is your image. Tap it to view full screen, or press **Download image** to save it to your Downloads folder. Tell me what to change and I will make a new version.' })
      emit({ t: 'done', provider: failed ? `${by} (auto-switched)` : by, ms: Date.now() - t0 })
    } catch (e) {
      if (signal?.aborted) return
      emit({ t: 'error', message: 'All image generators are busy right now. Please try again in a minute.\n(' + String((e as Error).message).slice(0, 200) + ')' })
    }
    return
  }
  const lastUser = [...msgs].reverse().find((m) => m.role === 'user')
  if (!lastUser) throw new Error('No message to answer.')

  const rawLast = [...rawList].reverse().find((m) => m?.role === 'user')
  const query = String(rawLast?.content ?? '').trim() || lastUser.text.slice(0, 200)
  const hasBinary = msgs.some((m) => m.images.length || m.files.length)
  const hasFileText = !!rawLast?.fileText

  // 0) links in the message are opened and read (Chrome-like access to any public page)
  let sources: Src[] = []
  const urls = [...new Set((query.match(/https?:\/\/[^\s<>")\]]+/g) ?? []).map((u) => u.replace(/[.,;:!?]+$/, '')))].slice(0, 3)
  if (urls.length && body.search !== false) {
    emit({ t: 'status', s: 'reading', text: urls.length > 1 ? 'Opening your links' : 'Opening your link' })
    const pages = (await Promise.all(urls.map(readPage))).filter((x): x is Src => !!x)
    sources.push(...pages)
  }

  // 1) web search
  if (wantsSearch(query, body.search, hasFileText || hasBinary)) {
    emit({ t: 'status', s: 'searching', text: 'Searching the web' })
    let found = await tavily(query)
    if (!found.length) found = await ddg(query)
    sources.push(...found)
  }
  if (sources.length) {
    emit({ t: 'sources', sources: sources.map(({ title, url }) => ({ title, url })) })
    emit({ t: 'status', s: 'reading', text: `Reading ${sources.length} sources` })
  }
  if (signal?.aborted) return

  // 2) system prompt (+ project + search context)
  let system = buildSystem(sources.length > 0, hasBinary, String(body.lang || '').slice(0, 24), body.think === true)
  const projectContext = String(body.projectContext ?? '').trim().slice(0, 8000)
  if (projectContext) system = projectContext + '\n\n' + system
  if (sources.length) system += '\n\nSEARCH RESULTS:\n' + sources.map((s, i) => `[${i + 1}] ${s.title}\n${s.url}\n${s.snippet ?? ''}`).join('\n\n')

  // 3) choose providers
  const all = buildProviders()
  const needVision = msgs.some((m) => m.images.length)
  const needPdf = msgs.some((m) => m.files.length)
  let pool: Provider[]
  if (needPdf) pool = all.filter((p) => p.pdf).concat(all.filter((p) => !p.pdf && (needVision ? p.vision : !p.vision)))
  else if (needVision) pool = all.filter((p) => p.vision)
  else pool = all.filter((p) => !p.vision || p.kind === 'gemini') // vision-only models are not used for plain text
  const usable = pool.filter(alive)
  if (!usable.length) throw new Error('No AI provider is configured. Add API keys to Supabase secrets.')
  const fresh = usable.filter(healthy)

  emit({ t: 'status', s: 'thinking', text: needVision ? 'Looking at your image' : 'Thinking' })
  const log: string[] = []
  let failed = 0
  // A fails (quota / limit / error) -> B starts INSTANTLY -> C ... A slow provider (8 s without a
  // token) is also overtaken. Providers that are out of quota are skipped for the time they ask for.
  const onFail = (name: string) => { failed++; emit({ t: 'status', s: 'switching', text: `${name} is unavailable — switching AI` }) }

  let win
  try {
    win = await race((fresh.length ? fresh : usable).map((p) => candidate(p, system, msgs)), 8000, 14000, log, onFail)
  } catch (e) {
    if (signal?.aborted) return
    // RECYCLE: every provider failed once. Wait a moment and go around again (limits reset, hiccups pass).
    emit({ t: 'status', s: 'retry', text: 'All AIs are busy — trying again' })
    await sleep(1500)
    const again = pool.filter(alive)
    if (!again.length) throw e
    win = await race(again.map((p) => candidate(p, system, msgs)), 8000, 20000, log, onFail)
  }
  if (signal?.aborted) { win.abort(); return }
  emit({ t: 'status', s: 'writing', text: 'Writing' })
  emit({ t: 'delta', d: win.first })
  let written = win.first
  let winId = win.id, winName = win.name, gen = win.gen, abort = win.abort

  // If the model dies in the MIDDLE of an answer, the next AI continues exactly where it stopped.
  const tried = new Set<string>()
  while (true) {
    try {
      for await (const d of gen) {
        if (signal?.aborted) { abort(); return }
        written += d
        emit({ t: 'delta', d })
      }
      break
    } catch (e) {
      if (signal?.aborted) return
      markFail(winId, e)
      tried.add(winId)
      const next = pool.filter((p) => alive(p) && !tried.has(p.id) && !(p.vision && p.kind !== 'gemini'))
      let resumed = false
      for (const p of next) {
        try {
          emit({ t: 'status', s: 'switching', text: `Connection lost — continuing with ${p.name}` })
          const cont: Msg[] = [...msgs,
            { role: 'assistant', text: written, images: [], files: [] },
            { role: 'user', text: 'Continue your previous answer exactly where it stopped. Do not repeat anything and do not add an introduction.', images: [], files: [] }]
          const c = candidate(p, system, cont)
          const ctrl = new AbortController()
          const g = c.open(ctrl.signal)
          let r = await g.next()
          while (!r.done && !r.value) r = await g.next()
          if (r.done) throw new Error('empty reply')
          emit({ t: 'delta', d: r.value }); written += r.value
          gen = g; abort = () => ctrl.abort(); winId = p.id; winName = p.name
          resumed = true
          break
        } catch (e2) { markFail(p.id, e2); tried.add(p.id) }
      }
      if (!resumed) { emit({ t: 'delta', d: '\n\n_…the connection to the AI was interrupted. Tap regenerate to continue._' }); break }
    }
  }
  emit({ t: 'done', provider: failed || tried.size ? `${winName} (auto-switched)` : winName, ms: Date.now() - t0 })
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
    const images: unknown[] = []
    try {
      await run(body, (o) => {
        if (o.t === 'delta') reply += o.d
        else if (o.t === 'sources') sources = o.sources as Src[]
        else if (o.t === 'image') images.push({ name: o.name, data: o.data })
        else if (o.t === 'done') provider = String(o.provider)
      })
      return json({ reply, sources, provider, images })
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
