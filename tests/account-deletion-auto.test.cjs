const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const root = path.resolve(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
const bot = fs.readFileSync(path.join(root, "supabase/functions/loopa-bot/index.js"), "utf8");
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/20261112100000_account_deletion_approval.sql"),
  "utf8",
);
const botGuide = fs.readFileSync(path.join(root, "supabase/BOT_WELCOME_SETUP.md"), "utf8");
const safetyGuide = fs.readFileSync(path.join(root, "supabase/USER_SAFETY_SETUP.md"), "utf8");

test("automatic deletion RPC is private and requires a request owned by the user", () => {
  assert.match(migration, /security definer[\s\S]*set search_path = ''/i);
  assert.match(migration, /d\.user_id = p_actor/i);
  assert.match(migration, /revoke all on function public\.loopa_account_deletion_process_v1[\s\S]*from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function public\.loopa_account_deletion_process_v1[\s\S]*to service_role/i);
  assert.match(migration, /delete from public\.loopa_dm_messages_v87[\s\S]*sender_id = v_user_id or recipient_id = v_user_id/i);
  assert.match(migration, /delete from public\.loopa_resume_points where user_id = \$1/i);
  assert.match(migration, /delete from public\.profiles/i);
  assert.match(migration, /delete from public\.loopa_account_deletion_requests_v1/i);
});

test("bot authenticates the user and automatically removes their Auth and public data", () => {
  assert.match(bot, /Origin"\)!==SITE_ORIGIN/);
  assert.match(bot, /db\.auth\.getUser\(jwt\)/);
  assert.match(bot, /input\.action==="delete_account"/);
  assert.match(bot, /p_action:"claim",p_request_id:requestId,p_actor:actorId\|\|null/);
  assert.match(bot, /db\.auth\.admin\.deleteUser\(userId\)/);
  assert.match(bot, /p_action:"purge"/);
  assert.match(bot, /p_action:"complete"/);
  assert.match(bot, /storage\.from\("avatars"\)[\s\S]*avatars\.remove\(/);
});

test("bot CORS allows the Supabase client info header", () => {
  assert.match(bot, /Access-Control-Allow-Headers[^}]*x-client-info/i);
});

test("owner Telegram message is informational and recovery is owner-only", () => {
  assert.match(bot, /LOOPA_OWNER_TELEGRAM_ID/);
  assert.match(bot, /sendMessage[\s\S]*deletionNoticeText\(requestId,"processing"\)/);
  assert.match(bot, /retryMessage\?\.chat\?\.type!=="private"/);
  assert.match(bot, /String\(chatId\)!==String\(ownerId\)/);
  assert.match(bot, /\/retrydelete/);
  assert.doesNotMatch(bot, /callback_data.*(?:approve|reject)|Подтвердить удаление/);
  assert.match(botGuide, /информационное сообщение без кнопок одобрения/i);
  assert.match(botGuide, /LOOPA_OWNER_TELEGRAM_ID/);
});

test("deletion screen clearly warns and invokes server cleanup after confirmation", () => {
  assert.match(html, /Удалить аккаунт и данные\?/);
  assert.match(html, /локальные данные на других устройствах/i);
  assert.match(html, /id="account-delete-ack" type="checkbox" required/i);
  assert.match(html, /action:'delete_account'/i);
  assert.match(html, /clearLocalAccountData\(owner\)/);
  assert.match(html, /client\.auth\.signOut\(\{scope:'local'\}\)/);
  assert.match(safetyGuide, /removed automatically/i);
  assert.match(safetyGuide, /request row is removed|request row is removed/i);
});

test("file cleanup precedes Auth deletion and a cleanup retry supports an already absent account", async () => {
  const vm = require("node:vm");
  const start = bot.indexOf("async function clearAccountAvatars(");
  const calls = [];
  const account = "11111111-1111-4111-8111-111111111111";
  const request = "22222222-2222-4222-8222-222222222222";
  const telegramId = "81001";
  const rules = { missing: false, storageError: false, purgeError: false };
  const files = new Map([
    [account, Array.from({ length: 100 }, (_, i) => ({ id: i + 1, name: i + ".jpg" }))
      .concat({ id: null, name: "nested" })],
    [account + "/nested", [{ id: 101, name: "extra.jpg" }]],
  ]);
  const db = {
    auth: { admin: {
      getUserById: async () => rules.missing
        ? { error: { status: 404 } } : { data: { user: { id: account } } },
      deleteUser: async () => {
        assert.ok([...files.values()].flat().every(file => !file.id));
        calls.push("delete");
        rules.missing = true;
        return {};
      },
    } },
    storage: { from: bucket => {
      assert.equal(bucket, "avatars");
      return {
        list: async (prefix, { limit, offset }) => ({ data: files.get(prefix).slice(offset, offset + limit) }),
        remove: async paths => {
          calls.push("remove");
          if (rules.storageError) return { error: new Error("fixture") };
          for (const [prefix, children] of files)
            files.set(prefix, children.filter(child => !paths.includes(prefix + "/" + child.name)));
          return {};
        },
      };
    } },
    rpc: async (_name, args) => {
      calls.push(args.p_action);
      switch (args.p_action) {
        case "claim": return { data: { status: "processing", user_id: account, telegram_id: telegramId } };
        case "purge": return rules.purgeError ? { error: new Error("fixture") } : { data: { status: "purged" } };
        case "complete": return { data: { status: "completed" } };
        case "release": return {};
      }
    },
  };
  const context = {
    REQUEST_ID_RE: /^[0-9a-f-]{36}$/,
    isMissingAuthUser: error => error?.status === 404,
    botAPI: async (_token, _method, payload) => { calls.push("notice:" + payload.chat_id); },
    editDeletionNotice: async () => {}, console: { error() {} },
  };
  vm.runInNewContext(bot.slice(start, bot.indexOf("async function miniAppAction(", start)), context);
  const run = (actor = account) => context.processAccountDeletion(db, "fake", request, actor, null);

  rules.storageError = true;
  assert.equal((await run()).error, "account_deletion_failed");
  assert.deepEqual(calls.splice(0), ["claim", "remove", "release"]);

  rules.storageError = false;
  rules.purgeError = true;
  assert.equal((await run()).error, "account_deleted_cleanup_incomplete");
  assert.deepEqual(calls.splice(0), ["claim", "remove", "remove", "delete", "purge"]);

  rules.purgeError = false;
  assert.equal((await run(null)).status, "completed");
  assert.deepEqual(calls, ["claim", "purge", "complete", "notice:81001"]);
});
