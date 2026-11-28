const assert = require('node:assert/strict');
const test = require('node:test');

const secret = 'a'.repeat(64);
const fixtures = [
  ['yt_yQNEKTOL_oA', 'Earth from Space in 4K', 'https://i.ytimg.com/vi/yQNEKTOL_oA/hqdefault.jpg'],
  ['vk_-235231136_456239363', 'Камчатка. Ключевская группа вулканов', 'https://images.live.vkvideo.ru/public_video_stream/record/photo.jpg?size=large&source=video'],
  ['rt_6c0a5ad61bee69fbf190211090902a67', 'Космос такой тёмный не просто так… и это пугает', 'https://pic.rtbcdn.ru/video/cover.jpg'],
  ['room_abcdef123456', 'Комната LOOPA', ''],
];

test('native invitations use a real preview URL and keep the original Telegram deep link', async () => {
  const {createInviteArticle} = await import('../supabase/functions/loopa-bot/invite-web.mjs');
  const {default: worker} = await import('../invite-edge/worker.mjs');
  for (const [destination, title, cover] of fixtures) {
    const card = await createInviteArticle(secret, destination, {title, cover}, destination, 'Видео');
    const content = card.input_message_content;
    const url = content.link_preview_options.url;
    assert.equal(card.type, 'article');
    assert.equal(card.photo_url, undefined);
    assert.equal(card.photo_file_id, undefined);
    assert.equal(content.message_text, 'LOOPA');
    assert.deepEqual(content.entities, [{type: 'text_link', offset: 0, length: 5, url}]);
    assert.match(url, /^https:\/\/loopacinema\.ru\/invite\/[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
    assert.deepEqual(content.link_preview_options, {url, prefer_large_media: true, show_above_text: true});
    const target = 'https://t.me/LOOPAvideo_bot/loopa?startapp=' + destination;
    assert.deepEqual(card.reply_markup, {inline_keyboard: [[{text: 'Смотреть вместе', url: target, style: 'danger'}]]});

    const env = {LOOPA_INVITE_SIGNING_SECRET: secret};
    const response = await worker.fetch(new Request(url), env);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'text/html; charset=utf-8');
    const html = await response.text();
    assert.ok(html.includes('property="og:title" content="' + title + '"'));
    assert.ok(html.includes('property="og:description" content="Заходи, посмотрим вместе"'));
    assert.ok(html.includes('property="og:type" content="website"'));
    assert.ok(html.includes('property="og:site_name" content="LOOPA"'));
    assert.ok(html.includes('name="twitter:card" content="summary_large_image"'));
    assert.ok(html.includes('href="' + target + '"'));
    if (cover) assert.ok(html.includes('property="og:image" content="' + cover.replaceAll('&', '&amp;') + '"'));
    else assert.match(html, /property="og:image" content="https:\/\/[^"]+card-v4\.jpg\?action=invite_photo"/);
    assert.equal(await (await worker.fetch(new Request(url, {method: 'HEAD'}), env)).text(), '');
    assert.equal((await worker.fetch(new Request(url, {method: 'POST'}), env)).status, 405);
  }
});

test('landing rejects modified tokens and escapes signed metadata', async () => {
  const {createInviteArticle, serveInviteLanding} = await import('../supabase/functions/loopa-bot/invite-web.mjs');
  const article = await createInviteArticle(secret, 'safe', {title: '"><script>alert(1)</script>', cover: 'https://example.org/cover.jpg'}, 'yt_yQNEKTOL_oA');
  const url = article.input_message_content.link_preview_options.url;
  const html = await (await serveInviteLanding(new Request(url), secret)).text();
  assert.doesNotMatch(html, /<script|example\.org/);
  assert.match(html, /&quot;&gt;&lt;script&gt;/);
  for (const invalid of [url.replace('/invite/', '/invite/A'), url + 'X', 'https://loopacinema.ru/invite/' + 'a'.repeat(2000)]) {
    assert.equal((await serveInviteLanding(new Request(invalid), secret)).status, 404);
  }
  assert.equal((await serveInviteLanding(new Request(url), 'b'.repeat(64))).status, 404);
  await assert.rejects(createInviteArticle(secret, 'unsafe', {title: 'test'}, 'https://example.org'), /invalid_invite_destination/);
  const long = await createInviteArticle(secret, 'long', {
    title: '🎬'.repeat(220), cover: 'https://i.ytimg.com/' + 'x'.repeat(770)
  }, 'vk_-1234567891234567890_1234567891234567890');
  assert.ok(long.input_message_content.link_preview_options.url.length < 2048);
});
