'use strict';

const { createHash } = require('node:crypto');
const { mkdtempSync, readFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { withContentSecurityPolicy, buildPages } = require('../scripts/build-pages.cjs');

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

test('Pages serves the deferred app as one content-versioned script', () => {
  const output = mkdtempSync(join(tmpdir(), 'loopa-build-'));
  try {
    buildPages(join(__dirname, '..'), output);
    const html = readFileSync(join(output, 'index.html'), 'utf8');
    const name = html.match(/<script defer src="\.\/assets\/(loopa-app\.[a-f0-9]{16}\.js)"><\/script>/)?.[1];
    assert.ok(name);
    const bundle = readFileSync(join(output, 'assets', name), 'utf8');
    assert.equal(name, 'loopa-app.' + createHash('sha256').update(bundle).digest('hex').slice(0, 16) + '.js');
    assert.match(bundle, /function startLoopa\(/);
    assert.doesNotMatch(html, /<script[^>]+src="[^"]*(?:iframe_api|videoplayer\.js|direct-messages\.js)"/);
    assert.ok(html.indexOf('telegram-web-app.js"></script>') < html.indexOf(name));
    assert.match(html, /<div class="app" inert>/);
  } finally {
    rmSync(output, {recursive: true, force: true});
  }
});
