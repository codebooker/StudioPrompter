"use strict";
// Port of PrompterCore ScriptMatcher, ReadingPositions and FollowMotion.
const tokenize = (text) =>
  text
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/’/g, "'")
    .match(/[\p{L}\p{N}]+(?:'([\p{L}\p{N}]+))?/gu) || [];
function localAlign(heard, script, anchor) {
  const lower = Math.max(0, anchor - 36),
    upper = Math.min(script.length, anchor + 70),
    target = script.slice(lower, upper),
    rows = heard.length,
    columns = target.length;
  if (!columns) return null;
  const grid = (fill) =>
    Array.from({ length: rows + 1 }, () => Array(columns + 1).fill(fill));
  const costs = grid(0),
    matches = grid(0),
    lastHeard = grid(-1),
    lastScript = grid(-1);
  for (let i = 1; i <= rows; i++) {
    costs[i][0] = i * 0.9;
    for (let j = 1; j <= columns; j++) {
      const equal = heard[i - 1] === target[j - 1],
        diagonal = costs[i - 1][j - 1] + (equal ? 0 : 1),
        insertion = costs[i - 1][j] + 0.9,
        deletion = costs[i][j - 1] + 0.65;
      let pi, pj;
      if (diagonal <= insertion && diagonal <= deletion) {
        costs[i][j] = diagonal;
        pi = i - 1;
        pj = j - 1;
        matches[i][j] = matches[pi][pj] + (equal ? 1 : 0);
        lastHeard[i][j] = equal ? i - 1 : lastHeard[pi][pj];
        lastScript[i][j] = equal ? j - 1 : lastScript[pi][pj];
      } else {
        if (insertion <= deletion) {
          costs[i][j] = insertion;
          pi = i - 1;
          pj = j;
        } else {
          costs[i][j] = deletion;
          pi = i;
          pj = j - 1;
        }
        matches[i][j] = matches[pi][pj];
        lastHeard[i][j] = lastHeard[pi][pj];
        lastScript[i][j] = lastScript[pi][pj];
      }
    }
  }
  let best = null;
  for (let j = 1; j <= columns; j++) {
    const exact = lastScript[rows][j];
    if (exact < 0 || rows - 1 - lastHeard[rows][j] > 4) continue;
    const index = lower + exact,
      confidence = 1 - costs[rows][j] / rows;
    if (
      matches[rows][j] < Math.max(3, Math.ceil(rows * 0.55)) ||
      confidence < 0.63
    )
      continue;
    const score = costs[rows][j] + Math.abs(index - anchor) * 0.012;
    if (!best || score < best.score)
      best = { cursor: index + 1, score, confidence };
  }
  return best;
}
function align(text, transcript, cursor) {
  const script = tokenize(text),
    heard = tokenize(transcript).slice(-16);
  if (heard.length < 3 || !script.length) return null;
  let best = localAlign(heard, script, cursor);
  for (const count of [8, 5, 3])
    if (heard.length > count) {
      const suffix = heard.slice(-count),
        candidate = localAlign(suffix, script, cursor);
      if (
        !candidate ||
        candidate.confidence < (count === 3 ? 0.999 : 0.85) ||
        candidate.cursor - 1 < cursor ||
        candidate.cursor - 1 > cursor + 32 ||
        (best && candidate.cursor <= best.cursor)
      )
        continue;
      if (count === 3) {
        let occurrences = 0;
        for (
          let i = Math.max(0, cursor - 12);
          i < Math.min(script.length - 2, cursor + 33);
          i++
        )
          if (suffix.every((w, j) => w === script[i + j])) occurrences++;
        if (occurrences !== 1) continue;
      }
      best = candidate;
    }
  return best;
}
function spread(lineStarts, lineStep, limit) {
  const result = [...lineStarts];
  let first = 0;
  while (first < lineStarts.length) {
    let next = first + 1;
    while (
      next < lineStarts.length &&
      Math.abs(lineStarts[next] - lineStarts[first]) < 0.5
    )
      next++;
    const end = next < lineStarts.length ? lineStarts[next] : limit;
    for (let i = first; i < next; i++)
      result[i] = Math.max(
        0,
        lineStarts[first] +
          ((end - lineStarts[first]) * (i - first)) / (next - first) -
          lineStep / 2,
      );
    if (next < lineStarts.length)
      result[next - 1] = Math.max(0, end - lineStep / 2);
    first = next;
  }
  return result;
}
class FollowMotion {
  constructor() {
    this.velocity = 0;
  }
  advance(current, target, seconds, lineStep) {
    const distance = Math.max(0, target - current);
    if (distance <= 0) {
      this.velocity = 0;
      return current;
    }
    const omega = 10,
      decay = Math.exp(-omega * seconds),
      coefficient = this.velocity - omega * distance,
      eased = distance + (-distance + coefficient * seconds) * decay;
    this.velocity = Math.min(
      lineStep * 4,
      Math.max(0, (this.velocity - omega * coefficient * seconds) * decay),
    );
    const step = Math.max(0, Math.min(distance, lineStep * 4 * seconds, eased));
    if (step >= distance) this.velocity = 0;
    return current + step;
  }
}

const api = window.studio;
const captureURL = new URL("capture-worklet.js", document.currentScript.src)
  .href;
let mirrorHorizontal = false,
  mirrorVertical = false,
  revision = null,
  remote = null,
  speechTarget = null,
  matchedWord = 0,
  heardPace = 130,
  lastSpeech = 0,
  matchedAt = -Infinity,
  renderedLineStep = 60,
  paceEstimator = new StudioPresentation.PaceEstimator();
let followMotion = new FollowMotion(),
  wordPositions = [],
  focusLines = [],
  layoutDirty = true,
  lastMetricsFrame = 0;
let audioContext = null,
  micStream = null,
  processor = null,
  micGeneration = 0,
  recognizing = false;
const voice = document.createElement("section");
voice.className = "desktop-card";
voice.innerHTML =
  '<label class="toggle-row"><b>Voice prompting</b><input id="voice-enabled" type="checkbox" role="switch"></label><select id="voice-mode" aria-label="Voice mode"><option value="follow">Follow script</option><option value="adaptive">Adaptive pace</option></select><select id="voice-model" aria-label="Speech model"><option value="tiny.en">Tiny English · fastest</option><option value="base.en">Base English · accurate</option></select><button id="download-model">Download model</button><p id="voice-status" class="status">Checking local model…</p><p id="voice-detail" aria-live="polite"></p><select id="mic" aria-label="Microphone"><option value="">System default microphone</option></select><select id="mic-channel" aria-label="Microphone channel"><option value="0">Channel 1</option><option value="1">Channel 2</option></select><meter id="mic-level" min="0" max="1" value="0" aria-label="Selected microphone level"></meter><p>Processes speech locally. Play starts the mic; Pause stops it. This preview has no hands-free commands.</p>';
document.querySelector(".settings").prepend(voice);
const mirror = document.createElement("section");
mirror.className = "desktop-card";
mirror.innerHTML =
  '<b>Mirror & flip · output only</b><label class="toggle-row">Mirror horizontally <input id="mirror-horizontal" type="checkbox"></label><label class="toggle-row">Flip vertically <input id="mirror-vertical" type="checkbox"></label>';
document.querySelector(".settings").append(mirror);
for (const id of ["mirror-horizontal", "mirror-vertical"])
  $(id).onchange = () => {
    mirrorHorizontal = $("mirror-horizontal").checked;
    mirrorVertical = $("mirror-vertical").checked;
    updateDocument();
  };
const prefsKey = "studio-desktop-preferences-v1";
let savedPrefs = {};
try {
  savedPrefs = JSON.parse(localStorage.getItem(prefsKey)) || {};
} catch {}
if (["tiny.en", "base.en"].includes(savedPrefs.model))
  $("voice-model").value = savedPrefs.model;
if (["follow", "adaptive"].includes(savedPrefs.mode))
  $("voice-mode").value = savedPrefs.mode;
$("voice-enabled").checked = savedPrefs.enabled === true;
if (
  Number.isInteger(savedPrefs.channel) &&
  savedPrefs.channel >= 0 &&
  savedPrefs.channel < 32
) {
  const select = $("mic-channel");
  while (select.options.length <= savedPrefs.channel)
    select.add(
      new Option(
        `Channel ${select.options.length + 1}`,
        String(select.options.length),
      ),
    );
  select.value = String(savedPrefs.channel);
}
$("mirror-horizontal").checked = mirrorHorizontal =
  savedPrefs.mirrorHorizontal === true;
$("mirror-vertical").checked = mirrorVertical =
  savedPrefs.mirrorVertical === true;
function savePrefs() {
  try {
    localStorage.setItem(
      prefsKey,
      JSON.stringify({
        model: $("voice-model").value,
        mode: $("voice-mode").value,
        enabled: $("voice-enabled").checked,
        microphone: $("mic").value,
        channel: Number($("mic-channel").value),
        mirrorHorizontal: $("mirror-horizontal").checked,
        mirrorVertical: $("mirror-vertical").checked,
      }),
    );
  } catch {
    toast("Could not save voice preferences");
  }
}
for (const id of [
  "voice-model",
  "voice-mode",
  "voice-enabled",
  "mic",
  "mic-channel",
  "mirror-horizontal",
  "mirror-vertical",
])
  $(id).addEventListener("change", savePrefs);
async function modelStatus() {
  try {
    const s = await api.modelStatus($("voice-model").value);
    $("download-model").hidden = s.ready;
    $("voice-status").textContent = s.ready
      ? "Model ready · works offline"
      : "Download a model to use voice prompting";
  } catch (e) {
    $("voice-status").textContent = e.message;
  }
}
$("voice-model").onchange = () => {
  stopMic();
  pause();
  modelStatus();
};
$("download-model").onclick = async () => {
  const b = $("download-model");
  b.disabled = true;
  try {
    await api.downloadModel($("voice-model").value);
    await modelStatus();
  } catch (e) {
    $("voice-status").textContent = e.message;
  } finally {
    b.disabled = false;
  }
};
api.onModelProgress(
  ({ received, total }) =>
    ($("voice-status").textContent =
      `Downloading model · ${Math.round((received / total) * 100)}%`),
);
async function microphones() {
  const devices = await navigator.mediaDevices.enumerateDevices();
  const select = $("mic"),
    saved = select.value || savedPrefs.microphone || "";
  select.replaceChildren(new Option("System default microphone", ""));
  for (const d of devices.filter((d) => d.kind === "audioinput"))
    select.add(new Option(d.label || "Microphone", d.deviceId));
  select.value = saved;
}
$("mic").onchange = $("mic-channel").onchange = () => {
  pause();
};
$("voice-enabled").onchange = () => {
  pause();
};
$("voice-mode").onchange = () => {
  speechTarget = null;
};
function stopMic() {
  const wasListening = micStream !== null;
  micGeneration++;
  micStream?.getTracks().forEach((t) => t.stop());
  micStream = null;
  processor?.disconnect();
  processor = null;
  audioContext?.close().catch(() => {});
  audioContext = null;
  api.stopSpeech();
  if ($("voice-detail")) $("voice-detail").textContent = "";
  speechTarget = null;
  recognizing = false;
  followMotion = new FollowMotion();
  paceEstimator = new StudioPresentation.PaceEstimator();
  matchedAt = -Infinity;
  if ($("mic-level")) $("mic-level").value = 0;
  if (wasListening)
    $("voice-status").textContent = "Microphone off · ready for Play";
}
function wav(samples) {
  const b = new ArrayBuffer(44 + samples.length * 2),
    v = new DataView(b);
  const str = (at, s) => {
    for (let i = 0; i < s.length; i++) v.setUint8(at + i, s.charCodeAt(i));
  };
  str(0, "RIFF");
  v.setUint32(4, b.byteLength - 8, true);
  str(8, "WAVE");
  str(12, "fmt ");
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, 1, true);
  v.setUint32(24, 16000, true);
  v.setUint32(28, 32000, true);
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  str(36, "data");
  v.setUint32(40, samples.length * 2, true);
  for (let i = 0; i < samples.length; i++)
    v.setInt16(44 + i * 2, Math.max(-1, Math.min(1, samples[i])) * 32767, true);
  return new Uint8Array(b);
}
async function startMic() {
  if (micStream) return;
  if (!(await api.modelStatus($("voice-model").value)).ready)
    throw Error("Download a speech model first");
  const generation = ++micGeneration;
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      deviceId: $("mic").value ? { exact: $("mic").value } : undefined,
      channelCount: { ideal: 8 },
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
    },
    video: false,
  });
  if (generation !== micGeneration) {
    stream.getTracks().forEach((t) => t.stop());
    return;
  }
  micStream = stream;
  audioContext = new AudioContext({
    sampleRate: 16000,
    latencyHint: "interactive",
  });
  if (audioContext.sampleRate !== 16000)
    throw Error("Microphone capture could not initialize at 16 kHz");
  await audioContext.resume();
  const source = audioContext.createMediaStreamSource(stream);
  const channels = stream.getAudioTracks()[0].getSettings().channelCount || 1;
  const selector = $("mic-channel"),
    picked = Number(selector.value);
  selector.replaceChildren();
  for (let n = 0; n < channels; n++)
    selector.add(new Option(`Channel ${n + 1}`, String(n)));
  selector.value = String(Math.min(picked, channels - 1));
  const captureContext = audioContext;
  await captureContext.audioWorklet.addModule(captureURL);
  if (generation !== micGeneration) return;
  processor = new AudioWorkletNode(captureContext, "studio-capture", {
    numberOfInputs: 1,
    numberOfOutputs: 1,
    outputChannelCount: [1],
    channelCount: channels,
    channelCountMode: "explicit",
    channelInterpretation: "discrete",
    processorOptions: { channel: Number(selector.value) },
  });
  source.connect(processor);
  processor.connect(audioContext.destination);
  let samples = [],
    since = 0,
    lastEnergy = -Infinity,
    captured = 0,
    requests = 0,
    emptyResults = 0;
  processor.port.onmessage = (event) => {
    if (generation !== micGeneration) return;
    const input = event.data;
    const energy = StudioAudio.rms(input);
    $("mic-level").value = Math.min(1, energy * 8);
    if (energy > StudioAudio.speechFloor) lastEnergy = performance.now();
    samples.push(...input);
    since += input.length;
    captured += input.length;
    if (samples.length > 96000) samples = samples.slice(-96000);
    if (
      since >= 4800 &&
      samples.length >= 16000 &&
      !recognizing &&
      performance.now() - lastEnergy < 650
    ) {
      since = 0;
      // Recent activity is enough: averaging a short phrase with the silence
      // in this rolling window used to block quiet laptop microphones.
      const chunk = StudioAudio.normalize(samples);
      const audioEnd = captured / 16000;
      recognizing = true;
      requests++;
      $("voice-detail").textContent = `Transcribing locally · pass ${requests}`;
      api
        .transcribe($("voice-model").value, wav(chunk))
        .then((recognition) => {
          if (generation !== micGeneration) return;
          if (!recognition) {
            $("voice-detail").textContent =
              "Speech engine busy · waiting for next audio";
            return;
          }
          if (!recognition.text.trim()) {
            emptyResults++;
            $("voice-detail").textContent =
              `Audio processed · no clear words yet (${recognition.inferenceSeconds.toFixed(2)} s)`;
            if (emptyResults >= 3)
              $("voice-status").textContent =
                "Whisper hears audio but cannot identify words. Check the microphone channel or try Base English.";
            return;
          }
          emptyResults = 0;
          const duration = chunk.length / 16000,
            tokens = recognition.tokens.filter(
              (t) =>
                typeof t.text === "string" &&
                Number.isFinite(t.start) &&
                Number.isFinite(t.end) &&
                t.start >= 0 &&
                t.end >= t.start &&
                t.end <= duration + 0.5,
            );
          // Token timestamps are estimates. An early timestamp must not hide
          // a valid transcript or suppress a reliable script match.
          const text = recognition.text;
          const result = align(plain(current().text), text, matchedWord);
          $("voice-status").textContent = `Heard: ${text.slice(-160)}`;
          $("voice-detail").textContent =
            `${recognition.inferenceSeconds.toFixed(2)} s${recognition.engine ? ` · ${recognition.engine}` : ""} · ${result && result.cursor >= matchedWord ? "Following script" : "Waiting for words that match the script"}`;
          lastSpeech = lastEnergy;
          const first = tokens[0]?.start ?? 0;
          const pace = paceEstimator.observe(
            tokenize(text).length,
            duration - first,
            audioEnd,
          );
          if (pace !== null) heardPace = pace;
          if (result && result.cursor >= matchedWord) {
            if (result.cursor > matchedWord) matchedAt = performance.now();
            matchedWord = result.cursor;
            speechTarget =
              matchedWord >= wordPositions.length
                ? maxScroll()
                : wordPosition(matchedWord);
          }
        })
        .catch((e) => {
          if (generation === micGeneration) {
            pause();
            $("voice-status").textContent = e.message;
          }
        })
        .finally(() => {
          if (generation === micGeneration) recognizing = false;
        });
    }
  };
  $("voice-status").textContent = "Listening to selected microphone channel";
  await microphones();
}
function measureWordPositions() {
  stage.style.setProperty("--scroll-remainder", "0px");
  stage.style.setProperty("--viewport-height", `${stage.clientHeight}px`);
  stage.style.setProperty("--script-size", `${state.settings.size}px`);
  stage.style.setProperty("--script-spacing", state.settings.spacing);
  renderedLineStep = parseFloat(getComputedStyle(content).lineHeight);
  const starts = [];
  focusLines = [];
  let firstTop;
  const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
  let node;
  const origin = stage.getBoundingClientRect().top;
  while ((node = walker.nextNode())) {
    for (const m of node.textContent.matchAll(
      /[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)?/gu,
    )) {
      const range = document.createRange();
      range.setStart(node, m.index);
      range.setEnd(node, m.index + m[0].length);
      const rect = range.getBoundingClientRect();
      const top = reader.scrollTop + rect.top - origin;
      if (firstTop === undefined) firstTop = top;
      // Keep unbounded line starts until spreading. Clamping here merges
      // distinct rows above the guide into one row after a manual retake.
      starts.push(top - firstTop);
      const previous = focusLines.at(-1);
      if (previous && Math.abs(previous.top - top) < 0.5)
        previous.height = Math.max(previous.height, rect.height);
      else focusLines.push({ top, height: rect.height });
    }
  }
  layoutDirty = false;
  wordPositions = spread(starts, renderedLineStep, maxScroll());
}
function wordPosition(index) {
  return clamp(
    wordPositions[Math.max(0, index - 1)] ?? maxScroll(),
    0,
    maxScroll(),
  );
}
function updateFocusBand() {
  if (editing) return;
  if (layoutDirty) measureWordPositions();
  const guide = parseFloat(stage.style.getPropertyValue("--guide-y"));
  const band = StudioPresentation.focusBand(
    guide,
    renderedLineStep,
    state.settings.guideHeight,
    focusLines,
    playing ? playhead : reader.scrollTop,
    stage.clientHeight,
  );
  stage.style.setProperty("--focus-top", `${band.top}px`);
  stage.style.setProperty("--focus-bottom", `${band.bottom}px`);
}
function presentScroll(value) {
  reader.scrollTop = Math.floor(value);
  stage.style.setProperty(
    "--scroll-remainder",
    `${StudioPresentation.scrollRemainder(value, reader.scrollTop)}px`,
  );
  updateFocusBand();
}
const originalPlay = play,
  originalPause = pause;
pause = function (message) {
  stage.style.setProperty("--scroll-remainder", "0px");
  originalPause(message);
  updateFocusBand();
  stopMic();
};
play = async function () {
  if (playing) return pause();
  if (editing) return;
  try {
    if ($("voice-enabled").checked) {
      measureWordPositions();
      matchedWord = wordPositions.findIndex((y) => y >= reader.scrollTop);
      if (matchedWord < 0) matchedWord = 0;
      await startMic();
    }
    originalPlay();
  } catch (e) {
    stopMic();
    $("voice-status").textContent = e.message;
  }
};
// Voice following holds on silence; smooth motion stays bounded by the last match.
tick = function (now) {
  if (!playing) return;
  const dt = Math.min((now - lastFrame) / 1000, 0.08);
  lastFrame = now;
  elapsed += dt;
  if (layoutDirty) {
    measureWordPositions();
    if (speechTarget !== null) speechTarget = wordPosition(matchedWord);
  }
  const limit = maxScroll();
  if (!$("voice-enabled").checked)
    playhead = Math.min(
      limit,
      playhead + (limit / Math.max(duration(), 1)) * dt,
    );
  else if (speechTarget !== null && now - matchedAt < 2000) {
    const active = now - lastSpeech < 3000;
    const target = Math.max(playhead, speechTarget);
    if ($("voice-mode").value === "follow")
      playhead = followMotion.advance(playhead, target, dt, renderedLineStep);
    else if (active) {
      const pace =
        ((limit / Math.max(words(current().text), 1)) * heardPace) / 60;
      // Match native adaptive transport: cadence supplies ordinary movement,
      // and a damped correction keeps it within a quarter line of the match.
      const lower = Math.max(0, target - renderedLineStep * 0.25);
      const correction = followMotion.advance(
        playhead,
        lower,
        dt,
        renderedLineStep,
      );
      playhead = Math.min(
        Math.max(playhead + pace * dt, correction),
        Math.max(playhead, target + renderedLineStep * 0.25),
        limit,
      );
    }
  } else followMotion = new FollowMotion();
  presentScroll(playhead);
  // Timing labels need no more than ten updates per second. Text motion
  // retains a frame callback for every display refresh.
  if (now - lastMetricsFrame >= 100) {
    metrics(limit);
    lastMetricsFrame = now;
  }
  if (playhead >= limit && limit > 0) {
    pause("That’s a wrap.");
    return;
  }
  frame = requestAnimationFrame(tick);
};
$("play").onclick = () => play();
const oldSave = save;
save = function () {
  oldSave();
  api
    .save(JSON.stringify(state))
    .catch((e) => toast(`Could not save library: ${e.message}`));
};
$("library-count").textContent =
  `${state.scripts.length} scripts · Local library`;
$("privacy").onclick = () =>
  info(
    "<h2>Your studio stays local.</h2><p>Scripts are saved on this computer. Speech models download once from Hugging Face, then audio is processed locally with whisper.cpp. Audio is processed in memory and is never saved to disk. Tablet output uses encrypted connections on your local network.</p>",
  );
$("help").onclick = () =>
  info(
    "<h2>StudioPrompter desktop preview</h2><p>Edit and import TXT or Markdown scripts, set bookmarks, and use Play to prompt. Choose a display or pair a tablet from Prompter Output. Enable Voice prompting and download a small English model to follow your microphone.</p><p>This first port does not yet include DOCX/PDF import, Webcam Layout, in-app updates, or hands-free AI commands.</p>",
  );
const pairDialog = document.createElement("dialog");
pairDialog.id = "desktop-pairing";
pairDialog.innerHTML =
  '<h2>Connect a tablet</h2><p>Connect this computer and your tablet to the same local network. Open StudioPrompter Companion and enter this code.</p><p class="pair-code" id="pair-code"></p><p id="pair-network-status"></p><div id="paired-devices"></div><section id="windows-network" hidden><p>If pairing cannot connect, allow the tablet service on your trusted private network. Windows will ask for administrator approval.</p><button id="allow-tablet-network">Allow tablet connections…</button><p id="network-setup-result"></p></section><button id="pair-close">Done</button>';
document.body.append(pairDialog);
$("windows-network").hidden = api.platform !== "win32";
$("allow-tablet-network").onclick = async () => {
  const button = $("allow-tablet-network");
  button.disabled = true;
  $("network-setup-result").textContent =
    "Approve Windows network setup to continue…";
  try {
    const result = await api.allowTabletNetwork();
    $("network-setup-result").textContent = result.privateNetwork
      ? "Tablet connections allowed. Try pairing again on the iPad."
      : "Access configured for private networks. Set this trusted Wi-Fi network to Private in Windows Settings, then try pairing again.";
  } catch (error) {
    $("network-setup-result").textContent = error.message;
  } finally {
    button.disabled = false;
  }
};
$("pair-close").onclick = () => pairDialog.close();
function pairingStatus(value) {
  $("pair-code").textContent = value.code;
  $("pair-network-status").textContent =
    value.connectionStatus || "Waiting for a tablet to connect…";
  const devices = $("paired-devices");
  devices.replaceChildren();
  for (const d of value.devices) {
    const row = document.createElement("div");
    row.className = "pair-device";
    const label = document.createElement("span");
    label.textContent = d.name;
    const remove = document.createElement("button");
    remove.textContent = "Remove";
    remove.onclick = () =>
      api
        .removeDevice(d.id)
        .then(pairingStatus)
        .catch((e) => toast(e.message));
    row.append(label, remove);
    devices.append(row);
  }
}
api.onPairing(pairingStatus);
async function outputMenu() {
  const options = document.querySelector(".output-options");
  options.replaceChildren();
  const make = (label, fn) => {
    const b = document.createElement("button");
    b.textContent = label;
    b.onclick = async () => {
      try {
        await fn();
        $("output-menu").open = false;
      } catch (e) {
        toast(e.message);
      }
    };
    options.append(b);
  };
  make("Producer preview only", () => api.output(null));
  for (const d of await api.displays())
    make(`${d.label}${d.primary ? " · primary" : ""}`, () => api.output(d.id));
  make("Connect a tablet…", async () => {
    pairingStatus(await api.pairing());
    pairDialog.showModal();
  });
  make("Focus view", () => focusMode());
  options.lastElementChild.id = "focus";
}
$("output-menu").addEventListener("toggle", () => {
  if ($("output-menu").open) outputMenu();
});
function updateDocument() {
  if (editing) return;
  measureWordPositions();
  const text = [],
    lines = [],
    emphasis = [];
  let offset = 0;
  const scale = 1000 / Math.max(1, reader.clientWidth);
  const paragraphs = [...content.querySelectorAll("p")];
  const base = paragraphs[0]?.getBoundingClientRect().top || 0;
  for (const p of paragraphs) {
    const walker = document.createTreeWalker(p, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      text.push(node.textContent);
      if (node.parentElement.closest("b,strong"))
        emphasis.push({
          location: offset,
          length: node.length,
          bold: true,
          underline: !!node.parentElement.closest("u"),
        });
      else if (node.parentElement.closest("u"))
        emphasis.push({
          location: offset,
          length: node.length,
          bold: false,
          underline: true,
        });
      for (let i = 0; i < node.length; i++) {
        const range = document.createRange();
        range.setStart(node, i);
        range.setEnd(node, i + 1);
        const r = range.getBoundingClientRect();
        const y = Math.max(0, (r.top - base) * scale);
        const previous = lines.at(-1);
        if (
          previous &&
          Math.abs(previous.y - y) < 1 &&
          previous.location + previous.length === offset + i
        )
          previous.length++;
        else
          lines.push({
            location: offset + i,
            length: 1,
            y,
            height: r.height * scale,
          });
      }
      offset += node.length;
    }
    text.push("\n\n");
    offset += 2;
  }
  revision = crypto.randomUUID();
  const s = state.settings;
  const fontSize = s.size * scale;
  remote = {
    revision,
    script: {
      id: crypto.randomUUID(),
      title: current().title,
      text: text.join(""),
      modified: Date.now() / 1000 - 978307200,
      cues: [],
      emphasis,
      settings: {
        wordsPerMinute: s.speed,
        fontSize,
        lineSpacing: s.spacing,
        margin: s.margins * 10,
        countdown: 0,
        mirrorHorizontal,
        mirrorVertical,
        showGuide: s.guide,
        guidePosition: s.guidePosition / 100,
        guideLines: s.guideHeight,
        focusMode: s.focusLine,
        typeface: s.font === "avenir" ? "avenirNext" : s.font,
      },
    },
    lines,
    textHeight: Math.max(
      fontSize * 1.2,
      ((paragraphs.at(-1)?.getBoundingClientRect().bottom ??
        base + state.settings.size * 1.2) -
        base) *
        scale,
    ),
    lineHeight: renderedLineStep * scale,
  };
  api.document(remote).catch((e) => toast(e.message));
}
let documentTimer;
const observer = new MutationObserver(() => {
  layoutDirty = true;
  requestAnimationFrame(updateFocusBand);
  clearTimeout(documentTimer);
  documentTimer = setTimeout(updateDocument, 120);
});
observer.observe(content, {
  childList: true,
  subtree: true,
  attributes: true,
  characterData: true,
});
window.addEventListener("resize", () => {
  layoutDirty = true;
  requestAnimationFrame(updateFocusBand);
  clearTimeout(documentTimer);
  documentTimer = setTimeout(updateDocument, 200);
});
for (const input of document.querySelectorAll(
  ".settings input,.settings select",
))
  input.addEventListener("change", () => {
    clearTimeout(documentTimer);
    documentTimer = setTimeout(updateDocument, 100);
  });
setInterval(() => {
  if (!remote) return;
  const first = content.querySelector("p");
  const guide = parseFloat(stage.style.getPropertyValue("--guide-y"));
  const consumed = first
    ? Math.max(
        0,
        stage.getBoundingClientRect().top +
          guide -
          first.getBoundingClientRect().top -
          state.settings.size * 0.2,
      )
    : 0;
  const progress = clamp(
    (consumed * (1000 / reader.clientWidth)) /
      Math.max(1, remote.textHeight - remote.script.settings.fontSize * 1.2),
    0,
    1,
  );
  api
    .playback({
      revision,
      progress,
      playing,
      blackout,
      countdown: 0,
      notice: null,
    })
    .catch(() => {});
}, 50);
modelStatus();
microphones().catch(() => {});
updateDocument();

api
  .load()
  .then((library) => {
    if (!library || editing || playing) return;
    try {
      const restored = validState(JSON.parse(library));
      if (restored) {
        state = restored;
        render();
        updateDocument();
      }
    } catch {
      toast(
        "The saved library could not be read. Its files have been preserved.",
      );
    }
  })
  .catch((e) => toast(e.message));

// Changes to reader geometry also happen when entering/leaving the editor or
// focus view, without a window resize. Rebuild positions once, never per frame.
new ResizeObserver(() => {
  layoutDirty = true;
  requestAnimationFrame(updateFocusBand);
}).observe(reader);
reader.addEventListener("scroll", () => {
  if (!playing) updateFocusBand();
});
requestAnimationFrame(updateFocusBand);
