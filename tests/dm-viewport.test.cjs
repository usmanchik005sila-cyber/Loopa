const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");
const assert = require("node:assert/strict");

const html = fs.readFileSync(path.resolve(__dirname, "..", "index.html"), "utf8");
const startMarker = "const dmInput=byId('dmInput')";
const start = html.indexOf(startMarker);
const end = html.indexOf("function showPageNow(", start);
assert.notEqual(start, -1, "DM viewport controller should remain in the page");
assert.notEqual(end, -1, "DM viewport controller should end before page navigation");

function createController({ telegramMiniApp = false } = {}) {
  const styles = new Map();
  const listeners = new Map();
  const bodyClasses = new Set();
  const htmlClasses = new Set(telegramMiniApp ? ["telegram-miniapp"] : []);
  const frames = new Map();
  const telegramListeners = new Map();
  const canceledFrames = [];
  let nextFrameId = 0;
  const viewport = { height: 844, offsetTop: 0, scale: 1, addEventListener: () => {} };
  const telegramWebApp = {
    viewportHeight: 844,
    viewportStableHeight: 844,
    onEvent: (name, fn) => telegramListeners.set(name, fn),
  };
  const input = {
    addEventListener: (name, fn) => listeners.set("input:" + name, fn),
    blur: () => { document.activeElement = null; listeners.get("input:blur")?.(); },
  };
  const dmLog = { scrollHeight: 1200, scrollTop: 0 };
  const send = { addEventListener: (name, fn) => listeners.set("send:" + name, fn) };
  const form = { requestSubmit: () => { form.submits++; }, submits: 0 };
  const classList = {
    contains: name => bodyClasses.has(name),
    add: name => bodyClasses.add(name),
    remove: (...names) => names.forEach(name => bodyClasses.delete(name)),
    toggle: (name, value) => { if (value) bodyClasses.add(name); else bodyClasses.delete(name); return value; },
  };
  const document = {
    hidden: false,
    activeElement: null,
    body: { classList },
    documentElement: {
      classList: { contains: name => htmlClasses.has(name) },
      style: { setProperty: (name, value) => styles.set(name, value), removeProperty: name => styles.delete(name) },
    },
    addEventListener: () => {},
  };
  const sandbox = {
    watchBrowserIOS: true,
    byId: id => ({ dmInput: input, dmLog, dmSend: send, dmForm: form })[id],
    document,
    window: { innerHeight: 844, scrollY: 0, visualViewport: viewport, Telegram: { WebApp: telegramWebApp }, addEventListener: () => {} },
    requestAnimationFrame: fn => { const id = ++nextFrameId; frames.set(id, fn); return id; },
    cancelAnimationFrame: id => { canceledFrames.push(id); frames.delete(id); },
    setTimeout: () => 1,
    clearTimeout: () => {},
    Math,
  };
  const source = html.slice(start, end) + "\nthis.testApi={updateDmViewport,setDmViewing,scheduleDmViewport};";
  vm.runInNewContext(source, sandbox);
  return {
    ...sandbox, input, dmLog, send, form, listeners, styles, viewport, frames, bodyClasses,
    telegramWebApp, telegramListeners, canceledFrames,
    flush: () => { const pending = [...frames.values()]; frames.clear(); pending.forEach(fn => fn()); },
  };
}

test("DM returns to the saved full height immediately on blur", () => {
  const c = createController();
  c.testApi.setDmViewing(true);
  assert.equal(c.styles.get("--dm-visual-height"), "844px");
  c.document.activeElement = c.input;
  c.viewport.height = 500;
  c.testApi.scheduleDmViewport(); c.flush();
  assert.equal(c.bodyClasses.has("dmKeyboardOpen"), true);
  assert.equal(c.styles.get("--dm-visual-height"), "500px");
  c.document.activeElement = null;
  c.listeners.get("input:blur")();
  assert.equal(c.bodyClasses.has("dmKeyboardOpen"), false);
  assert.equal(c.styles.get("--dm-visual-top"), "0px");
  assert.equal(c.styles.get("--dm-visual-height"), "844px");
});

test("reopening DM while iOS keyboard is still closing uses the last full height", () => {
  const c = createController();
  c.testApi.setDmViewing(true);
  c.document.activeElement = c.input;
  c.viewport.height = 500;
  c.testApi.scheduleDmViewport(); c.flush();
  c.document.activeElement = null;
  c.listeners.get("input:blur")();
  c.testApi.setDmViewing(false);
  c.viewport.height = 520;
  c.testApi.setDmViewing(true);
  assert.equal(c.styles.get("--dm-visual-top"), "0px");
  assert.equal(c.styles.get("--dm-visual-height"), "844px");
});

test("Telegram keeps DM pinned to the top while the keyboard is open", () => {
  const c = createController({ telegramMiniApp: true });
  c.testApi.setDmViewing(true);
  c.document.activeElement = c.input;
  c.window.scrollY = 96;
  c.viewport.height = 500;
  c.testApi.scheduleDmViewport(); c.flush();
  assert.equal(c.styles.get("--dm-visual-top"), "0px");
  assert.equal(c.styles.get("--dm-visual-height"), "500px");
});

test("Telegram viewportChanged updates DM even when visualViewport stays stale", () => {
  const c = createController({ telegramMiniApp: true });
  c.testApi.setDmViewing(true);
  c.document.activeElement = c.input;
  c.telegramWebApp.viewportHeight = 500;
  c.telegramListeners.get("viewportChanged")({ isStateStable: false });
  c.flush();
  assert.equal(c.bodyClasses.has("dmKeyboardOpen"), true);
  assert.equal(c.styles.get("--dm-visual-height"), "500px");
});

test("viewport event bursts keep one animation-frame update instead of cancelling it", () => {
  const c = createController({ telegramMiniApp: true });
  c.testApi.setDmViewing(true);
  c.frames.clear();
  c.testApi.scheduleDmViewport();
  c.testApi.scheduleDmViewport();
  c.testApi.scheduleDmViewport();
  assert.equal(c.frames.size, 1);
  assert.equal(c.canceledFrames.length, 0);
});

test("Telegram stable height is used to restore the chat after keyboard dismissal", () => {
  const c = createController({ telegramMiniApp: true });
  c.telegramWebApp.viewportStableHeight = 844;
  c.testApi.setDmViewing(true);
  c.document.activeElement = c.input;
  c.telegramWebApp.viewportHeight = 500;
  c.listeners.get("input:focus")?.();
  c.flush();
  c.document.activeElement = null;
  c.telegramWebApp.viewportHeight = 520;
  c.listeners.get("input:blur")();
  assert.equal(c.styles.get("--dm-visual-height"), "844px");
});

test("Telegram's stable viewport wins over a stale WebView innerHeight", () => {
  const c = createController({ telegramMiniApp: true });
  c.telegramWebApp.viewportHeight = 760;
  c.telegramWebApp.viewportStableHeight = 760;
  c.window.innerHeight = 844;
  c.viewport.height = 760;
  c.testApi.setDmViewing(true);
  assert.equal(c.styles.get("--dm-visual-height"), "760px");
});

test("a shrunken layout viewport moves the composer when other viewport reports are stale", () => {
  const c = createController({ telegramMiniApp: true });
  c.testApi.setDmViewing(true);
  c.document.activeElement = c.input;
  c.window.innerHeight = 500;
  c.viewport.height = 844;
  c.telegramWebApp.viewportHeight = 844;
  c.testApi.updateDmViewport();
  assert.equal(c.bodyClasses.has("dmKeyboardOpen"), true);
  assert.equal(c.styles.get("--dm-visual-height"), "500px");
});

test("Safari uses its smaller visible area when browser controls are expanded", () => {
  const c = createController();
  c.testApi.setDmViewing(true);
  c.viewport.height = 770;
  c.testApi.updateDmViewport();
  assert.equal(c.styles.get("--dm-visual-height"), "770px");
});

test("Safari keeps the immediate full-height position during keyboard dismissal", () => {
  const c = createController();
  c.testApi.setDmViewing(true);
  c.document.activeElement = c.input;
  c.viewport.height = 500;
  c.testApi.updateDmViewport();
  c.document.activeElement = null;
  c.viewport.height = 520;
  c.testApi.updateDmViewport();
  assert.equal(c.bodyClasses.has("dmKeyboardOpen"), false);
  assert.equal(c.styles.get("--dm-visual-height"), "844px");
});

test("opening the keyboard scrolls the DM log to the latest messages in Safari and Telegram", () => {
  for (const telegramMiniApp of [false, true]) {
    const c = createController({ telegramMiniApp });
    c.testApi.setDmViewing(true);
    c.document.activeElement = c.input;
    c.viewport.height = 500;
    c.testApi.updateDmViewport();
    assert.equal(c.bodyClasses.has("dmKeyboardOpen"), true);
    assert.equal(c.dmLog.scrollTop, c.dmLog.scrollHeight);
  }
});
