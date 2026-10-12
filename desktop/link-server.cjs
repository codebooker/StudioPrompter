"use strict";
const tls = require("node:tls");
const fs = require("node:fs");
const crypto = require("node:crypto");
const { Bonjour } = require("bonjour-service");
const {
  identity,
  secret,
  newCode,
  normalize,
  frame,
  Decoder,
  validDocument,
  validPlayback,
} = require("./protocol.cjs");
class LinkServer {
  constructor(file, name, changed = () => {}) {
    this.file = file;
    this.name = name;
    this.changed = changed;
    this.clients = new Set();
    if (fs.existsSync(file)) this.saved = JSON.parse(fs.readFileSync(file));
    else {
      this.saved = {
        hostID: crypto.randomUUID().toUpperCase(),
        pairingCode: newCode(),
        devices: [],
      };
      this.persist();
    }
    this.serviceName = "StudioPrompter-" + this.saved.hostID.slice(0, 8);
  }
  persist() {
    fs.writeFileSync(this.file + ".tmp", JSON.stringify(this.saved), {
      mode: 0o600,
    });
    fs.renameSync(this.file + ".tmp", this.file);
  }
  status() {
    return {
      code: this.saved.pairingCode,
      devices: this.saved.devices
        .filter((d) => !d.removed)
        .map(({ id, name }) => ({ id, name })),
      port: this.server?.address()?.port,
      connectionStatus:
        this.connectionStatus || "Waiting for a tablet to connect…",
    };
  }
  async start() {
    if (this.server) return this.status();
    this.server = tls.createServer(
      {
        minVersion: "TLSv1.2",
        maxVersion: "TLSv1.2",
        ciphers: "PSK-AES128-GCM-SHA256",
        pskCallback: (_socket, label) => {
          const key = [
            this.saved.pairingCode,
            ...this.saved.devices.map((d) => d.token),
          ].find((k) => identity(k) === label);
          this.connectionStatus = key
            ? "Tablet reached this computer · checking pairing…"
            : "A tablet reached this computer, but its pairing code was not accepted.";
          this.changed(this.status());
          return key ? secret(key) : null;
        },
      },
      (socket) => this.accept(socket),
    );
    this.server.on("tlsClientError", (error) => {
      if (!this.connectionStatus?.includes("not accepted"))
        this.connectionStatus = `Tablet connection could not complete (${error.code || "TLS error"}). Check its pairing code.`;
      this.changed(this.status());
    });
    await new Promise((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen({ port: 0, ipv6Only: false }, resolve);
    });
    this.bonjour = new Bonjour();
    this.advert = this.bonjour.publish({
      name: this.serviceName,
      type: "studioprompt",
      port: this.server.address().port,
      txt: { name: this.name },
    });
    return this.status();
  }
  accept(socket) {
    socket.setNoDelay(true);
    socket.setTimeout(15000, () => socket.destroy());
    const client = { socket, id: null };
    this.clients.add(client);
    socket.on("close", () => {
      this.clients.delete(client);
      this.changed(this.status());
    });
    socket.on("error", () => {});
    const decoder = new Decoder((message) => {
      if (client.id) return socket.destroy();
      let device;
      if (
        message.pair?.version === 2 &&
        typeof message.pair.name === "string" &&
        Buffer.byteLength(message.pair.name) <= 128 &&
        normalize(String(message.pair.code)) === this.saved.pairingCode
      ) {
        device = {
          id: crypto.randomUUID().toUpperCase(),
          name: message.pair.name,
          token: crypto.randomBytes(32).toString("hex").toUpperCase(),
          removed: false,
        };
        this.saved.devices.push(device);
        this.persist();
      } else if (message.resume?.version === 2)
        device = this.saved.devices.find(
          (d) =>
            d.id.toUpperCase() ===
              String(message.resume.deviceID).toUpperCase() &&
            d.token === message.resume.token,
        );
      if (!device) return socket.destroy();
      if (device.removed) return socket.end(frame({ removed: {} }));
      if ([...this.clients].some((c) => c !== client && c.id))
        return socket.end(
          frame({
            unavailable: {
              _0: "Another tablet is receiving this producer feed.",
            },
          }),
        );
      client.id = device.id;
      this.connectionStatus = `Connected to ${device.name}`;
      socket.setTimeout(0);
      socket.write(
        frame({
          paired: {
            _0: {
              hostID: this.saved.hostID,
              name: this.name,
              serviceName: this.serviceName,
              deviceID: device.id,
              token: device.token,
              removed: false,
            },
          },
        }),
      );
      if (this.document)
        socket.write(frame({ document: { _0: this.document } }));
      if (this.playback && this.playback.revision === this.document?.revision)
        socket.write(frame({ playback: { _0: this.playback } }));
      this.changed(this.status());
    });
    socket.on("data", (data) => {
      try {
        decoder.push(data);
      } catch {
        socket.destroy();
      }
    });
  }
  documentUpdate(document) {
    if (!validDocument(document)) throw Error("Invalid document");
    this.document = document;
    this.playback = null;
    this.send({ document: { _0: document } });
  }
  playbackUpdate(state) {
    if (!validPlayback(state) || state.revision !== this.document?.revision)
      return;
    this.playback = state;
    this.send({ playback: { _0: state } }, true);
  }
  send(message, motion = false) {
    const data = frame(message);
    for (const c of this.clients)
      if (c.id) {
        if (c.socket.writableLength > 1024 * 1024) c.socket.destroy();
        else if (!motion || c.socket.writableLength === 0) c.socket.write(data);
      }
  }
  remove(id) {
    const device = this.saved.devices.find((d) => d.id === id);
    if (!device) return;
    device.removed = true;
    this.saved.pairingCode = newCode();
    this.persist();
    for (const c of this.clients)
      if (c.id === id) c.socket.end(frame({ removed: {} }));
    this.changed(this.status());
  }
  stop() {
    for (const c of this.clients) c.socket.end(frame({ stopped: {} }));
    this.advert?.stop();
    this.bonjour?.destroy();
    this.server?.close();
    this.server = null;
  }
}
module.exports = { LinkServer };
