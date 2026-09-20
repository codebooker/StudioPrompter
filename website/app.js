"use strict";
const $ = (id) => document.getElementById(id);
const assetURL = new URL("icons.svg", document.currentScript.src).href;
const icon = (name) =>
  `<svg class="icon" aria-hidden="true"><use href="${assetURL}#${name}"/></svg>`;
const demoAvailable = () =>
  !window.matchMedia(
    "(max-width: 899px), (hover: none) and (max-height: 500px)",
  ).matches;
const KEY = "studioprompter-web-v1";
const defaults = () => ({
  version: 1,
  selected: "welcome",
  settings: {
    speed: 130,
    size: 38,
    spacing: 1.5,
    font: "system",
    guide: true,
    guidePosition: 28,
    guideHeight: 1,
    margins: 10,
    focusLine: true,
  },
  scripts: [
    {
      id: "welcome",
      title: "A little room for big ideas",
      text: "The best ideas don’t always arrive on cue.\n\nSometimes, they show up in the space between the things we planned. A quiet morning. A conversation that takes an unexpected turn. A moment when we finally slow down enough to listen.\n\n**That’s where the good stuff lives.**\n\nWelcome to StudioPrompter. A little less looking down at your notes. A little more looking someone in the eye.\n\nTry pressing Play. Find a pace that feels like you. If you need to go back, just scroll. There’s no rush. This is your take.\n\nMaybe you’re recording your first video. Maybe you’re producing your hundredth interview. Either way, the goal is the same: be here, with the person on the other side of the lens.\n\n<u>Make room for a pause.</u> Let a thought land. Give the important words a little room to breathe.\n\nYou don’t need to sound perfect. You need to sound like yourself.\n\nAnd when you’re ready, we’ll keep your place.",
      bookmarks: [
        { id: "intro", label: "Welcome to the studio", paragraph: 3 },
        { id: "pause", label: "Make room for a pause", paragraph: 6 },
      ],
    },
    {
      id: "interview",
      title: "Behind the microphone",
      text: "Welcome back. Today, we’re going behind the microphone with someone who sees the world a little differently.\n\nBefore we get to the work, I want to go back to the beginning. What was the first thing that made you think: **I want to do this**?\n\nAnd when you were starting out, what did you get wrong? What would you tell that earlier version of yourself?\n\nLet’s talk about the moment things changed. Was it a big decision, or a series of small ones?\n\n<u>Give the answer room to breathe.</u>\n\nI love that. And for someone listening who’s right at the beginning of their own journey, what’s one small thing they could do today?\n\nThank you for sharing your story. It’s a reminder that the best conversations start with a little curiosity.\n\nWe’ll see you next time.",
      bookmarks: [
        { id: "question", label: "The first question", paragraph: 1 },
        { id: "wrap", label: "One small thing", paragraph: 5 },
      ],
    },
    {
      id: "weekly",
      title: "The weekly update",
      text: "Hey everyone. Here’s what’s happening this week.\n\nFirst, a quick thank you. The work you’ve put in over the last few days has made a real difference. **It shows.**\n\nWe’ve got three things to focus on.\n\nOne: finish what we’ve started. Keep the scope small and the quality high.\n\nTwo: share what we’re learning. A five-minute conversation can save someone a whole afternoon.\n\nThree: leave a little room for the unexpected. That’s often where the best ideas come from.\n\nThat’s it for this week. Take care of yourselves, and let’s make something worth sharing.",
      bookmarks: [{ id: "three", label: "Three things", paragraph: 2 }],
    },
  ],
});
const fonts = {
  system: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
  avenir: '"Avenir Next", Avenir, "Segoe UI", sans-serif',
  arial: "Arial, sans-serif",
  verdana: "Verdana, sans-serif",
  georgia: "Georgia, serif",
};
const uid = () =>
  globalThis.crypto?.randomUUID?.() ||
  `id-${Date.now()}-${Math.random().toString(36).slice(2)}`;
function plain(text) {
  return text.replace(/\*\*|<\/?u>/g, "");
}
function paragraphs(text) {
  return text.split(/\n\s*\n/).filter((p) => p.trim());
}
function words(text) {
  return plain(text).trim().split(/\s+/).filter(Boolean).length;
}
function escapeHTML(text) {
  return text.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
}
function rich(text) {
  return escapeHTML(text)
    .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    .replace(/&lt;u&gt;([\s\S]*?)&lt;\/u&gt;/g, "<u>$1</u>")
    .replace(/\n/g, "<br>");
}
function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}
function validState(value) {
  if (
    value?.version !== 1 ||
    !Array.isArray(value.scripts) ||
    !value.scripts.length ||
    value.scripts.length > 30
  )
    return null;
  const d = defaults();
  const scripts = value.scripts
    .filter(
      (s) =>
        typeof s.id === "string" &&
        typeof s.title === "string" &&
        typeof s.text === "string" &&
        s.text.length <= 100000,
    )
    .map((s) => ({
      id: s.id,
      title: s.title.slice(0, 80),
      text: s.text,
      bookmarks: Array.isArray(s.bookmarks)
        ? s.bookmarks
            .filter(
              (b) =>
                typeof b.label === "string" &&
                Number.isInteger(b.paragraph) &&
                b.paragraph >= 0,
            )
            .slice(0, 50)
            .map((b) => ({
              id: typeof b.id === "string" ? b.id : uid(),
              label: b.label.slice(0, 70),
              paragraph: b.paragraph,
            }))
        : [],
    }));
  if (!scripts.length) return null;
  const s = value.settings || {};
  return {
    version: 1,
    scripts,
    selected: scripts.some((x) => x.id === value.selected)
      ? value.selected
      : scripts[0].id,
    settings: {
      speed: clamp(+s.speed || 130, 40, 260),
      size: clamp(+s.size || 38, 24, 72),
      spacing: clamp(+s.spacing || 1.5, 1.2, 2),
      font: s.font === "arial" ? "avenir" : fonts[s.font] ? s.font : "system",
      margins: clamp(+s.margins || 10, 5, 22),
      focusLine: s.focusLine !== false,
      guide: s.guide !== false,
      guidePosition: clamp(+s.guidePosition || 28, 10, 70),
      guideHeight: clamp(+s.guideHeight || 1, 1, 3),
    },
  };
}
let state = defaults();
try {
  state = validState(JSON.parse(localStorage.getItem(KEY))) || state;
} catch {}
let playing = false,
  editing = false,
  blackout = false,
  elapsed = 0,
  lastFrame = 0,
  frame = 0,
  playhead = 0,
  saveTimer,
  toastTimer,
  drag = null;
const reader = $("reader"),
  content = $("script-content"),
  stage = $("reader-stage");
function current() {
  return state.scripts.find((s) => s.id === state.selected);
}
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    try {
      localStorage.setItem(KEY, JSON.stringify(state));
      $("save-status").innerHTML =
        '<span class="live-dot"></span> Saved in this browser';
    } catch {
      $("save-status").textContent =
        "Storage unavailable · export to keep your script";
    }
  }, 200);
}
function toast(message) {
  $("toast").textContent = message;
  $("toast").classList.add("visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $("toast").classList.remove("visible"), 3200);
}
function time(seconds) {
  const n = Math.max(0, Math.floor(seconds));
  return `${String(Math.floor(n / 60)).padStart(2, "0")}:${String(n % 60).padStart(2, "0")}`;
}
function duration() {
  return (words(current().text) / state.settings.speed) * 60;
}
function maxScroll() {
  return Math.max(0, reader.scrollHeight - reader.clientHeight);
}
function ratio(limit = maxScroll()) {
  return limit ? reader.scrollTop / limit : 0;
}
function fill(input) {
  input.style.setProperty(
    "--fill",
    `${((input.value - input.min) / (input.max - input.min)) * 100}%`,
  );
}
function metrics(limit = maxScroll()) {
  const total = duration();
  const position = ratio(limit);
  $("script-title").textContent = current().title || "Untitled script";
  $("script-info").textContent =
    `${words(current().text)} words  ·  ≈ ${time(total)} at current pace`;
  $("current-time").textContent = time(position * total);
  $("remaining-time").textContent = "−" + time(total * (1 - position));
  $("progress").value = position * 1000;
  fill($("progress"));
  $("elapsed").textContent = time(elapsed);
}
function list() {
  const scripts = $("scripts");
  scripts.replaceChildren();
  $("library-count").textContent =
    `${state.scripts.length} scripts · Browser library`;
  const query = $("script-search").value.trim().toLowerCase();
  for (const s of state.scripts.filter((s) =>
    s.title.toLowerCase().includes(query),
  )) {
    const b = document.createElement("button");
    b.className = "script-item" + (s.id === state.selected ? " active" : "");
    b.setAttribute("aria-pressed", s.id === state.selected);
    b.innerHTML = `<span class="script-icon">${icon("doc")}</span><span><strong>${escapeHTML(s.title || "Untitled script")}</strong><small>${words(s.text)} words · ${time((words(s.text) / state.settings.speed) * 60)}</small></span>`;
    b.onclick = () => {
      pause();
      state.selected = s.id;
      elapsed = 0;
      setBlackout(false);
      render();
      reader.scrollTop = 0;
      save();
    };
    scripts.append(b);
  }
  renderBookmarks();
}
function renderBookmarks() {
  const el = $("bookmarks");
  el.replaceChildren();
  current().bookmarks.forEach((b, i) => {
    const row = document.createElement("div");
    row.className = "bookmark-row";
    const jump = document.createElement("button");
    jump.className = "bookmark-jump";
    jump.innerHTML = `<span>${String(i + 1).padStart(2, "0")}</span>${escapeHTML(b.label)}`;
    jump.onclick = () => jumpBookmark(b);
    const remove = document.createElement("button");
    remove.className = "icon-button bookmark-remove";
    remove.innerHTML = icon("trash");
    remove.setAttribute("aria-label", `Remove bookmark ${b.label}`);
    remove.onclick = () => {
      current().bookmarks = current().bookmarks.filter((x) => x.id !== b.id);
      renderBookmarks();
      save();
    };
    row.append(jump, remove);
    el.append(row);
  });
  $("bookmark-hint").hidden = current().bookmarks.length > 0;
  renderEditorBookmarks();
}
function render() {
  list();
  content.innerHTML =
    paragraphs(current().text)
      .map((p, i) => `<p data-paragraph="${i}">${rich(p)}</p>`)
      .join("") || "<p>Write a few words to get started.</p>";
  renderEditor();
  $("title-input").value = current().title;
  applySettings();
  metrics();
}
function applySettings() {
  const s = state.settings;
  const pos = ratio();
  const stageHeight = stage.clientHeight;
  $("speed").value = s.speed;
  $("font-size").value = s.size;
  $("line-spacing").value = s.spacing;
  $("font").value = s.font;
  $("guide-toggle").checked = s.guide;
  $("guide-position").value = s.guidePosition;
  $("guide-height").value = s.guideHeight;
  $("guide-height-value").textContent =
    s.guideHeight + (s.guideHeight === 1 ? " line" : " lines");
  $("speed-value").textContent = s.speed;
  $("margins").value = s.margins;
  $("margins-value").textContent = s.margins + "%";
  $("focus-line").checked = s.focusLine;
  content.style.paddingLeft = content.style.paddingRight = s.margins + "%";
  stage.classList.toggle("no-focus", !s.focusLine);
  $("pace-number").textContent = s.speed;
  $("font-size-value").textContent = s.size;
  $("line-spacing-value").textContent = s.spacing.toFixed(1) + "×";
  $("guide-position-value").textContent = s.guidePosition + "%";
  content.style.fontFamily = fonts[s.font];
  content.style.fontSize = s.size + "px";
  content.style.lineHeight = s.spacing;
  const band = Math.min(stageHeight, s.size * s.spacing * s.guideHeight * 1.18);
  stage.style.setProperty("--guide-height", band + "px");
  stage.style.setProperty(
    "--guide-y",
    Math.min(
      (stageHeight * s.guidePosition) / 100,
      Math.max(0, stageHeight - band),
    ) + "px",
  );
  stage.classList.toggle("no-guide", !s.guide);
  document.querySelectorAll("input[type=range]").forEach(fill);
  reader.scrollTop = pos * maxScroll();
  playhead = reader.scrollTop;
  metrics();
}
function pause(message = "Paused · take your time") {
  playing = false;
  cancelAnimationFrame(frame);
  playhead = reader.scrollTop;
  $("play-symbol").innerHTML = icon("play");
  $("play").setAttribute("aria-label", "Play script");
  $("play-status").textContent = message;
  $("play-dot").classList.remove("playing");
}
function play() {
  if (editing || !demoAvailable()) return;
  if (!words(current().text)) {
    toast("Add a few words to your script first.");
    return;
  }
  if (playing) {
    pause();
    return;
  }
  if (ratio() > 0.998) reader.scrollTop = 0;
  playing = true;
  lastFrame = performance.now();
  playhead = reader.scrollTop;
  $("play-symbol").innerHTML = icon("pause");
  $("play").setAttribute("aria-label", "Pause script");
  $("play-status").textContent = "Prompting · you set the pace";
  $("play-dot").classList.add("playing");
  frame = requestAnimationFrame(tick);
}
function tick(now) {
  if (!playing) return;
  const dt = Math.min((now - lastFrame) / 1000, 0.08);
  lastFrame = now;
  elapsed += dt;
  const limit = maxScroll();
  playhead = Math.min(limit, playhead + (limit / Math.max(duration(), 1)) * dt);
  reader.scrollTop = playhead;
  metrics(limit);
  if (playhead >= limit) {
    pause("That’s a wrap. Make it another take?");
    return;
  }
  frame = requestAnimationFrame(tick);
}
function seek(fraction) {
  pause("Repositioned · press Play when you’re ready");
  reader.scrollTop = clamp(fraction, 0, 1) * maxScroll();
  metrics();
}
function reset() {
  pause("Ready for another take");
  elapsed = 0;
  reader.scrollTop = 0;
  setBlackout(false);
  metrics();
}
function paragraphAtGuide() {
  const y =
    reader.scrollTop + parseFloat(stage.style.getPropertyValue("--guide-y"));
  const ps = [...content.querySelectorAll("p")];
  let n = 0;
  ps.forEach((p, i) => {
    if (p.offsetTop <= y + 5) n = i;
  });
  return n;
}
let editorSelection = null;
function editorHTML(text) {
  return (
    paragraphs(text)
      .map((p) => `<p>${rich(p)}</p>`)
      .join("") || "<p><br></p>"
  );
}
function markdownFromDOM(root) {
  function walk(node) {
    if (node.nodeType === Node.TEXT_NODE)
      return node.textContent.replace(/\u00a0/g, " ");
    if (
      node.nodeType !== Node.ELEMENT_NODE &&
      node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE
    )
      return "";
    if (node.nodeName === "BR") return "\n";
    let text = [...node.childNodes].map(walk).join("");
    const tag = node.nodeName;
    const style = node.style;
    if (
      ["B", "STRONG"].includes(tag) ||
      style?.fontWeight === "bold" ||
      +style?.fontWeight >= 600
    )
      text = text.trim() ? `**${text}**` : text;
    if (tag === "U" || style?.textDecorationLine.includes("underline"))
      text = text.trim() ? `<u>${text}</u>` : text;
    if (["P", "DIV"].includes(tag)) return text.replace(/\n+$/, "") + "\n\n";
    return text;
  }
  return [...root.childNodes]
    .map(walk)
    .join("")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
function rememberEditorSelection() {
  const selection = window.getSelection();
  if (
    selection.rangeCount &&
    $("editor-text").contains(selection.anchorNode) &&
    $("editor-text").contains(selection.focusNode)
  ) {
    editorSelection = selection.getRangeAt(0).cloneRange();
    for (const kind of ["bold", "underline"]) {
      document
        .querySelector(`[data-format="${kind}"]`)
        .setAttribute("aria-pressed", document.queryCommandState(kind));
    }
  }
}
function restoreEditorSelection() {
  $("editor-text").focus();
  if (
    editorSelection &&
    $("editor-text").contains(editorSelection.startContainer)
  ) {
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(editorSelection);
  }
}
function paragraphAtCursor() {
  restoreEditorSelection();
  const selection = window.getSelection();
  const editor = $("editor-text");
  if (!selection.rangeCount) return 0;
  const range = selection.getRangeAt(0);
  let block = range.startContainer;
  while (block !== editor && block.parentNode !== editor)
    block = block.parentNode;
  const blocks = [...editor.childNodes].filter((n) => n.textContent.trim());
  if (block !== editor) {
    let index = Math.max(0, blocks.indexOf(block));
    if (!range.collapsed && range.toString().trim()) {
      const tail = document.createRange();
      tail.selectNodeContents(block);
      tail.setStart(range.startContainer, range.startOffset);
      if (!tail.toString().trim())
        index = Math.min(index + 1, blocks.length - 1);
    }
    return index;
  }
  return Math.min(
    Math.max(0, blocks.length - 1),
    [...editor.childNodes]
      .slice(0, range.startOffset)
      .filter((n) => n.textContent.trim()).length,
  );
}
function renderEditor() {
  $("editor-text").innerHTML = editorHTML(current().text);
  editorSelection = null;
  decorateEditorBookmarks();
}
function decorateEditorBookmarks() {
  $("editor-text")
    .querySelectorAll("[data-bookmark]")
    .forEach((p) => p.removeAttribute("data-bookmark"));
  const blocks = [...$("editor-text").children].filter((p) =>
    p.textContent.trim(),
  );
  current().bookmarks.forEach((b, i) => {
    if (blocks[b.paragraph])
      blocks[b.paragraph].dataset.bookmark = String(i + 1).padStart(2, "0");
  });
}
function renderEditorBookmarks() {
  const list = $("editor-bookmark-list");
  list.replaceChildren();
  $("editor-bookmark-count").textContent = current().bookmarks.length;
  current().bookmarks.forEach((b, index) => {
    const row = document.createElement("div");
    row.className = "editor-bookmark-row";
    const jump = document.createElement("button");
    jump.className = "icon-button";
    jump.textContent = index + 1;
    jump.classList.add("bookmark-badge");
    jump.setAttribute("aria-label", `Go to bookmark ${b.label}`);
    jump.onclick = () => jumpBookmark(b);
    const name = document.createElement("input");
    name.value = b.label;
    name.maxLength = 70;
    name.setAttribute("aria-label", "Bookmark name");
    name.onchange = () => {
      b.label = name.value.trim() || "Bookmark";
      renderBookmarks();
      save();
    };
    const move = document.createElement("button");
    move.className = "text-button";
    move.textContent = "Move here";
    move.onclick = () => {
      b.paragraph = paragraphAtCursor();
      current().bookmarks.sort((a, b) => a.paragraph - b.paragraph);
      renderBookmarks();
      save();
    };
    const remove = document.createElement("button");
    remove.className = "icon-button";
    remove.innerHTML = icon("trash");
    remove.setAttribute("aria-label", `Delete bookmark ${b.label}`);
    remove.onclick = () => {
      current().bookmarks = current().bookmarks.filter((x) => x.id !== b.id);
      renderBookmarks();
      save();
    };
    const find = document.createElement("button");
    find.className = "text-button bookmark-find";
    find.textContent = "Find";
    find.onclick = () => jumpBookmark(b);
    row.append(jump, name, move, find, remove);
    list.append(row);
  });
  decorateEditorBookmarks();
}
function addBookmark(fromEditor = false) {
  if (current().bookmarks.length >= 50) {
    toast("This script already has 50 bookmarks.");
    return;
  }
  const paragraph = fromEditor ? paragraphAtCursor() : paragraphAtGuide();
  if (current().bookmarks.some((b) => b.paragraph === paragraph)) {
    toast("This paragraph already has a bookmark.");
    return;
  }
  const p = paragraphs(current().text)[paragraph];
  if (!p) {
    toast("Add some script text first.");
    return;
  }
  current().bookmarks.push({
    id: uid(),
    label: plain(p).trim().split(/\s+/).slice(0, 6).join(" "),
    paragraph,
  });
  current().bookmarks.sort((a, b) => a.paragraph - b.paragraph);
  renderBookmarks();
  save();
  toast("Bookmarked. Find this passage in the sidebar.");
}
function jumpBookmark(b) {
  pause("At your bookmark · ready when you are");
  if (editing) {
    const block = [...$("editor-text").children].filter((p) =>
      p.textContent.trim(),
    )[b.paragraph];
    if (block) {
      const range = document.createRange();
      range.selectNodeContents(block);
      editorSelection = range;
      restoreEditorSelection();
      block.scrollIntoView({ block: "nearest" });
    }
    return;
  }
  const p = content.querySelectorAll("p")[b.paragraph];
  if (p) {
    reader.scrollTop =
      p.offsetTop - parseFloat(stage.style.getPropertyValue("--guide-y"));
    metrics();
  }
}
function adjacentBookmark(direction) {
  const here = paragraphAtGuide();
  const marks = [...current().bookmarks].sort(
    (a, b) => a.paragraph - b.paragraph,
  );
  const b =
    direction > 0
      ? marks.find((b) => b.paragraph > here)
      : marks.reverse().find((b) => b.paragraph < here);
  if (b) jumpBookmark(b);
  else toast(direction > 0 ? "No later bookmarks." : "No earlier bookmarks.");
}
function setBlackout(value) {
  blackout = value;
  $("blackout").innerHTML = icon(value ? "eye-off" : "eye");
  $("blackout-cover").hidden = !value;
  $("blackout").setAttribute("aria-pressed", value);
  $("blackout").style.color = value ? "var(--orange)" : "";
}
function toggleEditor() {
  pause();
  editing = !editing;
  $("workspace").classList.toggle("editing", editing);
  $("editor").hidden = !editing;
  const hints = editing
    ? [
        ["⌘ / Ctrl B", "Bold"],
        ["⌘ / Ctrl U", "Underline"],
      ]
    : [
        ["SPACE", "Play / pause"],
        ["↑ ↓", "Pace"],
        ["← →", "Scroll"],
        ["R", "Reset"],
        ["B", "Blackout"],
      ];
  document.querySelector(".app-status > div").innerHTML = hints
    .map(([key, label]) => `<span><kbd>${key}</kbd> ${label}</span>`)
    .join("");
  $("edit").innerHTML = editing
    ? icon("check") + "Done editing"
    : icon("edit") + "Edit script";
  if (editing) {
    renderEditor();
    $("title-input").value = current().title;
    $("editor-text").focus();
  } else {
    render();
    reader.scrollTop = 0;
  }
  metrics();
}
function editChanged() {
  const previous = current().text;
  const next = markdownFromDOM($("editor-text")).slice(0, 100000);
  // Move paragraph bookmarks with insertions/deletions before their passage.
  const oldText = plain(previous),
    newText = plain(next);
  if (oldText !== newText) {
    let start = 0,
      end = 0;
    while (
      start < Math.min(oldText.length, newText.length) &&
      oldText[start] === newText[start]
    )
      start++;
    while (
      end < Math.min(oldText.length, newText.length) - start &&
      oldText[oldText.length - 1 - end] === newText[newText.length - 1 - end]
    )
      end++;
    const oldParts = [...oldText.matchAll(/\S[\s\S]*?(?=\n\s*\n|$)/g)];
    const newParts = [...newText.matchAll(/\S[\s\S]*?(?=\n\s*\n|$)/g)];
    for (const b of current().bookmarks) {
      let offset = oldParts[b.paragraph]?.index || 0;
      if (offset >= oldText.length - end)
        offset += newText.length - oldText.length;
      else if (offset > start) offset = start;
      b.paragraph = Math.max(
        0,
        newParts.findLastIndex((p) => p.index <= offset),
      );
    }
  }
  current().text = next;
  current().title = $("title-input").value.slice(0, 80);
  const count = paragraphs(next).length;
  current().bookmarks = current().bookmarks.filter((b) => b.paragraph < count);
  list();
  metrics();
  save();
  rememberEditorSelection();
}
function format(kind) {
  restoreEditorSelection();
  // Browser editing commands preserve the native selection and undo history.
  document.execCommand(kind === "clear" ? "removeFormat" : kind, false);
  editChanged();
}
function focusMode() {
  $("output-menu").open = false;
  if (editing) toggleEditor();
  const pos = ratio();
  document.body.classList.toggle("focus-mode");
  $("focus").setAttribute(
    "aria-pressed",
    document.body.classList.contains("focus-mode"),
  );
  applySettings();
  reader.scrollTop = pos * maxScroll();
  playhead = reader.scrollTop;
  reader.focus();
}
function newScript(title = "Untitled script", text = "") {
  $("script-search").value = "";
  if (state.scripts.length >= 30) {
    toast("This browser library holds up to 30 scripts.");
    return;
  }
  pause();
  const s = { id: uid(), title, text, bookmarks: [] };
  state.scripts.push(s);
  state.selected = s.id;
  elapsed = 0;
  render();
  if (!editing) toggleEditor();
  save();
}
$("script-search").oninput = list;
function changePace(delta) {
  state.settings.speed = clamp(state.settings.speed + delta, 40, 260);
  applySettings();
  save();
}
$("pace-up").onclick = () => changePace(5);
$("pace-down").onclick = () => changePace(-5);
$("focus-line").onchange = (e) => {
  state.settings.focusLine = e.target.checked;
  applySettings();
  save();
};
document.addEventListener("click", (e) => {
  if (!e.target.closest("#output-menu")) $("output-menu").open = false;
});
$("play").onclick = play;
$("reset").onclick = reset;
$("edit").onclick = toggleEditor;
$("focus").onclick = focusMode;
$("exit-focus").onclick = focusMode;
$("blackout").onclick = () => setBlackout(!blackout);
$("previous").onclick = () => adjacentBookmark(-1);
$("next").onclick = () => adjacentBookmark(1);
$("bookmark").onclick = () => addBookmark(editing);
$("editor-bookmark").onclick = () => addBookmark(true);
$("new-script").onclick = () => newScript();
$("progress").oninput = (e) => seek(+e.target.value / 1000);
reader.onscroll = () => {
  if (!playing) metrics();
};
for (const event of ["wheel", "touchstart", "pointerdown"])
  reader.addEventListener(
    event,
    () => {
      if (playing) pause("Manual control · press Play to continue");
    },
    { passive: true },
  );
let manualDrag = null;
reader.addEventListener("pointerdown", (e) => {
  if (e.pointerType !== "mouse" || e.button !== 0) return;
  manualDrag = { y: e.clientY, top: reader.scrollTop };
  reader.setPointerCapture(e.pointerId);
});
reader.addEventListener("pointermove", (e) => {
  if (manualDrag) reader.scrollTop = manualDrag.top + manualDrag.y - e.clientY;
});
reader.addEventListener("pointerup", () => (manualDrag = null));
reader.addEventListener("pointercancel", () => (manualDrag = null));
for (const [id, key] of [
  ["speed", "speed"],
  ["font-size", "size"],
  ["line-spacing", "spacing"],
  ["guide-position", "guidePosition"],
  ["guide-height", "guideHeight"],
  ["margins", "margins"],
])
  $(id).oninput = (e) => {
    state.settings[key] = +e.target.value;
    applySettings();
    save();
  };
$("font").onchange = (e) => {
  state.settings.font = e.target.value;
  applySettings();
  save();
};
$("guide-toggle").onchange = (e) => {
  state.settings.guide = e.target.checked;
  applySettings();
  save();
};
$("title-input").oninput = editChanged;
$("editor-text").oninput = editChanged;
document.addEventListener("selectionchange", rememberEditorSelection);
$("editor-text").onpaste = (e) => {
  e.preventDefault();
  const text = e.clipboardData.getData("text/plain").slice(0, 100000);
  document.execCommand("insertText", false, text);
  editChanged();
};
$("editor-text").ondrop = (e) => {
  e.preventDefault();
  toast("Use Import for a script file, or paste text into the editor.");
};
$("editor-text").onkeydown = (e) => {
  if ((e.metaKey || e.ctrlKey) && ["b", "u"].includes(e.key.toLowerCase())) {
    e.preventDefault();
    format(e.key.toLowerCase() === "b" ? "bold" : "underline");
  }
};
document
  .querySelectorAll(".editor-tools button")
  .forEach((b) => (b.onpointerdown = (e) => e.preventDefault()));
document
  .querySelectorAll("[data-format]")
  .forEach((b) => (b.onclick = () => format(b.dataset.format)));
$("import").onclick = () => $("file").click();
$("file").onchange = async (e) => {
  const f = e.target.files[0];
  if (!f) return;
  if (!/\.(txt|md|markdown)$/i.test(f.name)) {
    toast("Choose a TXT or Markdown file.");
    return;
  }
  if (f.size > 100000) {
    toast("Choose a script smaller than 100 KB.");
    return;
  }
  try {
    newScript(
      f.name.replace(/\.[^.]+$/, ""),
      (await f.text()).replace(/\r\n?/g, "\n"),
    );
    toast("Imported locally. Nothing was uploaded.");
  } catch {
    toast("This file could not be read. Try another script.");
  }
  e.target.value = "";
};
$("export").onclick = () => {
  const blob = new Blob([current().text], {
    type: "text/markdown;charset=utf-8",
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download =
    (current().title || "script").replace(/[^a-z0-9 _-]/gi, "").slice(0, 70) +
    ".md";
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
$("guide-handle").onpointerdown = (e) => {
  drag = { id: e.pointerId };
  $("guide-handle").setPointerCapture(e.pointerId);
  e.preventDefault();
};
$("guide-handle").onpointermove = (e) => {
  if (!drag) return;
  const rect = stage.getBoundingClientRect();
  state.settings.guidePosition = Math.round(
    clamp(((e.clientY - rect.top) / rect.height) * 100, 10, 70),
  );
  applySettings();
};
$("guide-handle").onpointerup = () => {
  drag = null;
  save();
};
$("guide-handle").onpointercancel = () => {
  drag = null;
  save();
};
$("guide-handle").onkeydown = (e) => {
  if (["ArrowUp", "ArrowDown"].includes(e.key)) {
    e.preventDefault();
    e.stopPropagation();
    state.settings.guidePosition = clamp(
      state.settings.guidePosition + (e.key === "ArrowUp" ? -1 : 1),
      10,
      70,
    );
    applySettings();
    save();
  }
};
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    if (document.body.classList.contains("focus-mode")) focusMode();
    else {
      $("output-menu").open = false;
      pause();
    }
    return;
  }
  if (
    !e.target.closest("#workspace") &&
    !document.body.classList.contains("focus-mode")
  )
    return;
  if (
    !demoAvailable() ||
    e.defaultPrevented ||
    editing ||
    e.target.closest("summary") ||
    $("output-menu").open
  )
    return;
  if (
    e.ctrlKey ||
    e.metaKey ||
    e.altKey ||
    $("info-dialog").open ||
    e.target.closest("input,textarea,select,[contenteditable]")
  )
    return;
  if (e.code === "Space") {
    if (e.target.closest("button,a")) return;
    e.preventDefault();
    play();
  }
  if (["ArrowUp", "ArrowDown"].includes(e.key)) {
    e.preventDefault();
    changePace(e.key === "ArrowUp" ? 5 : -5);
  }
  if (["ArrowLeft", "ArrowRight"].includes(e.key)) {
    e.preventDefault();
    seek(
      ratio() +
        ((e.key === "ArrowLeft" ? -1 : 1) *
          state.settings.size *
          state.settings.spacing) /
          Math.max(maxScroll(), 1),
    );
  }
  if (e.key.toLowerCase() === "r") reset();
  if (e.key.toLowerCase() === "b") setBlackout(!blackout);
});
document.addEventListener("visibilitychange", () => {
  if (document.hidden && playing) pause("Paused while this tab was away");
});
let resizeFrame = 0;
window.addEventListener("resize", () => {
  if (!demoAvailable() && playing)
    pause("Paused · open the demo on a larger screen");
  if (resizeFrame) return;
  resizeFrame = requestAnimationFrame(() => {
    resizeFrame = 0;
    applySettings();
  });
});
const helpHTML =
  '<p class="eyebrow">WELCOME TO THE BROWSER STUDIO</p><h2>Your first take, in a few clicks.</h2><ul><li>Pick a sample script, or use <b>Edit script</b> to make it yours. Import accepts TXT and Markdown.</li><li>Press <b>Play</b> or Space. Change reading pace, typeface, and text size to suit you.</li><li>Scroll to retake a line. Manual scrolling pauses playback. Press Play to continue.</li><li>Add a <b>bookmark</b> to return to a paragraph. In the editor, place your cursor and choose Add bookmark.</li><li><b>Prompter Output → Focus view</b> shows only the script with the script. Escape brings you back.</li></ul><p>This browser demo uses fixed-speed prompting. Voice following, hands-free AI, external-display controls, and iPad pairing are features of the native Mac app.</p>';
const privacyHTML =
  '<p class="eyebrow">YOUR SCRIPT STAYS WITH YOU</p><h2>A browser, not a cloud library.</h2><p>The demo stores scripts and appearance settings in this browser’s local storage. It does not upload scripts or use your microphone. There are no analytics, ads, or AI model downloads on this site.</p><p>Browser storage can be cleared by you or your browser. Use <b>Export .md</b> in the editor to keep a copy. On a shared computer, clear this site’s browser data when you’re done.</p><p>GitHub Pages hosts this site and may log ordinary web requests. Download links take you to GitHub. StudioPrompter is open source under the <a href="https://github.com/codebooker/StudioPrompter/blob/main/LICENSE">AGPL-3.0 license ↗</a>.</p>';
function info(html) {
  pause();
  $("dialog-content").innerHTML = html;
  $("info-dialog").showModal();
}
$("help").onclick = () => info(helpHTML);
$("privacy").onclick = () => info(privacyHTML);
$("close-dialog").onclick = () => $("info-dialog").close();
$("info-dialog").onclick = (e) => {
  if (e.target === $("info-dialog")) {
    const r = e.target.getBoundingClientRect();
    if (
      e.clientX < r.left ||
      e.clientX > r.right ||
      e.clientY < r.top ||
      e.clientY > r.bottom
    )
      e.target.close();
  }
};
render();
