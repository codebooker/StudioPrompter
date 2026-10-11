/* Capture on the audio thread so editor/layout work cannot interrupt the mic. */
class StudioCapture extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.channel = options.processorOptions.channel;
    this.samples = new Float32Array(1024);
    this.offset = 0;
  }
  process(inputs, outputs) {
    for (const output of outputs) for (const channel of output) channel.fill(0);
    const input = inputs[0]?.[this.channel];
    if (!input) return true;
    for (const sample of input) {
      this.samples[this.offset++] = sample;
      if (this.offset === this.samples.length) {
        this.port.postMessage(this.samples, [this.samples.buffer]);
        this.samples = new Float32Array(1024);
        this.offset = 0;
      }
    }
    return true;
  }
}
registerProcessor("studio-capture", StudioCapture);
