const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const test = require("node:test");
const assert = require("node:assert/strict");

const html = fs.readFileSync(path.resolve(__dirname, "..", "index.html"), "utf8");
const startMarker = "const dmInput=byId('dmInput'),dmBrowserIOS=watchBrowserIOS;";
const endMarker = "function scheduleDmViewport(){";
const start = html.indexOf(startMarker);
const end = html.indexOf(endMarker, start);
assert.notEqual(start, -1, "DM viewport controller should remain in the page");
assert.notEqual(end, -1, "DM viewport controller should end before its scheduler");

function createController() {
  const styles = new Map();
  const classes = new Set(["dmViewing"]);
  const input = {};
  const bodyClassList = {
    contains: (name) => classes.has(name),
    add: (name) => classes.add(name),
    remove: (name) => classes.delete(name),
    toggle: (name, enabled) => {
      if (enabled) classes.add(name);
      else classes.delete(name);
      return enabled;
    },
  };
  const viewport = { height: 844, offsetTop: 0, scale: 1 };
  const sandbox = {
    watchBrowserIOS: true,
    byId: () => input,
    document: {
      body: { classList: bodyClassList },
      documentElement: { style: { setProperty: (name, value) => styles.set(name, value) } },
      activeElement: null,
    },
    window: { innerHeight: 844, scrollY: 0, visualViewport: viewport },
    Math,
    clearTimeout: () => {},
    setTimeout: () => 1,
  };
  const source = html.slice(start, end)
    + "\nthis.dmViewportTest = { updateDmViewport, beginDmKeyboardDismiss, isDismissActive: () => dmKeyboardDismissActive };";
  vm.runInNewContext(source, sandbox);
  return { ...sandbox, classes, input, styles, viewport };
}

test("iOS DM keyboard dismissal snaps to full height and ignores intermediate viewport pans", () => {
  const controller = createController();
  const { document, window, classes, input, styles, viewport, dmViewportTest } = controller;

  dmViewportTest.updateDmViewport();
  assert.equal(styles.get("--dm-visual-top"), "0px");
  assert.equal(styles.get("--dm-visual-height"), "844px");

  document.activeElement = input;
  viewport.height = 500;
  dmViewportTest.updateDmViewport();
  assert.equal(classes.has("dmKeyboardOpen"), true);
  assert.equal(styles.get("--dm-visual-height"), "500px");

  document.activeElement = null;
  dmViewportTest.beginDmKeyboardDismiss();
  assert.equal(dmViewportTest.isDismissActive(), true);
  assert.equal(classes.has("dmKeyboardOpen"), false);
  assert.equal(styles.get("--dm-visual-top"), "0px");
  assert.equal(styles.get("--dm-visual-height"), "844px");

  viewport.height = 540;
  viewport.offsetTop = 155;
  window.scrollY = 155;
  dmViewportTest.updateDmViewport();
  assert.equal(dmViewportTest.isDismissActive(), true);
  assert.equal(styles.get("--dm-visual-top"), "0px");
  assert.equal(styles.get("--dm-visual-height"), "844px");

  viewport.height = 790;
  dmViewportTest.updateDmViewport();
  assert.equal(dmViewportTest.isDismissActive(), false);
  assert.equal(styles.get("--dm-visual-top"), "0px");
  assert.equal(styles.get("--dm-visual-height"), "790px");
});
