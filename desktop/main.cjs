"use strict";
const {
  app,
  BrowserWindow,
  ipcMain,
  screen,
  Menu,
  session,
  shell,
  protocol,
  net,
} = require("electron");
const { pathToFileURL } = require("node:url");
protocol.registerSchemesAsPrivileged([
  {
    scheme: "studio",
    privileges: { standard: true, secure: true, supportFetchAPI: true },
  },
]);
const path = require("node:path"),
  fs = require("node:fs"),
  os = require("node:os");
const { LinkProcess } = require("./link-process.cjs");
const { Speech } = require("./speech.cjs");
let producer, output, link, speech, documentState, playbackState;
const ui = path.join(__dirname, "ui");
function windowOptions(extra = {}) {
  return {
    backgroundColor: "#111316",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: false,
    },
    ...extra,
  };
}
function safeWindow(window) {
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (e) => e.preventDefault());
}
function authorized(event) {
  if (event.sender !== producer?.webContents)
    throw Error("Producer access required");
}
function sendOutput(channel, value) {
  if (output && !output.isDestroyed()) output.webContents.send(channel, value);
}
app.whenReady().then(() => {
  app.setName("StudioPrompter");
  protocol.handle("studio", (request) => {
    const url = new URL(request.url);
    if (url.hostname !== "app" || !/^\/[a-zA-Z0-9.-]+$/.test(url.pathname))
      return new Response("Not found", { status: 404 });
    const file = path.join(ui, url.pathname.slice(1));
    return net.fetch(pathToFileURL(file).toString());
  });
  if (process.platform === "darwin")
    app.dock.setIcon(path.join(ui, "app-icon.png"));
  screen.on("display-removed", () => {
    output?.close();
    output = null;
  });
  session.defaultSession.setPermissionRequestHandler(
    (contents, permission, callback) =>
      callback(contents === producer?.webContents && permission === "media"),
  );
  session.defaultSession.setPermissionCheckHandler(
    (contents, permission) =>
      contents === producer?.webContents && permission === "media",
  );
  producer = new BrowserWindow(
    windowOptions({
      width: 1440,
      height: 920,
      minWidth: 1024,
      minHeight: 720,
      title: "StudioPrompter",
      icon: path.join(ui, "app-icon.png"),
    }),
  );
  safeWindow(producer);
  producer.loadURL("studio://app/index.html");
  const storage = app.getPath("userData");
  fs.mkdirSync(storage, { recursive: true, mode: 0o700 });
  link = new LinkProcess(
    path.join(storage, "pairings.json"),
    os.hostname(),
    app.isPackaged
      ? path.join(process.resourcesPath, "runtime")
      : path.join(__dirname, "runtime"),
    (value) => producer?.webContents.send("pairing-status", value),
  );
  // Keep discovery available for saved tablets, including offline revocation notices.
  if (link.saved.devices.length > 0) {
    link
      .start()
      .catch((error) =>
        console.error("Tablet output could not start:", error.message),
      );
  }
  speech = new Speech(
    path.join(storage, "models"),
    app.isPackaged
      ? path.join(process.resourcesPath, "runtime")
      : path.join(__dirname, "runtime"),
    (value) => producer?.webContents.send("model-progress", value),
  );
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      { label: "File", submenu: [{ role: "quit" }] },
      {
        label: "Edit",
        submenu: [
          { role: "undo" },
          { role: "redo" },
          { type: "separator" },
          { role: "cut" },
          { role: "copy" },
          { role: "paste" },
          { role: "selectAll" },
        ],
      },
      { label: "View", submenu: [{ role: "togglefullscreen" }] },
      {
        label: "Help",
        submenu: [
          {
            label: "StudioPrompter on GitHub",
            click: () =>
              shell.openExternal(
                "https://github.com/codebooker/StudioPrompter",
              ),
          },
        ],
      },
    ]),
  );
  producer.on("closed", () => {
    producer = null;
    app.quit();
  });
});
ipcMain.handle("displays", (event) => {
  authorized(event);
  return screen.getAllDisplays().map((d) => ({
    id: d.id,
    label: d.label || `Display ${d.id}`,
    primary: d.id === screen.getPrimaryDisplay().id,
  }));
});
ipcMain.handle("output", async (event, id) => {
  authorized(event);
  output?.close();
  output = null;
  if (id === null) return;
  const display = screen.getAllDisplays().find((d) => d.id === id);
  if (!display) throw Error("Display disconnected");
  output = new BrowserWindow(
    windowOptions({
      x: display.bounds.x,
      y: display.bounds.y,
      width: display.bounds.width,
      height: display.bounds.height,
      frame: false,
      fullscreen: true,
      title: "StudioPrompter Output",
    }),
  );
  safeWindow(output);
  await output.loadURL("studio://app/output.html");
  sendOutput("document", documentState);
  sendOutput("playback", playbackState);
});
ipcMain.handle("close-output", (event) => {
  if (event.sender !== output?.webContents)
    throw Error("Reading display access required");
  output.close();
  output = null;
});
ipcMain.handle("pairing", async (event) => {
  authorized(event);
  return link.start();
});
ipcMain.handle("remove-device", async (event, id) => {
  authorized(event);
  return link.remove(id);
});
ipcMain.handle("document", (event, value) => {
  authorized(event);
  link.documentUpdate(value);
  documentState = value;
  sendOutput("document", value);
});
ipcMain.handle("playback", (event, value) => {
  authorized(event);
  link.playbackUpdate(value);
  playbackState = value;
  sendOutput("playback", value);
});
ipcMain.handle("model-status", (event, name) => {
  authorized(event);
  return speech.status(name);
});
ipcMain.handle("model-download", (event, name) => {
  authorized(event);
  return speech.download(name);
});
ipcMain.handle("transcribe", (event, name, bytes) => {
  authorized(event);
  return speech.transcribe(name, bytes);
});
ipcMain.handle("speech-stop", (event) => {
  authorized(event);
  speech.stop();
});
ipcMain.handle("load-library", (event) => {
  authorized(event);
  const file = path.join(app.getPath("userData"), "library.json");
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
});
ipcMain.handle("save-library", (event, library) => {
  authorized(event);
  if (typeof library !== "string" || library.length > 4000000)
    throw Error("Library exceeds limit");
  const data = JSON.parse(library);
  if (!Array.isArray(data.scripts) || data.scripts.length > 30)
    throw Error("Invalid library");
  const folder = path.join(app.getPath("userData"), "Scripts");
  fs.mkdirSync(folder, { recursive: true });
  for (const s of data.scripts) {
    if (!/^[a-zA-Z0-9-]+$/.test(s.id) || typeof s.text !== "string")
      throw Error("Invalid script");
    fs.writeFileSync(path.join(folder, s.id + ".md"), s.text, { mode: 0o600 });
  }
  fs.writeFileSync(
    path.join(app.getPath("userData"), "library.json.tmp"),
    library,
    { mode: 0o600 },
  );
  fs.renameSync(
    path.join(app.getPath("userData"), "library.json.tmp"),
    path.join(app.getPath("userData"), "library.json"),
  );
});
app.on("before-quit", () => {
  link?.stop();
  speech?.stop();
});
