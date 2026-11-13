'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261113090000_profile_usernames.sql'), 'utf8');

test('profile places the display name beside the avatar and edits it separately', () => {
  assert.match(html, /class="profile-identity-row"/);
  assert.match(html, /id="profile-display-name"/);
  assert.match(html, /id="profile-name-edit"[^>]*aria-controls="profile-name-editor"/);
  assert.match(html, /id="profile-name-editor" hidden/);
  assert.match(html, /id="profile-username"/);
});

test('profile saves a normalized optional username with the display name', () => {
  assert.ok(html.includes("const username=rawUsername.toLowerCase();"));
  assert.ok(html.includes("username:username||null"));
  assert.ok(html.includes("if(err?.code==='23505')"));
  assert.ok(html.includes("/^[a-z][a-z0-9_]{3,31}$/"));
});

test('friend search includes exact usernames and displays the matching handle', () => {
  assert.ok(html.includes(".eq('username',handle).limit(1)"));
  assert.ok(html.includes("'id,display_name,username,avatar_path,updated_at'"));
  assert.ok(html.includes("handle.textContent='@'+profile.username"));
});

test('database migration keeps usernames optional but enforces format and uniqueness', () => {
  assert.match(migration, /add column if not exists username text/i);
  assert.ok(migration.includes("username ~ '^[a-z][a-z0-9_]{3,31}$'"));
  assert.match(migration, /create unique index if not exists profiles_username_unique_v1/i);
  assert.match(migration, /where username is not null/i);
});
