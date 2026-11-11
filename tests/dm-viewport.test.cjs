const fs = require("node:fs");
    const path = require("node:path");
    const vm = require("node:vm");
    const test = require("node:test");
    const assert = require("node:assert/strict");

    const html = fs.readFileSync(path.resolve(__dirname, "..", "index.html"), "utf8");
    const startMarker = "const dmInput=byId('dmInput'),dmBrowserIOS=";
    const start = html.indexOf(startMarker);
    const end = html.indexOf("function showPageNow(", start);
    assert.notEqual(start, -1, "DM viewport controller should remain in the page");
    assert.notEqual(end, -1, "DM viewport controller should end before page navigation");

    function createController({ telegramMiniApp = false } = {}) {
      const styles = new Map();
      const listeners = new Map();
      const bodyClasses = new Set();
      const htmlClasses = new Set(telegramMiniApp ? ["telegram-miniapp"] : []);
      const frames = [];
      const viewport = { height: 844, offsetTop: 0, scale: 1, addEventListener: () => {} };
      const input = {
        addEventListener: (name, fn) => listeners.set("input:" + name, fn),
        blur: () => { document.activeElement = null; listeners.get("input:blur")?.(); },
      };
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
        byId: id => ({ dmInput: input, dmSend: send, dmForm: form })[id],
        document,
        window: { innerHeight: 844, scrollY: 0, visualViewport: viewport, addEventListener: () => {} },
        requestAnimationFrame: fn => { frames.push(fn); return frames.length; },
        cancelAnimationFrame: () => {},
        setTimeout: () => 1,
        clearTimeout: () => {},
        Math,
      };
      const source = html.slice(start, end) + "\nthis.testApi={updateDmViewport,setDmViewing,scheduleDmViewport};";
      vm.runInNewContext(source, sandbox);
      return { ...sandbox, input, send, form, listeners, styles, viewport, frames, bodyClasses, flush: () => { while (frames.length) frames.shift()(); } };
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
    