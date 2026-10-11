"use strict";

const tokenize = text => (text.toLowerCase().match(/[\p{L}\p{N}]+/gu)||[]);
// Require multiple ordered matches; search backward too after a producer retake.
function align(script,heard,cursor) {
  const words=tokenize(script),query=tokenize(heard).slice(-18); if(query.length<2)return null;
  let best=null;
  for(let start=Math.max(0,cursor-35);start<Math.min(words.length,cursor+90);start++) {
    let matched=0,end=start,qi=0;
    for(let wi=start;wi<Math.min(words.length,start+query.length+14)&&qi<query.length;wi++) {
      const found=query.slice(qi,qi+4).indexOf(words[wi]);if(found>=0){matched++;qi+=found+1;end=wi+1;}
    }
    const confidence=matched/query.length,score=matched*3-confidence*Math.abs(start-cursor)*.03;
    if(matched>=Math.min(3,query.length)&&confidence>=.55&&(!best||score>best.score))best={cursor:end,confidence,score};
  }
  return best;
}

const api=window.studio;
let mirrorHorizontal=false,mirrorVertical=false,revision=null,remote=null,speechTarget=null,matchedWord=0,heardPace=130,lastSpeech=0;
let audioContext=null,micStream=null,processor=null,micGeneration=0,recognizing=false;
const voice=document.createElement('section');voice.className='desktop-card';
voice.innerHTML='<label><b>Voice prompting</b><input id="voice-enabled" type="checkbox" role="switch"></label><select id="voice-mode" aria-label="Voice mode"><option value="follow">Follow script</option><option value="adaptive">Adaptive pace</option></select><select id="voice-model" aria-label="Speech model"><option value="tiny.en">Tiny English · fastest</option><option value="base.en">Base English · more accurate</option></select><button id="download-model">Download model</button><p id="voice-status" class="status">Checking local model…</p><select id="mic" aria-label="Microphone"><option value="">System default microphone</option></select><select id="mic-channel" aria-label="Microphone channel"><option value="0">Channel 1</option><option value="1">Channel 2</option></select><p>Processes speech locally. Play starts the mic; Pause stops it. This preview has no hands-free commands.</p>';
document.querySelector('.settings').prepend(voice);
const mirror=document.createElement('section');mirror.className='desktop-card';mirror.innerHTML='<b>Mirror & flip · output only</b><label>Mirror horizontally <input id="mirror-horizontal" type="checkbox"></label><label>Flip vertically <input id="mirror-vertical" type="checkbox"></label>';document.querySelector('.settings').append(mirror);
for(const id of ['mirror-horizontal','mirror-vertical'])$(id).onchange=()=>{mirrorHorizontal=$('mirror-horizontal').checked;mirrorVertical=$('mirror-vertical').checked;updateDocument();};
async function modelStatus(){try{const s=await api.modelStatus($('voice-model').value);$('download-model').hidden=s.ready;$('voice-status').textContent=s.ready?'Model ready · works offline':'Download a model to use voice prompting';}catch(e){$('voice-status').textContent=e.message;}}
$('voice-model').onchange=()=>{stopMic();pause();modelStatus();};
$('download-model').onclick=async()=>{const b=$('download-model');b.disabled=true;try{await api.downloadModel($('voice-model').value);await modelStatus();}catch(e){$('voice-status').textContent=e.message;}finally{b.disabled=false;}};
api.onModelProgress(({received,total})=>$('voice-status').textContent=`Downloading model · ${Math.round(received/total*100)}%`);
async function microphones(){const devices=await navigator.mediaDevices.enumerateDevices();const select=$('mic'),saved=select.value;select.replaceChildren(new Option('System default microphone',''));for(const d of devices.filter(d=>d.kind==='audioinput'))select.add(new Option(d.label||'Microphone',d.deviceId));select.value=saved;}
$('mic').onchange=$('mic-channel').onchange=()=>{pause();};
$('voice-enabled').onchange=()=>{pause();};
$('voice-mode').onchange=()=>{speechTarget=null;};
function stopMic(){micGeneration++;micStream?.getTracks().forEach(t=>t.stop());micStream=null;processor?.disconnect();processor=null;audioContext?.close();audioContext=null;api.stopSpeech();speechTarget=null;recognizing=false;}
function wav(samples){const b=new ArrayBuffer(44+samples.length*2),v=new DataView(b);const str=(at,s)=>{for(let i=0;i<s.length;i++)v.setUint8(at+i,s.charCodeAt(i));};str(0,'RIFF');v.setUint32(4,b.byteLength-8,true);str(8,'WAVE');str(12,'fmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,1,true);v.setUint32(24,16000,true);v.setUint32(28,32000,true);v.setUint16(32,2,true);v.setUint16(34,16,true);str(36,'data');v.setUint32(40,samples.length*2,true);for(let i=0;i<samples.length;i++)v.setInt16(44+i*2,Math.max(-1,Math.min(1,samples[i]))*32767,true);return new Uint8Array(b);}
async function startMic(){
  if(micStream)return; if(!(await api.modelStatus($('voice-model').value)).ready)throw Error('Download a speech model first');
  const generation=++micGeneration;
  const stream=await navigator.mediaDevices.getUserMedia({audio:{deviceId:$('mic').value?{exact:$('mic').value}:undefined,channelCount:{ideal:8},echoCancellation:false,noiseSuppression:false,autoGainControl:false},video:false});
  if(generation!==micGeneration){stream.getTracks().forEach(t=>t.stop());return;}
  micStream=stream;audioContext=new AudioContext();await audioContext.resume();const source=audioContext.createMediaStreamSource(stream);const channels=stream.getAudioTracks()[0].getSettings().channelCount||1;
  const selector=$('mic-channel'),picked=Number(selector.value);selector.replaceChildren();for(let n=0;n<channels;n++)selector.add(new Option(`Channel ${n+1}`,String(n)));selector.value=String(Math.min(picked,channels-1));
  processor=audioContext.createScriptProcessor(4096,channels,1);source.connect(processor);processor.connect(audioContext.destination);
  let samples=[],since=0;const rate=audioContext.sampleRate;let resamplePhase=0;
  processor.onaudioprocess=event=>{
    event.outputBuffer.getChannelData(0).fill(0);const input=event.inputBuffer.getChannelData(Number(selector.value));
    for(let i=0;i<input.length;i++){resamplePhase+=16000;if(resamplePhase>=rate){resamplePhase-=rate;samples.push(input[i]);since++;}}
    if(samples.length>96000)samples=samples.slice(-96000);
    if(since>=32000&&samples.length>=32000&&!recognizing){since=0;const chunk=Float32Array.from(samples);const rms=Math.sqrt(chunk.reduce((a,v)=>a+v*v,0)/chunk.length);if(rms<.004)return;
      recognizing=true;api.transcribe($('voice-model').value,wav(chunk)).then(text=>{
        if(generation!==micGeneration||!text)return;const result=align(plain(current().text),text,matchedWord);
        $('voice-status').textContent=`Heard: ${text}`;lastSpeech=performance.now();heardPace=clamp(tokenize(text).length/(chunk.length/16000)*60,40,260);
        if(result){matchedWord=result.cursor;speechTarget=wordPosition(matchedWord);}
      }).catch(e=>{if(generation===micGeneration){pause();$('voice-status').textContent=e.message;}}).finally(()=>{if(generation===micGeneration)recognizing=false;});
    }
  };$('voice-status').textContent='Listening to selected microphone channel';await microphones();
}
function wordPosition(index){const textNodes=[];const walker=document.createTreeWalker(content,NodeFilter.SHOW_TEXT);let n;while(n=walker.nextNode())textNodes.push(n);let seen=0;for(const node of textNodes){const matches=[...node.textContent.matchAll(/[\p{L}\p{N}]+/gu)];if(seen+matches.length>=index){const m=matches[Math.max(0,index-seen-1)];if(!m)break;const range=document.createRange();range.setStart(node,m.index);range.setEnd(node,m.index+m[0].length);const box=range.getBoundingClientRect();return clamp(reader.scrollTop+box.top-stage.getBoundingClientRect().top-parseFloat(stage.style.getPropertyValue('--guide-y')),0,maxScroll());}seen+=matches.length;}return maxScroll();}
const originalPlay=play,originalPause=pause;
pause=function(message){originalPause(message);stopMic();};
play=async function(){if(playing)return pause();if(editing)return;try{if($('voice-enabled').checked){matchedWord=Math.floor(ratio()*words(current().text));await startMic();}originalPlay();}catch(e){stopMic();$('voice-status').textContent=e.message;}};
// Voice following holds on silence; smooth motion stays bounded by the last match.
tick=function(now){if(!playing)return;const dt=Math.min((now-lastFrame)/1000,.08);lastFrame=now;elapsed+=dt;const limit=maxScroll();if(!$('voice-enabled').checked)playhead=Math.min(limit,playhead+(limit/Math.max(duration(),1))*dt);else if(speechTarget!==null){const active=now-lastSpeech<3000;const target=Math.max(playhead,speechTarget);if($('voice-mode').value==='follow')playhead+=Math.min(Math.max(0,target-playhead),Math.max(10,state.settings.size*state.settings.spacing*3)*dt);else if(active){const pace=limit/Math.max(words(current().text),1)*heardPace/60;playhead=Math.min(target,playhead+pace*dt);}}reader.scrollTop=playhead;metrics(limit);if(playhead>=limit&&limit>0){pause('That’s a wrap.');return;}frame=requestAnimationFrame(tick);};
$('play').onclick=()=>play();
const oldSave=save;save=function(){oldSave();api.save(JSON.stringify(state)).catch(e=>toast(`Could not save library: ${e.message}`));};
$('library-count').textContent=`${state.scripts.length} scripts · Local library`;
$('privacy').onclick=()=>info('<h2>Your studio stays local.</h2><p>Scripts are saved on this computer. Speech models download once from Hugging Face, then audio is processed locally with whisper.cpp. Temporary audio chunks are deleted after processing. Tablet output uses encrypted connections on your local network.</p>');
$('help').onclick=()=>info('<h2>StudioPrompter desktop preview</h2><p>Edit and import TXT or Markdown scripts, set bookmarks, and use Play to prompt. Choose a display or pair a tablet from Prompter Output. Enable Voice prompting and download a small English model to follow your microphone.</p><p>This first port does not yet include DOCX/PDF import, Webcam Layout, in-app updates, or hands-free AI commands.</p>');
const pairDialog=document.createElement('dialog');pairDialog.id='desktop-pairing';pairDialog.innerHTML='<h2>Connect a tablet</h2><p>Connect this computer and your tablet to the same local network. Open StudioPrompter Companion and enter this code.</p><p class="pair-code" id="pair-code"></p><div id="paired-devices"></div><button id="pair-close">Done</button>';document.body.append(pairDialog);$('pair-close').onclick=()=>pairDialog.close();
function pairingStatus(value){$('pair-code').textContent=value.code;const devices=$('paired-devices');devices.replaceChildren();for(const d of value.devices){const row=document.createElement('div');row.className='pair-device';const label=document.createElement('span');label.textContent=d.name;const remove=document.createElement('button');remove.textContent='Remove';remove.onclick=()=>api.removeDevice(d.id).then(pairingStatus).catch(e=>toast(e.message));row.append(label,remove);devices.append(row);}}
api.onPairing(pairingStatus);
async function outputMenu(){const options=document.querySelector('.output-options');options.replaceChildren();const make=(label,fn)=>{const b=document.createElement('button');b.textContent=label;b.onclick=async()=>{try{await fn();$('output-menu').open=false;}catch(e){toast(e.message);}};options.append(b);};make('Producer preview only',()=>api.output(null));for(const d of await api.displays())make(`${d.label}${d.primary?' · primary':''}`,()=>api.output(d.id));make('Connect a tablet…',async()=>{pairingStatus(await api.pairing());pairDialog.showModal();});make('Focus view',()=>focusMode());options.lastElementChild.id='focus';}
$('output-menu').addEventListener('toggle',()=>{if($('output-menu').open)outputMenu();});
function updateDocument(){
  const text=[],lines=[],emphasis=[];let offset=0;const scale=1000/Math.max(1,reader.clientWidth);const base=content.querySelector('p')?.getBoundingClientRect().top||0;
  for(const p of content.querySelectorAll('p')){const walker=document.createTreeWalker(p,NodeFilter.SHOW_TEXT);let node;while(node=walker.nextNode()){text.push(node.textContent);if(node.parentElement.closest('b,strong'))emphasis.push({location:offset,length:node.length,bold:true,underline:!!node.parentElement.closest('u')});else if(node.parentElement.closest('u'))emphasis.push({location:offset,length:node.length,bold:false,underline:true});for(let i=0;i<node.length;i++){const range=document.createRange();range.setStart(node,i);range.setEnd(node,i+1);const r=range.getBoundingClientRect();const y=Math.max(0,(r.top-base)*scale);const previous=lines.at(-1);if(previous&&Math.abs(previous.y-y)<1&&previous.location+previous.length===offset+i)previous.length++;else lines.push({location:offset+i,length:1,y,height:r.height*scale});}offset+=node.length;}text.push('\n\n');offset+=2;}
  revision=crypto.randomUUID();const s=state.settings;const fontSize=s.size*scale;
  remote={revision,script:{id:crypto.randomUUID(),title:current().title,text:text.join(''),modified:Date.now()/1000-978307200,cues:[],emphasis,settings:{wordsPerMinute:s.speed,fontSize,lineSpacing:s.spacing,margin:s.margins*10,countdown:0,mirrorHorizontal,mirrorVertical,showGuide:s.guide,guidePosition:s.guidePosition/100,guideLines:s.guideHeight,focusMode:s.focusLine,typeface:s.font==='avenir'?'avenirNext':s.font}},lines,textHeight:Math.max(fontSize*1.2,(lines.at(-1)?.y||0)+(lines.at(-1)?.height||fontSize)),lineHeight:fontSize*s.spacing};
  api.document(remote).catch(e=>toast(e.message));
}
let documentTimer;const observer=new MutationObserver(()=>{clearTimeout(documentTimer);documentTimer=setTimeout(updateDocument,120);});observer.observe(content,{childList:true,subtree:true,attributes:true,characterData:true});window.addEventListener('resize',()=>{clearTimeout(documentTimer);documentTimer=setTimeout(updateDocument,200);});
for(const input of document.querySelectorAll('.settings input,.settings select'))input.addEventListener('change',()=>{clearTimeout(documentTimer);documentTimer=setTimeout(updateDocument,100);});
setInterval(()=>{if(!remote)return;const first=content.querySelector('p');const guide=parseFloat(stage.style.getPropertyValue('--guide-y'));const consumed=first?Math.max(0,stage.getBoundingClientRect().top+guide-first.getBoundingClientRect().top):0;const progress=clamp(consumed*(1000/reader.clientWidth)/Math.max(1,remote.textHeight-remote.script.settings.fontSize*1.2),0,1);api.playback({revision,progress,playing,blackout,countdown:0,notice:null}).catch(()=>{});},50);
modelStatus();microphones().catch(()=>{});updateDocument();
