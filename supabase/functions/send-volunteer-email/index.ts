import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const BREVO_API_KEY = Deno.env.get("maak-supabase-email");

const SENDER_EMAIL = "maak.app.team@gmail.com";

type VolunteerEmailRequest = {
  email: string;
  name: string;
  status: "pending" | "approved" | "rejected";
  rejectionReason?: string;
};

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

serve(async (req) => {
  // Handle browser CORS preflight request.
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      status: 200,
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({
        error: "Method not allowed",
      }),
      {
        status: 405,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  }

  try {
    if (!BREVO_API_KEY) {
      throw new Error("BREVO_API_KEY is not configured.");
    }

    const body = (await req.json()) as VolunteerEmailRequest;

    const email = body.email?.trim();
    const name = body.name?.trim();
    const status = body.status;
    const rejectionReason = body.rejectionReason?.trim();

    if (!email || !name) {
      return new Response(
        JSON.stringify({
          error: "Email and name are required.",
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    if (!["pending", "approved", "rejected"].includes(status)) {
      return new Response(
        JSON.stringify({
          error: "Invalid application status.",
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    const safeName = escapeHtml(name);

    const safeReason = rejectionReason
      ? escapeHtml(rejectionReason)
      : "";

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
      message =
        "Your volunteer application was not approved at this time.";
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

    console.log(
      "Sending volunteer email to:",
      email,
      "status:",
      status,
    );

    const brevoResponse = await fetch(
      "https://api.brevo.com/v3/smtp/email",
      {
        method: "POST",
        headers: {
          "api-key": BREVO_API_KEY,
          "Content-Type": "application/json",
          "Accept": "application/json",
        },
        body: JSON.stringify({
          sender: {
            name: "Ma'ak",
            email: SENDER_EMAIL,
          },
          to: [
            {
              email: email,
              name: name,
            },
          ],
          subject: subject,
          htmlContent: html,
        }),
      },
    );

    const result = await brevoResponse.json();

    if (!brevoResponse.ok) {
      console.error(
        "Brevo error:",
        result,
      );

      return new Response(
        JSON.stringify({
          error: "Email could not be sent.",
          details: result,
        }),
        {
          status: brevoResponse.status,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    console.log(
      "Volunteer email sent successfully:",
      result.messageId,
    );

    return new Response(
      JSON.stringify({
        success: true,
        emailId: result.messageId,
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  } catch (error) {
    console.error(error);

    return new Response(
      JSON.stringify({
        error: error instanceof Error
          ? error.message
          : "Unexpected error.",
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  }
});
