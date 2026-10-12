"use strict";
const canvas = document.getElementById("canvas"),
  ctx = canvas.getContext("2d");
let doc,
  state,
  samples = [];
window.studio.onDocument((value) => {
  doc = value;
  state = null;
  samples = [];
});
window.studio.onPlayback((value) => {
  if (!doc || value?.revision !== doc.revision) return;
  state = value;
  const now = performance.now() / 1000;
  if (
    !value.playing ||
    Math.abs((samples.at(-1)?.p ?? value.progress) - value.progress) > 0.035
  )
    samples = [];
  samples.push({ t: now, p: value.progress });
  samples = samples.slice(-8);
});
function motion() {
  const target = performance.now() / 1000 - 0.1;
  for (let i = 1; i < samples.length; i++) {
    if (target <= samples[i].t) {
      const a = samples[i - 1],
        b = samples[i];
      return (
        a.p +
        (b.p - a.p) * Math.max(0, Math.min(1, (target - a.t) / (b.t - a.t)))
      );
    }
  }
  return samples.at(-1)?.p ?? 0;
}
function draw() {
  requestAnimationFrame(draw);
  const width = innerWidth,
    height = innerHeight;
  if (
    canvas.width !== width * devicePixelRatio ||
    canvas.height !== height * devicePixelRatio
  ) {
    canvas.width = width * devicePixelRatio;
    canvas.height = height * devicePixelRatio;
  }
  ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  ctx.fillStyle = "#0e0f12";
  ctx.fillRect(0, 0, width, height);
  if (!doc || !state || state.blackout) return;
  const s = doc.script.settings,
    scale = width / 1000,
    h = height / scale,
    guide = h * s.guidePosition,
    origin =
      guide -
      s.fontSize * 0.2 -
      motion() * Math.max(0, doc.textHeight - s.fontSize * 1.2);
  ctx.save();
  ctx.scale(scale, scale);
  ctx.translate(s.mirrorHorizontal ? 1000 : 0, s.mirrorVertical ? h : 0);
  ctx.scale(s.mirrorHorizontal ? -1 : 1, s.mirrorVertical ? -1 : 1);
  const band = {
    top: guide - 8,
    bottom: guide + doc.lineHeight * s.guideLines + 4,
  };
  const nominal = { ...band };
  const visible = doc.lines.filter(
    (l) => l.y + origin + l.height >= 0 && l.y + origin <= h,
  );
  for (const l of visible) {
    const y = l.y + origin;
    if (y < nominal.bottom && y + l.height > nominal.top) {
      band.top = Math.min(band.top, y - 2);
      band.bottom = Math.max(band.bottom, y + l.height + 2);
    }
  }
  if (s.showGuide) {
    ctx.fillStyle = "#ff824f0c";
    ctx.fillRect(0, band.top, 1000, band.bottom - band.top);
    ctx.fillStyle = "#ff824f";
    ctx.beginPath();
    ctx.moveTo(30, guide + 10);
    ctx.lineTo(44, guide + 23);
    ctx.lineTo(30, guide + 36);
    ctx.fill();
  }
  ctx.textBaseline = "top";
  const family =
    s.typeface === "georgia"
      ? "Georgia,serif"
      : s.typeface === "verdana"
        ? "Verdana,sans-serif"
        : "sans-serif";
  function lines(alpha) {
    ctx.globalAlpha = alpha;
    ctx.fillStyle = "#f5f5f5";
    for (const l of visible) {
      let x = s.margin;
      for (let i = l.location; i < l.location + l.length; i++) {
        const ch = doc.script.text[i];
        if (ch === "\n" || ch === "\r") continue;
        const marks = (doc.script.emphasis || []).filter(
          (m) => i >= m.location && i < m.location + m.length,
        );
        ctx.font = `${marks.some((m) => m.bold) ? 700 : 500} ${s.fontSize}px ${family}`;
        ctx.fillText(ch, x, l.y + origin);
        const w = ctx.measureText(ch).width;
        if (marks.some((m) => m.underline)) {
          ctx.fillRect(x, l.y + origin + s.fontSize * 1.05, w, 1.5);
        }
        x += w;
      }
    }
  }
  lines(s.focusMode ? 0.36 : 1);
  if (s.focusMode) {
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, band.top, 1000, band.bottom - band.top);
    ctx.clip();
    lines(1);
    ctx.restore();
  }
  ctx.restore();
}
draw();

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") window.studio.closeOutput();
});
