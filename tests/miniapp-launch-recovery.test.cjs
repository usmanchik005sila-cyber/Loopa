'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

const html = readFileSync(join(__dirname, '../index.html'), 'utf8');
const start = html.indexOf('    window.loopaLaunch=');
const source = html.slice(start, html.indexOf('  </script>', start));

function fixture({telegram = true} = {}) {
  const rootAttributes = new Set();
  const appAttributes = new Set();
  const timers = new Map();
  const listeners = new Map();
  const nativeEvents = [];
  let nextId = 0;
  let reloads = 0;
  const launchHash = telegram ? '#tgWebAppData=fixture-private-init-data' : '';
  const panel = {hidden:true};
  const splash = {hidden:false, classList:{add(){}}};
  const diagnostic = {};
  const button = {addEventListener: (_, listener) => listeners.set('retry',listener)};
  const root = {dataset:{}, classList:{add(){}},setAttribute: name => rootAttributes.add(name)};
  const window = {
    addEventListener: (name, listener) => listeners.set(name,listener),
    TelegramWebviewProxy: {postEvent: name => nativeEvents.push(name)}
  };
  vm.runInNewContext(source,{
    window,
    location:{hash:launchHash,search:'',origin:'https://loopacinema.ru',reload:()=>reloads++},
    setTimeout: (fn, ms) => {timers.set(++nextId,{fn,ms});return nextId;},
    clearTimeout: id => timers.delete(id),
    sessionStorage:{getItem:()=>null},
    document:{
      documentElement:root,
      addEventListener:(name,listener)=>listeners.set(name,listener),
      getElementById: id => ({loopaStartupRecovery:panel,loopaLaunchSplash:splash,
        loopaStartupCode:diagnostic,loopaStartupRetry:button})[id],
      querySelectorAll:()=>[],
      querySelector:()=>({setAttribute:name=>appAttributes.add(name),removeAttribute:name=>appAttributes.delete(name)})
    }
  });
  return {window, panel, splash, diagnostic, listeners, timers, rootAttributes, appAttributes, nativeEvents, reloads:()=>reloads};
}

test('a stalled SDK releases the native splash into a reloadable recovery screen', () => {
  const t=fixture();
  const guard=t.window.loopaLaunch;
  guard.mount();
  const [deadline]=t.timers.values();
  assert.equal(deadline.ms,9000);
  deadline.fn();
  assert.equal(t.panel.hidden,false);
  assert.equal(t.splash.hidden,true);
  assert.ok(t.appAttributes.has('inert'));
  assert.deepEqual(t.nativeEvents,['web_app_ready']);
  assert.match(t.diagnostic.textContent,/libraries-timeout/);
  assert.doesNotMatch(JSON.stringify(guard.snapshot()),/fixture-private-init-data/);
  t.listeners.get('retry')();
  assert.equal(t.reloads(),1);
});

test('the SDK signals readiness once and normal application startup cancels the watchdog', () => {
  const t=fixture();
  const guard=t.window.loopaLaunch;
  t.window.Telegram={WebApp:{initData:'fixture',ready:()=>t.nativeEvents.push('sdk-ready')}};
  t.listeners.get('load')({target:{id:'loopaTelegramSdk'}});
  guard.shell();
  guard.complete();
  assert.equal(t.timers.size,0);
  assert.deepEqual(t.nativeEvents,['sdk-ready']);
  assert.equal(t.panel.hidden,true);
  assert.equal(guard.failed(),false);
});

test('a first-party startup exception is fatal for Telegram but leaves the browser landing available', () => {
  for(const telegram of [true,false]){
    const t=fixture({telegram});
    t.window.loopaLaunch.mount();
    t.listeners.get('error')({filename:'https://loopacinema.ru/',message:'fixture error'});
    assert.equal(t.panel.hidden,!telegram);
    assert.equal(t.window.loopaLaunch.failed(),telegram);
  }
});
