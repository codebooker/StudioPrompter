"use strict";
const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const { Decoder } = require("./protocol.cjs");
const models = {
  "tiny.en": {
    size: 77704715,
    hash: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
  },
  "base.en": {
    size: 147964211,
    hash: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
  },
};
class Speech {
  constructor(directory, runtime, progress) {
    this.directory = directory;
    this.runtime = runtime;
    this.progress = progress;
    this.busy = false;
    this.downloading = false;
  }
  model(name) {
    if (!models[name]) throw Error("Unsupported speech model");
    return path.join(this.directory, `ggml-${name}.bin`);
  }
  async status(name) {
    const file = this.model(name);
    try {
      return { ready: (await fs.stat(file)).size === models[name].size };
    } catch {
      return { ready: false };
    }
  }
  async download(name) {
    const file = this.model(name),
      spec = models[name];
    if (this.downloading) throw Error("A model is already downloading");
    this.downloading = true;
    const temp = file + ".part";
    let handle;
    try {
      await fs.mkdir(this.directory, { recursive: true, mode: 0o700 });
      const response = await fetch(
        `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${name}.bin`,
        { signal: AbortSignal.timeout(600000) },
      );
      if (!response.ok || !response.body) throw Error("Model download failed");
      handle = await fs.open(temp, "w", 0o600);
      const hash = crypto.createHash("sha256");
      let size = 0,
        last = 0;
      for await (const chunk of response.body) {
        size += chunk.length;
        if (size > spec.size) throw Error("Unexpected model size");
        hash.update(chunk);
        await handle.write(chunk);
        if (Date.now() - last > 200) {
          last = Date.now();
          this.progress({ received: size, total: spec.size });
        }
      }
      await handle.close();
      handle = null;
      if (size !== spec.size || hash.digest("hex") !== spec.hash)
        throw Error("Model integrity check failed");
      await fs.rename(temp, file);
      return { ready: true };
    } finally {
      await handle?.close();
      await fs.rm(temp, { force: true });
      this.downloading = false;
    }
  }
  worker(name) {
    if (this.child && this.loaded === name) return this.child;
    this.stop();
    const exe = path.join(
      this.runtime,
      process.platform === "win32" ? "studio-whisper.exe" : "studio-whisper",
    );
    const child = spawn(exe, [this.model(name)], {
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.child = child;
    this.loaded = name;
    const fail = (error) => {
      if (this.child !== child) return;
      this.child = null;
      this.loaded = null;
      const pending = this.pending;
      this.pending = null;
      if (pending) {
        clearTimeout(pending.timer);
        pending.reject(error);
      }
    };
    const decoder = new Decoder((result) => {
      const pending = this.pending;
      if (!pending) return;
      this.pending = null;
      clearTimeout(pending.timer);
      if (result.error) pending.reject(Error(result.error));
      else if (
        typeof result.text !== "string" ||
        result.text.length > 4096 ||
        !Array.isArray(result.tokens) ||
        result.tokens.length > 1000
      )
        pending.reject(Error("Invalid speech result"));
      else pending.resolve(result);
    });
    child.stdout.on("data", (bytes) => {
      try {
        decoder.push(bytes);
      } catch {
        fail(Error("Invalid speech response"));
        child.kill();
      }
    });
    let diagnostics = "";
    child.stderr.on("data", (bytes) => {
      diagnostics = (diagnostics + bytes.toString()).slice(-4096);
    });
    child.on("error", (error) => fail(error));
    child.on("exit", (code, signal) => {
      const detail = diagnostics
        .split(/\r?\n/)
        .filter((line) => /error|failed|cannot/i.test(line))
        .at(-1);
      fail(
        Error(
          `Speech engine stopped (${signal || code})${detail ? `: ${detail.slice(0, 240)}` : ". Try Tiny English or reinstall this preview."}`,
        ),
      );
    });
    child.stdin.on("error", (error) => fail(error));
    return child;
  }
  async transcribe(name, bytes) {
    if (this.busy) return null;
    const audio = Buffer.from(bytes);
    if (
      audio.length > 320000 ||
      audio.length < 44 ||
      audio.toString("ascii", 0, 4) !== "RIFF" ||
      audio.toString("ascii", 8, 12) !== "WAVE"
    )
      throw Error("Invalid audio");
    if (!(await this.status(name)).ready)
      throw Error("Download the speech model first");
    this.busy = true;
    const started = performance.now();
    try {
      const child = this.worker(name);
      const result = await new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          this.pending = null;
          child.kill();
          reject(Error("Speech processing took too long"));
        }, 20000);
        this.pending = { resolve, reject, timer };
        const header = Buffer.alloc(4);
        header.writeUInt32BE(audio.length);
        child.stdin.write(Buffer.concat([header, audio]));
      });
      return {
        ...result,
        inferenceSeconds: (performance.now() - started) / 1000,
      };
    } finally {
      this.busy = false;
    }
  }
  stop() {
    const pending = this.pending;
    this.pending = null;
    if (pending) {
      clearTimeout(pending.timer);
      pending.reject(Error("Speech stopped"));
    }
    this.child?.kill();
    this.child = null;
    this.loaded = null;
  }
}
module.exports = { Speech, models };
