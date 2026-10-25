# CourseDeep 2.3 - what changed

## Deploy (in this order)
1. Unzip the update over your repo (Termux: `unzip -o CourseDeep_update_2.3.zip -d ~/CourseDeep`).
2. Edge function (image generator, link reading, search fallback):
   `supabase functions deploy coursedeep-ai --no-verify-jwt`
3. `git add . && git commit -m "2.3" && git push` -> GitHub Actions builds the APK and publishes release `v2.3.0.7`.
4. Install that APK ONCE by hand. From now on every older app shows the blocking "Update required" dialog.
   To ship a future update: raise `version:` in `app/pubspec.yaml` (e.g. `2.4.0+8`) and push.

## What was fixed
- **Downloads**: files/images/ZIPs go straight into the phone's Downloads folder (Android MediaStore, written by the build into MainActivity.kt). No share sheet, no Bluetooth. iOS has no public Downloads: files land in the app's Documents folder (add `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` = YES to ios/Runner/Info.plist to see them in the Files app).
- **Image generation**: "generate/draw/create an image/logo/poster..." now returns a real JPEG/PNG (not SVG, not a ZIP), shown in the chat with a Download image button. Recycling order: Gemini Image -> Cloudflare FLUX -> Hugging Face FLUX -> Pollinations FLUX. Ask for "svg" or "code" and you still get text/SVG.
- **Forced update dialog**: reads the latest GitHub release, cannot be dismissed, Upgrade downloads the APK inside the dialog with a % bar, then opens Android's installer. (The old dialog used a context above MaterialApp, so it could never show.)
- **Build blockers fixed**: `main.dart` still called `ChatPage(isDark:, onToggleTheme:)` and ignored AppSettings; now consistent with chat_page / settings.
- **Home screen**: greeting, capability cards (image, search, files, study) and prompt chips.
- **Frame drops / flicker**: answer parsing cached per message, 100 ms refresh, auto-scroll only stops when YOU scroll up, bigger list cache.
- **Search / "Chrome access"**: Tavily -> DuckDuckGo fallback, and any link you paste is opened and read by the server.
- **AI recycling**: Groq (3 models) -> Gemini (5) -> DeepSeek -> SambaNova -> NVIDIA -> Mistral -> OpenRouter -> Hugging Face -> Cloudflare; a provider that hits its limit is skipped for the time it reports.

## Honest limits
- I could not compile Flutter here. If the GitHub Action shows an error, send me the error line.
- Provider cooldowns live in memory of the running edge instance (reset on cold start).
- C++ (`native/coursedeep.cpp`) is connected through FFI (hashing, text squeeze, token estimate); the PHP gateway only works if you set `kFallbackUrl` in `app/lib/config.dart`.

---

# CourseDeep 2.1 — what changed & how to deploy

## Deploy (do these in order)
1. **Database** – run the new migration (adds the `feedback` table used by Settings → Help & feedback):
   `supabase db push`
2. **Edge functions** (login was broken because of the OLD deployed function):
   `supabase functions deploy email-code --no-verify-jwt`
   `supabase functions deploy coursedeep-ai --no-verify-jwt`
   (`SUPABASE_ANON_KEY` is already in your secrets list; no new secrets needed.)
3. **App** – copy this whole folder over your repo and push to `main`. GitHub Actions builds the APK.
   **Uninstall the old APK first**, then install the new one (the old build showed an error text that no longer exists in the code, so it is out of date).

## Login fixed
- `otp_expired`: the app redeemed the Supabase token with the wrong type (new users get a `signup` token, not `magiclink`). Now the **server** redeems it and sends back a ready session; the app only calls `setSession`.
- "server did not return a sign-in token": same root cause, removed.
- Code is saved before the email is sent; email failures now give a clear message.
- New login screen: same orb/gradient/dark theme as the chat, 6-box code input, paste button, auto-verify, resend timer.

## Logo
- Drawn in code: `app/lib/widgets/logo.dart` (in-app) and `branding/generate_icons.py` (Android launcher icon, adaptive + round icon, splash). CI copies `branding/android-res` over the generated Android project, so every Flutter icon is replaced.

## Settings (all working now)
Theme (auto/light/dark), live font size, web-search default, DeepThink default, answer language (really sent to the AI), haptics, clear chats (also refreshes the chat screen), check for updates (GitHub releases), feedback (saved in Supabase), log out (closes Settings first).

## Frame drops
- Streaming answers were re-parsing the whole markdown 25x/second → now only the last block is parsed; finished blocks are cached; UI refresh 80 ms; per-message repaint boundaries.
- Big animated blurred shadows (50–70 px) on the logo orb → replaced by compositor-only transforms on cached layers.
- Typing dots use one painter instead of rebuilding widgets.
- Start-up: Supabase and settings load in parallel.

## DeepSeek-style features
DeepThink toggle with a foldable "Thought process" block, Search toggle, greeting screen, history drawer, copy / regenerate / more actions.

## Honest limits
- I could not compile Flutter here. Push, and if the GitHub Action shows an error line, send it to me.
- "Real AI" quality depends on your providers (Groq, Gemini, DeepSeek …). DeepThink is prompt-based reasoning, not a separate reasoning model.

## AI recycling (v2.2)
Order: Groq (3 models) → Gemini (5 models) → DeepSeek → SambaNova → NVIDIA → Mistral → OpenRouter → Hugging Face → Cloudflare.
If one hits its quota/limit (429/402) or errors, the next starts instantly; the exhausted one is skipped for the time it asks for (Retry-After). If all fail, the app waits 1.5 s and goes around again. If a model dies mid-answer, the next one continues the same answer.

## Auto-update (v2.2)
Every push to `main` publishes a GitHub Release (tag `v<version>.<build>`) with `CourseDeep.apk`. Settings → Check for updates downloads that APK immediately and opens the release page.
Raise `version:` in `app/pubspec.yaml` (e.g. 2.2.0+6) for each new release, otherwise the app sees no newer version.

### Stable signing key (one time, needed so updates install over the old app)
GitHub repo → Settings → Secrets and variables → Actions → New repository secret → name `DEBUG_KEYSTORE_BASE64`, value = the whole text of `DEBUG_KEYSTORE_BASE64.txt`. Keep that text private. The first build with this key needs ONE uninstall of the old app; after that, updates install over it.
