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

function mockBridge({ linked = true, issueError = false, claimError = false, actionBudget = { data: 0 }, linkFailure = "" } = {}) {
  const claims = new Set();
  let mintCount = 0;
  const authCalls = [];
  const budgetCalls = [];
  let handler;
  let link = linked ? { user_id: 'synthetic-profile' } : null;
  let pending;
  let email = linked ? 'synthetic@example.invalid' : '';
  const linkCalls = [];
  const emailUpdates = [];
  const admin = {
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: link }) }) }),
      insert: async row => { link = row; return {}; },
    }),
    rpc: async (name, args) => {
      if (name === 'loopa_take_telegram_action_budget') {
        budgetCalls.push({ ...args });
        return actionBudget;
      }
      if (name === 'loopa_telegram_link_step') {
        const { p_user_id: userId, p_finish: finish } = args;
        linkCalls.push({ userId, finish });
        if (link?.user_id === userId) return { data: 'already_linked' };
        if (pending && pending !== userId) return { data: 'telegram_already_linked_to_another_profile' };
        if (!finish) {
          pending = userId;
          return { data: 'reserved' };
        }
        if (linkFailure === 'before_finish') {
          linkFailure = '';
          return { error: new Error('unavailable') };
        }
        assert.equal(pending, userId);
        assert.ok(email);
        pending = undefined;
        link = { user_id: userId };
        if (linkFailure === 'after_finish') {
          linkFailure = '';
          return { error: new Error('response lost') };
        }
        return { data: 'linked' };
      }
      assert.equal(name, 'loopa_claim_telegram_login');
      if (claimError) return { error: new Error('unavailable') };
      if (claims.has(args.p_fingerprint)) return { data: false };
      claims.add(args.p_fingerprint);
      return { data: true };
    },
    auth: { getUser: async token => {
      authCalls.push('getUser');
      return { data: { user: { id: token === 'other-session' ? 'other-profile' : 'synthetic-profile' } } };
    }, admin: {
      createUser: async options => {
        email = options.email;
        return { data: { user: { id: 'synthetic-profile' } } };
      },
      getUserById: async id => ({ data: { user: { id, email } } }),
      updateUserById: async (id, update) => {
        emailUpdates.push(id);
        assert.equal(pending, id);
        if (linkFailure === 'before_email_update') {
          linkFailure = '';
          return { error: new Error('update not applied') };
        }
        email = update.email;
        if (linkFailure === 'after_email_update') {
          linkFailure = '';
          return { error: new Error('response lost') };
        }
        return {};
      },
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
    request: async (action, fields, bearer = '') => {
      const response = await handler(new Request(origin, {
        method: 'POST',
        headers: { Origin: origin, ...(bearer ? { Authorization: 'Bearer ' + bearer } : {}) },
        body: JSON.stringify({ action, initData: fields.toString() }),
      }));
      return { code: response.status, headers: response.headers, body: await response.json() };
    },
    mintCount: () => mintCount,
    budgetCalls,
    authCalls,
    linkCalls,
    emailUpdates,
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

test('each action stops before account access when its Telegram budget is exhausted', async () => {
  const bridge = mockBridge({ actionBudget: { data: 10 } });
  const fields = signedLaunch();
  for (const action of ['login', 'register', 'link', 'status']) {
    const response = await bridge.request(action, fields, 'synthetic-session');
    assert.equal(response.code, 429);
    assert.equal(response.body.error, 'telegram_rate_limited');
    assert.equal(response.headers.get('Retry-After'), '10');
    assert.deepEqual(bridge.budgetCalls.at(-1), { p_telegram_id: '1234', p_action: action });
  }
  assert.deepEqual(bridge.authCalls, []);
  assert.equal(bridge.mintCount(), 0);
});

test('failed budget check blocks login and missing authorization spends no link budget', async () => {
  const bridge = mockBridge({ actionBudget: { error: new Error('unavailable') } });
  const fields = signedLaunch();
  assert.equal((await bridge.request('link', fields)).code, 401);
  assert.equal(bridge.budgetCalls.length, 0);
  assert.equal((await bridge.request('login', fields)).code, 503);
  assert.equal(bridge.mintCount(), 0);
});

test('allowed status and link requests still verify the Supabase session', async () => {
  const bridge = mockBridge();
  const fields = signedLaunch();
  assert.equal((await bridge.request('status', fields, 'synthetic-session')).body.status, 'linked');
  assert.equal((await bridge.request('link', fields, 'synthetic-session')).body.status, 'already_linked');
  assert.deepEqual(bridge.authCalls, ['getUser', 'getUser']);
});

for (const failure of ['before_email_update', 'after_email_update', 'before_finish', 'after_finish']) {
  test('link retry recovers after ' + failure, async () => {
    const bridge = mockBridge({ linked: false, linkFailure: failure });
    const fields = signedLaunch();
    assert.equal((await bridge.request('link', fields, 'synthetic-session')).code, 503);
    if (failure !== 'after_finish') {
      assert.equal((await bridge.request('login', fields)).body.status, 'unlinked');
      assert.equal((await bridge.request('link', fields, 'other-session')).code, 409);
    }
    const retried = await bridge.request('link', fields, 'synthetic-session');
    assert.equal(retried.body.status, failure === 'after_finish' ? 'already_linked' : 'linked');
    assert.deepEqual(bridge.emailUpdates,
      Array(failure === 'before_email_update' ? 2 : 1).fill('synthetic-profile'));
    assert.equal((await bridge.request('login', fields)).body.status, 'login_ready');
  });
}
