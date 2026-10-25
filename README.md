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
