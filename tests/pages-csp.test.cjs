'use strict';

const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { withContentSecurityPolicy } = require('../scripts/build-pages.cjs');

test('Pages adds CSP before scripts and authorizes each original inline script by hash', () => {
  const source = readFileSync(join(__dirname, '../index.html'), 'utf8');
  const built = withContentSecurityPolicy(source.replace(/\n/g, '\r\n'));
  const policy = built.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)?.[1];
  assert.ok(policy);
  assert.ok(built.indexOf('Content-Security-Policy') < built.indexOf('<script'));
  const scripts = [...built.matchAll(/<script(?: defer)?>([\s\S]*?)<\/script>/g)].map(match => match[1]);
  assert.ok(scripts.length > 0);
  const scriptSources = policy.split('; ').find(directive => directive.startsWith('script-src '));
  const expectedHashes = scripts.map(script => "'sha256-" + createHash('sha256').update(script).digest('base64') + "'");
  assert.deepEqual(scriptSources.match(/'sha256-[^']+'/g), [...new Set(expectedHashes)]);
  assert.doesNotMatch(scriptSources, /unsafe-inline|unsafe-eval/);
  assert.match(policy, /script-src-attr 'none'/);
  assert.match(policy, /object-src 'none'/);
});

test('Pages requires an explicit CSP marker before application scripts', () => {
  assert.throws(() => withContentSecurityPolicy('<script></script><!-- LOOPA_CSP -->'), /before the first script/);
});
