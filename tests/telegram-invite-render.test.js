import assert from "node:assert/strict";
import jpeg from "npm:jpeg-js@0.4.4";
import { invitePhoto } from "../supabase/functions/loopa-bot/invite-photo.js";

function cover(bottom) {
  const width = 320, height = 180;
  const data = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      // Reproduce a stable grey decoder tail and its stepped first row.
      const tail = y >= 136 || (y >= 132 && x >= 80);
      const color = tail ? bottom : [35 + Math.floor(x / 8), 70, 161];
      data.set([...color, 255], (y * width + x) * 4);
    }
  }
  return jpeg.encode({width, height, data}, 96).data;
}

function preview(bytes, label, meta, length = bytes.byteLength) {
  return invitePhoto("https://pic.rtbcdn.ru/" + label + ".jpg", meta, () =>
    Promise.resolve(new Response(bytes, {
      headers: {"content-type": "image/jpeg", "content-length": String(length)},
    })));
}

const rutube = {title: "Космос такой тёмный не просто так… и это пугает", source: "RUTUBE", seconds: 8204};

Deno.test("The invitation recovers a RUTUBE cover with a grey tail already encoded into it", async () => {
  const damaged = cover([128, 128, 128]);
  const recovered = await preview(damaged, "decoder-grey", rutube);
  const fallback = await invitePhoto("", rutube);
  assert.notDeepEqual(recovered, fallback);
  const {data, width, height} = jpeg.decode(recovered, {useTArray: true});
  assert.deepEqual([width, height], [1280, 720]);
  const [r, , b] = data.subarray((490 * width + 1190) * 4, (490 * width + 1190) * 4 + 3);
  assert.ok(b > r + 15, "recovered card retains the blue source behind the gradient");
  const intact = await preview(cover([104, 112, 120]), "legitimate-muted-landscape", rutube);
  assert.notDeepEqual(intact, recovered, "a tinted low-contrast region is preserved");
});

Deno.test("An incomplete JPEG is never delivered as a valid cover", async () => {
  const bytes = cover([40, 71, 110]);
  const incomplete = bytes.subarray(0, bytes.length - 100);
  const fallback = await invitePhoto("", rutube);
  assert.deepEqual(await preview(incomplete, "truncated", rutube, bytes.length), fallback);
  const premature = new Uint8Array(incomplete.length + 2);
  premature.set(incomplete);
  premature.set([255, 217], incomplete.length);
  assert.deepEqual(await preview(premature, "premature-end", rutube), fallback);
});
