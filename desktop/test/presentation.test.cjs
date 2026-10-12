const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  focusBand,
  scrollRemainder,
  PaceEstimator,
} = require("../presentation.cjs");
test("focus keeps every intersecting line completely bright as it crosses the reading area", () => {
  const lines = [
    { top: 100, height: 45 },
    { top: 160, height: 45 },
    { top: 220, height: 45 },
  ];
  for (let offset = 0; offset < 180; offset += 0.25) {
    const band = focusBand(100, 60, 1, lines, offset, 350);
    for (const line of lines) {
      const y = line.top - offset;
      if (y < 164 && y + line.height > 92) {
        assert.ok(band.top <= Math.max(0, y));
        assert.ok(band.bottom >= Math.min(350, y + line.height));
      }
    }
  }
});
test("focus expansion never changes guide anchor and stays inside a short viewport", () => {
  const guide = 280;
  const band = focusBand(guide, 60, 1, [{ top: 275, height: 45 }], 0, 320);
  assert.equal(guide, 280);
  assert.equal(band.bottom, 320);
  assert.equal(band.top, 272);
});
test("fractional presentation cancels browser scroll quantization", () => {
  for (let value = 0; value < 100; value += 0.07) {
    const actual = Math.round(value);
    assert.ok(
      Math.abs(-actual + scrollRemainder(value, actual) - -value) < 1e-9,
    );
  }
});
test("overlapping transcripts change cadence by elapsed audio time instead of revision count", () => {
  const slow = new PaceEstimator(),
    fast = new PaceEstimator();
  slow.observe(10, 6, 6);
  fast.observe(10, 6, 6);
  for (let i = 1; i <= 4; i++) slow.observe(20, 6, 6 + i * 0.5);
  for (let i = 1; i <= 20; i++) fast.observe(20, 6, 6 + i * 0.1);
  assert.ok(Math.abs(slow.value - fast.value) < 1);
  const prior = fast.value;
  fast.observe(30, 6, 8);
  assert.equal(fast.value, prior);
  fast.observe(5, 6, 9);
  assert.ok(
    fast.value < prior,
    "cadence eases down promptly when the reader slows",
  );
});

test("adaptive motion holds promptly on silence and waits for a measured cadence", () => {
  const { adaptiveActive } = require("../presentation.cjs");
  assert.equal(adaptiveActive(1000, 900, 900, 120), true);
  assert.equal(adaptiveActive(1500, 900, 900, 120), false);
  assert.equal(adaptiveActive(6000, 5900, 1000, 120), false);
  assert.equal(adaptiveActive(1000, 900, 900, null), false);
});
