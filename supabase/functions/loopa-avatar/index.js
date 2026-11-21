import { createClient } from "npm:@supabase/supabase-js@2";

const origin = "https://loopacinema.ru";
const avatarPath = /^([a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})\/(?:avatar\.(jpg|png|webp)|(telegram-avatar\.jpg))$/;
const mime = { jpg: "image/jpeg", png: "image/png", webp: "image/webp" };
const headers = {
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Headers": "apikey, authorization",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Cache-Control": "private, no-store",
  "Vary": "Origin, Authorization",
  "X-Content-Type-Options": "nosniff",
};

Deno.serve(async request => {
  const reply = status => new Response(null, { status, headers });
  if (request.headers.get("Origin") !== origin) return reply(403);
  if (request.method === "OPTIONS") return reply(204);
  if (request.method !== "GET") return reply(405);
  const token = /^Bearer (\S+)$/i.exec(request.headers.get("Authorization") ?? "")?.[1];
  if (!token) return reply(401);
  const path = new URL(request.url).searchParams.get("path");
  const match = path && avatarPath.exec(path);
  if (!match) return reply(404);
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const viewer = createClient(url, Deno.env.get("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: "Bearer " + token } },
      auth: { persistSession: false },
    });
    const { data: identity, error: authError } = await viewer.auth.getUser(token);
    if (authError || !identity?.user?.id) return reply(401);
    const { data: allowed, error: permissionError } = await viewer.rpc("loopa_avatar_can_read", { p_owner: match[1] });
    if (permissionError) return reply(503);
    if (allowed !== true) return reply(404);
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
    const { data: photo, error } = await admin.storage.from("avatars").download(path);
    if (error || !photo || photo.size > 5 * 1024 * 1024) return reply(404);
    return new Response(photo, { headers: { ...headers, "Content-Type": mime[match[2] ?? "jpg"] } });
  } catch {
    return reply(503);
  }
});
