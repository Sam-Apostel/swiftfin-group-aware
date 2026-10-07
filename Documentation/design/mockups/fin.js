
const FIN_D="M0 23 C0 10.5 8.5 4.6 19.5 4.6 C31 4.6 43 11 55 15.8 C61 18.2 67 17.6 74 13.4 C82 8.6 90 2.2 97 0.5 C100.4 -0.3 101.2 1.6 100.2 3.2 L88.6 20.2 C87.4 22 87.4 24 88.6 25.8 L100.2 42.8 C101.2 44.4 100.4 46.3 97 45.5 C90 43.8 82 37.4 74 32.6 C67 28.4 61 27.8 55 30.2 C43 35 31 41.4 19.5 41.4 C8.5 41.4 0 35.5 0 23 Z";
function finSVG(opts={}){
 const id='f'+Math.random().toString(36).slice(2,7);
 const flip=opts.flip?'transform="translate(100,0) scale(-1,1)"':'';
 const op=opts.opacity??1, glow=opts.glow??1.6, tex=opts.texture!==false;
 return `<svg viewBox="-6 -6 112 58" width="100%" height="100%" style="overflow:visible;opacity:${op}">
 <defs>
 <linearGradient id="b${id}" x1="0" x2="1"><stop offset="0" stop-color="#0d2fe0"/><stop offset=".35" stop-color="#061aa8"/><stop offset=".62" stop-color="#04107e"/><stop offset=".86" stop-color="#3a1fd0"/><stop offset="1" stop-color="#f04bfa"/></linearGradient>
 <radialGradient id="s${id}" cx=".42" cy=".5" r=".6"><stop offset="0" stop-color="#000530" stop-opacity=".75"/><stop offset=".7" stop-color="#000530" stop-opacity="0"/></radialGradient>
 <linearGradient id="r${id}" x1="0" x2="1"><stop offset="0" stop-color="#2a8cff"/><stop offset=".5" stop-color="#3fedfd"/><stop offset=".78" stop-color="#7a5cff"/><stop offset=".96" stop-color="#f949fa"/></linearGradient>
 <filter id="g${id}" x="-30%" y="-50%" width="160%" height="200%"><feGaussianBlur stdDeviation="${glow}"/></filter>
 <filter id="n${id}"><feTurbulence type="fractalNoise" baseFrequency="2.2 .7" numOctaves="2" seed="3"/><feColorMatrix values="0 0 0 0 .5  0 0 0 0 .7  0 0 0 0 1  0 0 0 .55 -.2"/><feComposite in2="SourceGraphic" operator="in"/></filter>
 </defs>
 <g ${flip}>
 <path d="${FIN_D}" fill="none" stroke="url(#r${id})" stroke-width="3" filter="url(#g${id})" opacity=".85"/>
 <path d="${FIN_D}" fill="url(#b${id})"/>
 <path d="${FIN_D}" fill="url(#s${id})"/>
 ${tex?`<path d="${FIN_D}" fill="#fff" filter="url(#n${id})" opacity=".35"/>`:''}
 <path d="${FIN_D}" fill="none" stroke="url(#r${id})" stroke-width=".6"/>
 </g></svg>`;
}
document.querySelectorAll('[data-fin]').forEach(e=>{e.innerHTML=finSVG(JSON.parse(e.dataset.fin||'{}'))});
