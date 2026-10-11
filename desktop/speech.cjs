'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const models = {
  'tiny.en': {size:77704715,hash:'921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f'},
  'base.en': {size:147964211,hash:'a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002'}
};
class Speech {
  constructor(directory,runtime,progress) { this.directory=directory; this.runtime=runtime; this.progress=progress; this.busy=false; this.downloading=false; }
  model(name) { if(!models[name]) throw Error('Unsupported speech model'); return path.join(this.directory,`ggml-${name}.bin`); }
  async status(name) { const file=this.model(name); try { return {ready:(await fs.stat(file)).size===models[name].size}; } catch { return {ready:false}; } }
  async download(name) {
    const file=this.model(name),spec=models[name]; if(this.downloading) throw Error('A model is already downloading'); this.downloading=true;
    const temp=file+'.part'; let handle;
    try {
      await fs.mkdir(this.directory,{recursive:true,mode:0o700});
      const response=await fetch(`https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${name}.bin`,{signal:AbortSignal.timeout(600000)});
      if(!response.ok || !response.body) throw Error('Model download failed');
      handle=await fs.open(temp,'w',0o600); const hash=crypto.createHash('sha256'); let size=0,last=0;
      for await (const chunk of response.body) { size+=chunk.length; if(size>spec.size) throw Error('Unexpected model size'); hash.update(chunk); await handle.write(chunk); if(Date.now()-last>200){last=Date.now();this.progress({received:size,total:spec.size});} }
      await handle.close();handle=null;
      if(size!==spec.size || hash.digest('hex')!==spec.hash) throw Error('Model integrity check failed');
      await fs.rename(temp,file); return {ready:true};
    } finally { await handle?.close(); await fs.rm(temp,{force:true}); this.downloading=false; }
  }
  async transcribe(name,bytes) {
    if(this.busy) return null;
    const audio=Buffer.from(bytes);
    if(audio.length>320000 || audio.length<44 || audio.toString('ascii',0,4)!=='RIFF' || audio.toString('ascii',8,12)!=='WAVE') throw Error('Invalid audio');
    if(!(await this.status(name)).ready) throw Error('Download the speech model first');
    this.busy=true;
    const dir=await fs.mkdtemp(path.join(this.directory,'audio-'));const file=path.join(dir,'chunk.wav'),out=path.join(dir,'result');
    try {
      await fs.writeFile(file,audio,{mode:0o600});
      const exe=path.join(this.runtime,process.platform==='win32'?'whisper-cli.exe':'whisper-cli');
      await new Promise((resolve,reject)=> {
        const child=spawn(exe,['-m',this.model(name),'-f',file,'-l','en','-nt','-otxt','-of',out,'-t','4'],{windowsHide:true,stdio:'ignore'});
        this.child=child;const timeout=setTimeout(()=>{child.kill();reject(Error('Speech processing took too long'));},20000);
        child.once('error',e=>{clearTimeout(timeout);reject(e);});child.once('exit',code=>{clearTimeout(timeout);code===0?resolve():reject(Error('Speech engine failed'));});
      });
      return (await fs.readFile(out+'.txt','utf8')).trim().slice(0,4096);
    } finally {this.child=null;this.busy=false;await fs.rm(dir,{recursive:true,force:true});}
  }
  stop() {this.child?.kill();}
}
module.exports={Speech,models};
