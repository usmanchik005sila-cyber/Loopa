import { Buffer } from "node:buffer";
import jpeg from "npm:jpeg-js@0.4.4";
import png from "npm:pngjs@7.0.0";
import { decode as webp, parseRiff, getWebpInfo } from "npm:@stacksjs/ts-webp@0.1.7";

const width = 960;
const height = 540;
const byteLimit = 2 * 1024 * 1024;
const cache = new Map();
const validSize = (w, h) => w > 0 && h > 0 && w <= 2048 && h <= 2048 && w * h <= 2_100_000;

async function readCover(source, fetchImage) {
  const response = await fetchImage(source, {
    headers: { Accept: "image/jpeg,image/png,image/webp" },
    redirect: "error", signal: AbortSignal.timeout(1500),
  });
  const type = response.headers.get("content-type")?.split(";")[0];
  if (!response.ok || !["image/jpeg", "image/png", "image/webp"].includes(type)
      || Number(response.headers.get("content-length")) > byteLimit || !response.body) {
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
  const file = bytes.subarray(0, size);
  if (type === "image/jpeg" && file[0] === 255 && file[1] === 216) {
    return jpeg.decode(file, { useTArray: true, maxResolutionInMP: 2.1, maxMemoryUsageInMB: 32 });
  }
  if (type === "image/png" && size >= 24 && file[0] === 137 && file[1] === 80) {
    const header = new DataView(file.buffer);
    if (validSize(header.getUint32(16), header.getUint32(20))) return png.PNG.sync.read(Buffer.from(file));
  }
  if (type === "image/webp") {
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

const wordmark = "iVBORw0KGgoAAAANSUhEUgAAAIwAAAAZCAYAAADja8bOAAAFXElEQVR42tWbW4hVVRjHf98omo6hGd7KMp3IW6goFnh5UPGlC+SIIlgZFkpKD12MoPIhn8IKUxIhMjLFgQoqMy0yy8ySsPDWdBPHLAdNxxjvmv57OOvgajXOOXvvc84sPzic/a2zv/9/n2//11p7XbZJagR6U9g+MrN7KZNJGgNMAMYB/YHuQDfgDNAEHAa2A18BG83s5NXAW2R+LwEngb+BeuA7oM7M9pY4x4uA57yiR8zsjSQYJqkLMNB9FrpvgOPA00ADsB/43cwulEEotcCzwEhXdArY4jiPAdVAT2Csu6G4G7kUeMXMTsTM20p+TwMb3HE10AsYAnT0wj8E5pnZnyXK9T5ggFe01czGZwHcqMvWQBlNUkdJr3t8hyXNkdShlZhRkjZ5MT9Kuu1q4C0mv5I6SZrlrilv+yX1LUG+xzq80/qv3Rq9YCSZpPc9rt8k3ZQgdpkX2yRpQMy8SfMraaCkZu/cdSXI+QqHNT8QzKKrQTALPJ4Lkm5PgbHZw/heUsdYedPkV9JLwY0dmCHfHSQdk9QoqUrSDg/3gCSLVjCSukk64fGsSIkzPEjo/Bh5MwhmYsDzWIac3+cwXnX+EwH2pGKxqqi8zQG6eP7baUDMbCew0yt6XFJVhLxpLRTUzRmwHnDfa913nRuZ5e2hmAUz3TtuArZlwPrAO64B7oyQN62dCfzOaVt04G6gwcy+daI/BGz2TquVdG10gpHUGRjuFe0xM2WA3B34Y2PizWhdA/9YSpxpbqheF5SvCcQ4PcYWZgTQ3vN/yohXH/h3RMabxcIH8j0l6o7y9h5wNmm3VGnB9Ar8oxnxwlrXOzLeLDbVOz4HfJaiRe9Hbga73sx2Bc9izYA/XB8nqSY2wXQL/FMZ8cJp+usi403bdU9wXUnelplZUwqo+wFroXVpqVsqqpWptGCqA/9siR8Mu0TGm1QoXSUtANYD7Vzxl8DzKSFneqOilmwDuSWgvD1YaE6mfYUF01yKJ/9W4psj423Nekh618Pr455b8vfkEvAa8IyZnU0hvlHAYGCHmf16hSmC85LecVMO+aH7RGBTLII5XuKaGQ4FmyLjLSS6qUE32QjsBbYCq8zsYAnmXuoKnLfGE0y+W4pGMIcCv2dGvDC+MTLe1uyAmd1SpumLdsAM5y6WtDhBeK2keVdaja+0YHa5/r+T8wdnxBsS+N9ExttWNtmNDP8gt5enkNW4qYd8yzcNWFmMMiuxluQv3jVLap8B68VgTWRkbLyVzq/jWeM45hV5/ojg/2yh3H9I0mxJh4s47+Hg4iZnSMzPHs7uGHnboEJWSzop6Zyk7gnidgf5qSn3sHpMC/MTLdlqctse8zYrZWLGAP4mppcj5a201bpphI8Tzt2sDvxZ5W5h6iXtLPLcGR7PJUmjE3JVSdruYWwtpotpK94KtzCfOvwpCeP6SrroX1/BfTJp/5Ck7u4GfJ0gZqnHdbCYaWkXZ5JWerGNkm6InbcSgpHUR9I/brNUhxTxnwfd0sRyCeYeF/NJghiTtNAJTZKOSnq0tR1skkZL2hLseOuXMCltwlshwTzpsJenjJ8dCGbV/4bVblf7IPfp7/12/RV2pZkbjncitwTfy+vTi34Fw20veEHSF+R2008Clrt5g83APi7v3u8NjOfyjvcjwBJgiZmdSZKUSvO6mj4IGBrkt6ukueTeUmhw8zLnUtzkPP4wYK4rbifpLuAXYL+ZXWytAgE3knuboUfw81RJ28itzteb2RFc01oqeytD7Rgm6SlJ69wo5C9J590Q+IB7dlgiaYqka0pYK8vKK2ltkbn7IeX1v1kAd3GB+JkJ7u/QfwH5u+UECw5qYgAAAABJRU5ErkJggg==";
const mark = png.PNG.sync.read(Buffer.from(wordmark, "base64"));

function compose(cover) {
  const data = new Uint8Array(width * height * 4);
  const scale = cover ? Math.max(width / cover.width, height / cover.height) : 1;
  const dx = cover ? (cover.width - width / scale) / 2 : 0;
  const dy = cover ? (cover.height - height / scale) / 2 : 0;
  for (let y = 0; y < height; y++) {
    const cy = Math.floor(y / scale + dy);
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      const cx = Math.floor(x / scale + dx);
      const j = cover ? (cy * cover.width + cx) * 4 : 0;
      const shade = cover ? 1 - 0.75 * Math.max(0, 1 - x / 415) * Math.max(0, 1 - y / 175) : 0;
      const alpha = cover ? cover.data[j + 3] / 255 : 0;
      const dark = 9 + 18 * Math.max(0, 1 - Math.hypot((x - 220) / 860, (y - 120) / 640));
      for (let c = 0; c < 3; c++) data[i + c] = (cover?.data[j + c] || 0) * shade * alpha + dark * (1 - alpha);
      data[i + 3] = 255;
    }
  }
  for (let y = 0; y < mark.height; y++) {
    for (let x = 0; x < mark.width; x++) {
      const alpha = mark.data[(y * mark.width + x) * 4 + 3] / 255;
      const i = ((y + 34) * width + x + 38) * 4;
      for (let c = 0; c < 3; c++) data[i + c] = data[i + c] * (1 - alpha) + 242 * alpha;
    }
  }
  return jpeg.encode({data, width, height}, 84).data;
}

let fallback;
export async function invitePhoto(source, fetchImage = fetch) {
  const existing = cache.get(source);
  if (existing?.until > Date.now()) return existing.photo;
  if (!source) return fallback ||= compose(null);
  if (cache.size >= 24) cache.delete(cache.keys().next().value);
  const entry = {until: Date.now() + 60_000};
  entry.photo = (async () => {
    try {
      const cover = await readCover(source, fetchImage);
      if (cover && validSize(cover.width, cover.height)) {
        const photo = compose(cover);
        entry.until = Date.now() + 3_600_000;
        return photo;
      }
    } catch { /* Timeouts and invalid covers use the dark card. */ }
    return fallback ||= compose(null);
  })();
  cache.set(source, entry);
  return entry.photo;
}
