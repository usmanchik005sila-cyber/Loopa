const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");
const assert = require("node:assert/strict");

const html = fs.readFileSync(path.resolve(__dirname, "..", "index.html"), "utf8");
const keyStart = html.indexOf("dmInput.addEventListener('keydown',event=>{");
const pointerStart = html.indexOf("byId('dmSend').addEventListener('pointerdown',event=>{", keyStart);
const blurStart = html.indexOf("dmInput.addEventListener('blur',()=>{", pointerStart);
const blurEnd = html.indexOf("document.addEventListener('visibilitychange'", blurStart);
const helperStart = html.indexOf("function finishDmSendPointer(){");
const helperEnd = html.indexOf("function setDmViewportBox(", helperStart);
assert.notEqual(keyStart, -1, "DM input should handle the keyboard Send key");
assert.notEqual(pointerStart, -1, "DM send button should track a tap before blur");
assert.notEqual(blurEnd, -1, "DM blur handler should remain in the page");
assert.notEqual(helperEnd, -1, "DM pointer cleanup helper should remain in the page");
const dmFormMarkup = html.match(/<form id="dmForm"[\s\S]*?<\/form>/)?.[0] ?? "";
assert.match(dmFormMarkup, /<button id="dmSend" type="submit"/, "the white arrow should submit the DM form");

function createHandlers(code) {
  const listeners = new Map();
  let submits = 0;
  let viewportSchedules = 0;
  let dismisses = 0;
  const input = {
    addEventListener: (name, listener) => listeners.set(`input:${name}`, listener),
  };
  const send = {
    addEventListener: (name, listener) => listeners.set(`send:${name}`, listener),
  };
  const form = { requestSubmit: () => submits++ };
  const sandbox = {
    byId: (id) => ({ dmInput: input, dmSend: send, dmForm: form })[id],
    dmInput: input,
    document: {
      body: { classList: { contains: () => true } },
      hidden: false,
      addEventListener: () => {},
    },
    window: { addEventListener: () => {} },
    clearTimeout: () => {},
    setTimeout: () => 1,
    finishDmKeyboardDismiss: () => {},
    scheduleDmViewport: () => viewportSchedules++,
    beginDmKeyboardDismiss: () => dismisses++,
  };
  sandbox.dmSendPointerActive = false;
  sandbox.dmSendPointerTimer = 0;
  vm.runInNewContext(code + "\nthis.isSendPointerActive=()=>dmSendPointerActive;", sandbox);
  return {
    listeners,
    submits: () => submits,
    viewportSchedules: () => viewportSchedules,
    dismisses: () => dismisses,
    isSendPointerActive: sandbox.isSendPointerActive,
  };
}

test("Enter sends the DM while Shift+Enter and IME composition remain text input", () => {
  const keyHandler = createHandlers(html.slice(keyStart, pointerStart));
  let prevented = 0;
  const onKeydown = keyHandler.listeners.get("input:keydown");

  onKeydown({ key: "Enter", shiftKey: false, isComposing: false, preventDefault: () => prevented++ });
  onKeydown({ key: "Enter", shiftKey: true, isComposing: false, preventDefault: () => prevented++ });
  onKeydown({ key: "Enter", shiftKey: false, isComposing: true, preventDefault: () => prevented++ });

  assert.equal(keyHandler.submits(), 1);
  assert.equal(prevented, 1);
});

test("tapping Send defers viewport dismissal until the tap can submit", () => {
  const pointerHandlers = createHandlers(
    html.slice(helperStart, helperEnd)
    + html.slice(pointerStart, blurEnd),
  );
  pointerHandlers.listeners.get("send:pointerdown")({ isPrimary: true, button: 0 });
  assert.equal(pointerHandlers.isSendPointerActive(), true);

  pointerHandlers.listeners.get("input:blur")();
  assert.equal(pointerHandlers.dismisses(), 0);
  assert.equal(pointerHandlers.viewportSchedules(), 0);

  pointerHandlers.listeners.get("send:click")();
  assert.equal(pointerHandlers.isSendPointerActive(), false);
  assert.equal(pointerHandlers.viewportSchedules(), 1);
});
