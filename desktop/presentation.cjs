"use strict";
// Same whole-line band rule as PrompterLayout.FocusGeometry. Only the band
// expands; the guide anchor and text origin never move with its edges.
const StudioPresentation = {
  focusBand(guide, lineStep, count, lines, offset, height) {
    const nominal = { top: guide - 8, bottom: guide + lineStep * count + 4 };
    let top = nominal.top,
      bottom = nominal.bottom;
    for (const line of lines) {
      const y = line.top - offset;
      if (y < nominal.bottom && y + line.height > nominal.top) {
        top = Math.min(top, y - 2);
        bottom = Math.max(bottom, y + line.height + 2);
      }
    }
    return { top: Math.max(0, top), bottom: Math.min(height, bottom) };
  },
  adaptiveActive(now, lastVoice, lastRecognition, pace) {
    return (
      pace !== null && now - lastVoice < 500 && now - lastRecognition < 4000
    );
  },
  scrollRemainder(desired, actual) {
    return actual - desired;
  },
};
StudioPresentation.PaceEstimator = class {
  constructor() {
    this.value = null;
    this.previous = null;
  }
  observe(count, span, audioEnd) {
    if (
      count < 4 ||
      span < 2 ||
      !Number.isFinite(span) ||
      audioEnd <= this.previous
    )
      return this.value;
    const rate = Math.min(300, Math.max(40, (count / span) * 60));
    if (this.value === null) this.value = Math.min(130, rate);
    else {
      const elapsed = Math.min(1, audioEnd - this.previous);
      const accelerating = rate > this.value;
      const adjustment =
        (rate - this.value) *
        (1 - Math.exp(-elapsed / (accelerating ? 3 : 0.65)));
      const limit = (accelerating ? 12 : 60) * elapsed;
      this.value += Math.max(-limit, Math.min(limit, adjustment));
    }
    this.previous = audioEnd;
    return this.value;
  }
};
if (typeof module !== "undefined") module.exports = StudioPresentation;
