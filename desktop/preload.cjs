"use strict";
const { contextBridge, ipcRenderer } = require("electron");
const on = (channel, callback) => {
  const fn = (_event, value) => callback(value);
  ipcRenderer.on(channel, fn);
  return () => ipcRenderer.removeListener(channel, fn);
};
contextBridge.exposeInMainWorld("studio", {
  platform: process.platform,
  allowTabletNetwork: () => ipcRenderer.invoke("allow-tablet-network"),
  displays: () => ipcRenderer.invoke("displays"),
  output: (id) => ipcRenderer.invoke("output", id),
  pairing: () => ipcRenderer.invoke("pairing"),
  removeDevice: (id) => ipcRenderer.invoke("remove-device", id),
  document: (value) => ipcRenderer.invoke("document", value),
  playback: (value) => ipcRenderer.invoke("playback", value),
  modelStatus: (name) => ipcRenderer.invoke("model-status", name),
  downloadModel: (name) => ipcRenderer.invoke("model-download", name),
  transcribe: (name, audio) => ipcRenderer.invoke("transcribe", name, audio),
  stopSpeech: () => ipcRenderer.invoke("speech-stop"),
  load: () => ipcRenderer.invoke("load-library"),
  closeOutput: () => ipcRenderer.invoke("close-output"),
  save: (library) => ipcRenderer.invoke("save-library", library),
  onDocument: (callback) => on("document", callback),
  onPlayback: (callback) => on("playback", callback),
  onPairing: (callback) => on("pairing-status", callback),
  onModelProgress: (callback) => on("model-progress", callback),
});
