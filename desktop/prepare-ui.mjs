import {mkdir, readFile, writeFile, copyFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
await mkdir(`${root}desktop/ui`, {recursive:true});
for (const asset of ['style.css','demo.css','icons.svg','icon.svg']) await copyFile(`${root}website/${asset}`, `${root}desktop/ui/${asset}`);
let html = await readFile(`${root}website/demo/index.html`, 'utf8');
html = html.replace(/\.\.\//g, '').replace(/\?v=03e6e33/g, '')
  .replace(/<script src="release.js" defer><\/script>/, '')
  .replace('<script src="app.js" defer></script>', '<script src="app.js" defer></script><script src="desktop.js" defer></script>')
  .replace('</head>', '<meta http-equiv="Content-Security-Policy" content="default-src \'self\'; script-src \'self\'; style-src \'self\' \'unsafe-inline\'; img-src \'self\' data:; media-src \'self\' blob:; connect-src \'none\'"><link rel="stylesheet" href="desktop.css"></head>')
  .replace(/<nav class="demo-navigation"[\s\S]*?<\/nav>/, '<nav class="demo-navigation"><span>StudioPrompter · Desktop preview</span><div><button id="help">Help</button><button id="privacy">Privacy</button></div></nav>')
  .replace('WEB DEMO', 'PREVIEW');
await writeFile(`${root}desktop/ui/index.html`, html);
let js = await readFile(`${root}website/app.js`, 'utf8');
js = js.replace(/const demoAvailable = \(\) =>[\s\S]*?\.matches;/, 'const demoAvailable = () => true;');
js = js.replace(/document.addEventListener\("visibilitychange",[\s\S]*?\n\}\);/, '');
await writeFile(`${root}desktop/ui/app.js`, js);
await copyFile(`${root}desktop/renderer.js`, `${root}desktop/ui/desktop.js`);
await copyFile(`${root}desktop/desktop.css`, `${root}desktop/ui/desktop.css`);

await copyFile(`${root}desktop/output.html`, `${root}desktop/ui/output.html`);
await copyFile(`${root}desktop/output.js`, `${root}desktop/ui/output.js`);
