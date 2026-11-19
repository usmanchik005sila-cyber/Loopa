'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createHmac, webcrypto } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');

const source = readFileSync(join(__dirname, '../supabase/functions/telegram-miniapp-auth/index.js'), 'utf8');
const syntheticBotToken = 'synthetic-test-token';
const origin = 'https://loopacinema.ru';

function signedLaunch() {
  const fields = {
    auth_date: String(Math.floor(Date.now() / 1000)),
    query_id: 'synthetic-launch',
    user: JSON.stringify({ id: 1234 }),
  };
  const canonical = Object.keys(fields).sort().map(key => key + '=' + fields[key]).join('\n');
  const key = createHmac('sha256', 'WebAppData').update(syntheticBotToken).digest();
  return new URLSearchParams({
    ...fields,
    hash: createHmac('sha256', key).update(canonical).digest('hex'),
  });
}

function mockBridge({ linked = true, issueError = false, claimError = false } = {}) {
  const claims = new Set();
  let mintCount = 0;
  let handler;
  let link = linked ? { user_id: 'synthetic-profile' } : null;
  const admin = {
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: link }) }) }),
      insert: async row => { link = row; return {}; },
    }),
    rpc: async (name, args) => {
      assert.equal(name, 'loopa_claim_telegram_login');
      if (claimError) return { error: new Error('unavailable') };
      if (claims.has(args.p_fingerprint)) return { data: false };
      claims.add(args.p_fingerprint);
      return { data: true };
    },
    auth: { admin: {
      createUser: async () => ({ data: { user: { id: 'synthetic-profile' } } }),
      getUserById: async () => ({ data: { user: { email: 'synthetic@example.invalid' } } }),
      generateLink: async () => {
        mintCount++;
        if (issueError) throw new Error('ambiguous transport error');
        return { data: { properties: { hashed_token: 'mock-output' }, user: { id: 'synthetic-profile' } } };
      },
    } },
  };
  runInNewContext(source.replace(/^import .*;$/m, ''), {
    createClient: () => admin,
    crypto: webcrypto,
    Response,
    TextEncoder,
    URLSearchParams,
    Deno: {
      env: { get: key => key === 'TELEGRAM_BOT_TOKEN' ? syntheticBotToken : 'mock-setting' },
      serve: callback => { handler = callback; },
    },
  });
  return {
    request: async (action, fields) => {
      const response = await handler(new Request(origin, {
        method: 'POST',
        headers: { Origin: origin },
        body: JSON.stringify({ action, initData: fields.toString() }),
      }));
      return { code: response.status, body: await response.json() };
    },
    mintCount: () => mintCount,
  };
}

test('concurrent login and register share one claim for the same signed launch', async () => {
  const bridge = mockBridge();
  const fields = signedLaunch();
  const reordered = new URLSearchParams([...fields].reverse());
  const results = await Promise.all([bridge.request('login', fields), bridge.request('register', reordered)]);
  assert.deepEqual(results.map(result => result.code).sort(), [200, 409]);
  assert.equal(bridge.mintCount(), 1);
});

test('unlinked automatic login leaves the launch available for explicit registration', async () => {
  const bridge = mockBridge({ linked: false });
  const fields = signedLaunch();
  assert.equal((await bridge.request('login', fields)).body.status, 'unlinked');
  assert.equal((await bridge.request('register', fields)).body.status, 'login_ready');
  assert.equal(bridge.mintCount(), 1);
});

test('ambiguous issuance failure cannot mint again and unavailable claims block issuance', async () => {
  const fields = signedLaunch();
  const brokenIssuance = mockBridge({ issueError: true });
  assert.equal((await brokenIssuance.request('login', fields)).code, 503);
  assert.equal((await brokenIssuance.request('login', fields)).body.error, 'reopen_miniapp');
  assert.equal(brokenIssuance.mintCount(), 1);

  const brokenClaims = mockBridge({ claimError: true });
  assert.equal((await brokenClaims.request('login', fields)).code, 503);
  assert.equal(brokenClaims.mintCount(), 0);
});
