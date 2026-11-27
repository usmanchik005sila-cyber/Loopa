const origin = "https://loopacinema.ru";
const openUrl = "https://t.me/LOOPAvideo_bot/loopa";
const defaultImage = "https://wnubqzwsvclvcvozibtc.supabase.co/functions/v1/loopa-bot/card-v4.jpg?action=invite_photo";
const description = "Заходи, посмотрим вместе";
const maxTokenLength = 1900;
const destinationPattern = /^(?:room_[a-f0-9]{12}|yt_[A-Za-z0-9_-]{11}|rt_[a-f0-9]{32}|vk_-?\d{1,19}_\d{1,19})$/;
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", {fatal: true});
const keyContext = "loopa.telegram.web-invite.v1:";

export function webInviteConfigured(secret) {
  return typeof secret === "string" && /^[a-f0-9]{64}$/i.test(secret);
}

function encode(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decode(base64) {
  return Uint8Array.from(atob(base64.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
}

function safeImage(value) {
  if (typeof value !== "string" || value.length > 800) return "";
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password || url.port ||
      !/^(?:pic\.rutubelist\.ru|(?:[a-z0-9-]+\.)*(?:ytimg\.com|rtbcdn\.ru|rutube\.ru|userapi\.com|vkusercdn\.ru|vkvideo\.ru))$/.test(url.hostname)) return "";
    url.hash = "";
    return url.href.length <= 800 ? url.href : "";
  } catch {
    return "";
  }
}

function key(secret) {
  return crypto.subtle.importKey("raw", encoder.encode(secret), {name: "HMAC", hash: "SHA-256"}, false, ["sign", "verify"]);
}

async function inviteToken(secret, details, destination) {
  if (!destinationPattern.test(destination)) throw Error("invalid_invite_destination");
  const metadata = {
    title: Array.from(String(details.title || "Приглашение в LOOPA")).slice(0, 220).join(""),
    image: safeImage(details.cover),
    destination
  };
  let payload = encode(encoder.encode(JSON.stringify(metadata)));
  if (payload.length + 44 > maxTokenLength) {
    metadata.title = Array.from(metadata.title).slice(0, 100).join("");
    payload = encode(encoder.encode(JSON.stringify(metadata)));
  }
  if (payload.length + 44 > maxTokenLength) throw Error("invite_token_too_long");
  const signature = await crypto.subtle.sign("HMAC", await key(secret), encoder.encode(keyContext + payload));
  return payload + "." + encode(signature);
}

async function inviteMetadata(secret, value) {
  if (!webInviteConfigured(secret) || value.length > maxTokenLength || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{43}$/.test(value)) return null;
  try {
    const [payload, signature] = value.split(".");
    const bytes = decode(signature);
    if (encode(bytes) !== signature || !await crypto.subtle.verify("HMAC", await key(secret), bytes,
      encoder.encode(keyContext + payload))) return null;
    const details = JSON.parse(decoder.decode(decode(payload)));
    if (typeof details.title !== "string" || !details.title || !destinationPattern.test(details.destination)) return null;
    return {...details, image: safeImage(details.image) || defaultImage};
  } catch {
    return null;
  }
}

export async function createInviteArticle(secret, id, details, destination, subtitle, publicOrigin = origin) {
  if (!webInviteConfigured(secret)) throw Error("invite_secret_not_configured");
  const base = new URL(publicOrigin);
  if (base.protocol !== "https:" || base.origin !== publicOrigin) throw Error("invalid_invite_origin");
  const token = await inviteToken(secret, details, destination);
  const url = publicOrigin + "/invite/" + token;
  const text = "LOOPA";
  const image = safeImage(details.cover);
  return {
    type: "article",
    id: "web1_" + id,
    title: details.title || "Приглашение в LOOPA",
    description: subtitle,
    ...(image ? {thumbnail_url: image} : {}),
    input_message_content: {
      message_text: text,
      entities: [{type: "text_link", offset: 0, length: text.length, url}],
      link_preview_options: {url, prefer_large_media: true, show_above_text: true}
    },
    reply_markup: {inline_keyboard: [[{text: "Смотреть вместе", url: openUrl + "?startapp=" + destination, style: "primary"}]]}
  };
}

const escapeAttribute = value => value.replace(/[&<>"']/g, char => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
})[char]);

export async function serveInviteLanding(request, secret, publicOrigin = origin) {
  const {pathname} = new URL(request.url);
  const match = /^\/invite\/([A-Za-z0-9_.-]+)\/?$/.exec(pathname);
  if (!match) return new Response("Приглашение не найдено", {status: 404});
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response(null, {status: 405, headers: {Allow: "GET, HEAD"}});
  }
  const details = await inviteMetadata(secret, match[1]);
  if (!details) return new Response("Приглашение не найдено", {status: 404});

  const title = escapeAttribute(details.title);
  const image = escapeAttribute(details.image);
  const canonical = escapeAttribute(publicOrigin + "/invite/" + match[1]);
  const destination = openUrl + "?startapp=" + details.destination;
  const html = `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>${title} · LOOPA</title>
<meta property="og:title" content="${title}">
<meta property="og:description" content="${description}">
<meta property="og:image" content="${image}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="LOOPA">
<meta property="og:url" content="${canonical}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${title}">
<meta name="twitter:description" content="${description}">
<meta name="twitter:image" content="${image}">
<link rel="canonical" href="${canonical}">
<style>
:root { color-scheme: dark; font-family: system-ui, sans-serif; background: #101014; color: #f5f5f7; }
body { margin: 0; min-height: 100svh; display: grid; place-items: center; }
main { width: min(90vw, 38rem); padding: 2rem 0; }
p { color: #bfc0ca; } h1 { font-size: clamp(1.5rem, 5vw, 2.5rem); line-height: 1.12; }
img { display: block; width: 100%; aspect-ratio: 16/9; object-fit: cover; border-radius: .9rem; }
a { display: inline-block; background: #3275d6; color: white; text-decoration: none; border-radius: .65rem; padding: .8rem 1.1rem; font-weight: 650; }
</style>
</head>
<body>
<main>
<p>LOOPA</p>
<img src="${image}" alt="">
<h1>${title}</h1>
<p>${description}</p>
<a href="${destination}">Смотреть вместе</a>
</main>
</body>
</html>`;
  return new Response(request.method === "HEAD" ? null : html, {headers: {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "public, max-age=300",
    "Content-Security-Policy": "default-src 'none'; img-src https:; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff"
  }});
}
