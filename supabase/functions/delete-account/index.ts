
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
  };

  if (req.method === "OPTIONS") {
    return new Response(null, { headers });
  }

  const respond = (message: string, status: number) =>
    new Response(JSON.stringify({ message }), { status, headers });

  if (req.method !== "POST") {
    return respond("Method not allowed.", 405);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const publishableKey =
      Deno.env.get("SUPABASE_ANON_KEY") ??
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY");

    if (!url || !serviceKey || !publishableKey) {
      return respond("Server configuration error.", 500);
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return respond("Please sign in again.", 401);
    }

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const authClient = createClient(url, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const token = authorization.substring(7);
    const { data, error: authError } =
      await authClient.auth.getUser(token);

    if (authError || !data.user) {
      return respond("Your session has expired. Please sign in again.", 401);
    }

    const userId = data.user.id;

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("role")
      .eq("id", userId)
      .single();

    if (profileError || !profile) {
      return respond("Unable to verify your account.", 500);
    }

    if (!["help_seeker", "volunteer"].includes(profile.role)) {
      return respond("Account deletion is not available for this role.", 403);
    }

    // Delete private verification documents before deleting the account.
    // If this fails, keep the account intact so the user can retry.
    const bucket = admin.storage.from("verification-documents");
    const { data: files, error: listError } =
      await bucket.list(userId, { limit: 1000 });

    if (listError) {
      return respond("Unable to prepare account deletion. Please try again.", 500);
    }

    const paths = (files ?? [])
      .filter((file) => file.name !== ".emptyFolderPlaceholder")
      .map((file) => `${userId}/${file.name}`);

    if (paths.length > 0) {
      const { error: storageError } = await bucket.remove(paths);

      if (storageError) {
        return respond("Unable to remove account documents. Please try again.", 500);
      }
    }

    // Database foreign keys with ON DELETE CASCADE remove dependent rows.
    const { error: deleteError } =
      await admin.auth.admin.deleteUser(userId);

    if (deleteError) {
      return respond("Account deletion failed. Please try again.", 500);
    }

    return respond("Your account has been permanently deleted.", 200);
  } catch (error) {
    console.error("Account deletion failed:", error);
    return respond("Something went wrong. Please try again.", 500);
  }
});
