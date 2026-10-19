import { createClient } from "npm:@supabase/supabase-js@2";

// Sends Ma'ak volunteer application emails (pending / approved / rejected).
//
// Security model: the caller never chooses the recipient or the content.
// - "pending": only the signed-in volunteer, to their own verified address,
//   while their application is pending_review.
// - "approved" / "rejected": only Ma'ak admins, and only after the decision
//   is stored. The rejection reason is read from the database.
// Client-supplied email, name and reason fields are ignored.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

const BREVO_API_KEY = Deno.env.get("maak-supabase-email");

const SENDER_EMAIL = "maak.app.team@gmail.com";

const STATUSES = ["pending", "approved", "rejected"];

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Best-effort duplicate guard per function instance (recipient + status).
const COOLDOWN_MS = 10 * 60 * 1000;
const recent = new Map<string, number>();

type Status = "pending" | "approved" | "rejected";

function reply(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function buildEmail(status: Status, name: string, rejectionReason: string) {
  const safeName = escapeHtml(name);

  const safeReason = rejectionReason ? escapeHtml(rejectionReason) : "";

  let subject = "";
  let heading = "";
  let message = "";
  let accentColor = "#D98B2B";

  if (status === "pending") {
    subject = "Ma'ak Volunteer Application Received";
    heading = "Application Received";
    message =
      "Your volunteer application has been received and is currently under review.";
    accentColor = "#D98B2B";
  } else if (status === "approved") {
    subject = "Ma'ak Volunteer Application Approved";
    heading = "Application Approved";
    message =
      "Your volunteer application has been approved. You can now access Ma'ak as a volunteer.";
    accentColor = "#2E7D32";
  } else {
    subject = "Ma'ak Volunteer Application Update";
    heading = "Application Not Approved";
    message = "Your volunteer application was not approved at this time.";
    accentColor = "#C62828";
  }

  const reasonSection =
    status === "rejected" && safeReason
      ? `
          <div style="
            margin-top:20px;
            padding:16px;
            background:#FDECEC;
            border-radius:10px;
          ">
            <strong style="
              color:#C62828;
            ">
              Reason for rejection
            </strong>

            <p style="
              margin:8px 0 0;
              line-height:1.6;
            ">
              ${safeReason}
            </p>
          </div>
        `
      : "";

  const html = `
      <!DOCTYPE html>
      <html>
        <body style="
          margin:0;
          padding:0;
          background:#F6F8FB;
          font-family:Arial, sans-serif;
          color:#1F2937;
        ">
          <div style="
            max-width:600px;
            margin:40px auto;
            padding:0 20px;
          ">
            <div style="
              background:#FFFFFF;
              border-radius:16px;
              padding:32px;
              box-shadow:0 4px 18px rgba(0,0,0,0.06);
            ">

              <h1 style="
                margin:0 0 24px;
                color:#173B57;
                font-size:28px;
              ">
                مَعَك | Ma'ak
              </h1>

              <div style="
                width:48px;
                height:4px;
                border-radius:4px;
                background:${accentColor};
                margin-bottom:24px;
              "></div>

              <h2 style="
                margin:0 0 18px;
                color:${accentColor};
              ">
                ${heading}
              </h2>

              <p style="
                line-height:1.7;
              ">
                Hello ${safeName},
              </p>

              <p style="
                line-height:1.7;
              ">
                ${message}
              </p>

              ${reasonSection}

              <p style="
                margin-top:28px;
                line-height:1.7;
                color:#667085;
              ">
                Thank you for being part of the Ma'ak community.
              </p>

            </div>
          </div>
        </body>
      </html>
    `;

  return { subject, html };
}

Deno.serve(async (req) => {
  // Handle browser CORS preflight request.
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return reply({ error: "sign_in_required" }, 401);
    }
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser(
      authorization.slice(7),
    );
    if (authError || !user) return reply({ error: "sign_in_required" }, 401);

    const input = await req.json().catch(() => ({}));
    const status = input?.status as Status;
    if (!STATUSES.includes(status)) return reply({ error: "invalid_status" }, 400);

    let volunteerId: string;
    if (status === "pending") {
      // A volunteer may only notify themselves; any supplied target is ignored.
      volunteerId = user.id;
    } else {
      const { data: isAdmin, error } = await userClient.rpc("is_maak_admin");
      if (error || isAdmin !== true) return reply({ error: "admin_only" }, 403);
      volunteerId = String(input?.volunteerId ?? "");
      if (!UUID.test(volunteerId)) return reply({ error: "invalid_volunteer" }, 400);
    }

    // Server-only client, used after the caller has been authorized above.
    const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false },
    });

    // The email must describe the decision already stored, never caller text.
    const { data: application, error: applicationError } = await service
      .from("volunteer_profiles")
      .select("status, rejection_reason")
      .eq("user_id", volunteerId)
      .maybeSingle();
    const expected = status === "pending" ? "pending_review" : status;
    if (applicationError || !application || application.status !== expected) {
      return reply({ error: "application_state_mismatch" }, 409);
    }

    let email: string | undefined;
    if (status === "pending") {
      email = user.email;
    } else {
      const { data: target, error: userError } = await service.auth.admin
        .getUserById(volunteerId);
      email = userError ? undefined : target?.user?.email;
    }
    if (!email) return reply({ error: "recipient_unavailable" }, 404);

    const { data: profile } = await service
      .from("profiles")
      .select("full_name")
      .eq("id", volunteerId)
      .maybeSingle();
    const name = String(profile?.full_name ?? "").trim() || "Volunteer";

    const key = `${volunteerId}:${status}`;
    const now = Date.now();
    if (now - (recent.get(key) ?? 0) < COOLDOWN_MS) {
      return reply({ error: "recently_sent" }, 429);
    }
    if (!BREVO_API_KEY) return reply({ error: "email_not_configured" }, 503);
    recent.set(key, now);
    if (recent.size > 2000) {
      for (const [k, time] of recent) if (now - time > COOLDOWN_MS) recent.delete(k);
    }

    const { subject, html } = buildEmail(
      status,
      name,
      String(application.rejection_reason ?? "").trim(),
    );

    const brevoResponse = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        "api-key": BREVO_API_KEY,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({
        sender: { name: "Ma'ak", email: SENDER_EMAIL },
        to: [{ email, name }],
        subject,
        htmlContent: html,
      }),
    });

    if (!brevoResponse.ok) {
      // Allow an admin retry; never return provider details to the client.
      recent.delete(key);
      console.error("Brevo error status:", brevoResponse.status);
      return reply({ error: "email_not_sent" }, 502);
    }

    const result = await brevoResponse.json().catch(() => ({}));
    // Log the status only, never the recipient address.
    console.log("Volunteer email sent:", status);
    return reply({ success: true, emailId: result?.messageId ?? null });
  } catch {
    console.error("send-volunteer-email failed");
    return reply({ error: "email_unavailable" }, 500);
  }
});
