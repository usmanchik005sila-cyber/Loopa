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
  let receive, searches = 0, quotaChecks = 0, allowed = true;
  vm.runInNewContext(source, {
    Deno: { env: { get: key => env[key] }, serve: handler => { receive = handler; } },
    crypto: webcrypto, TextEncoder, URL, URLSearchParams, AbortSignal, Response,
    createClient: () => ({
      rpc(name, args) {
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
        assert.equal(endpoint.searchParams.get('q'), 'Аниме');
        assert.equal(endpoint.searchParams.get('videoEmbeddable'), 'true');
        return Response.json({ items: [
          { id: { videoId: 'K8vD4XbI2Ww' }, snippet: { title: 'Пример', channelTitle: 'Автор' } },
          { id: { videoId: '../unsafe' }, snippet: { title: 'Неверный идентификатор' } }
        ] });
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
  assert.equal(answers[0].results.length, 1);
  assert.equal(answers[0].results[0].description, 'YouTube · Автор');
  assert.equal(answers[0].results[0].reply_markup.inline_keyboard[0][0].url,
    'https://t.me/LOOPAvideo_bot/loopa?startapp=yt_K8vD4XbI2Ww');

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
});
