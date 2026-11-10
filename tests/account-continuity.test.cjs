'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const helperSource = fs.readFileSync(path.join(root, 'assets/account-continuity.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261110120000_account_resume_points.sql'), 'utf8');
const setup = fs.readFileSync(path.join(root, 'supabase/ACCOUNT_CONTINUITY_SETUP.md'), 'utf8');
const telegramBridgePath = path.join(root, 'supabase/functions/telegram-miniapp-auth/index.js');
const telegramBridge = fs.readFileSync(
  fs.existsSync(telegramBridgePath) ? telegramBridgePath : path.join(root, 'index.js'),
  'utf8'
);
const sandbox = {};
sandbox.window = sandbox;
vm.runInNewContext(helperSource, sandbox, {filename: 'account-continuity.js'});
const continuity = sandbox.LOOPAAAccountContinuity;

test('merges local and cloud resume points by latest valid timestamp', () => {
  const now = 2_000_000_000_000;
  const local = [
    {video: 'youtube-a', pos: 120, duration: 900, savedAt: now - 3000},
    {video: 'rutube-b', pos: 75, duration: 600, savedAt: now - 500}
  ];
  const cloud = [
    {media: 'youtube-a', position_seconds: 150, duration_seconds: 900, updated_at: new Date(now - 1000).toISOString()},
    {media: 'rutube-b', position_seconds: 50, duration_seconds: 600, updated_at: new Date(now - 2000).toISOString()}
  ];
  const merged = continuity.mergeResumeCheckpoints(local, cloud, now);
  assert.equal(JSON.stringify(Array.from(merged, ({video, pos, cloud: synced}) => [video, pos, synced])), JSON.stringify([
    ['rutube-b', 75, false],
    ['youtube-a', 150, true]
  ]));
});

test('rejects malformed, future-dated and expired checkpoints', () => {
  const now = 2_000_000_000_000;
  const recent = {video: 'vk-video', pos: 30, duration: 100, savedAt: now - 10};
  assert.equal(continuity.normalizeResumeCheckpoint({...recent, pos: -1}, now), null);
  assert.equal(continuity.normalizeResumeCheckpoint({...recent, video: 'x'.repeat(2049)}, now), null);
  assert.equal(continuity.normalizeResumeCheckpoint({...recent, savedAt: now + 10 * 60 * 1000}, now), null);
  assert.equal(continuity.normalizeResumeCheckpoint({...recent, savedAt: now - continuity.CHECKPOINT_TTL_MS - 1}, now), null);
});

test('keeps the newest twenty distinct checkpoints', () => {
  const now = 2_000_000_000_000;
  const records = Array.from({length: 25}, (_, i) => ({
    video: `video-${i}`, pos: 30, duration: 200, savedAt: now - i
  }));
  const merged = continuity.mergeResumeCheckpoints(records, [], now);
  assert.equal(merged.length, 20);
  assert.equal(merged[0].video, 'video-0');
  assert.equal(merged.at(-1).video, 'video-19');
});

test('explains identity conflicts and disabled linking without suggesting account merging', () => {
  assert.match(continuity.identityLinkError({code: 'identity_already_exists'}, 'Google'), /уже привязан к другому профилю/);
  assert.match(continuity.identityLinkError({message: 'Identity is already linked to another user'}, 'Google'), /уже привязан к другому профилю/);
  assert.match(continuity.identityLinkError({code: 'identity_already_linked'}, 'Telegram'), /уже привязан к текущему профилю/);
  assert.match(continuity.identityLinkError({message: 'Manual linking is disabled'}, 'Telegram'), /Allow manual linking/);
  assert.equal(continuity.identityLinkError({message: 'network error'}, 'Google'), null);
});

test('the account page links the current identity and syncs only the signed-in owner’s resume point', () => {
  assert.match(html, /client\.auth\.linkIdentity\(\{provider:'google'/);
  assert.match(html, /client\.auth\.linkIdentity\(\{provider:TELEGRAM_PROVIDER/);
  assert.match(html, /client\.from\('loopa_resume_points'\)\.upsert/);
  assert.match(html, /\.eq\('user_id',userId\)/);
  assert.match(html, /guest-save-panel/);
  assert.match(html, /Регистрация созда[её]т новый профиль/i);
  assert.match(html, /не объединит их автоматически/i);
  assert.match(telegramBridge, /admin\.auth\.getUser\(match\[1\]\)/);
  assert.match(telegramBridge, /insert\(\{ telegram_id: telegramId, user_id: viewerId \}\)/);
});

test('resume point table is self-owned and unavailable to anonymous API-key clients', () => {
  assert.match(migration, /references auth\.users\(id\) on delete cascade/);
  assert.match(migration, /enable row level security/i);
  assert.match(migration, /auth\.uid\(\)\s*=\s*user_id/i);
  assert.match(migration, /revoke all.*from public,\s*anon/i);
  assert.match(migration, /grant select,\s*insert,\s*update,\s*delete.*to authenticated/i);
  assert.match(setup, /собственный домен.*платным дополнением/i);
  assert.match(setup, /SQL Editor/i);
});
