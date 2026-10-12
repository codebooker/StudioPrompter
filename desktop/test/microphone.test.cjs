const { test } = require("node:test");
const assert = require("node:assert/strict");
const StudioAudio = require("../audio.cjs");

const { captureHarness } = require("./capture-harness.cjs");
test("quiet selected-channel audio reaches Whisper and valid words survive early token timestamps", async () => {
  let count = 0;
  const harness = await captureHarness(async (_model, bytes) => {
    count++;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    assert.equal(view.getUint32(24, true), 16000);
    assert.ok(Math.abs(view.getInt16(44, true) / 32767) > 0.01);
    return {
      text: "And so my fellow Americans",
      tokens: [{ text: "Americans", start: 0, end: 0.1 }],
      inferenceSeconds: 0.1,
    };
  });
  // Well below the former 0.004 cutoff, yet clear audio after gain adjustment.
  await harness.feed(new Float32Array(96000).fill(0.002));
  assert.ok(count > 1);
  assert.match(
    harness.elements["voice-transcript"].textContent,
    /Heard:.*Americans/,
  );
  assert.ok(harness.context.matchedWord >= 4);
  assert.equal(
    harness.elements["voice-status"].textContent,
    "Listening · local Whisper",
    "normal status stays steady across live transcript revisions",
  );
});
test("digital silence is not sent to Whisper", async () => {
  const harness = await captureHarness(async () =>
    assert.fail("Silence must not trigger recognition"),
  );
  await harness.feed(new Float32Array(96000));
});
test("gain adjustment preserves waveform and limits amplification", () => {
  const audio = Float32Array.from([0.001, -0.002, 0.003, -0.004]);
  const normalized = StudioAudio.normalize(audio);
  assert.ok(
    normalized.every((value, i) => Math.abs(value / audio[i] - 20) < 0.001),
  );
  assert.deepEqual(
    StudioAudio.normalize(new Float32Array(1024)),
    new Float32Array(1024),
  );
});
