const fs=require('node:fs'),os=require('node:os'),path=require('node:path');const {LinkServer}=require('../link-server.cjs');
const folder=fs.mkdtempSync(path.join(os.tmpdir(),'android-link-'));const server=new LinkServer(path.join(folder,'pair.json'),'Interop fixture');server.saved.pairingCode='ABCDEFGHJKLM';server.persist();
server.start().then(status=>console.log(JSON.stringify(status)));
process.stdin.on('data',input=>{if(input.toString().trim()==='REMOVE'){for(const device of server.saved.devices.filter(d=>!d.removed))server.remove(device.id);}});
process.on('SIGTERM',()=>{server.stop();fs.rmSync(folder,{recursive:true,force:true});process.exit(0);});
