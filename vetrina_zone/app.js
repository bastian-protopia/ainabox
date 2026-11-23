// AINABOX — Local Portable Sovereign AI
// Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
// Licensed under GPL-3.0-or-later

async function apiFetch(url,options){
  var t=localStorage.getItem("vetrina_token");
  if(!t){t=prompt("Token AINABOX:");if(t)localStorage.setItem("vetrina_token",t)}
  if(options&&options.headers){options.headers["Authorization"]="Bearer "+t}
  else if(options){options.headers={"Authorization":"Bearer "+t}}
  else{options={headers:{"Authorization":"Bearer "+t}}}
  var _tmo=(options.timeout)||60000;delete options.timeout;options.signal=AbortSignal.timeout(_tmo);return fetch(url,options)
}

/* ═══════ i18n ENGINE ═══════ */
let LOCALE = localStorage.getItem("ainabox_locale") || (navigator.language.startsWith("it") ? "it" : "en");
let _dict = null;

async function loadDict(locale) {
  const r = await fetch("/i18n/" + locale + ".json");
  if (!r.ok) { console.warn("i18n fetch failed: " + r.status); return; }
  _dict = await r.json();
}

function t(key, args) {
  args = args || {};
  if (!_dict) return key;
  const parts = key.split(".");
  let val = _dict;
  for (const p of parts) { val = val ? val[p] : undefined; }
  if (typeof val !== "string") return key;
  return val.replace(/\{(\w+)\}/g, function(_, k) { return args[k] !== undefined ? args[k] : "{" + k + "}"; });
}

function applyLocale() {
  document.querySelectorAll("[data-i18n]").forEach(function(el) {
    const key = el.dataset.i18n;
    const args = el.dataset.i18nArgs ? JSON.parse(el.dataset.i18nArgs) : {};
    const attr = el.dataset.i18nAttr;
    const txt = t(key, args);
    if (attr === "placeholder") el.placeholder = txt;
    else if (attr === "title") el.title = txt;
    else el.textContent = txt;
  });
}

function setLocale(locale) {
  LOCALE = locale;
  localStorage.setItem("ainabox_locale", locale);
  loadDict(locale).then(applyLocale);
}

loadDict(LOCALE).then(function(){ applyLocale(); });

/* --- SELETTORE LINGUA --- */
document.getElementById("sel-locale").addEventListener("change", function(e) { setLocale(e.target.value); });
document.getElementById("sel-locale").value = LOCALE;
/* ═══════ HELPERS ═══════ */
function setInfo(msg, cls){
  var el=document.getElementById('barra-i-text');
  el.textContent=msg;
  if(cls) el.style.color=cls; else el.style.color='';
}
function setOut(msg){
  var o=document.getElementById('out'); if(o) o.textContent=msg;
}
function riga(t,v){
  var d=document.createElement('div'); d.className='hw-item';
  d.innerHTML='<span class="k">'+t+'</span><span class="v"></span>';
  d.lastChild.textContent=v; return d;
}
function setCirc(id, fraction){
  var c=document.getElementById(id); if(!c) return;
  var C=188.5; fraction=Math.max(0,Math.min(1,fraction));
  c.style.strokeDashoffset=(C*(1-fraction));
  var w=c.closest('.donut-wrap');if(w)w.style.setProperty('--pct',(fraction*100).toFixed(1));
}
function gb(x){ return (x>=1024)?(x/1024).toFixed(1)+' Tb':Math.round(x)+' Gb'; }

/* ═══════ SISTEMA + DONUT ═══════ */
async function rinfresca(){
  var s=await(await apiFetch('/api/sistema')).json();
  var sys=document.getElementById('sys'); sys.innerHTML='';
  sys.append(riga(t('hw.cpu'), s.cpu.nome));
  if(s.gpu.presente){
    var g=s.gpu;
    sys.append(riga(t('hw.gpu'), g.nome));
    sys.append(riga('VRAM', gb(g.vram_tot_gb)));
    setCirc('donut-vram',(g.vram_tot_gb-g.vram_libera_gb)/g.vram_tot_gb);
    document.getElementById('donut-vram-val').textContent=gb(g.vram_tot_gb);
  }else{ sys.append(riga(t('hw.gpu'),'assente')); }
  var r=s.ram;
  sys.append(riga('RAM', gb(r.ram_tot_gb)));
  setCirc('donut-ram',(r.ram_tot_gb-r.ram_libera_gb)/r.ram_tot_gb);
  document.getElementById('donut-ram-val').textContent=gb(r.ram_tot_gb);
  var silos=[['Silo Ollama','Ollama'],['Silo OWU','Open WebUI'],['Silo ComfyUI','ComfyUI']];
  var sb=document.createElement('div'); sb.className='silo-bars';
  for(var i=0;i<silos.length;i++){
    var c=s.cartelle[silos[i][0]];
    if(!c||c.gb===null) continue;
    var total=c.gb+(c.disco_libero_gb||0);
    var pct=total>0?Math.max(1,(c.gb/total)*100):0;
    var bar=document.createElement('div'); bar.className='silo-bar';
    bar.innerHTML='<span class="silo-bar__label">'+silos[i][1]+'</span><div class="silo-bar__track"><div class="silo-bar__fill" style="width:'+(100-pct).toFixed(1)+'%"></div></div><span class="silo-bar__val">'+c.gb.toFixed(2)+' GB</span>';
    sb.appendChild(bar);
  }
  sys.append(sb);
  var comfy=s.cartelle['Silo ComfyUI'];
  if(comfy&&comfy.disco_libero_gb!=null){
    var el=document.getElementById('donut-ssd-val');
    if(el) el.textContent=(comfy.disco_libero_gb>=1024?(comfy.disco_libero_gb/1024).toFixed(1)+' Tb':gb(comfy.disco_libero_gb));
  }
  var st2=document.getElementById('st'); if(st2){st2.style.display='none';var h3=st2.previousElementSibling;if(h3)h3.style.display='none';}
}
/* ═══════ LED + N° ATTIVI ═══════ */
function aggiornaCockpit(){
  apiFetch('/api/cockpit').then(function(r){return r.json()})
  .then(function(j){
    var map={ollama:'led-ollama',owu:'led-owu',comfy:'led-comfy',speaches:'led-speaches',hermes:'led-hermes'};
    var attivi=0;
    for(var k in map){ var el=document.getElementById(map[k]); if(el){ var on=j.servizi&&(k==='owu'?j.servizi.owu_http:j.servizi[k]); el.className='led '+(on?'on':'off'); if(on)attivi++; if(k==='owu'&&on){var _tv=document.getElementById('opt-vocale');if(_tv)_tv.style.display='';} } }
    var n=document.getElementById('n-attivi'); if(n) n.textContent=attivi;
    var b=document.getElementById('btn-spegni'); if(b) b.classList.toggle('off', attivi===0);
    var _l1={testuale:'btn-chat',assistente:'btn-assist',grafica:'btn-grafica'};
    for(var _m in _l1){ var _eb=document.getElementById(_l1[_m]); if(_eb) _eb.classList.toggle('active', j.attivo===_m); }
    var palco=document.getElementById('palco');
    if(palco){ var m2=j.attivo==='testuale'?'chat':j.attivo; if(m2){ if(window._palco_mod!==m2){ popolaPalco(m2); window._palco_mod=m2; } } else { if(palco.innerHTML){ vuotaPalco(); window._palco_mod=null; } } }
    var ck=document.querySelector(".cockpit"); if(ck) ck.dataset.state=(j.attivo==="testuale"?"chat":j.attivo)||"";
    var h=j.hardware;
    if(h){
      if(h.cpu&&h.cpu.cores>0){ setCirc('donut-cpu',h.cpu.percent/100); var e=document.getElementById('donut-cpu-val'); if(e){ e.textContent=Math.round(h.cpu.percent)+'%'; var t=e.nextElementSibling; if(t) t.textContent='CPU '+h.cpu.cores+'C'; } }
      if(h.vram&&h.vram.total_gb>0){ setCirc('donut-vram',h.vram.used_gb/h.vram.total_gb); var e=document.getElementById('donut-vram-val'); if(e){ e.textContent=h.vram.used_gb.toFixed(1); var t=e.nextElementSibling; if(t) t.textContent='GPU '+h.vram.total_gb.toFixed(1)+' GB'; } }
      if(h.ram&&h.ram.total_gb>0){ setCirc('donut-ram',h.ram.used_gb/h.ram.total_gb); var e=document.getElementById('donut-ram-val'); if(e){ e.textContent=h.ram.used_gb.toFixed(1); var t=e.nextElementSibling; if(t) t.textContent='RAM '+h.ram.total_gb.toFixed(1)+' GB'; } }
      if(h.ssd&&h.ssd.total_gb>0){ setCirc('donut-ssd',h.ssd.used_gb/h.ssd.total_gb); var e=document.getElementById('donut-ssd-val'); if(e){ e.textContent=h.ssd.used_gb.toFixed(1); var t=e.nextElementSibling; if(t) t.textContent='SSD '+h.ssd.total_gb.toFixed(1)+' GB'; } }
    }

  }).catch(function(){});
}

/* ═══════ MENU COL 3 ═══════ */
function showPanel(nome){
  var ids=['hw','conn','backup','lingua'];
  for(var i=0;i<ids.length;i++){
    document.getElementById('panel-'+ids[i]).style.display=(ids[i]===nome)?'flex':'none';
    var _m=document.getElementById('menu-'+ids[i]); if(_m) _m.className=(ids[i]===nome)?'menu-voce menu-voce--sel':'menu-voce';
  }
  if(nome==='hw'){ rinfresca(); }
  if(nome==='conn'){ popolaConn(); }
  if(nome==='backup'){ BP.open(); }
}

/* ═══════ PACCHETTI / MODELLI ═══════ */

/* ═══════ TOKEN HF ═══════ */
async function salvaHfToken(){
  var tok=document.getElementById('campo-hftoken').value.trim(); var st=document.getElementById('hfstatus');
  if(!tok){st.textContent='❌ Token vuoto';return;} st.textContent='⏳ Salvataggio…';
  try{ var r=await apiFetch('/api/config/hf_token',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:tok})});
    var d=await r.json(); st.textContent=d.ok?t(d.msg_key||'srv.hf_salvato',d.msg_args||{}):('❌ '+(d.detail||'errore')); if(d.ok)document.getElementById('campo-hftoken').value='';
  }catch(e){st.textContent='❌ '+e;}
}

/* ═══════ L1 — AVVIA SERVIZIO ═══════ */
async function avviaServizio(nome){
  if(window._busy) return; window._busy=true;var _l1m={testuale:'btn-chat',assistente:'btn-assist',grafica:'btn-grafica'},_bk=_l1m[nome];if(_bk)document.getElementById(_bk).classList.add('pending');
  setInfo(nome==='grafica'?t('avvio.grafica_prep'):(nome==='assistente'?t('avvio.assistente_prep'):t('avvio.chat_prep')));
  if(nome==='grafica') fermaPS();
  try{ var r=await apiFetch('/api/servizio/'+nome,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({lang:LOCALE})}); var j=await r.json();
    if(j.ok&&j.stato==='avviamento'){document.getElementById('barra-i-text').innerHTML=t('avvio.generale');var _t0=Date.now();var _pi=setInterval(async function(){try{var r2=await apiFetch('/api/cockpit');var j2=await r2.json();var s=j2.servizi||{};var ok=(nome==='testuale'&&s.ollama&&s.owu_http)||(nome==='grafica'&&s.comfy)||(nome==='assistente'&&s.hermes&&s.ollama)||(nome==='vocale'&&s.speaches)||(nome==='ascolto'&&s.speaches);if(ok){clearInterval(_pi);window._busy=false;avviaServizio(nome);}else if(Date.now()-_t0>300000){clearInterval(_pi);setInfo('\u274c Avvio non completato. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline">LOG</a>','#ff9999');}}catch(e){if(Date.now()-_t0>300000){clearInterval(_pi);setInfo('\u274c Timeout.','#ff9999');}}},3000);window._busy=false;return;}
  if(j.ok){ if(!j.gia_attivo){aggiornaCockpit();popolaPalco(nome==='testuale'?'chat':nome);window._palco_mod=(nome==='testuale'?'chat':nome);} if(nome==='testuale'){var _bt=(j.gia_attivo?t('servizi.chat_gia'):t('servizi.chat_attiva'))+' <a class="btn" href="http://localhost:3000" target="_blank">'+t('servizi.apri')+'</a>';if(j.avvertenze&&j.avvertenze.length){_bt+=' <span style="color:var(--tx-body)">'+t('avvertenze.inline')+'</span>';}var _p=document.getElementById('palco');if(_p&&j.modelli){var _oldA=_p.querySelector('.avvertenze-block');if(_oldA)_oldA.remove();var _blk=document.createElement('div');_blk.className='avvertenze-block';var _h='';var _ord={ok:0,warn:1,no:2};var _s=j.modelli.slice().sort(function(a,b){return _ord[a.grado]-_ord[b.grado];});if(_s.some(function(x){return x.grado!=='ok';})){_h+='<div class="avv-riga avv-header">'+t('avvertenze.hdr')+'</div>'}_s.forEach(function(m){var _i=m.grado==='ok'?'':(m.grado==='warn'?'\u26a0\ufe0f ':'\u274c ');var _t=m.grado==='ok'?t('avvertenze.ok'):(m.grado==='warn'?t('avvertenze.warn'):t('avvertenze.no'));_h+='<div class="avv-riga">'+_i+m.nome+_t+'</div>';});_blk.innerHTML=_h;var _psC=_p.querySelector('.ps-riga');if(_psC)_p.insertBefore(_blk,_psC);else _p.appendChild(_blk);}document.getElementById('barra-i-text').innerHTML=_bt;avviaPS();} else if(nome==='grafica'){ fermaPS(); document.getElementById('barra-i-text').innerHTML=(j.gia_attivo?t('servizi.grafica_gia'):t('servizi.grafica_attiva'))+' <a class="btn" href="https://127.0.0.1:8188" target="_blank">'+t('servizi.apri')+'</a>';if(j.avvertenze&&j.avvertenze.length){document.getElementById('barra-i-text').innerHTML+=' <span style="color:var(--tx-body)">'+t('avvertenze.inline')+'</span>';}var _p2=document.getElementById('palco');if(_p2&&j.modelli){var _oldA2=_p2.querySelector('.avvertenze-block');if(_oldA2)_oldA2.remove();var _blk2=document.createElement('div');_blk2.className='avvertenze-block';var _h2='';var _ord2={ok:0,warn:1,no:2};var _s2=j.modelli.slice().sort(function(a,b){return _ord2[a.grado]-_ord2[b.grado];});if(_s2.some(function(x){return x.grado!=='ok';})){_h2+='<div class="avv-riga avv-header">'+t('avvertenze.hdr')+'</div>'}_s2.forEach(function(m){var _i2=m.grado==='ok'?'':(m.grado==='warn'?'⚠️ ':'❌ ');var _t2=m.grado==='ok'?t('avvertenze.ok'):(m.grado==='warn'?t('avvertenze.warn'):t('avvertenze.no'));_h2+='<div class="avv-riga">'+_i2+m.nome+_t2+'</div>';});_blk2.innerHTML=_h2;var _psG=_p2.querySelector('.ps-riga');if(_psG)_p2.insertBefore(_blk2,_psG);else _p2.appendChild(_blk2);} } else if(nome==='assistente'){ document.getElementById('barra-i-text').innerHTML=(j.gia_attivo?t('servizi.assist_gia'):t('servizi.assist_attivo'))+' <a class="btn" href="http://127.0.0.1:9119" target="_blank">'+t('servizi.apri')+'</a>'; } else { setInfo(''+nome+' attivo.',''); } }
    else { if(j.stato==='nessuno'){document.getElementById('barra-i-text').innerHTML=t('errore.nessun_modello')+' <a href="javascript:void(0)" onclick="avvisaAggiornamenti()" style="color:var(--tx-body)">'+t('errore.vai_agg')+'</a>';} else { var _lbl=(nome==='testuale'?t('errore.non_partita_chat'):(nome==='grafica'?t('errore.non_partita_grafica'):t('errore.non_partita_gen',{nome:nome})));setInfo('❌ '+_lbl+'. '+(j.errore||(j.errore_key?t(j.errore_key):(j.errore||t('errore.spegni_riprova'))))+' <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">'+t('errore.controlla_log')+'</a>','#ff9999'); }}
  }catch(e){ setInfo('❌ '+e,'#ff9999'); }
  if(_bk)document.getElementById(_bk).classList.remove('pending');
  aggiornaCockpit();
  window._busy=false;
}
/* ═══════ PALCO ═══════ */
function popolaPalco(m){
  var p=document.getElementById('palco'),h='';
  if(m==='chat'){
    h='<div class="palco-titolo chat">Chat</div>'
     +(LOCALE==='it'?'<div class="palco-opzione" id="opt-vocale" style="display:none" onclick="toggleOpt(this)"><span class="tgl"></span><span class="opt-nome">'+t('vocale.modalita')+'</span><span class="opt-desc">'+t('vocale.desc')+'</span></div>':'')
  }else if(m==='assistente'){
    h='<div class="palco-titolo assistente">'+t('palco.assistente')+'</div>';
  }else if(m==='grafica'){
    h='<div class="palco-titolo grafica">'+t('palco.grafica')+'</div>';
  }
  p.innerHTML=h;
}
window._psInterval=null;function avviaPS(){clearInterval(window._psInterval);window._psInterval=setInterval(function(){apiFetch('/api/naso/ps').then(function(r){return r.json()}).then(function(j){if(window._psInterval===null)return;var p=document.getElementById('palco');if(!p)return;var el=p.querySelector('.ps-riga');if(!el){el=document.createElement('div');el.className='ps-riga';p.appendChild(el);}if(!j.ok){var _v3=document.getElementById('opt-vocale');var _o3=_v3&&_v3.querySelector('.tgl').classList.contains('on');if(_o3){el.textContent=t('ps.oom');var _vEl3=p.querySelector('.vocale-riga');if(!_vEl3){_vEl3=document.createElement('div');_vEl3.className='ps-riga vocale-riga';_vEl3.textContent=t('ps.vocale_fix');p.appendChild(_vEl3);}}else{el.textContent=t('ps.down');}clearInterval(window._psInterval);window._psInterval=null;}else if(!j.models||!j.models.length){el.textContent=t('ps.nessun_modello');}else{var m=j.models[0];el.textContent=t('ps.stat',{name:m.name,vram:m.vram_gb,ram:m.ram_gb});var _v2=document.getElementById('opt-vocale');var _on2=_v2&&_v2.querySelector('.tgl').classList.contains('on');var _vEl2=p.querySelector('.vocale-riga');if(_on2&&!_vEl2){_vEl2=document.createElement('div');_vEl2.className='ps-riga vocale-riga';_vEl2.textContent=t('ps.vocale_budget');p.insertBefore(_vEl2,el.nextSibling);}if(!_on2&&_vEl2){_vEl2.remove();}}}).catch(function(){var el=document.querySelector('.ps-riga');if(el)el.textContent=t('ps.down');clearInterval(window._psInterval);window._psInterval=null;});},5000);}function fermaPS(){clearInterval(window._psInterval);window._psInterval=null;var el=document.querySelector('.ps-riga');if(el)el.remove();}function vuotaPalco(){document.getElementById('palco').innerHTML='';fermaPS()}
async function toggleOpt(el){
var tgl=el.querySelector('.tgl');
var svc=el.id.replace('opt-','');
var isOn=tgl.classList.contains('on');
var path=isOn?'/api/servizio/'+svc+'/off':'/api/servizio/'+svc;
var method='POST';
tgl.style.opacity='.5';
try{
var r=await apiFetch(path,{method:method,headers:{'Content-Type':'application/json'},body:JSON.stringify({lang:LOCALE})});
var j=await r.json();
if(!j.ok){if(!isOn)tgl.classList.remove('on');showToggleFeedback(el,(j.msg_key&&t(j.msg_key,j.msg_args||{}))||j.msg||j.errore||'Errore');}
else{if(isOn)tgl.classList.remove('on');else tgl.classList.add('on');showToggleFeedback(el,(j.msg_key&&t(j.msg_key,j.msg_args||{}))||j.msg||(j.gia_attivo?t('toggle.gia'):t('toggle.attivo')));aggiornaBarraI();if(svc==='vocale'){var _v=isOn?0:1;apiFetch('/api/naso/classifica?vocale='+_v).then(function(r){return r.json()}).then(function(j){if(!j.ok||!j.modelli)return;var _p=document.getElementById('palco');if(!_p)return;var _old=_p.querySelector('.avvertenze-block');if(_old)_old.remove();var _ord={ok:0,warn:1,no:2};var _s=j.modelli.slice().sort(function(a,b){return _ord[a.grado]-_ord[b.grado];});var _h='';if(_s.some(function(x){return x.grado!=='ok';})){_h+='<div class="avv-riga avv-header">'+t('avvertenze.hdr')+'</div>'}_s.forEach(function(m){var _i=m.grado==='ok'?'':(m.grado==='warn'?'⚠\ufe0f ':'❌ ');var _t=m.grado==='ok'?t('avvertenze.ok'):(m.grado==='warn'?t('avvertenze.warn'):t('avvertenze.no'));_h+='<div class="avv-riga">'+_i+m.nome+_t+'</div>';});if(_h){var _b=document.createElement('div');_b.className='avvertenze-block';_b.innerHTML=_h;var _ps=_p.querySelector(".ps-riga");if(_ps)_p.insertBefore(_b,_ps);else _p.appendChild(_b);}var _bi=document.getElementById('barra-i-text');if(_bi){var _needsAvv=j.modelli.some(function(m){return m.grado!=='ok'});var _avv=' <span style="color:var(--tx-body)">'+t('avvertenze.inline')+'</span>';if(_needsAvv&&_bi.innerHTML.indexOf(t('avvertenze.inline'))===-1){_bi.innerHTML+=_avv;}else if(!_needsAvv&&_bi.innerHTML.indexOf(t('avvertenze.inline'))!==-1){_bi.innerHTML=_bi.innerHTML.replace(' <span style="color:var(--tx-body)">'+t('avvertenze.inline')+'</span>','');}}}).catch(function(){});}}
}catch(e){if(!isOn)tgl.classList.remove('on');showToggleFeedback(el,'\u274c Errore di rete.');}
finally{tgl.style.opacity='1';}
}
function showToggleFeedback(el,msg){
var fb=el.querySelector('.toggle-feedback');
if(!fb)return;
fb.textContent=msg;
fb.classList.add('show');
setTimeout(function(){fb.classList.remove('show');},4000);
}
function aggiornaBarraI(){var v=document.getElementById('opt-vocale');if(!v)return;var vocale=v.querySelector('.tgl').classList.contains('on');var msg;msg=vocale?t('servizi.vocale_attiva'):t('servizi.chat_attiva');document.getElementById('barra-i-text').innerHTML=msg+' <a class="btn" href="http://localhost:3000" target="_blank">' + t('servizi.apri') + '</a>';}
/* ═══════ SPEGNI ═══════ */
function spegniAINABOX(){
  if(window._busy) return; window._busy=true;
  setInfo(t('sp.corso'));
  apiFetch('/api/spegni',{method:'POST'}).then(function(r){return r.json()})
  .then(function(j){ if(j.ok){vuotaPalco();setInfo('Per usare uno strumento, clicca una voce dal menu principale');} else {setInfo('❌ Spegnimento fallito. '+(j.errore||''),'#ff9999');} })
  .catch(function(e){setInfo('❌ '+e,'#ff9999');})
  .finally(function(){aggiornaCockpit();rinfresca();window._busy=false;});
}

/* ═══════ BACKUP ═══════ */

const BP = {
  panel:  document.getElementById("panel-backup"),
  nome:   document.getElementById("bp-nome"),
  dest:   document.getElementById("bp-dest"),
  est:    document.getElementById("bp-est"),
  dry:    document.getElementById("bp-dry"),
  go:     document.getElementById("bp-go"),
  reset:  document.getElementById("bp-reset"),
  pwrap:  document.getElementById("bp-progress-wrap"),
  pfill:  document.getElementById("bp-bar-fill"),
  pstat:  document.getElementById("bp-status"),
  job: null,

  token() { return localStorage.getItem("vetrina_token") || ""; },
  hdr()   { return { "Authorization": "Bearer " + this.token() }; },

  async open() {
    this.panel.style.display = "flex";
    this.nome.value = new Date().toISOString()
      .slice(0,10).replace(/-/g,".") + "_" +
      new Date().toTimeString().slice(0,5).replace(":","") + "_AINABOX";
    // destinazioni
    // stima
    const e = await apiFetch("/api/backup/estimate");
    const est = await e.json();
    this.est.textContent = `Fonte: ${est.source}  →  ${est.size}`;
    this.loadArchives();
    this.dest.value = "/home/AINABOX_backups";
  },

  async launch(dry) {
    let dest = this.dest.value.trim();
    if (!dest) return alert("Inserisci un percorso di backup");
    localStorage.setItem("vetrina_bp_dest", dest);
    this.pwrap.style.display = "block";
    this.pfill.parentNode.style.display = "block";
    this.pfill.style.width = "0%";
    this.pstat.textContent = dry ? "Simulazione…" : "Backup in corso…";
    this.dry.disabled = this.go.disabled = true;
    try {
      const r = await apiFetch("/api/backup", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({ dest, nome: this.nome.value, dry_run: dry })
      });
      const { job_id } = await r.json();
      this.job = job_id;
      this._stream();
    } catch(e) {
      this.pstat.textContent = "❌ " + e;
      this.dry.disabled = this.go.disabled = false;
    }
  },
  _stream() {
    const tok = this.token();
    const es = new EventSource(
      "/api/backup/stream/" + this.job + "?token=" + encodeURIComponent(tok)
    );
    es.onmessage = (e) => {
      const d = JSON.parse(e.data);
      if (d.state === "done") {
        es.close();
        this.pfill.style.width = "100%";
        this.pstat.textContent = d.dry_run
          ? "SIMULAZIONE OK → " + (d.artifact || "")
          : t('backup.completo', {gb: d.total_gb});
        this.dry.disabled = this.go.disabled = false;
        var _fill=this.pfill; setTimeout(function(){_fill.style.width="0%";},2000); if (!d.dry_run) this.loadArchives();
      } else if (d.state === "error") {
        es.close();
        this.pfill.style.width = "100%";
        this.pfill.style.background = "#ef5350";
        this.pstat.textContent = "❌ " + (d.err || t('backup.errore'));
        this.dry.disabled = this.go.disabled = false;
      } else {
        this.pfill.style.width = d.pct + "%";
        this.pstat.textContent =
          d.gb + " / " + d.total_gb + " GB  ·  " + d.speed + "  ·  ETA " + d.eta;
      }
    };
    es.onerror = () => {
      es.close();
      this.pstat.textContent = "⚠️ connessione persa";
      this.dry.disabled = this.go.disabled = false;
    };
  },
  async loadArchives() {
    try {
      const _dest = this.dest.value.trim();
      const r = await apiFetch("/api/backup/archives" + (_dest ? "?dest=" + encodeURIComponent(_dest) : ""));
      const items = await r.json();
      const list = document.getElementById("bp-archives-list");
      document.getElementById("bp-archives").style.display = "block";
      if (!items.length) {
        list.innerHTML = '<div style="color:#667;font-size:0.7rem;padding:4px 0;">Nessun backup</div>';
        return;
      }
      list.innerHTML = items.map(a =>
        '<div style="display:flex;justify-content:space-between;align-items:center;padding:5px 0;border-bottom:1px solid rgba(255,255,255,.05);">'
        + '<span style="font-size:0.8rem;font-family:monospace;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;max-width:70%;">' + a.name + '</span>'
        + '<span style="font-size:0.7rem;color:#667;margin:0 8px;white-space:nowrap;">' + a.size + ' ' + a.dest + '</span>'
        + '<button data-arch="' + a.name + '" class="bp-del" style="background:none;border:none;cursor:pointer;font-size:14px;color:#667;opacity:.6;" onmouseover="this.style.opacity=1" onmouseout="this.style.opacity=.6"> ' + t('backup.delete_btn') + '</button>'
        + '</div>'
      ).join("");
      list.querySelectorAll(".bp-del").forEach(function(b) {
        b.onclick = function() { BP.delArch(b.dataset.arch); };
      });
    } catch(e) { console.error("loadArchives", e); }
  },
  delArch(name) {
    if (!confirm(t('backup.del_prefix') + ' ' + name + '?\n' + t('backup.del_suffix'))) return;
    apiFetch("/api/backup/archive/" + encodeURIComponent(name), { method: "DELETE" })
      .then(function(r) { return r.ok ? r.json() : r.json().then(function(e) { throw new Error(e.detail || t('backup.errore_gen')); }); })
      .then(function() { BP.loadArchives(); })
      .catch(function(e) { alert("\u274C " + (e.message || e)); });
  },
  close() {
    this.panel.style.display = "none";
    this.pwrap.style.display = "none";
    this.pfill.style.width = "0%";
    this.dry.disabled = this.go.disabled = false;
  }
};

BP.dry.addEventListener("click", () => BP.launch(true));
BP.go.addEventListener("click", () => BP.launch(false));
BP.reset.addEventListener("click", () => BP.loadArchives());
BP.dest.addEventListener("change", () => {
  BP.destOv.style.display = BP.dest.value === "__override__" ? "block" : "none";
});

setInterval(aggiornaCockpit,3000);
// FASE B — SSE (canale in tempo reale)
(function(){
  var t=localStorage.getItem('vetrina_token');
  if(!t) return;
  fetch('/api/events',{headers:{'Authorization':'Bearer '+t}}).then(function(r){
    if(!r.ok) throw new Error('SSE '+r.status);
    var rd=r.body.getReader(),dc=new TextDecoder(),buf='';
    function pump(){return rd.read().then(function({value,done}){
      if(done)return;
      buf+=dc.decode(value,{stream:true});
      var parts=buf.split('\n');buf=parts.pop()||'';
      parts.forEach(function(l){
        if(l.indexOf('data: ')===0){
          try{var d=JSON.parse(l.slice(6));if(d.msg_key)setInfo(t(d.msg_key,d.msg_args||{}),d.color||'');else if(d.msg)setInfo(d.msg,d.color||'');}catch(e){}
        }
      });
      pump();
    });}
    pump();
  }).catch(function(){console.log('SSE: fallback poll attivo');});
})();
setTimeout(function(){rinfresca().catch(function(){});},500);

/* ── Connessioni ── */
async function popolaConn(){
  var r = await apiFetch('/api/collegamenti/stato');
  var j = await r.json();
  var tgl = document.getElementById('tgl-int');
  var lbl = document.getElementById('tgl-label');
  if(tgl){ tgl.classList.toggle('on', !!j.internet); }
  if(lbl){ lbl.textContent = j.internet ? 'Online' : 'Offline'; }
}
async function toggleInternet(){
  var t = document.getElementById('tgl-int');
  var on = t.classList.contains('on');
  var mode = on ? 'offline' : 'casa';
  var lbl = document.getElementById('tgl-label');
  lbl.textContent='…';
  var r = await apiFetch('/api/collegamenti/toggle', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({mode:mode})});
  var j = await r.json();
  t.classList.toggle('on', !!j.internet);
  lbl.textContent = j.internet ? 'Online' : 'Offline';
  if(!j.ok) lbl.textContent += ' ⚠️';
}

function copyComfyURL(){
  var url='https://'+window.location.hostname+':8188';
  navigator.clipboard.writeText(url).then(function(){
    toast('URL ComfyUI copiato. Incollalo in una nuova scheda.');
  }).catch(function(){
    toast('Copia non riuscita. URL: '+url);
  });
}
function toast(msg){
  var t=document.createElement('div');
  t.textContent=msg;
  t.style.cssText='position:fixed;bottom:2rem;left:50%;transform:translateX(-50%);background:#1a1a2e;color:#fff;padding:0.75rem 1.5rem;border-radius:8px;font-size:0.9rem;z-index:9999;box-shadow:0 4px 12px rgba(0,0,0,0.3);transition:opacity 0.5s';
  document.body.appendChild(t);
  setTimeout(function(){t.style.opacity='0';setTimeout(function(){t.remove()},500)},4000);
}

/* ═══════════ LOG — slide + fetch + render ═══════════ */
function easeInOut(t){return t<0.5?2*t*t:1-Math.pow(-2*t+2,2)/2}
function scorriA(target,dur,cb){
  var s=window.pageYOffset,d=target-s,t0=performance.now();
  function step(now){
    var p=Math.min((now-t0)/dur,1);
    window.scrollTo(0,s+d*easeInOut(p));
    if(p<1)requestAnimationFrame(step);else if(cb)cb();
  }
  requestAnimationFrame(step);
}
var _logPoll=null;
function vaiLog(){
  document.getElementById("content").classList.add("slide");
  document.getElementById("schermata-log").classList.add("visibile");
  setTimeout(function(){avviaPollLog();},650);
}
function tornaCockpit(){
  fermaPollLog();
  document.getElementById("content").classList.remove("slide");
  document.getElementById("schermata-log").classList.remove("visibile");
}
function avviaPollLog(){
  refreshLog();
  if(_logPoll)return;
  _logPoll=setInterval(refreshLog,3000);
}
function fermaPollLog(){
  if(_logPoll){clearInterval(_logPoll);_logPoll=null;}
}
function refreshLog(){
  apiFetch('/api/log').then(function(r){return r.json();}).then(function(j){
    var body=document.getElementById('log-body');if(!body)return;
    var lines=j.lines||[];
    var h='';
    for(var i=0;i<lines.length;i++){
      var l=lines[i];
      var cls='';
      if(/FAIL|ERROR|refused|denied|killed|OOM|❌/i.test(l))cls=' log-err';
      else if(/ok|released|attivo|success|avviato|fermo|✅/i.test(l))cls=' log-ok';
      h+='<div class="log-line'+cls+'">'+l.replace(/&/g,'&amp;').replace(/</g,'&lt;')+'</div>';
    }
    var _sb=(body.scrollHeight-body.scrollTop-body.clientHeight)<50;
    body.innerHTML=h;
    if(_sb)body.scrollTop=body.scrollHeight;
  }).catch(function(){});
}
function copiaLog(){
  var el=document.getElementById('log-body');
  var b=document.getElementById('bottone-copia');
  function ok(){if(b){b.textContent='✅';setTimeout(function(){b.textContent='⧉';},1000);}}
  function fail(){if(b){b.textContent='❌';setTimeout(function(){b.textContent='⧉';},1500);}}
  if(!el||!el.textContent.trim()){fail();return;}
  var range=document.createRange();
  range.selectNodeContents(el);
  var sel=window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  var done=document.execCommand('copy');
  sel.removeAllRanges();
  if(done)ok();else fail();
}

/* ═══════ COLPO 4 — AGGIORNA MODELLI (2 famiglie) ═══════ */
var _fam = '';
var _sel_mod = null;
var _ollamaEraDown = false;
function famiglia(nome) {
  _fam = nome;
  _sel_mod = null;
  var voci = document.querySelectorAll('.agg-menu-voce');
  for (var i = 0; i < voci.length; i++) voci[i].classList.remove('agg-menu-voce--sel');
  var sel = document.getElementById('menu-agg-' + nome);
  if (sel) sel.classList.add('agg-menu-voce--sel');
  var _t=document.getElementById('agg-panel-titolo'),_s=document.getElementById('agg-panel-sottotitolo');
  if(nome==='chat'){_t.textContent=t('agg.titolo_chat');_s.textContent=t('agg.sotto_chat');}
  else if(nome==='grafica'){_t.textContent=t('agg.titolo_grafica');_s.textContent=t('agg.sotto_grafica');}
  else if(nome==='servizi'){_t.textContent=t('agg.titolo_servizi');_s.textContent=t('agg.sotto_servizi');}
  else{_t.textContent=t('agg.titolo_ainabox');_s.textContent='';}
  var modelli = document.getElementById('agg-modello');
  var servizi = document.getElementById('agg-servizi');
  var ainabox = document.getElementById('agg-ainabox');
  if (nome === 'chat' || nome === 'grafica') {
    modelli.style.display = 'flex';
    servizi.style.display = 'none';
    ainabox.style.display = 'none';
    document.getElementById('fam-lista').innerHTML = '';
    document.getElementById('fam-cerca').value = '';
    document.getElementById('btn-scarica').disabled = true;
    document.getElementById('scarica-stato').textContent = '';
    if (nome === 'chat') {
      // Mostra loading, nasconde il corpo del pannello
      var _ld = document.getElementById('agg-loading');
      var _bd = document.getElementById('agg-chat-body');
      if (_ld) _ld.style.display = 'block';
      if (_bd) _bd.style.display = 'none';
      // Reset barra
      var _fl = document.getElementById('agg-load-fill');
      if (_fl) _fl.style.width = '5%';
      // Reset testo loading (in caso di timeout precedente)
      if (_ld) _ld.innerHTML = '<div style="font-size:0.85rem;color:var(--tx-body);margin-bottom:0.8rem">'+t('agg.caricando')+'</div><div class="agg-load-bar" style="max-width:180px;margin:0 auto"><div class="agg-load-fill" id="agg-load-fill"></div></div>';
      // Controlla se Ollama \u00e8 gi\u00e0 up
      apiFetch('/api/ollama/up').then(function(r){return r.json();}).then(function(d){
        if (d.up) {
          aggChatPronto();
        } else {
          _ollamaEraDown = true;
          apiFetch('/api/ollama/accendi', {method:'POST', timeout: 90000})
            .then(function(){ aggChatPollUp(); })
            .catch(function(){ aggChatTimeout(); });
        }
      }).catch(function(){ aggChatTimeout(); });
    }
  } else if (nome === 'servizi') {
    modelli.style.display = 'none';
    servizi.style.display = 'flex';
    statoServizi();
    ainabox.style.display = 'none';
  } else if (nome === 'ainabox') {
    modelli.style.display = 'none';
    servizi.style.display = 'none';
    ainabox.style.display = 'flex';
    statoAinabox();
  }
}

/* ── AGG CHAT: polling Ollama up ── */
function aggChatPollUp() {
  var max = 15, i = 0;
  function tick() {
    i++;
    var bar = document.getElementById('agg-load-fill');
    if (bar) bar.style.width = Math.min(90, Math.round((i / max) * 100)) + '%';
    apiFetch('/api/ollama/up').then(function(r) { return r.json(); }).then(function(d) {
      if (d.up) {
        var b2 = document.getElementById('agg-load-fill');
        if (b2) b2.style.width = '100%';
        setTimeout(aggChatPronto, 300);
      } else if (i < max) {
        setTimeout(tick, 2000);
      } else {
        aggChatTimeout();
      }
    }).catch(function() {
      if (i < max) setTimeout(tick, 2000);
      else aggChatTimeout();
    });
  }
  setTimeout(tick, 2000);
}
function aggChatPronto() {
  var ld = document.getElementById('agg-loading');
  if (ld) ld.style.display = 'none';
  var bd = document.getElementById('agg-chat-body');
  if (bd) bd.style.display = 'flex';
  apiFetch('/api/ollama/installati').then(function(r) { return r.json(); }).then(function(d) {
    if (d.modelli && d.modelli.length) { renderInstallati(d.modelli); }
    else {
      document.getElementById('fam-installati-wrap').style.display = 'block';
      document.getElementById('fam-installati').innerHTML = '<div style="padding:0.4rem 0.5rem;color:#888;font-size:0.85rem">Nessun modello installato.</div>';
    }
  }).catch(function() {
    document.getElementById('fam-installati-wrap').style.display = 'block';
    document.getElementById('fam-installati').innerHTML = '<div style="padding:0.4rem 0.5rem;color:#888;font-size:0.85rem">Motore Chat non attivo.</div>';
  });
}
function aggChatTimeout() {
  var ld = document.getElementById('agg-loading');
  if (ld) {
    ld.innerHTML = '<div style="font-size:0.85rem;color:#ff9999">\u26A0\uFE0F Motore non avviato. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a></div>';
  }
  var bd = document.getElementById('agg-chat-body');
  if (bd) bd.style.display = 'flex';
}

function cercaFam() {
  if (!_fam) return;
  var q = document.getElementById('fam-cerca').value.trim();
  var url = '/api/modelli/' + _fam + (q ? '?q=' + encodeURIComponent(q) : '');
  var btn = document.getElementById('btn-scarica');
  btn.disabled = true;
  document.getElementById('scarica-stato').textContent = '⏳ Cerca…';
  apiFetch(url).then(function(r) { return r.json(); })
  .then(function(d) {
    if (!d.ok) { document.getElementById('scarica-stato').textContent = '❌ ' + (d.detail || 'errore'); return; }
    document.getElementById('scarica-stato').textContent = d.count + ' modelli trovati';
    renderLista(d.modelli);
  })
  .catch(function(e) { document.getElementById('scarica-stato').textContent = '❌ ' + e; });
}

function renderLista(modelli) {
  var box = document.getElementById('fam-lista');
  box.innerHTML = '';
  if (!modelli.length) { box.innerHTML = '<div style="padding:0.5rem;color:#999">Nessun modello trovato.</div>'; return; }
  modelli.forEach(function(m, i) {
    var row = document.createElement('div');
    row.style.cssText = 'padding:0.35rem 0.5rem;cursor:pointer;border-bottom:1px solid #333;display:flex;justify-content:space-between;align-items:center';
    row.style.background = 'transparent';
    var lbl = document.createElement('span');
    if (_fam === 'chat') {
      lbl.textContent = m.nome + ' · ' + (m.downloads ? Math.round(m.downloads / 1e6) + 'M dl' : '');
    } else {
      lbl.textContent = m.nome + ' · ' + m.type;
    }
    if (m.gated) { lbl.innerHTML += ' 🔐'; }
    if (m.installed) { lbl.innerHTML += '<span style="color:#888;font-size:0.8em">(installato)</span>'; }
    row.appendChild(lbl);
    row.onclick = function() {
      box.querySelectorAll('div').forEach(function(el) { el.style.background = 'transparent'; });
      row.style.background = '#1a6f3a';
      _sel_mod = m;
      document.getElementById('btn-scarica').disabled = (m.installed === true);
      document.getElementById('scarica-stato').textContent = m.installed ? 'Già installato' : m.file ? (m.file + ' · ' + m.size_gb + ' GB') : 'Selezionato';
    };
    box.appendChild(row);
  });
}

function scaricaFam() {
  if (!_sel_mod || !_fam) return;
  var btn = document.getElementById('btn-scarica');
  var stato = document.getElementById('scarica-stato');
  btn.disabled = true;
  stato.textContent = '⏳ Scaricando ' + (_sel_mod.nome || _sel_mod.file) + '…';
  var fam = _fam;
  if (fam === 'chat') {
    // 2 step: prima il tree per scegliere il file, poi scarica
    // Per ora: uso il nome del repo come repo, e chiedo al tree
    var repo = _sel_mod.nome;
    apiFetch('/api/modelli/chat/tree?repo=' + encodeURIComponent(repo)).then(function(r) { return r.json(); })
    .then(function(tree) {
      if (!tree.ok || !tree.file.length) { stato.textContent = '❌ Nessun file .gguf nel repo'; btn.disabled = false; return; }
      // default: Q4_K_M o il primo
      var f = tree.file.find(function(x) { return /Q4_K_M/i.test(x.file); }) || tree.file[0];
      stato.textContent = '⏳ Scaricando ' + f.file + ' (' + f.size_gb + ' GB)…';
      var url = '/api/modelli/scarica?famiglia=' + fam + '&repo=' + encodeURIComponent(repo) + '&file=' + encodeURIComponent(f.file);
      apiFetch(url, { method: "POST", timeout: 3600000 }).then(function(r) { return r.json(); })
      .then(function(d) {
        if (d.ok) { stato.textContent = '✅ Modello installato.'; }
        else { stato.textContent = '❌ ' + (d.errore || d.detail || d.fase || 'errore'); }
        btn.disabled = false;
      })
      .catch(function(e) { stato.textContent = '❌ ' + e; btn.disabled = false; });
    })
    .catch(function(e) { stato.textContent = '❌ ' + e; btn.disabled = false; });
  } else {
    // grafica: reference URL + save_path
    var ref = _sel_mod.reference || '';
    var fname = _sel_mod.filename || '';
    var spath = _sel_mod.save_path || '';
    if (!ref || !fname) { stato.textContent = '❌ Missing ref/filename'; btn.disabled = false; return; }
    // estraggo repo da reference (huggingface.co/xxx/yyy)
    var repo = '';
    var hfMatch = ref.match(/huggingface\.co\/([^/]+\/[^/]+)/);
    if (hfMatch) repo = hfMatch[1];
    if (!repo) { stato.textContent = '❌ Fonte non supportata'; btn.disabled = false; return; }
    var url = '/api/modelli/scarica?famiglia=' + fam + '&repo=' + encodeURIComponent(repo) + '&file=' + encodeURIComponent(fname) + '&folder=' + encodeURIComponent(spath);
    apiFetch(url, { method: "POST", timeout: 3600000 }).then(function(r) { return r.json(); })
    .then(function(d) {
      if (d.ok) { stato.textContent = '✅ Modello installato.'; }
      else { stato.textContent = '❌ ' + (d.errore || d.detail || d.fase || 'errore'); }
      btn.disabled = false;
    })
    .catch(function(e) { stato.textContent = '❌ ' + e; btn.disabled = false; });
  }
}

/* ═══════ COLPO C — AGGIORNAMENTI (sezione slide) ═══════ */
function avvisaAggiornamenti(){
  document.getElementById('barra-i-text').innerHTML =
    t('agg.avvisa_spegni')+' <a class="btn" style="padding:0.3rem 0.8rem;font-size:0.82rem" href="javascript:void(0)" onclick="procediAggiornamenti()">'+t('agg.procedi')+'</a>';
}

async function procediAggiornamenti(){
  if(window._busy) return; window._busy=true;
  setInfo(t('sp.spegnendo'));
  apiFetch('/api/spegni',{method:'POST'}).then(function(r){return r.json()})
  .catch(function(){})
  .finally(function(){
    document.getElementById('schermata-agg').classList.add('open');
    famiglia('grafica');
    aggiornaCockpit();
    window._busy=false;
  });
}

function chiudiAggiornamenti(){
  if (_ollamaEraDown) {
    apiFetch('/api/ollama/spegni', {method:'POST'});
    _ollamaEraDown = false;
  }
  document.getElementById('schermata-agg').classList.remove('open');
  document.getElementById('barra-i-text').textContent = t('sp.benvenuto');
}
/* ── AGG LOG ── */
var _aggLogPoll = null;
function aggMostraLog(){vaiLog();}
function aggChiudiLog() {
  if (_aggLogPoll) { clearInterval(_aggLogPoll); _aggLogPoll = null; }
  document.getElementById('agg-log-section').style.display = 'none';
  document.querySelector('.agg-content').style.display = 'flex';
}
function refreshLogAgg() {
  apiFetch('/api/log').then(function(r){return r.json();}).then(function(j){
    var body = document.getElementById('log-body-agg'); if(!body) return;
    var lines = j.lines || [];
    var h = '';
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i];
      var cls = '';
      if (/FAIL|ERROR|refused|denied|killed|OOM|❌/i.test(l)) cls = ' log-err';
      else if (/ok|released|attivo|success|avviato|fermo|✅/i.test(l)) cls = ' log-ok';
      h += '<div class="log-line' + cls + '">' + l.replace(/&/g,'&amp;').replace(/</g,'&lt;') + '</div>';
    }
    var _sb=(body.scrollHeight-body.scrollTop-body.clientHeight)<50;
    body.innerHTML = h;
    if(_sb)body.scrollTop=body.scrollHeight;
  }).catch(function(){});
}

function renderInstallati(modelli) {
  var box = document.getElementById('fam-installati');
  var wrap = document.getElementById('fam-installati-wrap');
  wrap.style.display = 'block';
  box.innerHTML = '';
  if (!modelli.length) { box.innerHTML = '<div style="padding:0.4rem 0.5rem;color:#888;font-size:0.85rem">Nessun modello installato.</div>'; return; }
  modelli.forEach(function(m) {
    var row = document.createElement('div');
    row.style.cssText = 'padding:0.35rem 0.5rem;border-bottom:1px solid #333;display:flex;justify-content:space-between;align-items:center';
    var lbl = document.createElement('span');
    lbl.style.cssText = 'font-size:0.85rem';
    var gb = (m.size / 1e9).toFixed(1);
    lbl.textContent = m.name + ' \u00b7 ' + gb + ' GB' + (m.params ? ' \u00b7 ' + m.params : '') + (m.quant ? ' \u00b7 ' + m.quant : '');
    row.appendChild(lbl);
    var btn = document.createElement('button');
    btn.className = 'btn';
    btn.textContent = t('agg.rimuovi');
    btn.style.cssText = 'font-size:0.75rem;padding:0.2rem 0.6rem;margin-left:0.5rem';
    btn.onclick = function() { rimuoviModello(m.name); };
    row.appendChild(btn);
    box.appendChild(row);
  });
}

function rimuoviModello(nome) {
  if (!confirm('Rimuovere "' + nome + '" da Ollama?')) return;
  apiFetch('/api/ollama/rimuovi?nome=' + encodeURIComponent(nome), {method:'POST'}).then(function(r){return r.json();}).then(function(d){
    if (d.ok) {
      var box = document.getElementById('fam-installati');
      box.innerHTML = '<div style="padding:0.4rem 0.5rem;color:#888;font-size:0.85rem">' + nome + ' rimosso.</div>';
      setTimeout(function(){
        apiFetch('/api/ollama/installati').then(function(r){return r.json();}).then(function(d2){
          if (d2.modelli && d2.modelli.length) { renderInstallati(d2.modelli); }
          else { document.getElementById('fam-installati-wrap').style.display = 'none'; }
        });
      }, 800);
    } else {
      alert('Errore: ' + (d.errore || 'non rimosso.'));
    }
  }).catch(function(){ alert('Errore di connessione.'); });
}

/* ═══════════ AGGIORNA SERVIZI (Colpo 5a) ═══════════ */
function statoServizi() {
  apiFetch('/api/servizi/stato').then(function(r){return r.json();}).then(function(d) {
    var el = document.getElementById('agg-servizi-righe');
    if (!el) return;
    if (!d.ok) { el.innerHTML = '<div style="padding:0.5rem;color:#ff9999;font-size:0.85rem">Errore: ' + (d.errore||'sconosciuto') + '</div>'; return; }
    var html = '';
    d.motori.forEach(function(m) {
      var up = m.disponibile && m.disponibile !== m.attuale;
      html += '<div class="agg-serv-riga">';
      html += '<div class="agg-serv-nome">' + (m.motore==='ollama'?'Ollama':'Open WebUI') + '</div>';
      html += '<div class="agg-serv-ver">' + m.attuale + ' <span class="agg-serv-data">(' + m.data + ')</span></div>';
      html += '<div class="agg-serv-btns">';
      if (up) html += '<button class="btn agg-serv-btn" onclick="aggiornaServizio(\''+m.motore+'\')" id="btn-agg-'+m.motore+'">'+t('agg.aggiorna')+'</button>';
      else html += '<button class="btn agg-serv-btn" disabled>'+t('agg.aggiorna')+'</button>';
      html += '<button class="btn agg-serv-btn" onclick="rollbackServizio(\'' + m.motore + '\')" id="btn-rb-' + m.motore + '" style="margin-left:0.5rem">ROLLBACK</button>';

      html += '</div></div>';
    });
    el.innerHTML = html;
    statoServizi5b();
  }).catch(function() {
    var el = document.getElementById('agg-servizi-righe');
    if (el) el.innerHTML = '<div style="padding:0.5rem;color:#888;font-size:0.85rem">Non raggiungibile.</div>';
  });
}
function statoServizi5b() {
  apiFetch('/api/servizi5b/stato').then(function(r){return r.json();}).then(function(d) {
    var el = document.getElementById('agg-servizi-righe');
    if (!el) return;
    if (!d.ok) { el.innerHTML = '<div style="padding:0.5rem;color:#ff9999;font-size:0.85rem">Errore: ' + (d.errore||'sconosciuto') + '</div>'; return; }
    var html = '';
    var nomi = {comfy:'ComfyUI',speaches:'Speaches',hermes:'Hermes'};
    ['comfy','speaches','hermes'].forEach(function(k) {
      var m = d.servizi[k];
      if (!m) return;
      html += '<div class="agg-serv-riga">';
      html += '<div class="agg-serv-nome">' + nomi[k] + '</div>';
      html += '<div class="agg-serv-ver">' + m.attuale + ' <span class="agg-serv-data">(' + m.data + ')</span></div>';
      html += '<div class="agg-serv-btns">';
      var _dis = (m.aggiornabile === false) ? ' disabled' : '';
      html += '<button class="btn agg-serv-btn" data-nome="'+k+'"'+_dis+'>'+t('agg.aggiorna')+'</button>';
      html += '<button class="btn agg-serv-btn rollback-btn" data-nome="'+k+'" style="margin-left:0.5rem">ROLLBACK</button>';
      html += '</div></div>';
    });
    el.querySelectorAll('.agg-serv-btn[data-nome]').forEach(function(b){ b.closest('.agg-serv-riga').remove(); });
    el.insertAdjacentHTML("beforeend", html);
    el.querySelectorAll(".agg-serv-btn[data-nome]").forEach(function(b){
  el.querySelectorAll(".rollback-btn[data-nome]").forEach(function(b){ b.addEventListener('click', function(){ rollbackServizio5b(b.getAttribute('data-nome')); });});
      b.addEventListener('click', function(){ aggiornaServizio5b(b.getAttribute('data-nome')); });
    });
  }).catch(function() {
    var el = document.getElementById('agg-servizi-righe');
    if (el) el.innerHTML = '<div style="padding:0.5rem;color:#888;font-size:0.85rem">Non raggiungibile.</div>';
  });
}
function aggiornaServizio5b(nome) {
  if(window._busy) return; window._busy=true;
  var btn = document.getElementById('btn-agg5b-' + nome);
  if (btn) { btn.disabled = true; btn.textContent = '\u23F3 IN CORSO\u2026'; }
  var bar = document.getElementById('barra-i-text');
  if (bar) bar.innerHTML = '\u23F3 Aggiornamento in corso\u2026';
  var _x5 = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
  if (_x5) { _x5.disabled = true; _x5.style.opacity = '0.4'; _x5.innerHTML = '\u26D4'; }
  function _unblock5(){window._busy=false;if(_x5){_x5.disabled=false;_x5.style.opacity='1';_x5.innerHTML='\u2715';}}
  apiFetch('/api/servizi5b/aggiorna/' + nome, {method:'POST', timeout: 600000}).then(function(r){return r.json();}).then(function(d) {
    if (d.ok) {
      if (bar) bar.innerHTML = '\u2705 ' + nome + ' aggiornato.';
      if (btn) { btn.disabled = false; btn.textContent = t('agg.aggiorna'); }
      statoServizi5b();
    } else {
      if (bar) bar.innerHTML = '\u26A0\uFE0F Aggiornamento non riuscito. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
      if (btn) { btn.disabled = false; btn.textContent = t('agg.aggiorna'); }
      statoServizi5b();
    }
    _unblock5();
  }).catch(function() {
    if (bar) bar.innerHTML = '\u26A0\uFE0F Errore di rete. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
    if (btn) { btn.disabled = false; btn.textContent = t('agg.aggiorna'); }
    _unblock5();
  });
}
function rollbackServizio5b(nome) {
  if(window._busy) return; window._busy=true;
  var _x_rb = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
  if (_x_rb) { _x_rb.disabled = true; _x_rb.style.opacity = '0.4'; _x_rb.innerHTML = '\u26D4'; }
  function _unblock_rb(){ if(_x_rb){ _x_rb.disabled=false; _x_rb.style.opacity='1'; _x_rb.innerHTML='\u2715'; } }
  var bar = document.getElementById('barra-i-text');
  if (bar) bar.innerHTML = '\u23F3 Rollback in corso\u2026';
  apiFetch('/api/servizi5b/rollback/' + nome, {method:'POST', timeout: 600000})
    .then(function(r){return r.json();})
    .then(function(d) {
      if (d.ok) {
        if (bar) bar.innerHTML = '\u2705 ' + nome + ': rollback completato. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#777;text-decoration:underline;cursor:pointer">LOG</a>';
      } else {
        if (bar) bar.innerHTML = '\u26A0\uFE0F Rollback non riuscito. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
      }
      statoServizi5b();
      window._busy=false;
      _unblock_rb();
    })
    .catch(function() {
      if (bar) bar.innerHTML = '\u26A0\uFE0F Errore di rete. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
      window._busy=false;
      _unblock_rb();
    });
}

function rollbackServizio(motore) {
  if(window._busy) return; window._busy=true;
  var _x_rb = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
  if (_x_rb) { _x_rb.disabled = true; _x_rb.style.opacity = '0.4'; _x_rb.innerHTML = '\u26D4'; }
  function _unblock_rb(){ if(_x_rb){ _x_rb.disabled=false; _x_rb.style.opacity='1'; _x_rb.innerHTML='\u2715'; } }
  var btn = document.getElementById('btn-rb-' + motore);
  if (btn) { btn.disabled = true; btn.textContent = '\u23F3 IN CORSO\u2026'; }
  var bar = document.getElementById('barra-i-text');
  if (bar) bar.innerHTML = '\u23F3 Rollback in corso\u2026';
  apiFetch('/api/servizi/rollback?motore=' + motore, {method:'POST', timeout: 600000})
    .then(function(r){return r.json();})
    .then(function(d) {
      if (d.ok) {
        if (bar) bar.innerHTML = '\u2705 ' + motore + ': rollback a ' + (d.versione||'precedente') + '.';
      } else {
        if (bar) bar.innerHTML = '\u26A0\uFE0F Rollback non riuscito. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
      }
      if (btn) { btn.disabled = false; btn.textContent = 'ROLLBACK'; }
      window._busy=false;
      _unblock_rb();
      statoServizi();
    })
    .catch(function() {
      if (bar) bar.innerHTML = '\u26A0\uFE0F Errore di rete. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
      if (btn) { btn.disabled = false; btn.textContent = 'ROLLBACK'; }
      window._busy=false;
      _unblock_rb();
    });
}

function aggiornaServizio(motore) {
  var btn = document.getElementById('btn-agg-' + motore);
  if (btn) { btn.disabled = true; btn.textContent = '\u23F3 IN CORSO\u2026'; }
  var bar = document.getElementById('barra-i-text');
  if (bar) bar.innerHTML = '\u23F3 Aggiornamento in corso\u2026';
  var _x = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
  if (_x) { _x.disabled = true; _x.style.opacity = '0.4'; _x.innerHTML = '\u26D4'; }
  apiFetch('/api/servizi/aggiorna?motore=' + motore, {method:'POST', timeout: 600000}).then(function(r){return r.json();}).then(function(d) {
    if (d.ok) {
      if (bar) bar.innerHTML = '\u2705 ' + motore + ' aggiornato a ' + (d.nuova||d.messaggio) + '.';
      var _xu = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
      if (_xu) { _xu.disabled = false; _xu.style.opacity = '1'; _xu.innerHTML = '\u2715'; }
      statoServizi();
    } else {
      if (bar) bar.innerHTML = '\u26A0\uFE0F Aggiornamento non riuscito. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
      var _xu2 = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
      if (_xu2) { _xu2.disabled = false; _xu2.style.opacity = '1'; _xu2.innerHTML = '\u2715'; }
      statoServizi();
    }
  }).catch(function() {
    if (bar) bar.innerHTML = '\u26A0\uFE0F Errore di rete. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
    var _xu3 = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
    if (_xu3) { _xu3.disabled = false; _xu3.style.opacity = '1'; _xu3.innerHTML = '\u2715'; }
    if (btn) { btn.disabled = false; btn.textContent = t('agg.aggiorna'); }
  });
}
function rollbackServizio(motore) {
  var bar = document.getElementById('barra-i-text');
  if (bar) bar.innerHTML = '\u23F3 Rollback in corso\u2026';
  var _x2 = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
  if (_x2) { _x2.disabled = true; _x2.style.opacity = '0.4'; _x2.innerHTML = '\u26D4'; }
  apiFetch('/api/servizi/rollback?motore=' + motore, {method:'POST', timeout: 120000}).then(function(r){return r.json();}).then(function(d) {
    if (d.ok) {
      if (bar) bar.innerHTML = '\u2705 Tornato a ' + d.versione + '.';
      var _xr = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
      if (_xr) { _xr.disabled = false; _xr.style.opacity = '1'; _xr.innerHTML = '\u2715'; }
      statoServizi();
    } else {
      if (bar) bar.innerHTML = '\u26A0\uFE0F Rollback non riuscito. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
      var _xr2 = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
      if (_xr2) { _xr2.disabled = false; _xr2.style.opacity = '1'; _xr2.innerHTML = '\u2715'; }
      statoServizi();
    }
  }).catch(function() {
    if (bar) bar.innerHTML = '\u26A0\uFE0F Errore di rete. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
    var _xr3 = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
    if (_xr3) { _xr3.disabled = false; _xr3.style.opacity = '1'; _xr3.innerHTML = '\u2715'; }
  });
}

/* ═══════════ AINABOX (Colpo 6) ═══════════ */
function statoAinabox() {
  apiFetch('/api/ainabox/stato').then(function(r){return r.json();}).then(function(d) {
    var ver  = document.getElementById('ainabox-ver');
    var stat = document.getElementById('ainabox-stat');
    var btn  = document.getElementById('btn-ainabox');
    if (!ver || !stat || !btn) return;
    if (!d.ok) {
      stat.innerHTML = '<span style="color:#ff9999">' + (d.errore||'Non raggiungibile.') + '</span>';
      btn.disabled = true;
      return;
    }
    ver.textContent = d.versione || '—';
    if (d.disponibile && d.disponibile !== d.versione) {
      stat.innerHTML = ' &rarr; <span class="agg-serv-nuova">' + d.disponibile + '</span>';
      btn.disabled = false;
      btn.textContent = t('agg.aggiorna');
    } else {
      stat.innerHTML = ' <span class="agg-serv-ok">&#10003;</span>';
      btn.disabled = true;
    }
    var disc = document.getElementById('ainabox-disclaimer');
    if (d.offline) { if(disc) disc.style.display='block'; }
    else { if(disc) disc.style.display='none'; }
  }).catch(function() {
    var stat = document.getElementById('ainabox-stat');
    var btn  = document.getElementById('btn-ainabox');
    if (stat) stat.innerHTML = '<span style="color:#888">Non raggiungibile.</span>';
    if (btn) btn.disabled = true;
  });
}
function aggiornaAinabox() {
  var btn   = document.getElementById('btn-ainabox');
  var barra = document.getElementById('ainabox-barra');
  var fill  = document.getElementById('ainabox-fill');
  var stat  = document.getElementById('ainabox-stat');
  if (btn)  { btn.disabled = true; btn.textContent = '\u23F3 IN CORSO\u2026'; }
  if (stat) stat.innerHTML = '<span class="agg-serv-data">\u23F3 Aggiornamento in corso\u2026</span>';
  if (barra) barra.style.display = 'block';
  if (fill) fill.style.width = '5%';
  var _x = document.querySelector('.agg-chiudi[onclick*="chiudiAggiornamenti"]');
  if (_x) { _x.disabled = true; _x.style.opacity = '0.4'; _x.innerHTML = '\u26D4'; }
  var bar = document.getElementById('barra-i-text');
  if (bar) bar.innerHTML = '\u23F3 Aggiornamento AINABOX in corso\u2026';
  var _iv = setInterval(function(){
    var w = parseInt((fill && fill.style.width) || '5', 10);
    if (w < 90) { w += Math.floor(Math.random()*8)+2; if(w>90)w=90; if(fill) fill.style.width = w+'%'; }
  }, 800);
  apiFetch('/api/ainabox/aggiorna', {method:'POST', timeout:600000}).then(function(r){return r.json();}).then(function(d) {
    clearInterval(_iv);
    if (_x) { _x.disabled = false; _x.style.opacity = '1'; _x.innerHTML = '\u2715'; }
    if (bar) bar.innerHTML = d.ok
      ? '\u2705 AINABOX aggiornata a ' + (d.versione || d.nuova || '') + '.'
      : '\u26A0\uFE0F Aggiornamento non riuscito. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
    if (d.ok && fill) fill.style.width = '100%';
    setTimeout(function(){ if(barra) barra.style.display='none'; }, d.ok ? 800 : 200);
    statoAinabox();
  }).catch(function() {
    clearInterval(_iv);
    if (_x) { _x.disabled = false; _x.style.opacity = '1'; _x.innerHTML = '\u2715'; }
    if (bar) bar.innerHTML = '\u26A0\uFE0F Errore di rete. <a href="javascript:void(0)" onclick="vaiLog()" style="color:#FF9999;text-decoration:underline;cursor:pointer">Controlla i LOG</a>';
    if (barra) barra.style.display='none';
    if (btn) { btn.disabled = false; btn.textContent = t('agg.aggiorna'); }
    if (stat) stat.innerHTML = '<span style="color:#ff9999">\u26A0\uFE0F Errore di rete.</span>';
  });
}
