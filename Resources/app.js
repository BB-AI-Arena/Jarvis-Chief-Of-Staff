'use strict';
const $=id=>document.getElementById(id);
const native=payload=>window.webkit?.messageHandlers.jarvis.postMessage(payload);
const storage={get(k,f){try{return JSON.parse(localStorage.getItem('jarvis.'+k))??f}catch{return f}},set(k,v){localStorage.setItem('jarvis.'+k,JSON.stringify(v))}};
let streamingVoice=false;let managerModel='';let claudeConnected=false;let claudeModel='claude-sonnet-5-5';let projectsModel='',debateLive=false,debateQueue=Promise.resolve(),debateQueueGen=0;let grokConnected=false,grokModel='grok-4.7',cursorConnected=false,cursorModel='',cursorRepo='https://github.com/BB-AI-Arena/Jarvis-Chief-Of-Staff';
let suggestions=[],lastTasks=[];let taskActive=false,mouthCues=[],audioTime=0,audioTimeStamp=0;
let state='idle',busy=false,spoken=storage.get('spoken',true),motion=storage.get('motion',true),conversationActive=false,audioLevel=0,voiceBackend=storage.get('voiceBackend','live');
if(!storage.get('lunaFrontV1',false)){storage.set('brain','luna');storage.set('lunaFrontV1',true)}
if(!storage.get('liveVoiceV1',false)){voiceBackend='live';storage.set('voiceBackend','live');storage.set('liveVoiceV1',true)}
if(!storage.get('voiceFirstV1',false)){spoken=true;storage.set('spoken',true);storage.set('voiceFirstV1',true)}
let liveDrafts={user:'',assistant:''};
let messages=storage.get('messages',[]),projects=storage.get('projects',[]),voices=storage.get('voices',{Jarvis:'bm_lewis',Claude:'bm_george',Grok:'am_michael',Local:'af_sarah',Designer:'bf_emma',Manager:'bm_daniel'});
let fileNodes=[],conceptNodes=[],conceptLinks=[],graphMode='folders',currentRoot='',pending=false;
const voiceNames={bm_lewis:'Lewis · British',bm_george:'George · British',bm_daniel:'Daniel · British',bm_fable:'Fable · British',bf_emma:'Emma · British',bf_alice:'Alice · British',bf_isabella:'Isabella · British',am_michael:'Michael · American',am_adam:'Adam · American',af_sarah:'Sarah · American',af_heart:'Heart · American',af_bella:'Bella · American'};
const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function notice(text){$('notice').textContent=text}
function setState(value){state=value;const labels={idle:'AT YOUR SERVICE',thinking:'CONSIDERING THE POSSIBILITIES',listening:'LISTENING · CONVERSATION ON',synthesizing:'PREPARING MY REPLY',resuming:'YOUR TURN',speaking:'SPEAKING'};$('stateLabel').textContent=labels[value]||value.toUpperCase();$('mic').classList.toggle('active',conversationActive);$('interrupt').hidden=!conversationActive||value==='listening';$('voiceSessionLabel').textContent=conversationActive?(streamingVoice?(value==='listening'?'Listening · speak naturally':'Conversation on · you can interrupt'):(value==='listening'?'Listening · pause to send automatically':'Conversation on · microphone paused')):'Click the microphone to start a conversation'}
function navigate(view){document.querySelectorAll('.view').forEach(el=>el.classList.toggle('active',el.id===view));document.querySelectorAll('nav button').forEach(el=>el.classList.toggle('selected',el.dataset.view===view));if(view==='files')requestAnimationFrame(drawGraph)}
function renderMessages(){document.body.classList.toggle('has-messages',messages.length>0);for(const target of [$('messages'),$('chatLog')]){target.replaceChildren();for(const message of messages){const row=document.createElement('div');row.className='message '+message.role;const who=document.createElement('span');who.className='who';who.textContent=message.role==='user'?'YOU':message.role==='error'?'CONNECTION NOTICE':'JARVIS';row.append(who);const text=document.createElement('span');text.textContent=message.text;row.append(text);if(message.role==='assistant'){const play=document.createElement('button');play.textContent='◖ Listen';play.onclick=()=>native({action:'speak',text:message.text,voice:voices.Jarvis});row.append(play)}target.append(row)}if(busy){const el=document.createElement('div');el.className='message sending';el.textContent='Jarvis is considering your request…';target.append(el)}target.scrollTop=target.scrollHeight}}
function voiceRequest(){return {action:'microphone',backend:['astra','luna'].includes($('brainSelect').value)?voiceBackend:'local',history:messages.filter(m=>m.role==='user'||m.role==='assistant').slice(-16).map(m=>({role:m.role,text:m.text}))}}

function saveMessages(){storage.set('messages',messages.slice(-100));renderMessages()}
function setBusy(value){busy=value;$('send').hidden=value;$('cancel').hidden=!value;$('prompt').disabled=value;renderMessages()}
function sendMessage(){const prompt=$('prompt').value.trim();if(!prompt||busy)return;const history=messages.filter(m=>m.role==='user'||m.role==='assistant').slice(-16).map(m=>`${m.role}: ${m.text}`).join('\n\n');messages.push({role:'user',text:prompt});$('prompt').value='';saveMessages();setBusy(true);native({action:'chat',prompt,history,model:$('brainSelect').value});notice('Connecting to '+($('brainSelect').value==='astra'?'GPT Astra':$('brainSelect').value==='luna'?'GPT-6 Luna':'Ollama')+'…')}
function renderCards(tab='overview'){
 const cards=tab==='agents'?[['◉','Jarvis','Chief of Staff','Chairs the board. Does not execute tasks.'],['♧','Directors','Astra runs Operations','Each seat shows its live connection on the board'],['◖','Voices','Kokoro on this Mac','Assign on the Board of Directors']]:tab==='artifacts'?[['▱','Project briefs',`${projects.length} saved locally`,'Open Projects'],['⌘','Knowledge graph',currentRoot?'Folder connected':'No folder connected','Open Knowledge map'],['✧','Build deliverables','No builds dispatched yet','Worker stage pending']]:[['✧','Your next great idea','Start with a conversation.','Astra brainstorming'],['▱','Project workspace',projects.length?`${projects.length} project brief${projects.length===1?'':'s'} saved`:'Ideas, decisions, next steps.','Stored on this Mac'],['⌘','Knowledge constellation',currentRoot?'Explore your connected folder.':'Connect the files that matter.','Graphify · local code mapping']];
 $('workspaceCards').innerHTML=cards.map(([icon,title,sub,detail])=>`<div class="task-card"><div class="icon">${icon}</div><div><h3>${title}</h3><p>${escape(sub)}</p><small>${escape(detail)}</small></div></div>`).join('')
}
// Boardroom: each seat is a layered character. Positions are percentages of the 16:9 stage.
// seatArt eye boxes [cx,cy,w,h] are % of each webp, measured from the emissive eye pixels (2026-11-09); fx is Research's brain glow.
const boardLayout={head:{x:50,b:47,h:27,z:10},left:{x:35,b:41,h:30,z:12},right:{x:65,b:41,h:30,z:12},projects:{x:22,b:25,h:38,z:20},operations:{x:83,b:24,h:40,z:20},creative:{x:8.5,b:9,h:44,z:30}};
const seatAlias={jarvis:'jarvis',head:'jarvis',chief:'jarvis',cto:'cto',technology:'cto',claude:'cto',research:'research',grok:'research',operations:'operations',ops:'operations',astra:'operations',local:'operations',creative:'creative',designer:'creative',projects:'projects',manager:'projects'};
const seatArt={jarvis:{eye:[50,26,34,7],wave:[50,39],c:'#39d6ff'},cto:{eye:[60,31.4,40,7],wave:[60,38],c:'#ffc35a'},research:{eye:[56.5,24.4,24,6],fx:[54,17.8,40,21],wave:[52,30],c:'#b58cff'},operations:{eye:[48,25.5,18,7],wave:[48,33],c:'#7fd8ff'},creative:{eye:[48.5,28.5,24,7],wave:[49,36],c:'#ff5fd2'},projects:{eye:[49,21.5,24,4.5],wave:[49,28],c:'#5dffa8'}};
const rand=(a,b)=>(a+Math.random()*(b-a)).toFixed(2);
function boardSeats(){return [
 {key:'Jarvis',seat:'head',id:'jarvis',title:'Chief of Staff',model:'GPT-6 Luna',status:'Chairs the table and does not execute tasks.',connected:true},
 {key:'Claude',seat:'left',id:'cto',title:'Chief Technology Officer',model:claudeConnected?claudeModel:'not connected',status:claudeConnected?'Engineering and review. connected':'Engineering and review. not connected',connected:claudeConnected},
 {key:'Grok',seat:'right',id:'research',title:'Director of Research',model:grokConnected?grokModel:'not connected',status:grokConnected?'Grok research. connected':'Grok research. not connected',connected:grokConnected},
 {key:'Local',seat:'operations',id:'operations',title:'Director of Operations',model:managerModel?managerModel+' · medium':'GPT Astra',status:managerModel?`Manager ${managerModel}. Hires local models as workers.`:'Hires local models as workers. Manager model not configured.',connected:true},
 {key:'Designer',seat:'creative',id:'creative',title:'Creative Director',label:'Creative Director · Cursor',model:cursorConnected?'Cursor · '+(cursorModel||'default model'):'Cursor · not connected',status:cursorConnected?'Cloud agents on '+cursorRepo.replace(/^https:\/\//,''):'Cloud agents. not connected',connected:cursorConnected},
 {key:'Manager',seat:'projects',id:'projects',title:'Director of Projects',model:projectsModel?'Ollama · '+projectsModel:'not connected',status:projectsModel?'Planning on this Mac. connected':'Planning. Local model not set',connected:!!projectsModel}
]}
function modelField(el,label,value,placeholder,aria,buttonText,action,key='model'){
 const field=document.createElement('label');field.className='manager-field';field.textContent=label;
 const input=document.createElement('input');input.value=value;input.placeholder=placeholder;input.setAttribute('aria-label',aria);
 field.append(input);el.append(field);
 const save=document.createElement('button');save.type='button';save.textContent=buttonText;save.onclick=()=>native({action,[key]:input.value});el.append(save);
}
function renderVoices(){
 const root=$('voiceGrid');const open=root.querySelector('.seat.open')?.dataset.seat;root.innerHTML='';
 for(const seat of boardSeats()){
  const pos=boardLayout[seat.seat],art=seatArt[seat.id];
  const el=document.createElement('section');el.className='seat '+seat.seat+(seat.connected?'':' disconnected')+(open===seat.id?' open':'');el.dataset.seat=seat.id;
  const vars={'--x':pos.x+'%','--b':pos.b+'%','--h':pos.h+'%','--z':pos.z,'--c':art.c,'--ex':art.eye[0]+'%','--ey':art.eye[1]+'%','--ew':art.eye[2]+'%','--eh':art.eye[3]+'%','--wx':art.wave[0]+'%','--wy':art.wave[1]+'%',
   '--breath':rand(3.4,5.2)+'s','--bdelay':'-'+rand(0,5)+'s','--look':rand(8,15)+'s','--ldelay':'-'+rand(0,12)+'s','--blink':rand(3.5,7.5)+'s','--blinkd':'-'+rand(0,6)+'s','--busy':rand(2.6,5.4)+'s','--busyd':'-'+rand(0,5)+'s','--scan':rand(1.6,2.8)+'s','--pulse':rand(2,3.4)+'s','--orbit':rand(6,9)+'s','--fill':rand(4,7)+'s'};
  if(art.fx)Object.assign(vars,{'--fxx':art.fx[0]+'%','--fxy':art.fx[1]+'%','--fxw':art.fx[2]+'%','--fxh':art.fx[3]+'%'});
  for(const [k,v] of Object.entries(vars))el.style.setProperty(k,String(v));
  if(seat.id==='creative')el.style.setProperty('--busy',rand(.8,1.1)+'s');
  el.innerHTML=`<div class="figure" role="button" tabindex="0" aria-label="${escape(seat.title)} settings"><div class="bob"><div class="sway"><div class="char"><img src="board/${seat.id}.webp" alt="${escape(seat.title)}" draggable="false"><i class="glow"></i><i class="blink"></i><i class="fx"></i><i class="wave"><b></b><b></b><b></b><b></b><b></b></i></div></div></div></div><div class="bubble" aria-live="polite"></div><div class="plate"><h2>${escape(seat.title)}</h2><p class="seat-model">${escape(seat.model)}</p><p class="seat-status">${escape(seat.status)}</p></div>`;
  const controls=document.createElement('div');controls.className='seat-controls';
  controls.innerHTML=`<h3>${escape(seat.label||seat.title)}<small>${escape(seat.model)} · ${escape(seat.status)}</small></h3><select aria-label="Voice for ${escape(seat.title)}">${Object.entries(voiceNames).map(([id,name])=>`<option value="${id}" ${voices[seat.key]===id?'selected':''}>${name}</option>`).join('')}</select><button type="button" class="preview">▷ Preview voice</button>`;
  el.append(controls);
  if(seat.seat==='left')modelField(controls,'Claude model',claudeModel,'claude-sonnet-5-5','Claude model id','Save model','setClaudeModel');
  if(seat.seat==='right')modelField(controls,'Grok model',grokModel,'grok-4.7','Grok model id','Save model','setGrokModel');
  if(seat.seat==='creative'){modelField(controls,'Target repository',cursorRepo,'https://github.com/owner/repo','Creative Director repository','Save repository','setCreativeRepo','repo');modelField(controls,'Cursor model (blank = default)',cursorModel,'default model','Creative Director Cursor model id','Save model','setCreativeModel')}
  if(seat.seat==='operations')modelField(controls,'Manager model',managerModel,'manager model not configured','Operations manager model','Save manager','setManagerModel');
  if(seat.seat==='projects')modelField(controls,'Local model (Ollama, blank = disconnect)',projectsModel,'e.g. gemma4:latest','Director of Projects local model','Save model','setProjectsModel');
  const close=document.createElement('button');close.type='button';close.className='close';close.textContent='Close';close.onclick=()=>el.classList.remove('open');controls.append(close);
  controls.querySelector('select').onchange=e=>{voices[seat.key]=e.target.value;storage.set('voices',voices)};
  controls.querySelector('.preview').onclick=()=>native({action:'speak',text:seat.key==='Jarvis'?'Good evening. Everything is in hand. Shall we turn that rather ambitious idea into a plan?':`Hello. I speak for the ${seat.title}.`,voice:voices[seat.key]});
  const toggle=()=>{const was=el.classList.contains('open');root.querySelectorAll('.seat.open').forEach(s=>s.classList.remove('open'));el.classList.toggle('open',!was)};
  el.querySelector('.figure').onclick=toggle;el.querySelector('.plate').onclick=toggle;
  el.querySelector('.figure').onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();toggle()}};
  root.append(el);
 }
}
// Debate playback: animates turns it is given. It does not generate or claim model output.
let debateToken=0;
function boardSeat(id){const key=seatAlias[String(id||'').toLowerCase()]||id;return $('voiceGrid').querySelector(`.seat[data-seat="${key}"]`)}
function clearBoardTalk(){const root=$('voiceGrid');root.querySelectorAll('.seat').forEach(s=>{s.classList.remove('talking','listening');s.style.removeProperty('--lean');s.style.removeProperty('--leanx')})}
function setBoardSpeaker(el,text){
 clearBoardTalk();const root=$('voiceGrid');root.classList.add('debating');
 el.classList.add('talking');el.querySelector('.bubble').textContent=text;
 const x=parseFloat(el.style.getPropertyValue('--x'))||50;
 root.querySelectorAll('.seat').forEach(s=>{if(s===el)return;const mx=parseFloat(s.style.getPropertyValue('--x'))||50;const dir=Math.sign(x-mx)||0;s.classList.add('listening');s.style.setProperty('--lean',(dir*2.4)+'deg');s.style.setProperty('--leanx',(dir*3)+'%')});
}
function playBoardDebate(turns,options={}){
 const {agreement=true,summary='',demo=false,pace=1,banner=''}=options;
 const token=++debateToken,root=$('voiceGrid'),ring=$('agreedRing');
 root.classList.remove('agreed');ring.hidden=true;$('debateBanner').textContent=demo?'DEMO · scripted lines, not model output':banner;$('debateBanner').hidden=!(demo||banner);
 const list=(turns||[]).filter(t=>t&&t.text);
 return new Promise(resolve=>{
  let index=0;
  const finish=done=>{if(token===debateToken){clearBoardTalk();root.classList.remove('debating','agreed');ring.hidden=true;$('debateBanner').hidden=true}resolve(done)};
  const step=()=>{
   if(token!==debateToken)return resolve(false);
   if(index>=list.length){
    clearBoardTalk();
    if(!agreement){finish(true);return}
    root.classList.add('agreed');ring.querySelector('small').textContent=summary;ring.hidden=false;
    setTimeout(()=>finish(true),2800*pace);return;
   }
   const turn=list[index++];const el=boardSeat(turn.seat);
   if(!el){step();return}
   setBoardSpeaker(el,String(turn.text));
   setTimeout(step,Math.min(6500,Math.max(1900,String(turn.text).length*58))*pace);
  };
  step();
 });
}
function stopBoardDebate(){debateToken++;debateQueueGen++;debateQueue=Promise.resolve();clearBoardTalk();$('voiceGrid').classList.remove('debating','agreed');$('agreedRing').hidden=true;$('debateBanner').hidden=true}
// Live debates arrive round by round; each round plays after the previous one finishes.
function queueDebate(turns,options){const gen=debateQueueGen;debateQueue=debateQueue.then(()=>gen===debateQueueGen?playBoardDebate(turns,options):false);return debateQueue}
function updateDebateControls(){const b=$('conveneDebate');if(b){b.disabled=debateLive;b.textContent=debateLive?'Debating…':'Convene debate'}}
window.playBoardDebate=playBoardDebate;window.stopBoardDebate=stopBoardDebate;
const demoDebateTurns=[
 {seat:'jarvis',text:'Demo topic: should we ship the boardroom this week?'},
 {seat:'cto',text:'Only if the checks pass. Keep it simple.'},
 {seat:'research',text:'Show me evidence people want it first.'},
 {seat:'operations',text:'Local models can render previews at no API cost.'},
 {seat:'creative',text:'Ship it bold. The androids sell it.'},
 {seat:'projects',text:'Cut scope: boardroom now, live debates next.'},
 {seat:'cto',text:'Fine, if live debates stay behind a flag.'},
 {seat:'jarvis',text:'Then we agree: boardroom now, debates next.'}
];
function ownerLabel(owner){const o=String(owner||'').toLowerCase();if(o==='technology'||o.startsWith('claude'))return 'CTO';if(o==='research'||o.startsWith('grok'))return 'Research';if(o==='creative')return 'Creative';if(o==='projects'||o.startsWith('projects'))return 'Projects';if(o==='board')return 'Board';if(o.startsWith('operations')||o==='source-worker'||o.startsWith('gpt-')||o.includes(':'))return 'Operations';return owner||'unassigned'}
// Suggested tasks wait here for Brandon's approval. Nothing reaches the ledger until Approve.
function suggestionRows(){return suggestions.map((t,i)=>`<article class="task-row suggested"><div><strong>${escape(t.title)}</strong><small><span class="chip">suggested</span>${escape(t.owner||ownerLabel(t.director))} · needs your approval</small></div><span><button type="button" data-approve="${i}">Approve</button> <button type="button" data-dismiss="${i}">Dismiss</button></span></article>`).join('')}
function wireSuggestions(panel){
 panel.querySelectorAll('button[data-approve]').forEach(b=>b.onclick=()=>{const t=suggestions[Number(b.dataset.approve)];if(!t)return;suggestions.splice(Number(b.dataset.approve),1);native({action:'approveTask',title:t.title,director:t.director});renderTasks(lastTasks)});
 panel.querySelectorAll('button[data-dismiss]').forEach(b=>b.onclick=()=>{suggestions.splice(Number(b.dataset.dismiss),1);renderTasks(lastTasks)});
}
function renderBoardTasks(tasks){
 const panel=$('boardTasks');if(!panel)return;
 const active=tasks.filter(t=>t.state==='running'||t.state==='proposed').slice(0,6);
 const recent=tasks.filter(t=>t.state!=='running'&&t.state!=='proposed').slice(0,4);
 const row=t=>`<article class="task-row ${escape(t.state)}"><div><strong>${escape(t.title)}</strong><small><span class="chip ${escape(t.state)}">${escape(t.state)}</span>${escape(ownerLabel(t.owner))}${t.parentID?' · subtask':''}${t.verified?' · ✓ verified':''}</small></div>${t.state==='running'?`<button type="button" data-stop="${escape(t.id)}">Stop</button>`:''}</article>`;
 panel.innerHTML=`<div class="panel-heading"><span>TASK LIST</span><span>${active.length} active</span></div>${suggestionRows()}${active.length||recent.length?active.map(row).join('')+recent.map(row).join(''):(suggestions.length?'':'<p>No tasks yet. Ask Jarvis for something and it lands here.</p>')}`;wireSuggestions(panel);
 panel.querySelectorAll('button[data-stop]').forEach(b=>b.onclick=()=>native({action:'stopTask',id:b.dataset.stop}));
}
function renderTasks(tasks){
 lastTasks=tasks;renderBoardTasks(tasks);
 const panel=$('taskPanel');
 if(!tasks.length&&!suggestions.length){panel.hidden=true;panel.replaceChildren();return}
 panel.hidden=false;
 const active=tasks.filter(task=>task.state==='running'||task.state==='proposed');
 const recent=tasks.filter(task=>task.state!=='running'&&task.state!=='proposed').slice(0,8);
 const row=task=>`<article class="task-row ${task.state}"><div><strong>${escape(task.title)}</strong><small>${escape(task.owner)} · ${escape(task.state)}${task.parentID?' · subtask':''}${task.verified?' · verified':''}${task.resultSummary?' · '+escape(task.resultSummary):''}</small></div>${task.state==='running'?`<button type="button" data-stop="${escape(task.id)}">Stop</button>`:''}</article>`;
 panel.innerHTML=`<div class="panel-heading">TASKS</div>${suggestions.length?`<div class="task-group"><h3>Suggested</h3>${suggestionRows()}</div>`:''}<div class="task-group"><h3>Active</h3>${active.length?active.map(row).join(''):'<p>No active tasks.</p>'}</div><div class="task-group"><h3>Recent</h3>${recent.length?recent.map(row).join(''):'<p>No recent tasks.</p>'}</div>`;
 panel.querySelectorAll('button[data-stop]').forEach(button=>button.onclick=()=>native({action:'stopTask',id:button.dataset.stop}));
 wireSuggestions(panel);
}
function renderProjects(){$('projectGrid').innerHTML='';if(!projects.length){$('projectGrid').innerHTML='<section class="project-card"><p class="eyebrow">A BLANK PAGE IS AN OPPORTUNITY</p><h2>Give your idea a home.</h2><p>Save a project brief here, then work through it with Jarvis. Agent execution will be connected in a later stage.</p></section>';return}projects.forEach(project=>{const card=document.createElement('section');card.className='project-card';card.innerHTML=`<small>PROJECT BRIEF · ${escape(project.date)}</small><h2>${escape(project.title)}</h2><p>${escape(project.brief)}</p><button class="secondary">Discuss with Jarvis ↗</button>`;card.querySelector('button').onclick=()=>{$('projectName').innerHTML='✧ &nbsp; '+escape(project.title);navigate('presence');$('prompt').value='Let’s work on '+project.title+'. Here is the brief:\n'+project.brief;$('prompt').focus()};$('projectGrid').append(card)})}
function newProject(){const modal=document.createElement('div');modal.className='modal-shade';modal.innerHTML='<form class="project-dialog"><p class="eyebrow">A NEW BEGINNING</p><h2>What are we building?</h2><input name="title" required placeholder="Project name" maxlength="120"><textarea name="brief" required placeholder="The idea, who it helps, what matters…" rows="6" maxlength="12000"></textarea><div><button type="button" class="secondary">Cancel</button><button class="primary" type="submit">Save project</button></div></form>';document.body.append(modal);modal.querySelector('input').focus();modal.querySelector('button').onclick=()=>modal.remove();modal.querySelector('form').onsubmit=e=>{e.preventDefault();const data=new FormData(e.target);projects.push({title:data.get('title'),brief:data.get('brief'),date:new Date().toLocaleDateString()});storage.set('projects',projects);renderProjects();renderCards();modal.remove()}}
window.receive=({event,data})=>{
 if(window.JARVIS_MODE==='orb'&&['taskStarted','taskResult'].includes(event)){taskActive=event==='taskStarted';return;}
 if(window.JARVIS_MODE==='orb'&&!['state','conversation','ready','audioLevel','mouthCues','audioTime'].includes(event))return;
 switch(event){
 case'taskStarted':taskActive=true;$('stopTask').hidden=false;notice('A background worker is working on Jarvis. You can keep talking.');break;
 case'taskUpdate':renderTasks(data||[]);break;
 case'taskSuggestion':if(data&&data.title&&!suggestions.some(t=>t.title===data.title)){suggestions.unshift({title:String(data.title),director:String(data.director||''),owner:String(data.owner||'')});suggestions=suggestions.slice(0,5);renderTasks(lastTasks)}break;
 case'managerModel':managerModel=data||'';renderVoices();break;
 case'claudeStatus':claudeConnected=!!(data&&data.connected);if(data&&data.model)claudeModel=data.model;renderVoices();break;
 case'projectsStatus':projectsModel=data&&data.connected&&data.model?data.model:'';renderVoices();break;
 case'debateStarted':stopBoardDebate();debateLive=true;updateDebateControls();queueDebate([{seat:'jarvis',text:'Board, the question: '+data.topic}],{agreement:false,banner:'LIVE · directors are answering'});notice('Board debate started with '+(data.seats||[]).length+' directors.');break;
 case'debateRound':queueDebate(data.turns||[],{agreement:false,banner:'LIVE · round '+data.round+' · model output'});if((data.silent||[]).length)notice('No answer this round from: '+data.silent.join(', '));break;
 case'debateResult':{debateLive=false;updateDebateControls();const line=data.failed?data.decision:(data.agreed?'Agreed. ':'No consensus. ')+data.decision;queueDebate([{seat:'jarvis',text:line}],{agreement:!!data.agreed,summary:data.decision,banner:data.failed?'LIVE · debate failed':'LIVE · chair: '+(data.chair||'')});if(!data.failed){messages.push({role:'assistant',text:'Board debate: '+data.topic+'\n\n'+(data.agreed?'Agreed':'No consensus')+' after '+data.rounds+' round'+(data.rounds===1?'':'s')+': '+data.decision+'\n\n'+(data.transcript||'')});saveMessages()}notice(data.failed?data.decision:'Board debate finished. The transcript is in Conversation and on the task list.');if(data.announce==='page'&&data.announcement&&(spoken||conversationActive))native({action:'speak',text:data.announcement,voice:voices.Jarvis,conversation:conversationActive});break}
 case'debateStopped':debateLive=false;updateDebateControls();stopBoardDebate();break;
 case'grokStatus':grokConnected=!!(data&&data.connected);if(data&&data.model)grokModel=data.model;renderVoices();break;
 case'creativeStatus':cursorConnected=!!(data&&data.connected);if(data&&typeof data.model==='string')cursorModel=data.model;if(data&&data.repo)cursorRepo=data.repo;renderVoices();break;
 case'taskResult':taskActive=false;$('stopTask').hidden=true;messages.push({role:'assistant',text:(data.success?'Task completed.\n\n':'Task needs attention.\n\n')+data.text});saveMessages();notice(data.success?'Background task finished. Open Conversation for the result.':'Background task needs attention. Open Conversation.');break;
 case'inputLevel':$('inputMeter').value=Number(data)||0;break;
 case'voiceStreaming':streamingVoice=!!data;$('inputMeter').hidden=!data;setState(state);if(data)$('connection').textContent='Live voice · Luna backend';break;
 case'cloudVoiceConfigured':if(data){voiceBackend='live';storage.set('voiceBackend','live');$('voiceBackend').value='live';notice('API voice connected. Start a conversation to use streaming audio.')}break;
 case'voiceBackend':voiceBackend=data;storage.set('voiceBackend',data);$('voiceBackend').value=data;break;
 case'liveDelta':liveDrafts[data.role]=(liveDrafts[data.role]||'')+data.text;$('liveTranscript').textContent=liveDrafts[data.role];break;
 case'liveMessage':{liveDrafts[data.role]='';$('liveTranscript').textContent='';const last=messages.at(-1);if(!last||last.role!==data.role||last.text!==data.text){messages.push({role:data.role,text:data.text});saveMessages()}if(data.role==='assistant')setBusy(false);$('connection').textContent='Live voice · Luna connected';break;}
 case'ready':if(data.voiceReady)$('voiceStatus').textContent='Kokoro · local · ready';break;
 case'mouthCues':mouthCues=data;audioTime=0;audioTimeStamp=performance.now();break;
 case'audioTime':audioTime=Number(data)||0;audioTimeStamp=performance.now();break;
 case'audioLevel':audioLevel=Number(data)||0;break;
 case'state':setState(data);if(data==='idle'&&$('voiceStatus').textContent.includes('playing'))$('voiceStatus').textContent='Kokoro · local · ready';break;
 case'notice':notice(data);break;
 case'reply':messages.push({role:'assistant',text:data.text});saveMessages();setBusy(false);$('connection').innerHTML='<b style="background:#65e7d1"></b>'+escape(data.model)+' · connected';notice('Reply received. Conversation saved locally.');if(spoken||conversationActive)native({action:'speak',text:data.text,voice:voices.Jarvis,conversation:conversationActive});break;
 case'chatError':messages.push({role:'error',text:data});saveMessages();setBusy(false);notice('Connection needs attention.');if(conversationActive)native({action:'speak',text:'I couldn’t complete that reply. Please try again, or we can switch models.',voice:voices.Jarvis,conversation:true});break;
 case'cancelled':setBusy(false);setState('idle');notice('Response stopped.');break;
 case'conversation':conversationActive=data.active;document.body.classList.toggle('voice-conversation',conversationActive);$('mic').title=conversationActive?'End voice conversation':'Start voice conversation';$('mic').setAttribute('aria-label',$('mic').title);$('mic').setAttribute('aria-pressed',String(conversationActive));$('voiceSessionToggle').textContent=conversationActive?'■ End conversation':'◉ Start conversation';updateSpeech();setState(state);if(!conversationActive){$('liveTranscript').textContent='';notice('Microphone off. Start a conversation when you’re ready.')}break;
 case'transcript':$('liveTranscript').textContent=data;notice('Listening… Jarvis will answer after you pause.');break;
 case'voiceTurn':if(conversationActive&&!busy){$('liveTranscript').textContent='';$('prompt').value=data;sendMessage()}break;
 case'voice':if(data.ready){$('voiceStatus').textContent='Kokoro · local · ready';notice('Kokoro ready. Jarvis’s voice: Lewis.')}if(data.path){$('voiceStatus').textContent='Kokoro · playing locally';notice(`Local voice · ${data.voice} · ${data.seconds}s to synthesize`)}if(data.error){$('voiceStatus').textContent='Kokoro · needs attention';notice(data.error)}break;
 case'indexing':pending=true;currentRoot=data.path;$('mapSubtitle').textContent=data.name+' · '+data.path;$('mapNote').textContent='Building your folder map, then extracting code relationships locally…';$('chooseFolder').disabled=true;$('refreshMap').disabled=true;notice('Mapping '+data.name+' in the background…');break;
 case'files':fileNodes=data.nodes;conceptNodes=[];conceptLinks=[];$('mapEmpty').hidden=fileNodes.length>0;$('mapNote').textContent=(data.limited?'Showing the first 1,500 entries. ':'')+'Folder structure ready. Graphify is extracting code relationships…';renderCards();drawGraph();break;
 case'graph':pending=false;$('chooseFolder').disabled=false;$('refreshMap').disabled=false;conceptNodes=data.nodes??[];conceptLinks=data.links??data.edges??[];$('mapNote').textContent='Graphify code extraction complete · local AST parsing · no model calls. Folder structure and semantic code relationships are separate views.';notice('Knowledge map ready.');drawGraph();break;
 case'graphError':pending=false;$('chooseFolder').disabled=false;$('refreshMap').disabled=false;$('mapNote').textContent=data;notice('Folder map ready; Graphify needs attention.');break;
 case'models':{const select=$('brainSelect');select.querySelectorAll('option:not([value="astra"]):not([value="luna"])').forEach(e=>e.remove());for(const model of data.models??[]){const o=document.createElement('option');o.value=model;o.textContent=model+' · Ollama';select.append(o)}if(!storage.get('localFirstV1',false)&&(data.models??[]).includes('gemma4:latest')){storage.set('brain','gemma4:latest');storage.set('voiceBackend','local');voiceBackend='local';$('voiceBackend').value='local';storage.set('localFirstV1',true)}const saved=storage.get('brain','luna');if(Array.from(select.options).some(o=>o.value===saved))select.value=saved;updateBrain();$('ollamaStatus').textContent=data.error||`${data.models.length} local model${data.models.length===1?'':'s'} available through Ollama.`;$('localRoster').textContent=data.models?.length?'Local workers available':'Ollama not running';break;}
 }
};
// Deterministic particle geometry: one Canvas, no textures or large UI framework.
function startOrb(canvas,small=false){if(window.JarvisPresence){try{new window.JarvisPresence(canvas,small,()=>({active:small?conversationActive:(conversationActive||$('presence').classList.contains('active')),state,motion,level:audioLevel,mouth:mouthPose(),working:pending||busy||taskActive}));return}catch(error){notice('3D presence could not start. '+error.message)}}const ctx=canvas.getContext('2d');let width=0,height=0,last=0,time=0;const points=[];for(let i=0;i<(small?650:1900);i++){const y=1-2*(i+.5)/(small?650:1900);const phi=i*2.399963229728653;const r=Math.sqrt(1-y*y);points.push([Math.cos(phi)*r,y,Math.sin(phi)*r,i])}let needsResize=true;new ResizeObserver(()=>needsResize=true).observe(canvas);function frame(now){requestAnimationFrame(frame);if(document.hidden||now-last<33||(!motion&&last>0&&!needsResize))return;if(!canvas.getClientRects().length)return;last=now;time=motion?now*.00018:0;if(needsResize){const rect=canvas.getBoundingClientRect();width=rect.width;height=rect.height;const dpr=Math.min(devicePixelRatio,1.7);canvas.width=width*dpr;canvas.height=height*dpr;ctx.setTransform(dpr,0,0,dpr,0,0);needsResize=false}ctx.clearRect(0,0,width,height);const cx=width*.5,cy=height*(small?.48:.46),radius=Math.min(width*(small?.36:.27),height*.35);const pulse=state==='thinking'?1+.025*Math.sin(now*.003):state==='speaking'?1+.035*Math.sin(now*.012):1;const halo=ctx.createRadialGradient(cx,cy,radius*.1,cx,cy,radius*1.7);halo.addColorStop(0,'#2cbcf91b');halo.addColorStop(.55,'#159eea12');halo.addColorStop(1,'#169fff00');ctx.fillStyle=halo;ctx.fillRect(0,0,width,height);ctx.save();ctx.translate(cx,cy);ctx.rotate(-.23);ctx.strokeStyle='#73daff22';ctx.lineWidth=.7;ctx.beginPath();ctx.ellipse(0,0,radius*1.62,radius*.27,0,0,Math.PI*2);ctx.stroke();ctx.restore();const body=ctx.createRadialGradient(cx-radius*.25,cy-radius*.3,0,cx,cy,radius);body.addColorStop(0,'#2962a02a');body.addColorStop(.75,'#04315b22');body.addColorStop(.94,'#22b8f044');body.addColorStop(1,'#81eaffaa');ctx.fillStyle=body;ctx.beginPath();ctx.arc(cx,cy,radius*pulse,0,Math.PI*2);ctx.fill();const sin=Math.sin(time),cos=Math.cos(time);for(const p of points){const x=p[0]*cos+p[2]*sin,z=p[2]*cos-p[0]*sin;const twist=.07*Math.sin(p[1]*9+time*2),xx=x+twist;const perspective=1+z*.1;const px=cx+xx*radius*perspective*pulse,py=cy+p[1]*radius*perspective*pulse;const a=.15+(z+1)*.34;ctx.fillStyle=`rgba(${z>.5?160:69},${z>.5?233:185},255,${a})`;ctx.beginPath();ctx.arc(px,py,(small?.5:.65)+(z+1)*.38,0,6.283);ctx.fill()}for(let band=0;band<7;band++){ctx.beginPath();for(let i=0;i<=100;i++){const a=i/100*Math.PI*2;const y=Math.sin(a)*Math.cos(band*.4+time*.25);const x=Math.cos(a);const z=Math.sin(a)*Math.sin(band*.4+time*.25);const rx=x*cos+z*sin;const rz=z*cos-x*sin;const px=cx+rx*radius,py=cy+y*radius;if(i===0)ctx.moveTo(px,py);else ctx.lineTo(px,py)}ctx.strokeStyle=`rgba(81,211,255,${.08+band*.009})`;ctx.lineWidth=.7;ctx.stroke()}const flare=ctx.createRadialGradient(cx-radius*.37,cy-radius*.72,0,cx-radius*.37,cy-radius*.72,radius*.6);flare.addColorStop(0,'#c1f9ff77');flare.addColorStop(1,'#54e0ff00');ctx.fillStyle=flare;ctx.fillRect(cx-radius*1.1,cy-radius*1.4,radius*2.2,radius*2.8)}requestAnimationFrame(frame)}
// The knowledge map repaints only on data/input/resize, never in the orb's animation loop.
let displayed=[],displayEdges=[],zoom=1,panX=0,panY=0,dragging=false,dragStart=null,hitNodes=[];
function graphData(){const source=graphMode==='folders'?fileNodes:conceptNodes;let search=$('graphSearch').value.toLowerCase();let filtered=source.filter(n=>!search||String(n.label??n.name??n.id).toLowerCase().includes(search));const nodes=filtered.slice(0,700);const ids=new Set(nodes.map(n=>String(n.id)));const links=graphMode==='folders'?nodes.filter(n=>n.parent&&ids.has(n.parent)).map(n=>({source:n.parent,target:n.id})):conceptLinks.filter(e=>ids.has(String(e.source))&&ids.has(String(e.target))).slice(0,1800);return{nodes,links,total:filtered.length}}
function drawGraph(){if(!$('files').classList.contains('active'))return;const canvas=$('graphCanvas'),rect=canvas.getBoundingClientRect();if(!rect.width||!rect.height)return;const dpr=Math.min(devicePixelRatio,2);canvas.width=rect.width*dpr;canvas.height=rect.height*dpr;const ctx=canvas.getContext('2d');ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,rect.width,rect.height);const {nodes,links,total}=graphData();$('graphStats').textContent=`${nodes.length}${total>nodes.length?' / '+total:''} nodes · ${links.length} links`;const positions=new Map();nodes.forEach((n,i)=>{const angle=i*2.399963229728653;const r=i===0?0:Math.sqrt(i)*14;positions.set(String(n.id),{x:Math.cos(angle)*r,y:Math.sin(angle)*r,node:n})});const scale=Math.min(rect.width,rect.height)/(Math.sqrt(Math.max(nodes.length,20))*34)*zoom;ctx.save();ctx.translate(rect.width/2+panX,rect.height/2+panY);ctx.scale(scale,scale);ctx.lineWidth=.6/scale;for(const edge of links){const a=positions.get(String(edge.source)),b=positions.get(String(edge.target));if(!a||!b)continue;ctx.strokeStyle=graphMode==='folders'?'#51c5e52a':'#a995ee30';ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke()}hitNodes=[];for(const {x,y,node} of positions.values()){const folder=node.kind==='folder',color=folder?'#69dcf6':graphMode==='folders'?'#ad9ce7':'#81b8fa';const radius=folder?5:2.8;ctx.fillStyle=color;ctx.shadowColor=color;ctx.shadowBlur=folder?10:3;ctx.beginPath();ctx.arc(x,y,radius/Math.sqrt(scale),0,6.283);ctx.fill();ctx.shadowBlur=0;const index=hitNodes.length;if(nodes.length<65||zoom>1.8||folder||index<8){ctx.fillStyle=folder?'#b5e7f5':'#8ba7bd';ctx.font=`${10/scale}px -apple-system`;const label=String(node.label??node.name??node.id).split('/').pop();ctx.fillText(label.slice(0,35),x+8/scale,y+3/scale)}hitNodes.push({x:x*scale+rect.width/2+panX,y:y*scale+rect.height/2+panY,node})}ctx.restore();if(graphMode==='graphify'&&!nodes.length&&currentRoot){ctx.fillStyle='#7396ae';ctx.font='13px -apple-system';ctx.textAlign='center';ctx.fillText(pending?'Graphify is building code relationships…':'No code relationships found in this folder.',rect.width/2,rect.height/2)}}
document.querySelectorAll('nav button').forEach(button=>button.onclick=()=>navigate(button.dataset.view));document.querySelectorAll('.tabs button').forEach(button=>button.onclick=()=>{document.querySelectorAll('.tabs button').forEach(b=>b.classList.toggle('selected',b===button));renderCards(button.dataset.tab)});document.querySelectorAll('.roster button').forEach(button=>button.onclick=()=>navigate('team'));
$('send').onclick=sendMessage;$('prompt').onkeydown=e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();sendMessage()}};$('prompt').oninput=()=>{$('prompt').style.height='auto';$('prompt').style.height=Math.min($('prompt').scrollHeight,96)+'px'};
$('cancel').onclick=()=>native({action:'cancel'});$('mic').onclick=()=>native(voiceRequest());$('interrupt').onclick=()=>native({action:'interrupt'});$('collapse').onclick=()=>native({action:'collapse'});$('miniOpen').onclick=()=>native({action:'open'});let miniDragging=false;$('dragHandle').onpointerdown=e=>{miniDragging=true;e.target.setPointerCapture(e.pointerId);native({action:'dragBegin'});e.preventDefault()};$('dragHandle').onpointermove=()=>{if(miniDragging)native({action:'dragMove'})};$('dragHandle').onpointerup=()=>{miniDragging=false;native({action:'dragEnd'})};$('dragHandle').onpointercancel=()=>{miniDragging=false;native({action:'dragEnd'})};
for(const id of ['chooseFolder','chooseFolderEmpty','attach'])$(id).onclick=()=>{navigate('files');native({action:'folder'})};$('refreshMap').onclick=()=>native({action:'refresh'});$('refreshModels').onclick=()=>native({action:'models'});$('showMini').onclick=()=>native({action:'collapse'});$('voiceSettings').onclick=()=>navigate('team');$('newProject').onclick=newProject;$('projectName').onclick=()=>navigate('projects');$('meetingBrainstorm').onclick=()=>{navigate('presence');$('prompt').value='Help me think through an important decision. Ask me what you need to know.';$('prompt').focus()};
$('voiceSessionToggle').onclick=()=>native(voiceRequest());$('speechToggle').onclick=()=>{spoken=!spoken;storage.set('spoken',spoken);updateSpeech();if(!spoken)native({action:'stopSpeech'})};function updateSpeech(){$('speechToggle').textContent=conversationActive?'◖ Voice conversation on':'◖ Spoken replies '+(spoken?'on':'off');$('speechToggle').disabled=conversationActive}updateSpeech();$('motionToggle').checked=motion;document.body.classList.toggle('no-motion',!motion);$('motionToggle').onchange=e=>{motion=e.target.checked;storage.set('motion',motion);document.body.classList.toggle('no-motion',!motion)};$('clearChat').onclick=()=>{if(confirm('Clear this local conversation?')){messages=[];saveMessages();notice('Conversation cleared.')}};
function updateBrain(){const m=$('brainSelect').value;$('modelCaption').textContent=m==='luna'?'Luna conversation · Astra reasoning':m==='astra'?'GPT Astra · deep reasoning':m+' · on this Mac';$('connection').textContent=m==='luna'?'Luna · conversation ready':m==='astra'?'Astra · ready to connect':'Ollama · local mode'}$('brainSelect').onchange=()=>{storage.set('brain',$('brainSelect').value);updateBrain()};
$('folderMode').onclick=()=>{graphMode='folders';$('folderMode').classList.add('selected');$('semanticMode').classList.remove('selected');drawGraph()};$('semanticMode').onclick=()=>{graphMode='graphify';$('semanticMode').classList.add('selected');$('folderMode').classList.remove('selected');drawGraph()};$('graphSearch').oninput=drawGraph;const map=$('graphCanvas');map.onwheel=e=>{e.preventDefault();zoom=Math.min(6,Math.max(.35,zoom*Math.exp(-e.deltaY*.003)));drawGraph()};map.onmousedown=e=>{dragStart={x:e.clientX,y:e.clientY,panX,panY};dragging=false};window.addEventListener('mousemove',e=>{if(!dragStart)return;const dx=e.clientX-dragStart.x,dy=e.clientY-dragStart.y;if(Math.abs(dx)+Math.abs(dy)>4)dragging=true;panX=dragStart.panX+dx;panY=dragStart.panY+dy;drawGraph()});window.addEventListener('mouseup',()=>dragStart=null);map.onclick=e=>{if(dragging)return;const rect=map.getBoundingClientRect();const node=hitNodes.find(p=>Math.hypot(p.x-(e.clientX-rect.left),p.y-(e.clientY-rect.top))<12)?.node;if(!node){$('nodeDetail').hidden=true;return}const detail=$('nodeDetail');detail.hidden=false;const label=node.label??node.name??node.id;const path=node.kind?node.id:node.source_file??node.file??'';detail.innerHTML=`<strong>${escape(label)}</strong><p>${escape(path||'Graphify code concept')}</p><small>${graphMode==='folders'?'Filesystem structure':'Graphify code relationship'}</small>`;if(path&&currentRoot&&(String(path).startsWith(currentRoot+'/')||path===currentRoot)){const reveal=document.createElement('button');reveal.textContent='Reveal in Finder ↗';reveal.onclick=()=>native({action:'reveal',path});detail.append(document.createElement('br'),reveal)}};new ResizeObserver(drawGraph).observe(map);
if(window.JARVIS_MODE==='orb'){document.body.classList.add('orb-mode');startOrb($('miniOrb'),true)}else{startOrb($('heroOrb'));renderMessages();renderVoices();renderBoardTasks([]);renderCards();renderProjects();native({action:'models'})}native({action:'ready',backend:voiceBackend,history:messages.filter(m=>m.role==='user'||m.role==='assistant').slice(-16).map(m=>({role:m.role,text:m.text}))});

$('backToJarvis').onclick=()=>navigate('presence');$('chatSend').onclick=()=>{$('prompt').value=$('chatPrompt').value;$('chatPrompt').value='';sendMessage()};$('chatPrompt').onkeydown=e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();$('chatSend').click()}};$('voiceBackend').value=voiceBackend;$('voiceBackend').onchange=e=>{voiceBackend=e.target.value;storage.set('voiceBackend',voiceBackend);if(conversationActive)native({action:'cancel'});notice('Voice connection saved. Start a new conversation to use it.')};

$('configureCloudVoice').onclick=()=>native({action:'configureCloudVoice'});
$('configureClaude').onclick=()=>native({action:'configureClaude'});
$('configureGrok').onclick=()=>native({action:'configureGrok'});

$('configureCursor').onclick=()=>native({action:'configureCursor'});

$('stopTask').onclick=()=>native({action:'stopTask'});
$('conveneDebate').onclick=()=>{const topic=$('debateTopic').value.trim();if(!topic){notice('Give the board a question to debate.');return}native({action:'debate',topic})};
$('debateTopic').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();$('conveneDebate').click()}};
$('demoDebate').onclick=()=>playBoardDebate(demoDebateTurns,{agreement:true,summary:'Demo · boardroom now, debates next',demo:true});

function mouthPose(){
 if(state!=='speaking'||!mouthCues.length)return null;
 const t=audioTime+Math.min(.09,(performance.now()-audioTimeStamp)/1000);
 const index=mouthCues.findIndex(c=>t>=c.start-.025&&t<c.end);
 if(index<0)return [0,0,0,0];
 const current=mouthCues[index],previous=mouthCues[index-1],next=mouthCues[index+1];
 const pose=current.pose.slice();
 // Brief anticipation and overlap, rather than snapping between phonemes.
 if(previous&&t<current.start+.035){const k=Math.max(0,Math.min(1,(t-current.start+.025)/.06));for(let n=0;n<4;n++)pose[n]=previous.pose[n]*(1-(k*k*(3-2*k)))+pose[n]*(k*k*(3-2*k));}
 if(next&&t>current.end-.035){const k=Math.min(.45,Math.max(0,(t-current.end+.035)/.07));for(let n=0;n<4;n++)pose[n]=pose[n]*(1-(k*k*(3-2*k)))+next.pose[n]*(k*k*(3-2*k));}
 return pose;
}
