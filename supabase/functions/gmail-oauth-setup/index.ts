const corsHeaders = {
  "Access-Control-Allow-Origin": "https://accounts.google.com",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const enc = new TextEncoder();
const redirectUri =
  "https://zbwmmmstzlgjmhhoceiv.supabase.co/functions/v1/gmail-oauth-setup";

function b64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function fromB64url(value: string): Uint8Array {
  const s = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(s + "=".repeat((4 - s.length % 4) % 4));
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function sign(value: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  return b64url(new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(value))));
}

async function validState(state: string, secret: string): Promise<boolean> {
  try {
    const [payload, signature] = state.split(".");
    if (!payload || !signature) return false;
    const expected = await sign(payload, secret);
    const a = enc.encode(signature);
    const b = enc.encode(expected);
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    if (diff !== 0) return false;
    const data = JSON.parse(new TextDecoder().decode(fromB64url(payload)));
    return Number.isFinite(data.ts) &&
      Date.now() - data.ts >= 0 &&
      Date.now() - data.ts < 10 * 60 * 1000;
  } catch {
    return false;
  }
}

function page(message: string, status = 200): Response {
  return new Response(
    `<!doctype html><html><head><meta name="viewport" content="width=device-width"><title>CourseDeep Gmail setup</title></head><body style="font:16px system-ui;max-width:720px;margin:40px auto;padding:20px"><h2>CourseDeep Gmail OAuth</h2><pre style="white-space:pre-wrap;overflow-wrap:anywhere">${message.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")}</pre></body></html>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } },
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const clientId = Deno.env.get("GMAIL_CLIENT_ID") ?? "";
  const clientSecret = Deno.env.get("GMAIL_CLIENT_SECRET") ?? "";
  const bootstrap = Deno.env.get("GMAIL_OAUTH_BOOTSTRAP_SECRET") ?? "";

  if (!clientId || !clientSecret || !bootstrap) {
    return page("Missing GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, or GMAIL_OAUTH_BOOTSTRAP_SECRET in Supabase secrets.", 500);
  }

  const url = new URL(req.url);

  if (req.method === "POST" && url.pathname.endsWith("/gmail-oauth-setup")) {
    let body: { action?: string; secret?: string };
    try {
      body = await req.json();
    } catch {
      return Response.json({ error: "Send JSON with action and secret." }, { status: 400 });
    }

    if (body.secret !== bootstrap) {
      return Response.json({ error: "Unauthorized." }, { status: 401 });
    }
    if (body.action !== "start") {
      return Response.json({ error: "Unknown action." }, { status: 400 });
    }

    const payload = b64url(enc.encode(JSON.stringify({
      ts: Date.now(),
      nonce: crypto.randomUUID(),
    })));
    const state = `${payload}.${await sign(payload, bootstrap)}`;

    const google = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    google.searchParams.set("client_id", clientId);
    google.searchParams.set("redirect_uri", redirectUri);
    google.searchParams.set("response_type", "code");
    google.searchParams.set("scope", "https://www.googleapis.com/auth/gmail.send");
    google.searchParams.set("access_type", "offline");
    google.searchParams.set("prompt", "consent");
    google.searchParams.set("state", state);

    return Response.json({ authorization_url: google.toString() }, {
      headers: { "Cache-Control": "no-store" },
    });
  }

  if (req.method === "GET" && url.pathname.endsWith("/gmail-oauth-setup")) {
    const error = url.searchParams.get("error");
    if (error) return page(`Google authorization was not completed: ${error}`, 400);

    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state") ?? "";

    if (!code || !(await validState(state, bootstrap))) {
      return page("Invalid or expired OAuth state. Restart the authorization process.", 400);
    }

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: "authorization_code",
      }),
    });

    const tokens = await tokenResponse.json();
    if (!tokenResponse.ok) {
      console.error("Google token exchange failed:", tokens.error);
      return page("Google token exchange failed. Check the Google OAuth client and exact redirect URI, then retry.", 400);
    }

    if (!tokens.refresh_token) {
      return page("Google did not return a refresh token. Revoke this app's access in your Google Account, then restart with prompt=consent.", 400);
    }

    // Displayed only in this no-store response. Never log or save the token to source.
    return page(
      "REFRESH TOKEN (copy it now; do not share it):\n\n" +
      tokens.refresh_token +
      "\n\nNext, save it as the Supabase secret GMAIL_REFRESH_TOKEN. Then remove this temporary setup function."
    );
  }

  return new Response("Method not allowed", { status: 405 });
});

