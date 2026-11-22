const assert = require('node:assert/strict');
const { createHmac, webcrypto } = require('node:crypto');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = readFileSync(path.join(__dirname, '../supabase/functions/loopa-bot/index.js'), 'utf8')
  .replace(/^import .*\n/, '');
const token = 'fixture-bot-token';
const signature = createHmac('sha256', token).update('loopa.telegram.webhook.v1').digest('hex');

test('Telegram inline video search requires a signed update, caches results and respects quota', async () => {
  const env = {
    TELEGRAM_BOT_TOKEN: token, YOUTUBE_API_KEY: 'fixture-youtube-key',
    SUPABASE_SERVICE_ROLE_KEY: 'fixture-service-key', SUPABASE_URL: 'https://example.test'
  };
  const answers = [];
  let receive, searches = 0, quotaChecks = 0, allowed = true, rutubeAvailable = true;
  const consumed = new Set();
  const rtId = '1234567890abcdef1234567890abcdef';
  const verify = (body, proof) => receive(new Request('https://example.test/loopa-bot?action=verify-inline-rutube', {
    method: 'POST', headers: { 'X-Loopa-Inline-Proof': proof }, body
  }));
  vm.runInNewContext(source, {
    Deno: { env: { get: key => env[key] }, serve: handler => { receive = handler; } },
    crypto: webcrypto, TextEncoder, TextDecoder, URL, URLSearchParams, AbortSignal, Response,
    createClient: () => ({
      rpc(name, args) {
        if (name === 'loopa_consume_inline_rutube_ticket') {
          return { abortSignal: async () => {
            const fresh = !consumed.has(args.p_ticket);
            consumed.add(args.p_ticket);
            return { data: fresh };
          }};
        }
        quotaChecks++;
        assert.equal(name, 'loopa_take_inline_video_budget');
        assert.match(args.p_actor, /^[a-f0-9]{64}$/);
        return { abortSignal: async () => ({ data: allowed }) };
      }
    }),
    fetch: async (url, options) => {
      const endpoint = new URL(url);
      if (endpoint.hostname === 'www.googleapis.com') {
        searches++;
        assert.ok(['Аниме','Музыка'].includes(endpoint.searchParams.get('q')));
        assert.equal(endpoint.searchParams.get('videoEmbeddable'), 'true');
        return Response.json({ items: [
          { id: { videoId: 'K8vD4XbI2Ww' }, snippet: { title: 'Пример', channelTitle: 'Автор' } },
          { id: { videoId: '../unsafe' }, snippet: { title: 'Неверный идентификатор' } }
        ] });
      }
      if (endpoint.hostname === 'functions.yandexcloud.net') {
        if (!rutubeAvailable) return Response.json({}, { status: 503 });
        const proof = options.headers['X-Loopa-Inline-Proof'];
        assert.equal((await verify(options.body + ' ', proof)).status, 401);
        assert.equal((await verify(options.body, proof)).status, 200);
        assert.equal((await verify(options.body, proof)).status, 401);
        return Response.json({ items: [{ url: 'https://rutube.ru/video/' + rtId + '/',
          title: 'Ролик RUTUBE', author: 'Канал', image: 'https://pic.rutube.ru/cover.jpg' }] });
      }
      assert.equal(endpoint.pathname, '/bot' + token + '/answerInlineQuery');
      answers.push(JSON.parse(options.body));
      return Response.json({ ok: true, result: true });
    }
  });
  const update = (id, query, secret = signature) => receive(new Request('https://example.test/loopa-bot', {
    method: 'POST',
    headers: { 'X-Telegram-Bot-Api-Secret-Token': secret },
    body: JSON.stringify({ inline_query: { id, from: { id: 42 }, query } })
  }));
  assert.equal((await update('bad', 'Аниме', 'wrong')).status, 401);
  assert.equal(answers.length, 0);
  assert.equal((await update('query-1', ' Аниме ')).status, 200);
  assert.equal(answers[0].inline_query_id, 'query-1');
  assert.equal(answers[0].results.length, 2);
  assert.equal(answers[0].results[0].description, 'YouTube · Автор');
  assert.equal(answers[0].results[0].reply_markup.inline_keyboard[0][0].url,
    'https://t.me/LOOPAvideo_bot/loopa?startapp=yt_K8vD4XbI2Ww');

  assert.equal(answers[0].results[1].description, 'RUTUBE · Канал');
  assert.equal(answers[0].results[1].reply_markup.inline_keyboard[0][0].url,
    'https://t.me/LOOPAvideo_bot/loopa?startapp=rt_' + rtId);
  assert.equal(consumed.size, 1);

  await update('query-2', 'аниме');
  assert.deepEqual(answers[1].results, answers[0].results);
  await update('query-3', 'ан');
  assert.deepEqual(answers[2].results, []);
  assert.equal(quotaChecks, 1);

  allowed = false;
  await update('query-4', 'другой запрос');
  assert.deepEqual(answers[3].results, []);
  assert.equal(answers[3].cache_time, 0);
  assert.equal(searches, 1);
  assert.equal(quotaChecks, 2);

  allowed = true;
  rutubeAvailable = false;
  await update('query-5', 'Музыка');
  assert.deepEqual(answers[4].results, [answers[0].results[0]]);
  assert.equal(answers[4].cache_time, 10);
});
