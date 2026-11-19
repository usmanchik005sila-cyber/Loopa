// LOOPA Telegram Mini App authentication bridge (Supabase Edge Function).
// Deploy with verify_jwt=false. Every action validates Telegram's signed initData
// itself; the optional Link action ALSO verifies a Supabase user access token.
// Never log initData, returned token_hash, user data or server secrets.
import { createClient } from "npm:@supabase/supabase-js@2";

const ALLOWED_ORIGIN = "https://loopacinema.ru";
const MAX_INIT_DATA_AGE_SECONDS = 600; // 10 minutes
const MAX_BODY_BYTES = 12000;
const encoder = new TextEncoder();

function reply(body, status = 200, retryAfter = 0) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      "Pragma": "no-cache",
      "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
      "Vary": "Origin",
      "Access-Control-Allow-Headers": "apikey, authorization, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      ...(retryAfter ? { "Retry-After": String(retryAfter), "Access-Control-Expose-Headers": "Retry-After" } : {}),
    },
  });
}

function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

function hexToBytes(hex) {
  if (!/^[a-f0-9]{64}$/i.test(hex)) return null;
  const bytes = new Uint8Array(32);
  for (let i = 0; i < 32; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}

async function verifyTelegramInitData(initData, botToken) {
  if (typeof initData !== "string" || !initData || initData.length > 8192) {
    throw new Error("invalid_init_data");
  }
  const params = new URLSearchParams(initData);
  const seen = new Set();
  for (const [key] of params) {
    if (seen.has(key)) throw new Error("duplicate_init_data_fields");
    seen.add(key);
  }
  const providedHash = hexToBytes(params.get("hash") || "");
  if (!providedHash || !params.has("user") || !params.has("auth_date")) {
    throw new Error("missing_init_data_fields");
  }

  const authDate = Number(params.get("auth_date"));
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isSafeInteger(authDate) || authDate > now + 30 ||
      now - authDate > MAX_INIT_DATA_AGE_SECONDS) {
    throw new Error("stale_init_data");
  }

  const checkString = [...params]
    .filter(([key]) => key !== "hash")
    .map(([key, value]) => key + "=" + value)
    .sort()
    .join("\n");

  // Telegram HMAC scheme: HMAC("WebAppData", botToken) -> HMAC(secret, fields).
  const tokenKey = await crypto.subtle.importKey(
    "raw", encoder.encode("WebAppData"), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const secret = await crypto.subtle.sign("HMAC", tokenKey, encoder.encode(botToken));
  const secretKey = await crypto.subtle.importKey(
    "raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const calculatedHash = new Uint8Array(
    await crypto.subtle.sign("HMAC", secretKey, encoder.encode(checkString))
  );
  if (!constantTimeEqual(providedHash, calculatedHash)) throw new Error("invalid_signature");

  let user;
  try { user = JSON.parse(params.get("user") || ""); }
  catch { throw new Error("invalid_user"); }
  if (!user || !Number.isSafeInteger(user.id) || user.id <= 0) {
    throw new Error("invalid_user");
  }
  return { telegramId: String(user.id), authDate, signature: calculatedHash };
}

function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  let key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY");
  if (!key) {
    try { key = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default; }
    catch { /* no keys */ }
  }
  if (!url || !key) throw new Error("missing_server_configuration");
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function lookup(admin, telegramId) {
  const { data, error } = await admin.from("telegram_miniapp_links")
    .select("telegram_id,user_id").eq("telegram_id", telegramId).maybeSingle();
  if (error) throw error;
  return data;
}

function internalEmail(telegramId) {
  // Used ONLY for previously email-less users who explicitly link their
  // existing account. Never delivered to; not a user-supplied recovery address.
  return "miniapp-" + telegramId + "@auth.loopacinema.invalid";
}

Deno.serve(async (request) => {
  if (request.headers.get("Origin") !== ALLOWED_ORIGIN) {
    return reply({ error: "origin_not_allowed" }, 403);
  }
  if (request.method === "OPTIONS") return reply({ ok: true });
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);

  try {
    if (Number(request.headers.get("Content-Length") || "0") > MAX_BODY_BYTES) {
      return reply({ error: "request_too_large" }, 413);
    }
    const raw = await request.text();
    if (raw.length > MAX_BODY_BYTES) return reply({ error: "request_too_large" }, 413);
    let body;
    try { body = JSON.parse(raw); }
    catch { return reply({ error: "invalid_json" }, 400); }

    const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
    if (!token) return reply({ error: "backend_not_configured" }, 503);
    let telegram;
    try { telegram = await verifyTelegramInitData(body?.initData, token); }
    catch (error) {
      const stale = error instanceof Error && error.message === "stale_init_data";
      return reply({ error: stale ? "reopen_miniapp" : "invalid_telegram_data" }, 401);
    }

    const { telegramId } = telegram;
    const { action } = body;
    if (!["login", "register", "link", "status"].includes(action)) {
      return reply({ error: "unknown_action" }, 400);
    }

    const needsSession = action === "link" || action === "status";
    const match = needsSession
      ? /^(?:Bearer)\s+(.+)$/i.exec(request.headers.get("Authorization") || "")
      : null;
    if (needsSession && !match) return reply({ error: "login_required" }, 401);

    const admin = adminClient();
    const { data: retryAfter, error: budgetError } = await admin.rpc("loopa_take_telegram_action_budget", {
      p_telegram_id: telegramId,
      p_action: action,
    });
    if (budgetError || !Number.isSafeInteger(retryAfter) || retryAfter < 0) {
      return reply({ error: "service_unavailable" }, 503);
    }
    if (retryAfter > 0) return reply({ error: "telegram_rate_limited" }, 429, retryAfter);

    if (!needsSession) {
      let link = await lookup(admin, telegramId);
      if (!link && action === "register") {
        // Create a distinct LOOPA profile only after explicit registration in the
        // Mini App, based on HMAC-verified Telegram initData (never initDataUnsafe).
        // Existing profiles must be linked separately; do not merge them silently.
        const email = internalEmail(telegramId);
        const passwordBytes = crypto.getRandomValues(new Uint8Array(32));
        const password = Array.from(passwordBytes, b => b.toString(16).padStart(2, "0")).join("");
        const { data: created, error: createError } = await admin.auth.admin.createUser({
          email, password, email_confirm: true,
          user_metadata: { display_name: "Участник LOOPA" },
        });
        if (createError || !created?.user?.id) {
          // Concurrent attempts or an existing internal email must not mint a
          // session unless this Telegram ID is already mapped to that user.
          link = await lookup(admin, telegramId);
          if (!link) return reply({ error: "registration_unavailable" }, 409);
        } else {
          const createdId = created.user.id;
          const { error: bindError } = await admin.from("telegram_miniapp_links")
            .insert({ telegram_id: telegramId, user_id: createdId });
          if (bindError) {
            // The new identity is not yet exposed to the browser. Prevent orphan
            // profiles if another request linked the Telegram ID concurrently.
            await admin.auth.admin.deleteUser(createdId).catch(() => {});
            link = await lookup(admin, telegramId);
            if (!link) return reply({ error: "registration_unavailable" }, 409);
          } else {
            link = { telegram_id: telegramId, user_id: createdId };
          }
        }
      }
      if (!link) return reply({ status: "unlinked" });

      const { data: userResponse, error: userError } =
        await admin.auth.admin.getUserById(link.user_id);
      if (userError || !userResponse?.user?.email) {
        return reply({ status: "login_unavailable" });
      }

      // Claim the verified payload before calling Auth. Never release the claim:
      // a transport failure can leave the result of generateLink unknown.
      const fingerprintBytes = await crypto.subtle.digest("SHA-256", telegram.signature);
      const fingerprint = Array.from(new Uint8Array(fingerprintBytes), byte =>
        byte.toString(16).padStart(2, "0")).join("");
      const { data: claimed, error: claimError } = await admin.rpc("loopa_claim_telegram_login", {
        p_fingerprint: fingerprint,
        p_auth_date: telegram.authDate,
      });
      if (claimError) throw claimError;
      if (claimed !== true) return reply({ error: "reopen_miniapp" }, 409);

      // The link is minted ONLY for the UUID bound to verified Telegram initData.
      // The hash is single-use and is never written to URLs or logs.
      const { data, error } = await admin.auth.admin.generateLink({
        type: "magiclink", email: userResponse.user.email,
      });
      if (error || !data?.properties?.hashed_token ||
          data.user?.id !== link.user_id) {
        return reply({ status: "login_unavailable" });
      }
      return reply({ status: "login_ready", token_hash: data.properties.hashed_token });
    }

    // A Supabase user JWT must be validated with Auth; do not decode/trust it locally.
    const { data: viewer, error: authError } = await admin.auth.getUser(match[1]);
    if (authError || !viewer?.user?.id) {
      return reply({ error: "login_required" }, 401);
    }
    const viewerId = viewer.user.id;
    if (action === "status") {
      const existing = await lookup(admin, telegramId);
      if (existing) {
        return reply({ status: existing.user_id === viewerId ? "linked" : "claimed_by_another_profile" });
      }
      const { data: other, error } = await admin.from("telegram_miniapp_links")
        .select("telegram_id").eq("user_id", viewerId).maybeSingle();
      if (error) throw error;
      return reply({ status: other ? "profile_linked_elsewhere" : "unlinked" });
    }

    const linkArgs = { p_telegram_id: telegramId, p_user_id: viewerId };
    const { data: reservation, error: reserveError } = await admin.rpc("loopa_telegram_link_step", {
      ...linkArgs, p_finish: false,
    });
    if (reserveError) throw reserveError;
    if (reservation === "already_linked") return reply({ status: reservation });
    if (reservation === "telegram_already_linked_to_another_profile" ||
        reservation === "profile_already_linked_to_another_telegram") {
      return reply({ error: reservation }, 409);
    }
    if (reservation !== "reserved") return reply({ error: "service_unavailable" }, 503);

    // Re-read Auth after reserving the pair. A retry can finish a prior
    // successful email update even if its response was lost.
    const { data: account, error: accountError } = await admin.auth.admin.getUserById(viewerId);
    if (accountError || account?.user?.id !== viewerId) {
      return reply({ error: "service_unavailable" }, 503);
    }
    if (!account.user.email) {
      const { error: emailError } = await admin.auth.admin.updateUserById(viewerId, {
        email: internalEmail(telegramId),
        email_confirm: true,
      });
      if (emailError) throw emailError;
    }

    const { data: completed, error: completeError } = await admin.rpc("loopa_telegram_link_step", {
      ...linkArgs, p_finish: true,
    });
    if (completeError) throw completeError;
    if (completed !== "linked" && completed !== "already_linked") {
      return reply({ error: "service_unavailable" }, 503);
    }
    return reply({ status: completed });
  } catch {
    // No details, initData, or credentials leaked to the caller or Edge logs.
    return reply({ error: "service_unavailable" }, 503);
  }
});
