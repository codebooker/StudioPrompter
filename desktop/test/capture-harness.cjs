const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const StudioAudio = require("../audio.cjs");
// Exercise the production renderer capture -> WAV -> IPC -> result handling.
// A moving meter alone is not an adequate microphone regression test.
async function captureHarness(transcribe) {
  const elements = Object.fromEntries(
    [
      "voice-model",
      "mic",
      "mic-channel",
      "mic-level",
      "voice-status",
      "voice-detail",
    ].map((id) => [
      id,
      {
        value: id === "voice-model" ? "tiny.en" : "0",
        textContent: "",
        replaceChildren() {},
        add() {},
      },
    ]),
  );
  let processor;
  const context = vm.createContext({
    StudioAudio,
    StudioPresentation: require("../presentation.cjs"),
    paceEstimator: new (require("../presentation.cjs").PaceEstimator)(),
    wordPositions: Array(20).fill(0),
    maxScroll: () => 200,
    matchedAt: 0,
    lastVoice: -Infinity,
    Float32Array,
    Uint8Array,
    ArrayBuffer,
    DataView,
    performance,
    $: (id) => elements[id],
    api: { modelStatus: async () => ({ ready: true }), transcribe },
    micStream: null,
    audioContext: null,
    micGeneration: 0,
    recognizing: false,
    navigator: {
      mediaDevices: {
        getUserMedia: async () => ({
          getAudioTracks: () => [{ getSettings: () => ({ channelCount: 1 }) }],
          getTracks: () => [{ stop() {} }],
        }),
      },
    },
    AudioContext: class {
      sampleRate = 16000;
      audioWorklet = { addModule: async () => {} };
      destination = {};
      async resume() {}
      createMediaStreamSource() {
        return { connect() {} };
      }
    },
    AudioWorkletNode: class {
      constructor() {
        processor = this;
        this.port = {};
      }
      connect() {}
    },
    Option: class {},
    captureURL: "capture-worklet.js",
    microphones: async () => {},
    plain: (text) => text,
    current: () => ({
      text: "And so my fellow Americans ask not what your country",
    }),
    align: require("../tracking.cjs").align,
    matchedWord: 0,
    speechTarget: null,
    lastSpeech: 0,
    heardPace: 130,
    wordPosition: (word) => word,
    tokenize: require("../tracking.cjs").tokenize,
    clamp: (value, min, max) => Math.max(min, Math.min(max, value)),
    pause: () => assert.fail("Capture should not fail"),
  });
  const source = fs.readFileSync(
    path.join(__dirname, "../renderer.js"),
    "utf8",
  );
  vm.runInContext(
    source.slice(
      source.indexOf("function wav("),
      source.indexOf("function measureWordPositions("),
    ),
    context,
  );
  await context.startMic();
  return {
    elements,
    context,
    async feed(samples) {
      for (let i = 0; i < samples.length; i += 1024) {
        processor.port.onmessage({ data: samples.subarray(i, i + 1024) });
        while (context.recognizing)
          await new Promise((resolve) => setTimeout(resolve, 10));
      }
    },
  };
}
module.exports = { captureHarness };
