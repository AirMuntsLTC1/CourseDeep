# CourseDeep 2.0 — what changed & how to deploy

## Deploy (3 steps)
1. **Edge function** – replace `supabase/functions/coursedeep-ai/index.ts`, then:
   `supabase functions deploy coursedeep-ai --no-verify-jwt`
   (your 11 secrets stay as they are; no new secrets needed).
2. **App** – copy `app/` (lib, pubspec.yaml, test), `native/coursedeep.cpp`, `.github/workflows/build.yml` over your repo and push to `main`.
3. Optional PHP backup route: upload `backend/api-proxy.php`, set env `SUPABASE_FN_URL`, then put its URL in `kFallbackUrl` (app/lib/config.dart).

## Optional secrets (Supabase → Edge Functions → Secrets)
- `APP_SHARED_SECRET` + `kAppKey` in config.dart → blocks strangers from using your 11 keys.
- `MODEL_GROQ`, `MODEL_GEMINI` (comma list), `MODEL_DEEPSEEK`, `MODEL_MISTRAL`, `MODEL_OPENROUTER`, `MODEL_HF`, `MODEL_CF`… → change a model name without touching code.

## Fixed
- Answers now **stream** token by token (was: wait for the whole reply).
- Providers are **raced**: if the first one is slow (3.5 s) or fails, the next starts in parallel; rate-limited/dead providers are skipped for a while. Your 11 keys now really add reliability.
- Old 4-second timeout on every provider caused most "all providers failed" errors → first-token timeout is 14 s.
- Extra `image` field was sent to every text provider (some reject it) → clean payloads.
- Hugging Face used a retired endpoint → now the OpenAI-compatible router.
- App start pinged the real AI + Tavily (wasted quota) → free `ping` handled instantly.
- Tavily only runs when a question needs it; 5 sources instead of 2.
- **Source links**: `selectable: true` in the markdown widget swallowed link taps → removed. Source cards and `[1]` citations open an in-app browser (progress bar, back, reload, open in browser, copy, share, error page).
- **C++ library**: CI compiled it with the Linux host compiler, so Android could never load it. Now built with the Android NDK (arm64, 16 KB-page ready). It is really used now: request ids + whitespace squeeze of big files.
- Frame drops: images were base64-decoded on every rebuild, all chats were re-encoded on the UI thread after every message, ZIPs were unpacked on the UI thread. Now: file-based images, one debounced file per chat, work in background isolates, only the streaming bubble rebuilds.
- Files: PDF, ZIP, Word, Excel, PowerPoint, code/text, up to 6 attachments + multiple images + camera. The AI can **create files** (txt, md, csv, json, html, code, svg…); several files → one ZIP, share/save from the card.
- Stop button, regenerate, retry, scroll-to-bottom button, grouped chat history with undo-delete, dark/light saved.

## Limits (honest)
- The AI creates **text-based** files only (no real .docx/.pdf/.png output).
- Images/PDFs need Gemini (best) or a vision provider; plain-text providers can't see them.
- I could not compile Flutter here — run the GitHub Action once and send me any error line.
