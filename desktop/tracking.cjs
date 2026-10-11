'use strict';
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
module.exports={tokenize,align};
