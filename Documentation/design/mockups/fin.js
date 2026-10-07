// Brand artwork only: the fin is the cut-out from the logo set, never redrawn.
document.querySelectorAll('[data-fin]').forEach(e=>{const o=JSON.parse(e.dataset.fin||'{}');
 e.innerHTML=`<img src="${o.tail?'fin-tail.png':'fin-fish.png'}" style="width:100%;display:block;opacity:${o.opacity??1};${o.flip?'transform:scaleX(-1)':''}">`});
