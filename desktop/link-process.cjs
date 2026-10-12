"use strict";
const { spawn } = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");
const {
  frame,
  Decoder,
  validDocument,
  validPlayback,
} = require("./protocol.cjs");
class LinkProcess {
  constructor(file, name, runtime, changed = () => {}) {
    this.file = file;
    this.name = name;
    this.runtime = runtime;
    this.changed = changed;
    this.pending = new Map();
    this.nextID = 0;
    this.snapshot = null;
    this.saved = fs.existsSync(file)
      ? JSON.parse(fs.readFileSync(file, "utf8"))
      : { devices: [] };
  }
  launch() {
    if (this.child) return;
    const binary = path.join(
      this.runtime,
      process.platform === "win32" ? "node.exe" : "node",
    );
    const child = spawn(
      binary,
      [path.join(__dirname, "link-host.cjs"), this.file, this.name],
      { windowsHide: true, stdio: ["pipe", "pipe", "pipe"] },
    );
    this.child = child;
    const fail = (error) => {
      if (this.child !== child) return;
      this.child = null;
      for (const p of this.pending.values()) {
        clearTimeout(p.timer);
        p.reject(error);
      }
      this.pending.clear();
    };
    const decoder = new Decoder((message) => {
      if (message.event === "status") {
        this.snapshot = message.value;
        this.changed(message.value);
        return;
      }
      const p = this.pending.get(message.id);
      if (!p) return;
      this.pending.delete(message.id);
      clearTimeout(p.timer);
      message.error
        ? p.reject(Error(message.error))
        : p.resolve(message.result);
    });
    child.stdout.on("data", (bytes) => {
      try {
        decoder.push(bytes);
      } catch {
        fail(Error("Invalid connection service response"));
        child.kill();
      }
    });
    child.stderr.on("data", () => {});
    child.on("error", fail);
    child.on("exit", () => fail(Error("Tablet connection service stopped")));
    child.stdin.on("error", fail);
  }
  request(method, ...args) {
    this.launch();
    const id = ++this.nextID;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(Error("Tablet service timed out"));
      }, 15000);
      this.pending.set(id, { resolve, reject, timer });
      this.child.stdin.write(frame({ id, method, args }));
    });
  }
  notify(method, ...args) {
    if (!this.child) return;
    if (method === "playback" && this.child.stdin.writableLength > 1000000)
      return;
    this.child.stdin.write(frame({ method, args }));
  }
  async start() {
    const value = await this.request("start");
    this.snapshot = value;
    if (this.document) this.notify("document", this.document);
    if (this.playback) this.notify("playback", this.playback);
    return value;
  }
  status() {
    return this.snapshot;
  }
  remove(id) {
    return this.request("remove", id);
  }
  documentUpdate(doc) {
    if (!validDocument(doc)) throw Error("Invalid document");
    this.document = doc;
    this.playback = null;
    this.notify("document", doc);
  }
  playbackUpdate(state) {
    if (!validPlayback(state) || state.revision !== this.document?.revision)
      return;
    this.playback = state;
    this.notify("playback", state);
  }
  stop() {
    if (!this.child) return;
    this.notify("stop");
    this.child.stdin.end();
  }
}
module.exports = { LinkProcess };
