"use strict";
const { LinkServer } = require("./link-server.cjs");
const { Decoder, frame } = require("./protocol.cjs");
const reply = (message) => process.stdout.write(frame(message));
const server = new LinkServer(process.argv[2], process.argv[3], (value) =>
  reply({ event: "status", value }),
);
let ending = false;
const shutdown = () => {
  if (ending) return;
  ending = true;
  server.stop();
  setTimeout(() => process.exit(0), 250);
};
const decoder = new Decoder(async (request) => {
  try {
    let result;
    switch (request.method) {
      case "start":
        result = await server.start();
        break;
      case "remove":
        server.remove(request.args[0]);
        result = server.status();
        break;
      case "document":
        server.documentUpdate(request.args[0]);
        break;
      case "playback":
        server.playbackUpdate(request.args[0]);
        break;
      case "stop":
        shutdown();
        break;
      default:
        throw Error("Unsupported connection request");
    }
    if (request.id) reply({ id: request.id, result });
  } catch (error) {
    if (request.id) reply({ id: request.id, error: error.message });
  }
});
process.stdin.on("data", (bytes) => {
  try {
    decoder.push(bytes);
  } catch {
    server.stop();
    process.exit(1);
  }
});
process.stdin.on("end", shutdown);
process.on("SIGTERM", shutdown);
