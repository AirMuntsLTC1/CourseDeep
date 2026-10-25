import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const encoder = new TextEncoder();

async function hashCode(email: string, code: string, pepper: string) {
  const data = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(`${pepper}:${email}:${code}`),
  );
  return Array.from(new Uint8Array(data))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function sendEmail(email: string, code: string) {
  const clientId = Deno.env.get("GMAIL_CLIENT_ID");
  const clientSecret = Deno.env.get("GMAIL_CLIENT_SECRET");
  const refreshToken = Deno.env.get("GMAIL_REFRESH_TOKEN");
  const sender = Deno.env.get("GMAIL_SENDER_EMAIL");

  if (!clientId || !clientSecret || !refreshToken || !sender) {
    throw new Error("Gmail configuration is incomplete");
  }

  const tokenResponse = await fetch(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      }),
    },
  );

  if (!tokenResponse.ok) {
    throw new Error("Gmail OAuth token request failed");
  }

  const tokenData = await tokenResponse.json();
  if (!tokenData.access_token) {
    throw new Error("Gmail access token missing");
  }

  const message = [
    `From: CourseDeep <${sender}>`,
    `To: ${email}`,
    "Subject: Your CourseDeep verification code",
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "",
    `Your six-digit CourseDeep verification code is: ${code}`,
    "",
    "This code expires in 10 minutes. If you did not request it, ignore this email.",
  ].join("\r\n");

  const response = await fetch(
    "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${tokenData.access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ raw: base64Url(encoder.encode(message)) }),
    },
  );

  if (!response.ok) {
    throw new Error("Gmail message sending failed");
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return reply({ error: "Use POST." }, 405);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const pepper = Deno.env.get("EMAIL_CODE_PEPPER");

    if (!url || !serviceKey || !pepper) {
      return reply({ error: "Server configuration incomplete." }, 500);
    }

    const db = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const input = await req.json();
    const action = input?.action;
    const email = String(input?.email ?? "").trim().toLowerCase();

    if (
      email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
    ) {
      return reply({ error: "Enter a valid email address." }, 400);
    }

    if (action === "send") {
      const { data: old, error: oldError } = await db
        .from("email_verification_codes")
        .select("last_sent_at")
        .eq("email", email)
        .maybeSingle();

      if (oldError) throw oldError;

      if (
        old &&
        Date.now() - new Date(old.last_sent_at).getTime() < 60_000
      ) {
        return reply({ error: "Wait 60 seconds before requesting another code." }, 429);
      }

      const random = crypto.getRandomValues(new Uint32Array(1))[0];
      const code = String(random % 1_000_000).padStart(6, "0");
      const code_hash = await hashCode(email, code, pepper);

      const now = new Date();
      // Save the code FIRST, then email it, so a code that reaches the inbox can always be verified.
      const { error } = await db
        .from("email_verification_codes")
        .upsert({
          email,
          code_hash,
          expires_at: new Date(now.getTime() + 10 * 60_000).toISOString(),
          attempts: 0,
          last_sent_at: now.toISOString(),
          verified_at: null,
          created_at: now.toISOString(),
        }, { onConflict: "email" });

      if (error) throw error;

      try {
        await sendEmail(email, code);
      } catch (mailError) {
        console.error("sendEmail failed:", mailError instanceof Error ? mailError.message : mailError);
        await db.from("email_verification_codes").delete().eq("email", email);
        return reply({ error: "We could not send the email right now. Please try again in a minute." }, 502);
      }

      return reply({
        success: true,
        message: "We sent a six-digit code to your email.",
      });
    }

    if (action === "verify") {
      const code = String(input?.code ?? "").trim();

      if (!/^\d{6}$/.test(code)) {
        return reply({ error: "Enter the six-digit code." }, 400);
      }

      const { data: row, error } = await db
        .from("email_verification_codes")
        .select("code_hash, expires_at, attempts")
        .eq("email", email)
        .maybeSingle();

      if (error) throw error;

      if (!row || new Date(row.expires_at).getTime() <= Date.now()) {
        return reply({ error: "Invalid or expired code." }, 400);
      }

      if (row.attempts >= 5) {
        return reply({ error: "Too many attempts. Request a new code." }, 429);
      }

      const supplied = await hashCode(email, code, pepper);

      if (supplied !== row.code_hash) {
        const { error: updateError } = await db
          .from("email_verification_codes")
          .update({ attempts: row.attempts + 1 })
          .eq("email", email);

        if (updateError) throw updateError;
        return reply({ error: "Invalid or expired code." }, 400);
      }

      // The code is valid. Ask Supabase Auth for a one-time token, then redeem it
      // HERE on the server, so the app receives a ready session (access + refresh
      // token). This removes the client-side "otp_expired" / missing-token errors:
      // the token type (magiclink vs signup for brand-new users) is read from the
      // response instead of being guessed by the app.
      const { data: linkData, error: linkError } =
        await db.auth.admin.generateLink({ type: "magiclink", email });

      if (linkError) {
        console.error("generateLink failed:", linkError.message);
        throw new Error("Unable to create a sign-in session.");
      }

      const tokenHash = linkData?.properties?.hashed_token;
      const tokenType = (linkData?.properties?.verification_type ??
        "magiclink") as "magiclink" | "signup" | "recovery" | "email";
      if (!tokenHash) throw new Error("Supabase did not return a sign-in token.");

      const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
      if (!anonKey) throw new Error("SUPABASE_ANON_KEY is missing.");
      const anon = createClient(url, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      const { data: sess, error: sessError } = await anon.auth.verifyOtp({
        token_hash: tokenHash,
        type: tokenType,
      });

      if (sessError || !sess?.session) {
        console.error("verifyOtp failed:", sessError?.message);
        throw new Error("Unable to open a session.");
      }

      await db.from("email_verification_codes").delete().eq("email", email);

      return reply({
        success: true,
        verified: true,
        email,
        access_token: sess.session.access_token,
        refresh_token: sess.session.refresh_token,
        expires_in: sess.session.expires_in,
      });
    }

    return reply({ error: "Action must be send or verify." }, 400);
  } catch (error) {
    console.error(
      "email-code:",
      error instanceof Error ? error.message : "Unknown error",
    );
    return reply({ error: "Something went wrong on our side. Please request a new code." }, 500);
  }
});

