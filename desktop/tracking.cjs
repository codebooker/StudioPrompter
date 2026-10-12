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
module.exports = { tokenize, align, spread, FollowMotion };
