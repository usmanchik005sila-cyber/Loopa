const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const root = path.resolve(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/20261110180000_user_safety_requests.sql"),
  "utf8",
);
const dmDefaultMigration = fs.readFileSync(
  path.join(root, "supabase/migrations/20261110190000_dm_policy_default_everyone.sql"),
  "utf8",
);
const setup = fs.readFileSync(path.join(root, "supabase/USER_SAFETY_SETUP.md"), "utf8");

test("report and deletion queues are closed to regular users", () => {
  for (const table of ["loopa_user_reports_v1", "loopa_account_deletion_requests_v1"]) {
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`, "i"));
    assert.match(
      migration,
      new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`, "i"),
    );
    assert.doesNotMatch(migration, new RegExp(`create policy[^;]*${table}`, "is"));
  }
  assert.match(migration, /grant execute on function public\.loopa_submit_user_report[\s\S]*?to authenticated/i);
  assert.match(migration, /grant execute on function public\.loopa_request_account_deletion[\s\S]*?to authenticated/i);
});

test("report RPC binds the reporter to auth and validates referenced messages", () => {
  assert.match(migration, /v_actor uuid := auth\.uid\(\)/i);
  assert.match(migration, /m\.id::text = p_message_ref/i);
  assert.match(migration, /v_recipient <> v_actor/i);
  assert.match(migration, /report_rate_limit/i);
  assert.match(migration, /char_length\(p_details\) > 500/i);
  assert.match(migration, /set search_path = ''/i);
  assert.doesNotMatch(migration, /message_body|reported_message_text/i);
});

test("new profiles allow DMs from everyone and keep the privacy choice editable", () => {
  assert.match(migration, /add column if not exists dm_policy text default 'everyone'/i);
  assert.match(migration, /alter column dm_policy set default 'everyone'/i);
  assert.match(migration, /new\.dm_policy := 'everyone'/i);
  assert.match(dmDefaultMigration, /alter column dm_policy set default 'everyone'/i);
  assert.match(dmDefaultMigration, /new\.dm_policy := 'everyone'/i);
  assert.match(dmDefaultMigration, /before insert on public\.profiles/i);
  assert.doesNotMatch(dmDefaultMigration, /update public\.profiles/i);
  assert.match(html, /id="open-dm-policy"/);
  assert.match(html, /value="everyone"/);
  assert.match(html, /value="friends"/);
  assert.match(html, /update\(\{dm_policy:choice\}\)/);
  assert.match(html, /Новые профили по умолчанию открыты для сообщений от всех/);
  assert.match(migration, /before insert on public\.profiles/i);
  assert.doesNotMatch(migration, /update public\.profiles/i);
  assert.match(html, /текущие настройки не меняются/i);
});

test("deletion UI requires acknowledgement and only creates a request", () => {
  assert.match(html, /id="account-delete-ack" type="checkbox" required/i);
  assert.match(html, /client\.rpc\('loopa_request_account_deletion'\)/i);
  assert.match(html, /не удалит аккаунт или данные автоматически/i);
  assert.doesNotMatch(migration, /delete\s+from\s+auth\.users/i);
  assert.doesNotMatch(html, /auth\.admin\.deleteUser|deleteUser\s*\(/i);
});

test("users can report a profile and an incoming DM", () => {
  assert.match(html, /id="friendPageReport"/);
  assert.match(html, /id="dmReportUser"/);
  assert.match(html, /Пожаловаться на сообщение/);
  assert.match(html, /client\.rpc\('loopa_submit_user_report'/i);
  assert.match(html, /p_message_ref:ref/);
});

test("retention guide stays an unconfirmed operator draft", () => {
  assert.match(setup, /publicly readable/i);
  assert.match(setup, /not\*\* the user-facing privacy policy/i);
  assert.match(setup, /@loopasupport/);
  assert.match(html, /https:\/\/t\.me\/loopasupport/);
  assert.match(setup, /no reliable automatic deletion schedule/i);
  assert.match(setup, /do not present a retention promise/i);
});
