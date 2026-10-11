const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const tls = require("node:tls");
const {
  frame,
  Decoder,
  identity,
  secret,
  validDocument,
} = require("../protocol.cjs");
const { LinkServer } = require("../link-server.cjs");
const { align, tokenize } = require("../tracking.cjs");
test("bounded framing preserves fragmented Unicode and rejects oversized messages", () => {
  const received = [];
  const decoder = new Decoder((m) => received.push(m));
  const data = frame({ text: "🎙️ café 中文" });
  for (const byte of data) decoder.push(Buffer.from([byte]));
  assert.deepEqual(received, [{ text: "🎙️ café 中文" }]);
  assert.throws(() => decoder.push(Buffer.from([0, 255, 255, 255])));
});
test("invalid document positions are rejected", () => {
  assert.equal(
    validDocument({
      revision: "x",
      script: {
        text: "a",
        settings: {
          fontSize: 50,
          margin: 100,
          guidePosition: 0.3,
          guideLines: 1,
        },
      },
      textHeight: 60,
      lineHeight: 60,
      lines: [{ location: 0, length: 2, y: 0, height: 60 }],
    }),
    false,
  );
});
test("follow script tolerates skipped words without jumping on unrelated speech", () => {
  const script =
    "Today I want to talk to you about something important the tiny things that change everything";
  assert.ok(
    align(script, "Today I want talk to you about important", 0)?.cursor >= 10,
  );
  assert.equal(align(script, "purple horses wearing shoes", 0), null);
  assert.ok(
    align(script, "the tiny things that change everything", 12)?.cursor ===
      tokenize(script).length,
  );
});
function connect(port, key, message) {
  return new Promise((resolve, reject) => {
    const socket = tls.connect(
      {
        host: "127.0.0.1",
        port,
        minVersion: "TLSv1.2",
        maxVersion: "TLSv1.2",
        ciphers: "PSK-AES128-GCM-SHA256",
        pskCallback: () => ({ identity: identity(key), psk: secret(key) }),
        checkServerIdentity: () => undefined,
      },
      () => socket.write(frame(message)),
    );
    const decoder = new Decoder((value) => {
      socket.end();
      resolve(value);
    });
    socket.on("data", (d) => {
      try {
        decoder.push(d);
      } catch (e) {
        reject(e);
      }
    });
    socket.once("error", reject);
    socket.setTimeout(3000, () => {
      socket.destroy();
      reject(Error("Timed out"));
    });
  });
}
test("TLS PSK pairing persists, resumes and reports offline removal", async () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), "studio-link-"));
  let server = new LinkServer(path.join(folder, "pairs.json"), "Test Producer");
  try {
    const status = await server.start();
    const paired = await connect(status.port, status.code, {
      pair: { version: 2, name: "Android tablet", code: status.code },
    });
    const saved = paired.paired._0;
    assert.equal(saved.token.length, 64);
    await new Promise((r) => setTimeout(r, 30));
    const resumed = await connect(status.port, saved.token, {
      resume: { version: 2, deviceID: saved.deviceID, token: saved.token },
    });
    assert.equal(resumed.paired._0.deviceID, saved.deviceID);
    server.remove(saved.deviceID);
    const newCode = server.status().code;
    assert.notEqual(newCode, status.code);
    server.stop();
    server = new LinkServer(path.join(folder, "pairs.json"), "Test Producer");
    const next = await server.start();
    const removed = await connect(next.port, saved.token, {
      resume: { version: 2, deviceID: saved.deviceID, token: saved.token },
    });
    assert.deepEqual(removed, { removed: {} });
    await assert.rejects(
      connect(next.port, "WRONGCODE1234", {
        pair: { version: 2, name: "intruder", code: "WRONGCODE1234" },
      }),
    );
  } finally {
    server.stop();
    fs.rmSync(folder, { recursive: true, force: true });
  }
});
test("reading positions move within a line and expose the next unread line at its final word", () => {
  const { spread } = require("../tracking.cjs");
  const positions = spread([0, 0, 0, 60, 60, 60, 120], 60, 200);
  assert.equal(positions[2], 30);
  assert.equal(positions[5], 90);
  assert.ok(positions[4] > positions[3]);
});
test("follow motion keeps velocity between recognition updates without overshooting", () => {
  const { FollowMotion } = require("../tracking.cjs");
  const motion = new FollowMotion();
  let value = 0;
  for (let i = 0; i < 60; i++) {
    const before = value;
    value = motion.advance(value, 120, 1 / 60, 60);
    assert.ok(value >= before && value <= 120);
    assert.ok(value - before <= 4);
  }
  assert.ok(value > 115);
});
