"use strict";
// Shared by the renderer and microphone-path tests. The level meter measures
// the original selected channel; only Whisper's copy is gain-normalized.
const StudioAudio = {
  rms(samples) {
    return Math.sqrt(
      samples.reduce((sum, value) => sum + value * value, 0) /
        Math.max(1, samples.length),
    );
  },
  speechFloor: 0.0005,
  normalize(samples) {
    const rms = this.rms(samples);
    const peak = samples.reduce(
      (max, value) => Math.max(max, Math.abs(value)),
      0,
    );
    const gain =
      rms > this.speechFloor
        ? Math.max(1, Math.min(20, 0.06 / rms, 0.95 / peak))
        : 1;
    return Float32Array.from(samples, (value) => value * gain);
  },
};
if (typeof module !== "undefined") module.exports = StudioAudio;
