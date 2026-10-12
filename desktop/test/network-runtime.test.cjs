const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const { LinkProcess } = require("../link-process.cjs");
const runtime = path.resolve(__dirname, "../runtime"),
  exe = path.join(runtime, process.platform === "win32" ? "node.exe" : "node");
function client(port, key, operation, id = "") {
  return new Promise((resolve, reject) => {
    const child = spawn(
      exe,
      [
        path.join(__dirname, "runtime-client.cjs"),
        String(port),
        key,
        operation,
        id,
      ],
      { stdio: ["ignore", "pipe", "inherit"] },
    );
    let output = "";
    child.stdout.on("data", (b) => (output += b));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        try {
          resolve(JSON.parse(output));
        } catch (e) {
          reject(e);
        }
      } else reject(Error("TLS client failed"));
    });
  });
}
test(
  "desktop runtime bridge delivers document/playback, resumes, and revokes without Electron TLS",
  { skip: !fs.existsSync(exe), timeout: 20000 },
  async () => {
    const folder = fs.mkdtempSync(path.join(os.tmpdir(), "studio-runtime-"));
    const link = new LinkProcess(
      path.join(folder, "pairs.json"),
      "Runtime producer",
      runtime,
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
      assert.equal(status.name, "Runtime producer");
      assert.match(status.serviceName, /^StudioPrompter-[A-F0-9]{8}$/);
      const paired = await client(status.port, status.code, "pair");
      assert.equal(paired.document.script.text, "Hello 👋 world");
      assert.equal(paired.playback.progress, 0.42);
      await new Promise((r) => setTimeout(r, 100));
      const saved = paired.saved;
      const resumed = await client(
        status.port,
        saved.token,
        "resume",
        saved.deviceID,
      );
      assert.equal(resumed.saved.deviceID, saved.deviceID);
      await link.remove(saved.deviceID);
      assert.deepEqual(
        await client(status.port, saved.token, "resume", saved.deviceID),
        { removed: true },
      );
    } finally {
      link.stop();
      await new Promise((r) => setTimeout(r, 350));
      fs.rmSync(folder, { recursive: true, force: true });
    }
  },
);
