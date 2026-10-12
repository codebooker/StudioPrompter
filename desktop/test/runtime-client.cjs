const tls = require("node:tls");
const { identity, secret, frame, Decoder } = require("../protocol.cjs");
const [port, key, operation, id] = process.argv.slice(2);
let saved, doc, playback;
const socket = tls.connect(
  {
    host: "127.0.0.1",
    port: Number(port),
    minVersion: "TLSv1.2",
    maxVersion: "TLSv1.2",
    // TLS-PSK authenticates the endpoint with the shared key, without a certificate.
    checkServerIdentity: () => undefined,
    ciphers: "PSK-AES128-GCM-SHA256",
    pskCallback: () => ({ identity: identity(key), psk: secret(key) }),
  },
  () =>
    socket.write(
      frame(
        operation === "pair"
          ? { pair: { version: 2, name: "Runtime test tablet", code: key } }
          : { resume: { version: 2, deviceID: id, token: key } },
      ),
    ),
);
const decoder = new Decoder((value) => {
  if (value.paired) saved = value.paired._0;
  if (value.document) doc = value.document._0;
  if (value.playback) playback = value.playback._0;
  if (value.removed) {
    console.log(JSON.stringify({ removed: true }));
    socket.end();
  } else if (saved && doc && playback) {
    console.log(JSON.stringify({ saved, document: doc, playback }));
    socket.end();
  }
});
socket.on("data", (bytes) => decoder.push(bytes));
socket.on("error", error => {console.error(error.message);process.exit(1);});
socket.setTimeout(5000, () => {
  socket.destroy();
  process.exit(1);
});
