const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const { LinkProcess } = require("../link-process.cjs");
test(
  "Apple companion protocol pairs and receives playback from the desktop runtime",
  { skip: !process.env.STUDIO_APPLE_CLIENT, timeout: 20000 },
  async () => {
    const folder = fs.mkdtempSync(path.join(os.tmpdir(), "studio-apple-"));
    const link = new LinkProcess(
      path.join(folder, "pairs.json"),
      "Windows-compatible producer",
      path.resolve(__dirname, "../runtime"),
    );
    try {
      const revision = crypto.randomUUID();
      link.documentUpdate({
        revision,
        script: {
          id: crypto.randomUUID(),
          title: "Test",
          text: "Hello 👋 world",
          modified: 0,
          cues: [],
          emphasis: [],
          settings: {
            fontSize: 54,
            margin: 100,
            guidePosition: 0.32,
            guideLines: 1,
          },
        },
        lines: [{ location: 0, length: 14, y: 0, height: 70 }],
        textHeight: 80,
        lineHeight: 80,
      });
      link.playbackUpdate({
        revision,
        progress: 0.42,
        playing: true,
        blackout: false,
        countdown: 0,
      });
      const status = await link.start();
      const result = await new Promise((resolve, reject) => {
        const child = spawn(process.env.STUDIO_APPLE_CLIENT, [
          String(status.port),
          status.code,
        ]);
        let output = "";
        child.stdout.on("data", (b) => (output += b));
        child.stderr.on("data", (b) => (output += b));
        child.on("error", reject);
        child.on("exit", (code) => resolve({ code, output }));
      });
      assert.equal(result.code, 0, result.output);
      assert.match(result.output, /paired, document, playback/);
    } finally {
      link.stop();
      fs.rmSync(folder, { recursive: true, force: true });
    }
  },
);
