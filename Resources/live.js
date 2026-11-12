// Live board: hand-offs from Jarvis to each director, directors at work, the video Studio, Results (play and read
// inside Jarvis) and each director's detail panel (tasks, activity, tokens). It only draws what the app reports:
// "work", "videoProgress", "usage", "results", "showResult" and "resultReady" events. It invents no progress.
(()=>{
const L={work:{},video:{},usage:null,results:[],current:null,flash:{},toastTimer:0};
const seatOf=s=>seatAlias[String(s||'').toLowerCase().split(/[\s·-]/)[0]]||String(s||'');
const usageKey={jarvis:'jarvis',cto:'technology',research:'research',operations:'operations',creative:'creative',projects:'projects'};
const names={jarvis:'Jarvis',cto:'CTO',research:'Research',operations:'Operations',creative:'Creative',projects:'Projects'};
const colors={jarvis:'#39d6ff',cto:'#ffc35a',research:'#b58cff',operations:'#7fd8ff',creative:'#ff5fd2',projects:'#5dffa8'};
const fmt=ms=>{const s=Math.max(0,Math.floor((ms||0)/1000)),m=Math.floor(s/60),h=Math.floor(m/60);return h?`${h}:${String(m%60).padStart(2,'0')}:${String(s%60).padStart(2,'0')}`:`${m}:${String(s%60).padStart(2,'0')}`};
const num=n=>{n=n||0;return n>=1e6?(n/1e6).toFixed(n>=1e7?0:1)+'M':n>=1e3?(n/1e3).toFixed(n>=1e4?0:1)+'k':String(n)};
const short=(t,n)=>{t=String(t||'');return t.length>n?t.slice(0,n-1)+'…':t};
const testing=/jsdom/i.test(navigator.userAgent||'');

// ---------- Board: hand-off orbs, working seats ----------
function seatPoint(el){const g=v=>parseFloat(el.style.getPropertyValue(v));return{x:g('--x')||50,y:(g('--b')||10)+(g('--h')||30)*.55}}
function handoff(from,to,label,color){
 const grid=$('voiceGrid'),a=boardSeat(from),b=boardSeat(to);if(!grid||!a||!b||a===b)return;
 const p=seatPoint(a),q=seatPoint(b),orb=document.createElement('div');
 orb.className='handoff-orb';orb.style.setProperty('--c',color||'#39d6ff');orb.innerHTML=`<i></i><span>${escape(short(label,42))}</span>`;
 orb.style.left=p.x+'%';orb.style.bottom=p.y+'%';grid.append(orb);
 const go=()=>{orb.classList.add('fly');orb.style.left=q.x+'%';orb.style.bottom=q.y+'%'};
 if(testing)go();else requestAnimationFrame(()=>requestAnimationFrame(go));
 setTimeout(()=>{orb.classList.add('land');b.classList.add('receiving');setTimeout(()=>b.classList.remove('receiving'),900)},1250);
 setTimeout(()=>orb.remove(),1900);
}
function flash(seat,text,ms){L.flash[seat]={text,until:Date.now()+(ms||4000)};paint()}
function onWork(w){
 const seat=seatOf(w.seat);
 if(w.phase==='handoff'){
  L.work[seat]=w;
  flash('jarvis',`${names[seat]||'Director'}, this one's yours: ${short(w.title,60)}`,3200);
  handoff('jarvis',seat,w.title,colors[seat]);
 }else if(w.phase==='update'){if(L.work[seat]?.taskID===w.taskID||!L.work[seat])L.work[seat]=w}
 else{
  if(L.work[seat]?.taskID===w.taskID)delete L.work[seat];
  flash(seat,w.phase==='done'?'Done ✓ Result is in Results.':'Couldn’t finish: '+short(w.text,60),6000);
  if(w.phase==='done')setTimeout(()=>handoff(seat,'jarvis','✓ '+w.title,'#65e7a8'),400);
 }
 paint();
}
function workText(w){return !w.text||w.text==='On it'?'Working on: '+short(w.title,70):w.text}
function paint(){
 const grid=$('voiceGrid'),now=Date.now();
 if(grid)grid.querySelectorAll('.seat').forEach(el=>{
  const id=el.dataset.seat,w=L.work[id],f=L.flash[id]&&L.flash[id].until>now?L.flash[id]:null,bubble=el.querySelector('.bubble');
  el.classList.toggle('working',!!w);el.classList.toggle('note',!!f);
  let badge=el.querySelector('.work-badge');
  if(w){if(!badge){badge=document.createElement('div');badge.className='work-badge';el.querySelector('.plate')?.append(badge)}badge.innerHTML=`<i></i>Working · ${fmt(now-(w.since||w.at))}`}
  else if(badge)badge.remove();
  if(bubble&&!el.classList.contains('talking')&&(f||w))bubble.textContent=f?f.text:workText(w);
  if(el.classList.contains('open'))detail(el);
 });
 strip();
 document.querySelectorAll('[data-since]').forEach(el=>{const t=Number(el.dataset.since);if(t)el.textContent=fmt(now-t)});
}

// ---------- Home strip: the board at work, visible from the Jarvis view ----------
function strip(){
 const host=$('boardStrip');if(!host)return;
 const seats=['cto','research','operations','creative','projects'],now=Date.now();
 host.innerHTML=seats.map(id=>{const w=L.work[id],f=L.flash[id]&&L.flash[id].until>now?L.flash[id]:null;
  return `<button class="strip-seat ${w?'working':''} ${f?'note':''}" data-goto="${id}" style="--c:${colors[id]}"><img src="board/${id}.webp" alt=""><span><b>${names[id]}</b><small>${escape(w?short(workText(w),46):f?short(f.text,46):'Idle')}</small></span>${w?`<time>${fmt(now-(w.since||w.at))}</time>`:''}</button>`}).join('');
 host.querySelectorAll('[data-goto]').forEach(b=>b.onclick=()=>openDirector(b.dataset.goto));
}
function openDirector(id){navigate('team');const el=boardSeat(id);if(!el)return;$('voiceGrid').querySelectorAll('.seat.open').forEach(s=>s.classList.remove('open'));el.classList.add('open');detail(el)}

// ---------- Director detail panel (click a director) ----------
function tasksFor(id){
 return (lastTasks||[]).filter(t=>!t.parentID&&seatOf(t.owner)===id);
}
function runFor(parent){return (lastTasks||[]).find(t=>t.parentID===parent.id&&t.state==='running')}
function detail(el){
 const id=el.dataset.seat,controls=el.querySelector('.seat-controls');if(!controls)return;
 let box=controls.querySelector('.seat-live');
 if(!box){box=document.createElement('div');box.className='seat-live';controls.querySelector('h3')?.after(box)}
 const w=L.work[id],now=Date.now(),list=tasksFor(id);
 const active=list.filter(t=>t.state==='running'||t.queued),done=list.filter(t=>t.state==='completed'),failed=list.filter(t=>t.state==='failed');
 const u=L.usage,key=usageKey[id]||id,today=u?.today?.[key],all=u?.allTime?.[key];
 const models=today?.models?Object.entries(today.models).map(([m,v])=>`<li><span>${escape(m)}</span><b>${num(v.input)} in · ${num(v.output)} out · ${v.calls} call${v.calls===1?'':'s'}</b></li>`).join(''):'';
 const run=w?(lastTasks||[]).find(t=>t.id===w.taskID):null;
 const video=w&&L.video[w.taskID]?studio(w.taskID,true):'';
 const row=t=>{const r=runFor(t);return `<li class="${escape(t.queued?'queued':t.state)}"><span class="chip">${escape(t.queued?'queued':t.state)}</span><div><b>${escape(short(t.title,90))}</b>${r&&r.resultSummary?`<small>${escape(short(r.resultSummary,90))}</small>`:''}</div>${t.state==='completed'?`<button data-open="${escape(t.id)}">Open</button>`:''}</li>`};
 box.innerHTML=`<div class="live-now ${w?'on':''}"><i></i><div><b>${w?'Working':'Idle'}</b>${w?`<time data-since="${w.since||w.at}">${fmt(now-(w.since||w.at))}</time>`:''}<p>${escape(w?workText(w):'Waiting for Jarvis to hand something over.')}</p>${run&&run.resultSummary&&run.resultSummary!==w?.text?`<small>${escape(short(run.resultSummary,120))}</small>`:''}</div></div>
 ${video}
 <div class="live-stats"><div><b>${active.length}</b><small>active</small></div><div><b>${done.length}</b><small>done</small></div><div><b>${failed.length}</b><small>failed</small></div><div><b>${num(today?.total)}</b><small>tokens today</small></div></div>
 <div class="live-tokens"><h4>Tokens <small>${u?`today ${num(today?.input)} in · ${num(today?.output)} out · ${today?.calls||0} calls · all time ${num(all?.total)}`:'not reported yet'}</small></h4>${models?`<ul>${models}</ul>`:''}<p class="hint">Read from each provider's reply. ${id==='operations'?'The Operations worker reports one total per run.':id==='jarvis'?'Routing and follow-up offers; the Luna voice brain is not counted.':id==='creative'?'Shot planning; renders are billed per second, not tokens.':''}</p></div>
 <div class="live-tasks"><h4>Tasks</h4>${list.length?`<ul>${[...active,...list.filter(t=>!active.includes(t))].slice(0,8).map(row).join('')}</ul>`:'<p class="hint">Nothing assigned yet.</p>'}</div>`;
 box.querySelectorAll('button[data-open]').forEach(b=>b.onclick=e=>{e.stopPropagation();native({action:'openResult',id:b.dataset.open})});
}

// ---------- Video Studio card ----------
function studio(taskID,compact){
 const j=L.video[taskID];if(!j)return'';
 const stages=[['choosing','Renderer'],['planning','Shot list'],['rendering','Render'],['joining','Join'],['finished','Done']];
 const at=stages.findIndex(s=>s[0]===j.stage);
 const steps=stages.map((s,i)=>`<li class="${j.stage==='finished'||i<at?'done':i===at?'now':''}">${s[1]}</li>`).join('');
 const live=s=>s.state==='rendering'||s.state==='downloading';
 const shots=(j.shots||[]).map(s=>{
  const label=s.state==='rendering'?(s.activity||'rendering')+(s.steps&&s.activity==='diffusing'?` ${s.step}/${s.steps}`:''):s.state==='downloading'?'downloading':s.state==='done'?'ready':s.state==='failed'?'failed':'queued';
  const time=s.startedMs?fmt((s.endedMs||Date.now())-s.startedMs):'';
  return `<figure class="shot ${escape(s.state)}" title="${escape(s.prompt)}"><div class="thumb"${s.thumb?` style="background-image:url('${s.thumb}')"`:''}><b>${s.n}</b>${live(s)?'<i class="spin"></i>':''}</div><figcaption><span>${escape(label)}</span><small${live(s)&&s.startedMs?` data-since="${s.startedMs}"`:''}>${time}</small></figcaption><i class="bar"><b style="width:${s.percent||0}%"></b></i></figure>`}).join('');
 return `<div class="studio ${compact?'compact':''} ${escape(j.stage)}" data-studio="${escape(taskID)}">
  <div class="studio-head"><span class="clap"></span><div><strong>${escape(j.headline)}</strong><small>${escape([j.renderer,j.note].filter(Boolean).join(' · '))}</small></div><time${j.endedMs?'':` data-since="${j.startedMs}"`}>${fmt((j.endedMs||Date.now())-j.startedMs)}</time></div>
  <div class="studio-progress"><b style="width:${j.percent||0}%"></b></div>
  ${compact?'':`<ol class="studio-steps">${steps}</ol>`}
  ${shots?`<div class="studio-shots">${shots}</div>`:''}
  ${j.gpu?`<p class="studio-gpu"><i></i>${escape(j.gpu)}</p>`:''}
  ${j.stage==='finished'?`<button class="primary play" data-play="${escape(taskID)}">▶ Play video</button>`:''}
 </div>`;
}
document.addEventListener('click',e=>{const b=e.target.closest&&e.target.closest('button[data-play]');if(!b)return;e.stopPropagation();const run=(lastTasks||[]).find(t=>t.id===b.dataset.play);native({action:'openResult',id:run?.parentID||b.dataset.play})});
function onVideo(j){
 L.video[j.taskID]=j;
 const cards=[...document.querySelectorAll('.studio')].filter(c=>c.dataset.studio===j.taskID);
 if(!cards.length){if(typeof renderTasks==='function')renderTasks(lastTasks||[]);return}
 cards.forEach(c=>{const t=document.createElement('div');t.innerHTML=studio(j.taskID,c.classList.contains('compact'));c.replaceWith(t.firstElementChild)});
}

// ---------- Results: play and read inside Jarvis ----------
function md(text){
 const lines=String(text||'').split('\n');let html='',list=false;
 const inline=s=>escape(s).replace(/\*\*(.+?)\*\*/g,'<b>$1</b>').replace(/`([^`]+)`/g,'<code>$1</code>');
 for(const raw of lines){const l=raw.trimEnd();
  const item=l.match(/^\s*(?:[-*]|\d+\.)\s+(.*)$/);
  if(item){if(!list){html+='<ul>';list=true}html+=`<li>${inline(item[1])}</li>`;continue}
  if(list){html+='</ul>';list=false}
  if(/^#\s/.test(l))html+=`<h2>${inline(l.slice(2))}</h2>`;else if(/^##+\s/.test(l))html+=`<h3>${inline(l.replace(/^#+\s/,''))}</h3>`;
  else if(/^---+$/.test(l))html+='<hr>';else if(l.trim())html+=`<p>${inline(l)}</p>`;
 }
 return html+(list?'</ul>':'');
}
function renderResults(){
 const list=$('resultList');if(!list)return;
 list.innerHTML=L.results.length?L.results.map(r=>`<button class="result-item ${L.current?.key===r.key?'selected':''}" data-key="${escape(r.key)}"><span class="kind ${escape(r.kind)}">${r.kind==='video'?'▶':'▤'}</span><span><b>${escape(short(r.title,80))}</b><small>${escape(r.date)}${r.summary?' · '+escape(short(r.summary,90)):''}</small></span></button>`).join(''):'<p class="hint">Nothing finished yet. When a director finishes a task, it appears here.</p>';
 list.querySelectorAll('[data-key]').forEach(b=>b.onclick=()=>native({action:'showResult',key:b.dataset.key}));
}
function showResult(item){
 L.current=item;navigate('results');renderResults();
 const v=$('resultViewer');if(!v)return;
 const shots=(item.shots||[]);
 v.innerHTML=`<header><div><p class="eyebrow">${escape(item.date)} · ${item.kind==='video'?'VIDEO':'DOCUMENT'}</p><h2>${escape(item.title)}</h2></div><button class="secondary" data-reveal>Show in Finder</button></header>
 ${item.video?`<video id="resultVideo" src="${escape(item.video)}" controls autoplay playsinline></video>${shots.length>1?`<div class="shot-picks"><button class="selected" data-src="${escape(item.video)}">Full video</button>${shots.map((s,i)=>`<button data-src="${escape(s)}">Shot ${i+1}</button>`).join('')}</div>`:''}`:''}
 <article class="md">${md(item.text)}</article>`;
 v.querySelector('[data-reveal]').onclick=()=>native({action:'revealResult',key:item.key});
 v.querySelectorAll('[data-src]').forEach(b=>b.onclick=()=>{v.querySelectorAll('[data-src]').forEach(x=>x.classList.toggle('selected',x===b));const video=$('resultVideo');video.src=b.dataset.src;video.play?.().catch(()=>{})});
}
function toast(item){
 let t=$('resultToast');
 if(!t){t=document.createElement('div');t.id='resultToast';t.className='result-toast';document.body.append(t)}
 t.innerHTML=`<span class="kind ${escape(item.kind)}">${item.kind==='video'?'▶':'▤'}</span><div><small>RESULT READY</small><b>${escape(short(item.title,70))}</b></div><button class="primary">${item.kind==='video'?'Play':'Open'}</button><button class="secondary close" aria-label="Dismiss">×</button>`;
 t.hidden=false;t.classList.add('show');
 t.querySelector('.primary').onclick=()=>{native({action:'showResult',key:item.key});t.classList.remove('show')};
 t.querySelector('.close').onclick=()=>t.classList.remove('show');
 clearTimeout(L.toastTimer);L.toastTimer=setTimeout(()=>t.classList.remove('show'),30000);
}

// ---------- Wiring ----------
function receive(event,data){
 switch(event){
  case'work':if(data&&data.seat)onWork(data);return true;
  case'videoProgress':if(data&&data.taskID)onVideo(data);return true;
  case'usage':L.usage=data;paint();return true;
  case'results':L.results=Array.isArray(data)?data:[];renderResults();return true;
  case'showResult':if(data&&data.key)showResult(data);return true;
  case'resultReady':if(data&&data.key){toast(data);if(document.querySelector('#results.active'))native({action:'listResults'})}return true;
 }
 return false;
}
function tasks(list){
 const running=new Set((list||[]).filter(t=>t.state==='running').map(t=>t.id));
 for(const [seat,w] of Object.entries(L.work))if(w.taskID&&!running.has(w.taskID))delete L.work[seat];
 paint();
}
document.querySelector('nav button[data-view="results"]')?.addEventListener('click',()=>native({action:'listResults'}));
$('refreshResults')&&($('refreshResults').onclick=()=>native({action:'listResults'}));
$('reloadUI')&&($('reloadUI').onclick=()=>native({action:'reloadUI'}));
if(!testing)setInterval(paint,1000);
window.JarvisLive={receive,tasks,studio,paint,md,state:L};
})();
