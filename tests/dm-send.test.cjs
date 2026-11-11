const fs = require("node:fs");
    const path = require("node:path");
    const vm = require("node:vm");
    const test = require("node:test");
    const assert = require("node:assert/strict");

    const html = fs.readFileSync(path.resolve(__dirname, "..", "index.html"), "utf8");
    const keyStart = html.indexOf("dmInput.addEventListener('keydown',event=>{");
    const pointerStart = html.indexOf("byId('dmSend').addEventListener('pointerdown',event=>{", keyStart);
    const focusStart = html.indexOf("dmInput.addEventListener('focus',()=>{", pointerStart);
    const helperStart = html.indexOf("function finishDmSendPointer(){");
    const helperEnd = html.indexOf("function setDmViewportBox(", helperStart);
    assert.notEqual(keyStart, -1);
    assert.notEqual(pointerStart, -1);

    function makeHarness(code) {
      const listeners = new Map();
      let submits = 0;
      let prevented = 0;
      let scheduled = 0;
      const input = { addEventListener: (name, fn) => listeners.set("input:" + name, fn) };
      const send = { addEventListener: (name, fn) => listeners.set("send:" + name, fn) };
      const sandbox = {
        byId: id => ({ dmInput: input, dmSend: send, dmForm: { requestSubmit: () => submits++ } })[id],
        dmInput: input,
        document: { body: { classList: { contains: () => true } }, hidden: false, addEventListener: () => {} },
        window: { addEventListener: () => {} },
        clearTimeout: () => {}, setTimeout: () => 1,
        scheduleDmViewport: () => scheduled++, Math,
      };
      sandbox.dmSendPointerActive = false;
      sandbox.dmSendPointerTimer = 0;
      vm.runInNewContext(code + "\nthis.getActive=()=>dmSendPointerActive;", sandbox);
      return { listeners, submits: () => submits, prevented: () => prevented, scheduled: () => scheduled, getActive: sandbox.getActive, prevent: () => prevented++ };
    }

    test("Enter submits, while Shift+Enter and IME composition do not", () => {
      const h = makeHarness(html.slice(keyStart, pointerStart));
      const key = h.listeners.get("input:keydown");
      key({ key: "Enter", shiftKey: false, isComposing: false, preventDefault: h.prevent });
      key({ key: "Enter", shiftKey: true, isComposing: false, preventDefault: h.prevent });
      key({ key: "Enter", shiftKey: false, isComposing: true, preventDefault: h.prevent });
      assert.equal(h.submits(), 1);
      assert.equal(h.prevented(), 1);
    });

    test("white-arrow tap keeps the input focused until the form submits", () => {
      const code = html.slice(helperStart, helperEnd) + html.slice(pointerStart, focusStart);
      const h = makeHarness(code);
      let downPrevented = 0;
      h.listeners.get("send:pointerdown")({ isPrimary: true, button: 0, preventDefault: () => downPrevented++ });
      assert.equal(h.getActive(), true);
      assert.equal(downPrevented, 1);
      h.listeners.get("send:click")();
      assert.equal(h.getActive(), false);
      assert.equal(h.scheduled(), 1);
    });
    