'use strict';

const { createHash } = require('node:crypto');
const { cpSync, mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const path = require('node:path');

const coverDomains = ['ytimg.com', 'youtube.com', 'userapi.com', 'vk.com', 'vk.ru', 'vkvideo.ru', 'rutube.ru', 'rtbcdn.ru'];
const marker = '<!-- LOOPA_CSP -->';

function withContentSecurityPolicy(source) {
  // HTML parsers normalize CRLF before comparing inline script hashes.
  const html = source.replace(/\r\n?/g, '\n');
  if (html.split(marker).length !== 2 || html.indexOf(marker) > html.indexOf('<script')) {
    throw new Error('Place exactly one CSP marker before the first script');
  }
  const inlineHashes = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)]
    .filter(([, attributes]) => !/\bsrc\s*=/i.test(attributes))
    .map(([, , script]) => "'sha256-" + createHash('sha256').update(script).digest('base64') + "'");

  const policy = [
    "default-src 'none'",
    "base-uri 'none'",
    "object-src 'none'",
    "form-action 'self'",
    [
      "script-src 'self'",
      'https://telegram.org/js/telegram-web-app.js',
      'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.119.0/dist/umd/supabase.js',
      'https://www.youtube.com/iframe_api',
      'https://www.youtube.com/s/player/',
      'https://vkvideo.ru/js/api/videoplayer.js',
      'https://vkvideo.ru/dist/public/api/',
      ...new Set(inlineHashes),
    ].join(' '),
    "script-src-attr 'none'",
    "style-src 'self' 'unsafe-inline'",
    ["img-src 'self' data: blob:", ...coverDomains.flatMap(domain => ['https://' + domain, 'https://*.' + domain])].join(' '),
    "connect-src 'self' https://wnubqzwsvclvcvozibtc.supabase.co wss://wnubqzwsvclvcvozibtc.supabase.co",
    'frame-src https://www.youtube.com https://vkvideo.ru https://rutube.ru',
    "worker-src 'self' blob:",
  ].join('; ');
  return html.replace(marker, '<meta http-equiv="Content-Security-Policy" content="' + policy + '">');
}

if (require.main === module) {
  const root = path.resolve(__dirname, '..');
  const output = path.join(root, '_site');
  const html = withContentSecurityPolicy(readFileSync(path.join(root, 'index.html'), 'utf8'));
  mkdirSync(output, { recursive: true });
  for (const item of ['assets', 'CNAME']) cpSync(path.join(root, item), path.join(output, item), { recursive: true });
  writeFileSync(path.join(output, 'index.html'), html);
}

module.exports = { withContentSecurityPolicy };
