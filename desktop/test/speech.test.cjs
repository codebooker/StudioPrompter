const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { Speech } = require("../speech.cjs");
function pcmWave(source) {
  assert.equal(source.toString("ascii", 0, 4), "RIFF");
  let position = 12,
    format,
    data;
  while (position + 8 <= source.length) {
    const type = source.toString("ascii", position, position + 4),
      size = source.readUInt32LE(position + 4);
    if (type === "fmt ")
      format = source.subarray(position + 8, position + 8 + size);
    if (type === "data")
      data = source.subarray(position + 8, position + 8 + size);
    position += 8 + size + (size % 2);
  }
  assert.ok(format && data);
  assert.equal(format.readUInt16LE(0), 1);
  assert.equal(format.readUInt16LE(2), 1);
  assert.equal(format.readUInt32LE(4), 16000);
  assert.equal(format.readUInt16LE(14), 16);
  const audio = data.subarray(0, 192000),
    result = Buffer.alloc(audio.length + 44);
  result.write("RIFF");
  result.writeUInt32LE(result.length - 8, 4);
  result.write("WAVEfmt ", 8);
  result.writeUInt32LE(16, 16);
  format.copy(result, 20, 0, 16);
  result.write("data", 36);
  result.writeUInt32LE(audio.length, 40);
  audio.copy(result, 44);
  return result;
}
test(
  "downloaded model transcribes audio repeatedly in one persistent native process",
  { skip: process.env.STUDIO_WHISPER_TEST !== "1", timeout: 180000 },
  async () => {
    const folder = await fs.mkdtemp(path.join(os.tmpdir(), "studio-model-"));
    const speech = new Speech(
      folder,
      path.resolve(__dirname, "../runtime"),
      () => {},
    );
    try {
      await speech.download("tiny.en");
      assert.equal((await speech.status("tiny.en")).ready, true);
      const audio = pcmWave(await fs.readFile(process.env.STUDIO_SPEECH_WAV));
      let child;
      for (let i = 0; i < 2; i++) {
        const result = await speech.transcribe("tiny.en", audio);
        assert.match(result.text, /Americans|country/i);
        assert.ok(result.tokens.length > 0);
        assert.ok(
          result.tokens.every(
            (t) =>
              Number.isFinite(t.start) &&
              Number.isFinite(t.end) &&
              t.start <= t.end,
          ),
        );
        if (i) assert.equal(speech.child, child);
        child = speech.child;
        console.log(
          `${process.platform}/${process.arch} ${result.engine}: ${result.inferenceSeconds.toFixed(2)} s (${i ? "warm" : "cold"})`,
        );
        assert.ok(
          result.inferenceSeconds < (i ? 3 : 15),
          "live recognition must be fast enough to follow a reader",
        );
      }
      await speech.download("base.en");
      for (let i = 0; i < 2; i++) {
        const result = await speech.transcribe("base.en", audio);
        assert.match(result.text, /Americans|country/i);
        console.log(
          `${process.platform}/${process.arch} Base ${result.engine}: ${result.inferenceSeconds.toFixed(2)} s (${i ? "warm" : "cold"})`,
        );
        assert.ok(
          result.inferenceSeconds < (i ? 3 : 15),
          "Base must keep up with live speech too",
        );
      }
      // Reproduce a low-gain laptop mic through the actual renderer pipeline,
      // not just a loud prerecorded WAV sent directly to the worker.
      const { captureHarness } = require("./capture-harness.cjs");
      const microphone = await captureHarness((model, bytes) =>
        speech.transcribe(model, bytes),
      );
      const quiet = new Float32Array((audio.length - 44) / 2);
      for (let i = 0; i < quiet.length; i++)
        quiet[i] = (audio.readInt16LE(44 + i * 2) / 32768) * 0.02;
      await microphone.feed(new Float32Array(32000)); // silence before speaking
      await microphone.feed(quiet);
      assert.match(
        microphone.elements["voice-status"].textContent,
        /Heard:.*(Americans|country)/i,
      );
      assert.ok(
        microphone.context.matchedWord >= 4,
        "quiet microphone speech advances the script",
      );
      await assert.rejects(
        speech.transcribe("tiny.en", Buffer.alloc(44)),
        /Invalid audio/,
      );
      assert.equal(
        (await fs.readdir(folder)).some((name) => name.startsWith("audio-")),
        false,
      );
    } finally {
      speech.stop();
      await fs.rm(folder, { recursive: true, force: true });
    }
  },
);
