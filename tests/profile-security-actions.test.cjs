const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const html = fs.readFileSync(path.resolve(__dirname, "../index.html"), "utf8");
const safetyGroup = html.match(/<div class="privacy-group"><h3>БЕЗОПАСНОСТЬ<\/h3>([\s\S]*?)<\/div>\s*<p class="privacy-section-note">/i)?.[1];

test("profile security actions use the requested order and labels", () => {
  assert.ok(safetyGroup, "security settings group exists");

  const passwordIndex = safetyGroup.indexOf('id="privacy-reset"');
  const linkedAccountsIndex = safetyGroup.indexOf('id="open-linked-accounts"');
  const supportIndex = safetyGroup.indexOf('class="privacy-action safety-support-link"');
  const signOutIndex = safetyGroup.indexOf('id="privacy-signout"');

  assert.ok(passwordIndex < linkedAccountsIndex, "password change comes first");
  assert.ok(linkedAccountsIndex < supportIndex, "linked accounts come before support");
  assert.ok(supportIndex < signOutIndex, "support is second-to-last and sign out is last");
  assert.match(safetyGroup, /Сменить пароль \(электронная почта\)/);
});

test("support and sign-out actions use distinct Telegram-blue and danger styles", () => {
  assert.match(html, /\.safety-support-link\{[^}]*#8bd5ff/i);
  assert.match(html, /#privacy-signout\{[^}]*#ff9a9a/i);
});
