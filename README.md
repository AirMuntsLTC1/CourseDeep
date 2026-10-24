# CourseDeep 🤖

A free AI assistant built with Flutter, PHP, and C++.

## Structure
- `backend/api-proxy.php` — PHP proxy (hides API key, forwards to Groq)
- `native/coursedeep.cpp` — C++ native lib (compiled via Termux clang)
- `app/` — Flutter app (built to APK via GitHub Actions)

## Build APK
Push to `main` → go to Actions tab → **Build CourseDeep APK** → download artifact.

## Deploy backend
Upload `backend/api-proxy.php` to any free PHP host (InfinityFree / 000webhost),
set `AI_API_KEY` as env var, then update `kProxyUrl` in `app/lib/main.dart`.
