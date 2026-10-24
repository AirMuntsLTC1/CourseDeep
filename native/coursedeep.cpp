// CourseDeep native helpers (loaded from Flutter via dart:ffi as libcoursedeep.so)
#include <cstddef>
#include <cstdint>

#define CD_EXPORT extern "C" __attribute__((visibility("default")))

// Stable 64-bit FNV-1a hash — used by the app as request id + answer-cache key.
CD_EXPORT uint64_t coursedeep_hash(const char* s) {
  uint64_t h = 1469598103934665603ULL;
  while (s && *s) { h ^= (unsigned char)(*s++); h *= 1099511628211ULL; }
  return h;
}

// Shrinks big file dumps before they are sent to the AI (fewer tokens, faster answers):
//  - removes \r and NUL bytes
//  - strips trailing spaces/tabs on every line
//  - collapses 3+ blank lines into 1 blank line
// `out` must have room for `n` bytes. Returns the new length (UTF-8 stays valid: only ASCII bytes are touched).
CD_EXPORT size_t coursedeep_squeeze(const uint8_t* in, size_t n, uint8_t* out) {
  size_t o = 0; int nl = 0;
  for (size_t i = 0; i < n; i++) {
    uint8_t c = in[i];
    if (c == '\r' || c == 0) continue;
    if (c == '\n') {
      while (o > 0 && (out[o - 1] == ' ' || out[o - 1] == '\t')) o--;
      if (++nl <= 2) out[o++] = c;
    } else { nl = 0; out[o++] = c; }
  }
  return o;
}

// Rough token estimate (~4 chars per token) shown in the UI for big attachments.
CD_EXPORT int32_t coursedeep_estimate_tokens(size_t chars) { return (int32_t)((chars + 3) / 4); }

CD_EXPORT const char* coursedeep_version() { return "CourseDeep-native-2.0"; }
