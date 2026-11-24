import { Buffer } from "node:buffer";
import jpeg from "npm:jpeg-js@0.4.4";
import png from "npm:pngjs@7.0.0";
import { decode as webp, parseRiff, getWebpInfo } from "npm:@stacksjs/ts-webp@0.1.7";

import { atlasPng, glyphs } from "./invite-font.js";

const width = 1280;
const height = 720;
const byteLimit = 2 * 1024 * 1024;
const cache = new Map();
const validSize = (w, h) => w > 0 && h > 0 && w <= 2048 && h <= 2048 && w * h <= 2_100_000;

async function readCover(source, fetchImage) {
  const response = await fetchImage(source, {
    headers: { Accept: "image/jpeg,image/png,image/webp" },
    redirect: "error", signal: AbortSignal.timeout(1500),
  });
  const type = response.headers.get("content-type")?.split(";")[0];
  const length = Number(response.headers.get("content-length"));
  if (!response.ok || !["image/jpeg", "image/png", "image/webp"].includes(type)
      || length > byteLimit || !response.body) {
    await response.body?.cancel();
    return null;
  }

  const reader = response.body.getReader();
  const bytes = new Uint8Array(byteLimit);
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (size + value.length > byteLimit) {
      await reader.cancel();
      return null;
    }
    bytes.set(value, size);
    size += value.length;
  }
  if (length && !response.headers.get("content-encoding") && size !== length) return null;
  const file = bytes.subarray(0, size);
  if (type === "image/jpeg" && file[0] === 255 && file[1] === 216
      && file[size - 2] === 255 && file[size - 1] === 217) {
    return jpeg.decode(file, { useTArray: true, tolerantDecoding: false, maxResolutionInMP: 2.1, maxMemoryUsageInMB: 32 });
  }
  if (type === "image/png" && size >= 24 && file[0] === 137 && file[1] === 80) {
    const header = new DataView(file.buffer);
    if (validSize(header.getUint32(16), header.getUint32(20))) return png.PNG.sync.read(Buffer.from(file));
  }
  if (type === "image/webp" && size >= 12 && new DataView(file.buffer).getUint32(4, true) + 8 === size) {
    const chunks = parseRiff(file);
    const frames = chunks.filter(chunk => ["VP8 ", "VP8L"].includes(chunk.fourCC));
    if (frames.length !== 1 || chunks.some(chunk => chunk.data.length !== chunk.size)) return null;
    const canvas = getWebpInfo(chunks);
    const frame = getWebpInfo(frames);
    if (!canvas.hasAnimation && validSize(frame.width, frame.height)
        && canvas.width === frame.width && canvas.height === frame.height) return webp(file);
  }
  return null;
}

function decoderGrayShare({data, width}, y) {
  let gray = 0, samples = 0;
  const step = Math.max(1, Math.floor(width / 90));
  const right = Math.floor(width * 0.98);
  for (let x = Math.ceil(width * 0.02); x < right; x += step) {
    const i = (y * width + x) * 4;
    const r = data[i], g = data[i + 1], b = data[i + 2];
    if (r >= 125 && r <= 131 && r === g && g === b && data[i + 3] === 255) gray++;
    samples++;
  }
  return samples ? gray / samples : 0;
}

function repairRutubeCover(image) {
  const {height, width} = image;
  const step = Math.max(1, Math.floor(height / 180));
  let y = height - 1;
  // A recompressed, incomplete JPEG can have a valid checksum and still contain a decoder-gray tail.
  while (y >= 0 && decoderGrayShare(image, y) >= 0.96) y -= step;
  if (height - 1 - y < Math.max(14, height / 10)) return image;
  // The first incomplete MCU row may have a mixture of source and decoder pixels.
  while (y >= 0 && decoderGrayShare(image, y) >= 0.12) y -= step;
  const cleanHeight = y + 1;
  if (cleanHeight < height * 0.55) return null;
  return {...image, height: cleanHeight, data: image.data.subarray(0, width * cleanHeight * 4)};
}

const atlas = png.PNG.sync.read(Buffer.from(atlasPng, "base64"));
const edge = 62;
const titleWidth = width - 2 * edge - 25;
const leftShade = Float32Array.from({length: width}, (_, x) =>
  Math.max(0, 1 - (Math.max(0, x - 215) / 340) ** 1.3));
const backdropX = Float32Array.from({length: width}, (_, x) => ((x - 338) / 1000) ** 2);

function glyph(face, character) {
  return glyphs[face][character] ?? glyphs.title["□"];
}

function textWidth(face, text, scale = 1) {
  return Array.from(text).reduce((sum, character) => sum + glyph(face, character)[6], 0) * scale;
}

function wrapTitle(text, scale) {
  if (!text) return [];
  const lines = [];
  let line = "";
  for (const word of text.split(" ")) {
    if (line && textWidth("title", line + " " + word, scale) > titleWidth) {
      lines.push(line);
      line = "";
    }
    for (const character of (line ? " " : "") + word) {
      if (line && textWidth("title", line + character, scale) > titleWidth) {
        lines.push(line);
        line = "";
      }
      line += character;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function titleLayout(title) {
  const single = wrapTitle(title, 1);
  if (single.length < 2) return {lines: single, scale: 1};
  const oneLineScale = titleWidth / textWidth("title", title);
  if (oneLineScale >= 55 / 64) return {lines: [title], scale: oneLineScale};
  const scale = 58 / 64;
  const lines = wrapTitle(title, scale);
  if (lines.length === 2) {
    const words = title.split(" ");
    let balance = Infinity;
    for (let i = 1; i < words.length; i++) {
      const left = words.slice(0, i).join(" ");
      const right = words.slice(i).join(" ");
      const a = textWidth("title", left, scale);
      const b = textWidth("title", right, scale);
      if (!/^[-–—]/.test(right) && Math.max(a, b) <= titleWidth && Math.abs(a - b) < balance) {
        balance = Math.abs(a - b);
        lines[0] = left;
        lines[1] = right;
      }
    }
  }
  if (lines.length > 3) {
    lines.length = 3;
    let last = Array.from(lines[2].trimEnd());
    while (textWidth("title", last.join("") + "…", scale) > titleWidth) last.pop();
    lines[2] = last.join("").trimEnd().replace(/[ ,:–—-]+$/, "") + "…";
  }
  return {lines, scale};
}

function blend(data, index, color, alpha) {
  const inverse = 1 - alpha;
  data[index] = data[index] * inverse + color[0] * alpha;
  data[index + 1] = data[index + 1] * inverse + color[1] * alpha;
  data[index + 2] = data[index + 2] * inverse + color[2] * alpha;
}

function drawText(data, face, text, x, baseline, color, scale = 1) {
  for (const character of text) {
    const [sx, sy, sw, sh, left, top, advance] = glyph(face, character);
    const originX = Math.round(x + left * scale);
    const originY = Math.round(baseline + top * scale);
    for (let y = 0; y < sh * scale; y++) {
      const row = (sy + Math.floor(y / scale)) * atlas.width;
      for (let x = 0; x < sw * scale; x++) {
        const alpha = atlas.data[(row + sx + Math.floor(x / scale)) * 4] / 255;
        if (alpha) blend(data, ((originY + y) * width + originX + x) * 4, color, alpha);
      }
    }
    x += advance * scale;
  }
}

function badge(data, label) {
  if (!label) return;
  const radius = 30;
  const badgeWidth = Math.ceil(textWidth("detail", label, 0.9)) + 54;
  const start = width - edge - badgeWidth;
  for (let y = 48; y < 108; y++) {
    const inset = Math.ceil(radius - Math.sqrt(radius ** 2 - (y - 77.5) ** 2));
    for (let x = start + inset; x < width - edge - inset; x++) {
      blend(data, (y * width + x) * 4, [14,16,23], 0.62);
    }
  }
  drawText(data, "detail", label, start + 27, 87, [240,241,245], 0.9);
}

function durationLabel(seconds) {
  if (!seconds) return "";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor(seconds / 60) % 60;
  const s = String(seconds % 60).padStart(2, "0");
  return h ? h + ":" + String(m).padStart(2, "0") + ":" + s : m + ":" + s;
}

function compose(cover, {title, source, seconds}) {
  const text = titleLayout(title);
  const step = Math.floor(64 * text.scale * 1.1);
  const firstBaseline = 615 - Math.max(0, text.lines.length - 1) * step;
  const data = new Uint8Array(width * height * 4);
  const scale = cover ? Math.max(width / cover.width, height / cover.height) : 1;
  const dx = cover ? (cover.width - width / scale) / 2 : 0;
  const dy = cover ? (cover.height - height / scale) / 2 : 0;
  const coverX = Int32Array.from({length: width}, (_, x) => Math.floor(x / scale + dx) * 4);
  const fadeStart = Math.max(145, firstBaseline - 250);
  for (let y = 0; y < height; y++) {
    const cy = cover ? Math.floor(y / scale + dy) * cover.width * 4 : 0;
    const shade = Math.max(0, Math.min(1, (y - fadeStart) / (636 - fadeStart)));
    const footer = 0.985 * shade ** 2 * (3 - 2 * shade);
    const top = 0.38 * Math.max(0, 1 - y / 192) ** 2;
    const corner = 0.95 * Math.max(0, 1 - Math.max(0, y - 83) / 115) ** 2;
    const backdropY = ((y - 80) / 780) ** 2;
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      const j = cy + coverX[x];
      const fade = 1 - Math.max(footer, top, corner * leftShade[x]);
      const alpha = cover ? cover.data[j + 3] / 255 * fade : 0;
      const dark = 9 + (cover ? 0 : 27 * Math.max(0, 1 - backdropX[x] - backdropY));
      data[i] = alpha ? cover.data[j] * alpha + dark * (1 - alpha) : dark;
      data[i + 1] = alpha ? cover.data[j + 1] * alpha + (dark + 1) * (1 - alpha) : dark + 1;
      data[i + 2] = alpha ? cover.data[j + 2] * alpha + (dark + 4) * (1 - alpha) : dark + 4;
      data[i + 3] = 255;
    }
  }
  drawText(data, "logo", "LOOPA", edge, 92, [240,241,245]);
  const duration = durationLabel(seconds);
  badge(data, [source, duration].filter(Boolean).join("  ·  "));
  text.lines.forEach((line, index) =>
    drawText(data, "title", line, edge, firstBaseline + index * step, [247,247,248], text.scale));
  drawText(data, "detail", "Ближе, даже на расстоянии", edge, 665, [211,214,222]);
  return jpeg.encode({data, width, height}, 87).data;
}

export async function invitePhoto(cover, metadata = {}, fetchImage = fetch) {
  const title = typeof metadata.title === "string" ? metadata.title.normalize("NFC").trim().replace(/\s+/g, " ") : "";
  const source = ["YouTube", "VK Видео", "RUTUBE"].includes(metadata.source) ? metadata.source : "";
  const seconds = Number.isSafeInteger(metadata.seconds) && metadata.seconds > 0 ? metadata.seconds : 0;
  const details = {title, source, seconds};
  const key = JSON.stringify([cover, title, source, seconds]);
  const existing = cache.get(key);
  if (existing?.until > Date.now()) return existing.photo;
  if (cache.size >= 24) cache.delete(cache.keys().next().value);
  const entry = {until: Date.now() + (cover ? 60_000 : 3_600_000)};
  entry.photo = (async () => {
    if (cover) {
      try {
        const decoded = await readCover(cover, fetchImage);
        if (decoded && validSize(decoded.width, decoded.height) && decoded.data.length === decoded.width * decoded.height * 4) {
          const image = source === "RUTUBE" ? repairRutubeCover(decoded) : decoded;
          if (!image) return compose(null, details);
          const photo = compose(image, details);
          entry.until = Date.now() + 3_600_000;
          return photo;
        }
      } catch { /* Timeouts and invalid covers use the dark card. */ }
    }
    return compose(null, details);
  })();
  cache.set(key, entry);
  return entry.photo;
}
