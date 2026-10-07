const ART={
 "Tidewater":["#0f3b4f","#e8a35c","#14202b"], "Paper Moons":["#2b1a3d","#f2d6a2","#120b1c"],
 "The Long Field":["#5a6b2f","#e9dcb0","#1d230f"], "Northbound":["#203a5c","#d8e4f2","#0c1726"],
 "Saltwater Kids":["#0f6b73","#ffd166","#062a2e"], "Ember Road":["#5c1a0d","#ff8a3d","#1f0904"],
 "Glasshouse":["#1f4d3a","#b9f5d0","#0a1f17"], "Small Hours":["#2a2f6b","#ff6fae","#0d0f2a"],
 "Velvet Static":["#3d0f3f","#ff4fd8","#14031a"], "Low Tide":["#29506b","#9fe3ff","#0b1b26"],
 "The Orchard":["#6b2f2f","#ffc2a8","#230f0f"], "Kilowatt":["#111","#f5e000","#000"],
 "Harbor Lights":["#0d2140","#ffb347","#050c18"], "Quiet Planet":["#18303f","#cfe8ef","#08131a"],
 "Brass & Bone":["#4a3820","#e9c46a","#1a1309"], "Monday Club":["#3a2a6b","#a5f0c5","#130d26"],
 "Sundown Diner":["#6b1f3a","#ffcf7a","#220a13"], "Ice Station 9":["#1c3b57","#e6f7ff","#081420"]
};
function art(t){const [a,b,c]=ART[t]||["#223","#99f","#001"];const h=[...t].reduce((s,ch)=>s+ch.charCodeAt(0),0);
 const x=20+h%60, y=20+(h*7)%50;
 return `background:radial-gradient(60% 45% at ${x}% ${y}%,${b} 0%,${b}00 70%),radial-gradient(90% 60% at ${100-x}% 100%,${a} 0%,${a}00 75%),linear-gradient(${h%180}deg,${a},${c})`;}
document.querySelectorAll('[data-poster]').forEach(e=>{const t=e.dataset.poster;e.setAttribute('style',(e.getAttribute('style')||'')+';'+art(t));
 if(!e.dataset.notitle){const d=document.createElement('div');d.className='t';d.textContent=t;if(e.dataset.progress){d.style.bottom='20px'}e.appendChild(d)}
 if(e.dataset.progress){const b=document.createElement('div');b.className='bar';b.innerHTML=`<i style="width:${e.dataset.progress}%"></i>`;e.appendChild(b)}});
