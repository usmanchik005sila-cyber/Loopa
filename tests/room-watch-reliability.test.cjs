'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../assets/room-watch-reliability.js'), 'utf8');
const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const sandbox = {URL, encodeURIComponent};
sandbox.window = sandbox;
vm.runInNewContext(source, sandbox, {filename: 'room-watch-reliability.js'});
const reliability = sandbox.LOOPAWatchReliability;

test('normalizes accepted video links for the three supported providers', () => {
  assert.match(reliability.normalizeMedia('https://youtu.be/dQw4w9WgXcQ', 'https://loopacinema.ru'), /youtube\.com\/embed\/dQw4w9WgXcQ/);
  assert.match(reliability.normalizeMedia('https://rutube.ru/video/0123456789abcdef0123456789abcdef/', 'https://loopacinema.ru'), /rutube\.ru\/play\/embed\/0123456789abcdef0123456789abcdef\//);
  assert.match(reliability.normalizeMedia('https://vkvideo.ru/video-123_456?hash=abc', 'https://loopacinema.ru'), /vkvideo\.ru\/video_ext\.php\?oid=-123&id=456&js_api=1&hash=abc/);
  assert.throws(() => reliability.normalizeMedia('https://example.com/not-a-video', 'https://loopacinema.ru'), /YouTube, VK Видео или RUTUBE/);
  assert.throws(() => reliability.normalizeMedia('http://youtu.be/dQw4w9WgXcQ', 'https://loopacinema.ru'), /HTTPS/);
});

test('identifies provider from the normalized player URL', () => {
  assert.equal(reliability.providerFor('https://www.youtube.com/embed/dQw4w9WgXcQ'), 'youtube');
  assert.equal(reliability.providerFor('https://rutube.ru/play/embed/0123456789abcdef0123456789abcdef/'), 'rutube');
  assert.equal(reliability.providerFor('https://vkvideo.ru/video_ext.php?oid=-1&id=2'), 'vk');
});

test('maps YouTube playback failures to actionable next steps', () => {
  assert.match(reliability.playerError('youtube', 100).message, /удалено, закрыто или недоступно/);
  assert.match(reliability.playerError('youtube', 101).message, /запретил просмотр.*встроенном плеере/);
  assert.equal(reliability.playerError('youtube', 150).message, reliability.playerError('youtube', 101).message);
  assert.match(reliability.playerError('youtube', 153).message, /не распознал встроенный плеер/);
});

test('gives a tap-to-play instruction when autoplay is blocked', () => {
  assert.match(reliability.autoplayBlocked(true).message, /Нажми ▶ в самом видео/);
  assert.match(reliability.autoplayBlocked(false).message, /Дождись запуска видео ведущим/);
  assert.match(reliability.autoplaySoundProhibited(true).message, /ограничил автозапуск со звуком/);
});

test('shows distinct states for missing host, stale host and sync service failures', () => {
  assert.match(reliability.syncMessage({ready: false}), /Ждём ведущего/);
  assert.match(reliability.syncMessage({ready: true, age: 5}), /Ведущий временно не на связи/);
  assert.match(reliability.syncMessage({errorCode: 'PGRST202'}), /не настроена на сервере/);
  assert.match(reliability.syncMessage({errorCode: 'NETWORK'}), /Проверь интернет/);
  assert.match(reliability.syncMessage({ready: 'video-mismatch'}), /Видео в комнате сменилось/);
  assert.equal(reliability.syncMessage({ready: true, age: 1}), '');
});

test('treats room playback snapshots as stale after their explicit expiry', () => {
  const snapshot = {expires: 4500};
  assert.equal(reliability.isSnapshotFresh(snapshot, 4500), true);
  assert.equal(reliability.isSnapshotFresh(snapshot, 4501), false);
  assert.equal(reliability.isSnapshotFresh(null, 1), false);
  assert.equal(reliability.isFreshSample(3.49), true);
  assert.equal(reliability.isFreshSample(3.5), false);
  assert.equal(reliability.snapshotPosition({pos: 30, playing: true, received: 1000, expires: 4500}, 2500), 31.5);
  assert.equal(reliability.snapshotPosition({pos: 30, playing: true, received: 1000, expires: 4500}, 6000), 33.5);
  assert.equal(reliability.snapshotPosition({pos: 30, playing: false, received: 1000, expires: 4500}, 6000), 30);
});

test('keeps normal drift correction conservative but allows explicit re-sync', () => {
  const base = {now: 5000, lastCorrection: 3000, manualUntil: 0, measured: 40, target: 40.5, currentPlaying: true, desiredPlaying: true};
  assert.equal(reliability.correctionDecision(base).apply, false);
  assert.deepEqual({...reliability.correctionDecision({...base, target: 42})}, {seek: true, apply: true});
  assert.deepEqual({...reliability.correctionDecision({...base, manualUntil: 6000, target: 42})}, {seek: false, apply: false});
  assert.deepEqual({...reliability.correctionDecision({...base, force: true, manualUntil: 6000})}, {seek: true, apply: true});
});

test('the live room page wires provider errors and retry controls to the tested helpers', () => {
  assert.match(html, /room-watch-reliability\.js/);
  assert.match(html, /onError:event=>setPlayerIssue\(LOOPAWatchReliability\.playerError\('youtube'/);
  assert.match(html, /m\?\.type==='player:error'.*playerError\('rutube'/);
  assert.match(html, /onAutoplayBlocked:.*autoplayBlocked/);
  assert.match(html, /autoplaySoundProhibited/);
  assert.match(html, /syncPlayback\(\{forceCorrection:true\}\)/);
  assert.match(html, /isSnapshotFresh\(syncSnapshot/);
  assert.match(html, /snapshotPosition\(syncSnapshot/);
});
