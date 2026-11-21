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

function signedLaunch(profile = {}, authDate = Math.floor(Date.now() / 1000)) {
  const fields = {
    auth_date: String(authDate),
    query_id: 'synthetic-launch',
    user: JSON.stringify({ id: 1234, ...profile }),
  };
  const canonical = Object.keys(fields).sort().map(key => key + '=' + fields[key]).join('\n');
  const key = createHmac('sha256', 'WebAppData').update(syntheticBotToken).digest();
  return new URLSearchParams({
    ...fields,
    hash: createHmac('sha256', key).update(canonical).digest('hex'),
  });
}

function mockBridge({ linked = true, issueError = false, claimError = false, actionBudget = { data: 0 }, linkFailure = '', registrationFailure = '', repairCandidate = false, telegramFetch = async () => Response.json({ ok: true, result: { photos: [] } }) } = {}) {
  const claims = new Set();
  let mintCount = 0;
  const authCalls = [];
  const budgetCalls = [];
  let handler;
  let link = linked ? { user_id: 'synthetic-profile' } : null;
  let pending;
  let candidate;
  let createCount = 0;
  let createdOptions;
  const uploads = [];
  const repairCalls = [];
  let email = linked ? 'synthetic@example.invalid' : '';
  const linkCalls = [];
  const emailUpdates = [];
  const admin = {
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: link }) }) }) }),
    rpc: async (name, args) => {
      if (name === 'loopa_repair_telegram_profile') {
        repairCalls.push({...args});
        return { data: args.p_apply ? { imported:true } : { eligible:true, avatar_missing:true } };
      }
      if (name === 'loopa_take_telegram_action_budget') {
        budgetCalls.push({ ...args });
        return actionBudget;
      }
      if (name === 'loopa_complete_telegram_registration') {
        if (pending) return { data: { status: 'link_pending' } };
        if (link) return { data: { status: 'linked', user_id: link.user_id } };
        if (!candidate) return { data: { status: 'missing' } };
        link = { user_id: candidate };
        if (registrationFailure === 'after_link_commit') {
          registrationFailure = '';
          return { error: new Error('response lost') };
        }
        return { data: { status: 'linked', user_id: candidate } };
      }
      if (name === 'loopa_telegram_link_step') {
        const { p_user_id: userId, p_finish: finish } = args;
        linkCalls.push({ userId, finish });
        if (link?.user_id === userId) return { data: 'already_linked' };
        if (pending && pending !== userId) return { data: 'telegram_already_linked_to_another_profile' };
        if (!finish) {
          if (candidate) return { data: 'telegram_registration_pending' };
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
    storage: { from: bucket => ({
      upload: async (path, image, options) => { uploads.push({ bucket, path, image, options }); return {}; },
    }) },
    auth: { getUser: async token => {
      authCalls.push('getUser');
      return { data: { user: { id: token === 'other-session' ? 'other-profile' : 'synthetic-profile',
        app_metadata: repairCandidate ? { loopa_telegram_registration:'1234' } : {},
      } } };
    }, admin: {
      createUser: async options => {
        assert.equal(options.app_metadata.loopa_telegram_registration, '1234');
        assert.equal(++createCount, 1);
        createdOptions = options;
        email = options.email;
        candidate = 'synthetic-profile';
        if (registrationFailure === 'after_auth_commit') {
          registrationFailure = '';
          throw new Error('response lost');
        }
        return { data: { user: { id: candidate } } };
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
    AbortSignal,
    fetch: telegramFetch,
    TextEncoder,
    TextDecoder,
    URL,
    URLSearchParams,
    Deno: {
      env: { get: key => key === 'TELEGRAM_BOT_TOKEN' ? syntheticBotToken : 'mock-setting' },
      serve: callback => { handler = callback; },
    },
  });
  return {
    responseFor: request => handler(request),
    request: async (action, fields, bearer = '') => {
      const response = await handler(new Request(origin, {
        method: 'POST',
        headers: { Origin: origin, ...(bearer ? { Authorization: 'Bearer ' + bearer } : {}) },
        body: JSON.stringify({ action, initData: fields.toString() }),
      }));
      return { code: response.status, headers: response.headers, body: await response.json() };
    },
    mintCount: () => mintCount,
    createCount: () => createCount,
    createdOptions: () => createdOptions,
    uploads,
    repairCalls,
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

test('an expired Telegram launch asks for a fresh launch before touching the account', async () => {
  const bridge = mockBridge({linked: false});
  const expired = signedLaunch({}, Math.floor(Date.now() / 1000) - 601);
  for (const action of ['login', 'register']) {
    const response = await bridge.request(action, expired);
    assert.equal(response.code, 401);
    assert.equal(response.body.error, 'reopen_miniapp');
  }
  assert.deepEqual(bridge.budgetCalls, []);
  assert.deepEqual(bridge.authCalls, []);
  assert.equal(bridge.createCount(), 0);
  assert.equal(bridge.mintCount(), 0);
});

test('ambiguous issuance failure cannot mint again and unavailable claims block issuance', async () => {
  const fields = signedLaunch();
  const brokenIssuance = mockBridge({ issueError: true });
  const failedIssuance = await brokenIssuance.request('login', fields);
  assert.equal(failedIssuance.code, 503);
  assert.equal(failedIssuance.body.error, 'reopen_miniapp');
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

for (const failure of ['after_auth_commit', 'after_link_commit']) {
  test('registration retries reuse the account after ' + failure, async () => {
    const bridge = mockBridge({ linked: false, registrationFailure: failure });
    const fields = signedLaunch();
    assert.equal((await bridge.request('register', fields)).code, 503);
    if (failure === 'after_auth_commit') {
      assert.equal((await bridge.request('link', fields, 'other-session')).body.error,
        'telegram_registration_pending');
    }
    assert.equal((await bridge.request('register', fields)).body.status, 'login_ready');
    assert.equal(bridge.createCount(), 1);
    assert.equal(bridge.mintCount(), 1);
  });
}

test('registration leaves a pending explicit link with its owner', async () => {
  const bridge = mockBridge({ linked: false, linkFailure: 'before_finish' });
  const fields = signedLaunch();
  assert.equal((await bridge.request('link', fields, 'synthetic-session')).code, 503);
  assert.equal((await bridge.request('register', fields)).body.error, 'telegram_link_pending');
  assert.equal(bridge.createCount(), 0);
  assert.equal((await bridge.request('link', fields, 'synthetic-session')).body.status, 'linked');
});

test('request stream is capped by bytes without requiring Content-Length', async () => {
  const bridge = mockBridge();
  const chunks = Array(3).fill(new TextEncoder().encode('я'.repeat(3000)));
  let cancelled = false;
  const body = new ReadableStream({
    pull(controller) {
      controller.enqueue(chunks.shift());
      if (!chunks.length) controller.close();
    },
    cancel() { cancelled = true; },
  });
  const response = await bridge.responseFor(new Request(origin, {
    method: 'POST', headers: { Origin: origin }, body, duplex: 'half',
  }));
  assert.equal(response.status, 413);
  assert.ok(cancelled || chunks.length === 0);
  assert.equal(bridge.budgetCalls.length, 0);
});

test('an existing Telegram binding confirms only the matching Supabase session', async () => {
  const bridge = mockBridge();
  const fields = signedLaunch();
  const owner = await bridge.request('status', fields, 'synthetic-session');
  assert.deepEqual(owner.body, { status: 'linked' });

  const anotherProfile = await bridge.request('status', fields, 'other-session');
  assert.deepEqual(anotherProfile.body, { status: 'claimed_by_another_profile' });
  assert.equal(bridge.mintCount(), 0);
});

test('registration imports signed profile fields and copies a JPEG only from the Telegram Bot API', async () => {
  const visited = [];
  const bridge = mockBridge({ linked: false, telegramFetch: async url => {
    const endpoint = new URL(url);
    assert.equal(endpoint.hostname, 'api.telegram.org');
    visited.push(endpoint.pathname.split('/').at(-1));
    if (url.endsWith('/getUserProfilePhotos')) {
      return Response.json({ ok: true, result: { photos: [[{ file_id: 'fixture', width: 160, height: 160 }]] } });
    }
    if (url.endsWith('/getFile')) return Response.json({ ok: true, result: { file_path: 'photos/photo.jpg' } });
    return new Response(Uint8Array.of(255,216,255,224,255,217));
  } });
  const fields = signedLaunch({ first_name: '  Маша ', last_name: ' Иванова', username: 'Masha_01',
    photo_url: 'https://example.invalid/ignored.jpg' });
  assert.equal((await bridge.request('register', fields)).body.status, 'login_ready');
  assert.equal(bridge.createdOptions().user_metadata.display_name, 'Маша Иванова');
  assert.equal(bridge.createdOptions().app_metadata.loopa_telegram_username, 'masha_01');
  assert.equal(bridge.uploads.length, 1);
  assert.equal(bridge.uploads[0].bucket, 'avatars');
  assert.equal(bridge.uploads[0].path, 'synthetic-profile/telegram-avatar.jpg');
  assert.equal(bridge.uploads[0].options.upsert, false);
  assert.deepEqual(visited, ['getUserProfilePhotos', 'getFile', 'photo.jpg']);

  assert.equal((await bridge.request('status', fields, 'synthetic-session')).body.status, 'linked');
  assert.equal(bridge.uploads.length, 1);
  assert.equal(bridge.createCount(), 1);
});

test('a long username and unavailable avatar do not block Telegram registration', async () => {
  const bridge = mockBridge({ linked: false, telegramFetch: async () => { throw new Error('fixture offline'); } });
  const fields = signedLaunch({ username: 'very_long_telegram_username' });
  assert.equal((await bridge.request('register', fields)).body.status, 'login_ready');
  assert.equal(bridge.createdOptions().app_metadata.loopa_telegram_username, null);
  assert.equal(bridge.uploads.length, 0);
});

test('an existing placeholder imports once through the verified session, including a signed Telegram photo', async () => {
  const visited = [];
  const bridge = mockBridge({ repairCandidate:true, telegramFetch:async (url, init) => {
    visited.push(String(url));
    assert.equal(init.redirect,'error');
    return new Response(Uint8Array.of(255,216,255,224,255,217));
  } });
  const fields = signedLaunch({ first_name:'Алексей', username:'alex_test',
    photo_url:'https://t.me/i/userpic/320/fixture.jpg' });
  assert.equal((await bridge.request('status',fields,'other-session')).body.status,'claimed_by_another_profile');
  assert.equal(bridge.repairCalls.length,0);
  assert.equal((await bridge.request('status',fields,'synthetic-session')).body.status,'linked');
  assert.deepEqual(visited,['https://t.me/i/userpic/320/fixture.jpg']);
  assert.equal(bridge.repairCalls.length,2);
  assert.equal(bridge.repairCalls[1].p_display_name,'Алексей');
  assert.equal(bridge.repairCalls[1].p_username,'alex_test');
  assert.equal(bridge.uploads[0].path,'synthetic-profile/telegram-avatar.jpg');
});
