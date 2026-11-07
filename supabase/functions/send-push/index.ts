import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

// Sends a Ma'ak push notification to every device of one user through
// Firebase Cloud Messaging (HTTP v1 API).
//
// Called only by the database (public.send_maak_push via pg_net), never by the
// app. Requests must carry the shared secret in the x-push-secret header.
//
// Secrets (supabase secrets set ...):
//   PUSH_WEBHOOK_SECRET   same value as the vault secret maak_push_secret
//   FCM_SERVICE_ACCOUNT   the full JSON of a Firebase service account key
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type PushRequest = {
  user_id: string;
  title: string;
  body: string;
  kind: string;
  reference_id?: string | null;
  notification_id?: string | null;
};

function reply(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function safeEqual(a: string, b: string): boolean {
  if (!a || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function clip(value: unknown, max: number): string {
  const text = typeof value === "string" ? value.trim() : "";
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

// Google OAuth access token, cached per function instance.
let cachedToken: { value: string; expires: number } | null = null;

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expires - 120 > now) return cachedToken.value;

  const key = await importPKCS8(account.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setSubject(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`oauth_failed_${res.status}`);
  const json = await res.json();
  cachedToken = {
    value: json.access_token,
    expires: now + Number(json.expires_in ?? 3600),
  };
  return cachedToken.value;
}

// True when FCM says the token will never work again.
function isDeadToken(status: number, error: unknown): boolean {
  if (status === 404) return true;
  const details = (error as { error?: { details?: { errorCode?: string }[] } })
    ?.error?.details ?? [];
  // INVALID_ARGUMENT is not treated as dead: it can also mean a bad payload,
  // and deleting every token over a payload bug would silence all devices.
  return details.some((d) => d.errorCode === "UNREGISTERED");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  if (!WEBHOOK_SECRET || !SERVICE_ACCOUNT_JSON) {
    return reply({ error: "not_configured" }, 500);
  }
  if (!safeEqual(req.headers.get("x-push-secret") ?? "", WEBHOOK_SECRET)) {
    return reply({ error: "unauthorized" }, 401);
  }

  let input: PushRequest;
  try {
    input = await req.json();
  } catch {
    return reply({ error: "invalid_json" }, 400);
  }
  if (typeof input?.user_id !== "string" || !UUID.test(input.user_id)) {
    return reply({ error: "invalid_user" }, 400);
  }
  const title = clip(input.title, 120);
  const body = clip(input.body, 300);
  const kind = clip(input.kind, 40) || "info";
  if (!title) return reply({ error: "invalid_title" }, 400);

  const account = JSON.parse(SERVICE_ACCOUNT_JSON) as ServiceAccount;
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // A restricted member gets exactly one push: "Your account has been
  // restricted". This runs after the block is saved, so it also drops any other
  // notification written during the block ("Account access updated", status
  // updates), whichever order the database wrote them in.
  if (kind !== "account_blocked") {
    const { data: block, error: blockError } = await supabase
      .from("account_blocks")
      .select("user_id")
      .eq("user_id", input.user_id)
      .maybeSingle();
    if (blockError) return reply({ error: "block_lookup_failed" }, 500);
    if (block) return reply({ sent: 0, skipped: "restricted" });
  }

  const { data: rows, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", input.user_id);
  if (error) return reply({ error: "token_lookup_failed" }, 500);
  if (!rows?.length) return reply({ sent: 0 });

  const bearer = await accessToken(account);
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;

  // FCM data values must be strings.
  const data: Record<string, string> = { kind };
  if (input.reference_id) data.reference_id = String(input.reference_id);
  if (input.notification_id) data.id = String(input.notification_id);

  // Messages from one conversation replace each other instead of piling up.
  const tag = kind === "message" && input.reference_id
    ? `chat-${input.reference_id}`
    : undefined;

  let sent = 0;
  const dead: string[] = [];
  await Promise.all(rows.map(async ({ token }) => {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: {
              // High-importance channel created by the app (MainActivity.kt):
              // pops up on screen, plays the sound and vibrates.
              channel_id: "maak_alerts",
              sound: "default",
              default_vibrate_timings: true,
              notification_priority: "PRIORITY_HIGH", // Android 7 and older
              ...(tag ? { tag } : {}),
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    });
    if (res.ok) {
      sent++;
      return;
    }
    const err = await res.json().catch(() => null);
    if (isDeadToken(res.status, err)) dead.push(token);
    else console.error("fcm_send_failed", res.status, JSON.stringify(err));
  }));

  if (dead.length) {
    await supabase.from("device_tokens").delete().in("token", dead);
  }
  return reply({ sent, removed: dead.length });
});
