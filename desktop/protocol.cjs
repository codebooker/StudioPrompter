'use strict';
const crypto = require('node:crypto');
const MAX = 8 * 1024 * 1024;
const normalize = key => key.toUpperCase().replace(/[^A-Z0-9]/g, '');
const identity = key => 'StudioPrompter-v2-' + crypto.createHash('sha256').update('identity:' + normalize(key)).digest('hex');
const secret = key => crypto.createHash('sha256').update(normalize(key)).digest();
function newCode() { const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; return Array.from({length:12}, () => alphabet[crypto.randomInt(alphabet.length)]).join(''); }
function frame(message) { const body = Buffer.from(JSON.stringify(message)); if (!body.length || body.length > MAX) throw Error('Message exceeds limit'); const head = Buffer.alloc(4); head.writeUInt32BE(body.length); return Buffer.concat([head,body]); }
class Decoder {
  constructor(onMessage) { this.buffer = Buffer.alloc(0); this.onMessage = onMessage; }
  push(data) {
    this.buffer = Buffer.concat([this.buffer, data]);
    while (this.buffer.length >= 4) {
      const size = this.buffer.readUInt32BE(); if (!size || size > MAX) throw Error('Invalid frame size');
      if (this.buffer.length < size + 4) return;
      const message = JSON.parse(this.buffer.subarray(4,size+4).toString('utf8'));
      this.buffer = this.buffer.subarray(size+4); this.onMessage(message);
    }
  }
}
const bounded = (v,min,max) => Number.isFinite(v) && v >= min && v <= max;
function validDocument(d) {
  const s = d?.script?.settings, text = d?.script?.text;
  return typeof d?.revision === 'string' && typeof text === 'string' && text.length <= 500000 && s &&
    bounded(d.textHeight,0,10000000) && bounded(d.lineHeight,1,1000) && bounded(s.fontSize,1,200) &&
    bounded(s.margin,0,450) && bounded(s.guidePosition,0,1) && bounded(s.guideLines,1,3) &&
    Array.isArray(d.lines) && d.lines.length <= 100000 && d.lines.every(l => Number.isInteger(l.location) && Number.isInteger(l.length) && l.location >= 0 && l.length >= 0 && l.location+l.length <= text.length && bounded(l.y,0,10000000) && bounded(l.height,0,1000));
}
function validPlayback(s) { return typeof s?.revision === 'string' && bounded(s.progress,0,1) && typeof s.playing === 'boolean' && typeof s.blackout === 'boolean' && Number.isInteger(s.countdown) && bounded(s.countdown,0,10); }
module.exports = {MAX, normalize, identity, secret, newCode, frame, Decoder, validDocument, validPlayback};
