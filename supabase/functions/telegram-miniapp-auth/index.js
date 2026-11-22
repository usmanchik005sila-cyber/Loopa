// LOOPA Telegram Mini App authentication bridge (Supabase Edge Function).
// Deploy with verify_jwt=false. Every action validates Telegram's signed initData
// itself; the optional Link action ALSO verifies a Supabase user access token.
// Never log initData, returned token_hash, user data or server secrets.
import { createClient } from "npm:@supabase/supabase-js@2";

const ALLOWED_ORIGIN = "https://loopacinema.ru";
const MAX_INIT_DATA_AGE_SECONDS = 600; // 10 minutes
const MAX_BODY_BYTES = 12000;
const MAX_AVATAR_BYTES = 1024 * 1024;
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
  return { telegramId: String(user.id), authDate, signature: calculatedHash, user, startParam: params.get("start_param") };
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

async function recordTrackingOpen(admin, token, telegram) {
  const id = /^ref_([a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12})$/.exec(telegram.startParam || "")?.[1];
  if (!id || telegram.telegramId === Deno.env.get("LOOPA_OWNER_TELEGRAM_ID")?.trim()) return;
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(token), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const hashed = new Uint8Array(await crypto.subtle.sign(
    "HMAC", key, encoder.encode("loopa.tracking.open.v1:" + id + ":" + telegram.telegramId)
  ));
  const visitorHash = Array.from(hashed, byte => byte.toString(16).padStart(2, "0")).join("");
  await admin.rpc("loopa_record_telegram_tracking_open", { p_link_id: id, p_visitor_hash: visitorHash })
    .abortSignal(AbortSignal.timeout(2000));
}

async function lookup(admin, telegramId) {
  const { data, error } = await admin.from("telegram_miniapp_links")
    .select("telegram_id,user_id").eq("telegram_id", telegramId).maybeSingle();
  if (error) throw error;
  return data;
}

async function completeRegistration(admin, telegramId) {
  const { data, error } = await admin.rpc("loopa_complete_telegram_registration", {
    p_telegram_id: telegramId,
  });
  if (error || !data) throw error || new Error("registration_state_unavailable");
  return data;
}

function telegramProfile(user) {
  const fullName = [user.first_name, user.last_name].filter(value => typeof value === "string")
    .join(" ").replace(/[\x00-\x1f\x7f]/g, " ").replace(/\s+/g, " ").trim();
  const displayName = [...fullName].slice(0, 40).join("").trim() || "Участник LOOPA";
  const handle = typeof user.username === "string" ? user.username.toLowerCase() : "";
  return { displayName, username: /^[a-z][a-z0-9_]{3,15}$/.test(handle) ? handle : null };
}

async function readBoundedBytes(input, limit) {
  if (Number(input.headers.get("Content-Length") || "0") > limit) return null;
  if (!input.body) return new Uint8Array();
  const reader = input.body.getReader();
  const bytes = new Uint8Array(limit);
  let length = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) return bytes.subarray(0, length);
      if (length + value.byteLength > limit) {
        void reader.cancel().catch(() => {});
        return null;
      }
      bytes.set(value, length);
      length += value.byteLength;
    }
  } finally {
    reader.releaseLock();
  }
}

function telegramPhotoUrl(value) {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password || url.port) return null;
    if (url.hostname === "t.me" && url.pathname.startsWith("/i/userpic/")) return url;
    if (/^cdn[0-9]{1,2}\.telesco\.pe$/.test(url.hostname) && url.pathname.startsWith("/file/")) return url;
  } catch {}
  return null;
}

async function downloadJpeg(url, signal) {
  const response = await fetch(url, { signal, redirect: "error" });
  if (!response.ok) return null;
  const image = await readBoundedBytes(response, MAX_AVATAR_BYTES);
  return image?.[0] === 0xff && image[1] === 0xd8 && image[2] === 0xff ? image : null;
}

async function importAvatar(admin, token, telegram, userId) {
  // Only download from Telegram with an enforced size and time limit.
  try {
    const photo = telegramPhotoUrl(telegram.user.photo_url);
    let image = photo ? await downloadJpeg(photo, AbortSignal.timeout(1200)).catch(() => null) : null;
    if (!image) {
      const signal = AbortSignal.timeout(2400);
      const api = "https://api.telegram.org/bot" + token + "/";
      const request = async (method, payload) => {
        const response = await fetch(api + method, {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload), signal, redirect: "error",
        });
        if (!response.ok) return null;
        const body = await response.json();
        return body.ok ? body.result : null;
      };
      const photos = await request("getUserProfilePhotos", { user_id: Number(telegram.telegramId), limit: 1 });
      const size = photos?.photos?.[0]?.find(photo => photo.width >= 160 && photo.height >= 160)
        || photos?.photos?.[0]?.[0];
      if (!size?.file_id || size.file_size > MAX_AVATAR_BYTES) return;
      const file = await request("getFile", { file_id: size.file_id });
      if (file?.file_size > MAX_AVATAR_BYTES ||
          !/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*\.jpe?g$/i.test(file?.file_path || "")) return;
      image = await downloadJpeg("https://api.telegram.org/file/bot" + token + "/" + file.file_path, signal);
    }
    if (!image) return;
    const bucket = admin.storage.from("avatars");
    await bucket.upload(userId + "/telegram-avatar.jpg", image, { contentType: "image/jpeg", upsert: false });
  } catch {
    // An unavailable Telegram photo must not block login or registration.
  }
}

async function repairTelegramProfile(admin, token, telegram, account) {
  if (account.app_metadata?.loopa_telegram_registration !== telegram.telegramId) return;
  const args = { p_telegram_id: telegram.telegramId, p_user_id: account.id };
  try {
    const { data, error } = await admin.rpc("loopa_repair_telegram_profile", { ...args, p_apply: false });
    if (error || !data?.eligible) return;
    const profile = telegramProfile(telegram.user);
    if (data.avatar_missing) await importAvatar(admin, token, telegram, account.id);
    await admin.rpc("loopa_repair_telegram_profile", {
      ...args, p_apply: true, p_display_name: profile.displayName, p_username: profile.username,
    });
  } catch {
    // Login remains available if the optional profile import fails.
  }
}

Deno.serve(async (request) => {
  if (request.headers.get("Origin") !== ALLOWED_ORIGIN) {
    return reply({ error: "origin_not_allowed" }, 403);
  }
  if (request.method === "OPTIONS") return reply({ ok: true });
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);

  try {
    const raw = await readBoundedBytes(request, MAX_BODY_BYTES);
    if (raw === null) return reply({ error: "request_too_large" }, 413);
    let body;
    try { body = JSON.parse(new TextDecoder().decode(raw)); }
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
    if (telegram.startParam?.startsWith("ref_") && action !== "link") {
      const tracking = recordTrackingOpen(admin, token, telegram).catch(() => {});
      if (globalThis.EdgeRuntime?.waitUntil) globalThis.EdgeRuntime.waitUntil(tracking);
      else await tracking;
    }

    if (!needsSession) {
      let link = await lookup(admin, telegramId);
      if (!link && action === "register") {
        let registration = await completeRegistration(admin, telegramId);
        if (registration.status === "missing") {
          // Auth can commit even if the response is lost. Mark the candidate
          // at creation so a retry can finish the same UUID without deleting it.
          const passwordBytes = crypto.getRandomValues(new Uint8Array(32));
          const password = Array.from(passwordBytes, b => b.toString(16).padStart(2, "0")).join("");
          const profile = telegramProfile(telegram.user);
          const { data: created, error: creationError } = await admin.auth.admin.createUser({
            email: "miniapp-" + telegramId + "@auth.loopacinema.invalid",
            password,
            email_confirm: true,
            user_metadata: { display_name: profile.displayName },
            app_metadata: {
              loopa_telegram_registration: telegramId,
              loopa_telegram_profile_seed: true,
              loopa_telegram_username: profile.username,
            },
          });
          if (!creationError && created?.user?.id) {
            await importAvatar(admin, token, telegram, created.user.id);
          }
          registration = await completeRegistration(admin, telegramId);
          if (registration.status === "missing" && creationError && creationError.status >= 500) {
            throw creationError;
          }
        }
        if (registration.status === "link_pending") return reply({ error: "telegram_link_pending" }, 409);
        if (registration.status !== "linked" || !registration.user_id) {
          return reply({ error: "registration_unavailable" }, 409);
        }
        link = registration;
      }
      if (!link) return reply({ status: "unlinked" });

      const { data: userResponse, error: userError } =
        await admin.auth.admin.getUserById(link.user_id);
      if (userError || userResponse?.user?.id !== link.user_id || !userResponse.user.email) {
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
      if (action === "login") await repairTelegramProfile(admin, token, telegram, userResponse.user);

      // The link is minted ONLY for the UUID bound to verified Telegram initData.
      // The hash is single-use and is never written to URLs or logs.
      let generated;
      try {
        generated = await admin.auth.admin.generateLink({
          type: "magiclink", email: userResponse.user.email,
        });
      } catch {
        return reply({ error: "reopen_miniapp" }, 503);
      }
      const { data, error } = generated;
      if (error || !data?.properties?.hashed_token || data.user?.id !== link.user_id) {
        return reply({ error: "reopen_miniapp" }, 503);
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
        if (existing.user_id !== viewerId) return reply({ status: "claimed_by_another_profile" });
        await repairTelegramProfile(admin, token, telegram, viewer.user);
        return reply({ status: "linked" });
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
        reservation === "profile_already_linked_to_another_telegram" ||
        reservation === "telegram_registration_pending") {
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
        email: "miniapp-link-" + viewerId + "@auth.loopacinema.invalid",
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
