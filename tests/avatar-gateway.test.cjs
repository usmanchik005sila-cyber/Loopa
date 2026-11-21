const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

test('avatar gateway checks session and permission before fetching a private photo', async () => {
  const source = readFileSync('supabase/functions/loopa-avatar/index.js', 'utf8').replace(/^import.*\n/, '');
  const account = '00000000-0000-4000-8000-000000000511';
  let handler;
  let block = false;
  let downloads = 0;
  vm.runInNewContext(source, {
    URL, Response,
    Deno: { serve: fn => { handler = fn; }, env: { get: name => name } },
    createClient: (_url, key) => key === 'SUPABASE_ANON_KEY' ? {
      auth: { getUser: async token => token === 'local-fixture' ? { data: { user: { id: account } } } : { error: true } },
      rpc: async (_name, params) => ({ data: params.p_owner === account && !block }),
    } : { storage: { from: () => ({ download: async () => {
      downloads++;
      return { data: new Blob(['test image']) };
    } }) } },
  });
  const request = token => handler(new Request('https://fixture.example/avatar?path=' + account + '/telegram-avatar.jpg', {
    headers: { Origin: 'https://loopacinema.ru', Authorization: 'Bearer ' + token },
  }));
  assert.equal((await request('expired-fixture')).status, 401);
  let response = await request('local-fixture');
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Cache-Control'), 'private, no-store');
  assert.equal(response.headers.get('Content-Type'), 'image/jpeg');
  block = true;
  response = await request('local-fixture');
  assert.equal(response.status, 404);
  assert.equal(downloads, 1);
});
