# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina

"""PACCHETTI v4 — 4 anelli + pianerottolo + pulizia"""
import os, re, glob, subprocess
import requests, json, time
from fastapi import HTTPException
SCR = {
 "scout":("svc_updater",
  ["/usr/bin/python3",
   "/mnt/ainabox/updater_zone/svc_scout.py"]),
 "updater":("svc_updater",
  ["/usr/bin/bash",
   "/mnt/ainabox/updater_zone/svc_updater.sh"]),
 "manutentore":("svc_manutentore",
  ["/usr/bin/bash",
   "/usr/local/sbin/svc_manutentore.sh"]),
}
LOG_F="/mnt/ainabox/vetrina_zone/ainabox.log"
def _log(msg):
 try:
  with open(LOG_F,"a") as f:
   f.write("[" + time.strftime("%H:%M:%S") + "] [Aggiorna Modelli] " + msg + "\n")
 except Exception:
  pass
NOME_OK=re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$")
_LOCK="/tmp/vetrina.lock"
TIMEOUT={"scout":60,"updater":3600,
 "manutentore":600,"ingest":1800}
PIANO="/mnt/ainabox/modelli/ollama_modelli/"

def _run(utente,cmd,timeout):
 try:
  fd=os.open(_LOCK,os.O_CREAT|os.O_EXCL|os.O_WRONLY)
  os.write(fd,str(os.getpid()).encode())
 except FileExistsError:
  raise HTTPException(409,"Operazione in corso.")
 try:
  p=subprocess.run(["sudo","-n","-u",utente,*cmd],
   capture_output=True,text=True,timeout=timeout)
  return {"ok":p.returncode==0,
   "exit":p.returncode,
   "stdout":p.stdout[-4000:],
   "stderr":p.stderr[-4000:]}
 except subprocess.TimeoutExpired:
  return {"ok":False,"errore":
   f"timeout dopo {timeout}s"}
 finally:
  try:os.unlink(_LOCK)
  except OSError:pass

def registra(app):

 @app.get("/api/pianerottolo")
 def piano():
  files=sorted(
   glob.glob(PIANO+"*.gguf"),reverse=True)
  out=[]
  for f in files:
   out.append({
    "file":os.path.basename(f),
    "size_gb":round(
     os.path.getsize(f)/1e9,2)})
  return out


 def _hf_tree(repo):
  url = "https://huggingface.co/api/models/" + repo + "/tree/main"
  r = requests.get(url, timeout=15)
  r.raise_for_status()
  out = {}
  for f in r.json():
   p = f.get("path","")
   if "lfs" in f: out[p] = (f["lfs"]["oid"], f.get("size",0))
  return out

 def _scrivi_manifesto(m):
  dest = "/mnt/ainabox/updater_zone/manifesti/" + m["id"] + ".json"
  with open(dest,"w") as f: json.dump(m,f)
  os.chmod(dest,0o644)

 @app.get("/api/modelli/chat")
 def modelli_chat(q: str = ""):
  u = "https://huggingface.co/api/models?filter=gguf&sort=downloads&limit=20"
  if q: u += "&search=" + requests.utils.quote(q)
  try:
   data = requests.get(u, timeout=8).json()
  except Exception:
   raise HTTPException(502,"Catalogo non raggiungibile.")
  try:
   _tags=requests.get("http://127.0.0.1:11434/api/tags",timeout=2).json().get("models",[])
   _inst={m["name"].split(":")[0].lower().replace("-","").replace("_","").replace(".","") for m in _tags}
  except Exception:
   try:
    _run("svc_ollama", ["/mnt/ainabox/engine_zone/runtime/bin/ollama_accendi.sh"], 30)
    import time
    _tags=[]
    for _i in range(12):
        try:
            _tags=requests.get("http://127.0.0.1:11434/api/tags",timeout=3).json().get("models",[])
            break
        except Exception:
            time.sleep(3)
    _inst={m["name"].split(":")[0].lower().replace("-","").replace("_","").replace(".","") for m in _tags}
   except Exception:
    _inst=set()
  def _gi(nm):
   n=nm.lower().split("/")[-1].replace("-","").replace("_","").replace(".","").replace("gguf","")
   return any(i and (i in n or n in i) for i in _inst)
  out = [{"nome":m["id"],"downloads":m.get("downloads",0),"gated":m.get("gated") or None,"installed":_gi(m["id"])} for m in data if not q or q.lower() in m["id"].lower()]
  return {"ok":True,"famiglia":"chat","q":q,"count":len(out),"modelli":out}

 @app.get("/api/modelli/chat/tree")
 def chat_tree(repo: str):
  try: tree = _hf_tree(repo)
  except Exception: raise HTTPException(502,"Repo non raggiungibile.")
  out = [{"file":p,"size_gb":round(s/1e9,2)} for p,(_,s) in tree.items() if p.endswith(".gguf")]
  out.sort(key=lambda x:x["size_gb"])
  return {"ok":True,"repo":repo,"count":len(out),"file":out}

 @app.get("/api/modelli/grafica")
 def modelli_grafica(q: str = ""):
  url = "https://raw.githubusercontent.com/Comfy-Org/ComfyUI-Manager/main/model-list.json"
  try:
   data = requests.get(url, timeout=15).json()["models"]
  except Exception:
   raise HTTPException(502,"Catalogo non raggiungibile.")
  base = "/mnt/ainabox/comfy_zone/ComfyUI/models"
  out = []
  for m in data:
   nm = m.get("name","")
   if q and q.lower() not in nm.lower() and q.lower() not in m.get("type","").lower(): continue
   sp,fn = m.get("save_path",""), m.get("filename","")
   out.append({"nome":nm,"type":m.get("type",""),"save_path":sp,"filename":fn,"reference":m.get("reference",""),"installed":os.path.isfile(os.path.join(base,sp,fn)) if (sp and fn) else False})
  out.sort(key=lambda x:(not x["installed"],x["nome"].lower()))
  return {"ok":True,"famiglia":"grafica","q":q,"count":len(out),"modelli":out[:50]}

 @app.post("/api/modelli/scarica")
 def scarica(famiglia: str, repo: str, file: str, folder: str = ""):
  try:
   if famiglia not in ("chat","grafica"): raise HTTPException(400,"famiglia: chat o grafica")
   try: tree = _hf_tree(repo)
   except Exception: raise HTTPException(502,"Repo non raggiungibile.")
   if file not in tree: raise HTTPException(404,"File non trovato nel repo.")
   sha,size = tree[file]
   m = {"id":"s_"+str(int(time.time())),"tipo":"modello","destinazione":"ollama_zone" if famiglia=="chat" else "comfy_zone","sottocartella":folder,"file":[{"file":file,"url":"https://huggingface.co/"+repo+"/resolve/main/"+file,"sha256":sha,"size":size}],"generato":time.strftime("%Y-%m-%dT%H:%M:%S"),"fonte":"huggingface"}
   try: _scrivi_manifesto(m)
   except Exception as e: return {"ok":False,"fase":"manifesto","errore":str(e)[:300]}
   r4 = _run("svc_updater",["/usr/bin/bash","/mnt/ainabox/updater_zone/svc_updater.sh"],3600)
   _log(f"r4 UPDATER: ok={r4['ok']} exit={r4.get('exit')} err={(r4.get('stderr') or '')[-200:]} out={(r4.get('stdout') or '')[-300:]}")
   if not r4["ok"]:
    ggufs=glob.glob("/mnt/ainabox/updater_zone/inbox/*.gguf")
    if ggufs:
     _log("r4: exit="+str(r4.get("exit"))+" ma "+str(len(ggufs))+" gguf in inbox, procedo")
    else:
     rc=r4.get("exit")
     if rc is not None and rc<0: return {"ok":False,"fase":"scarica","errore":"killed by signal "+str(-rc)}
     elif rc is not None and rc>0:
      tail=(r4.get("stderr") or "").strip()[-200:]
      return {"ok":False,"fase":"scarica","errore":"exit "+str(rc)+((": "+tail) if tail else "")}
     else: return {"ok":False,"fase":"scarica","errore":"errore sconosciuto"}
   r5 = _run("svc_manutentore",["/usr/bin/bash","/usr/local/sbin/svc_manutentore.sh"],600)
   _log(f"r5 MANUTENTORE: ok={r5['ok']} exit={r5.get('exit')} err={(r5.get('stderr') or '')[-200:]}")
   if not r5["ok"]: return {"ok":False,"fase":"installa","errore":(r5.get("stderr") or "")[:500]}
   if famiglia=="chat":
    r6 = _run("svc_ollama",["/mnt/ainabox/engine_zone/runtime/bin/vetrina_ingest.sh",file.replace(".gguf","").lower(),file],1800)
    _log(f"r6 INGEST: ok={r6['ok']} exit={r6.get('exit')} err={(r6.get('stderr') or '')[-200:]}")
    if not r6["ok"]: return {"ok":False,"fase":"ingest","errore":(r6.get("stderr") or "")[:500]}
   return {"ok":True,"fase":"completo","modello":file,"size_gb":round(size/1e9,2)}
  except HTTPException: raise
  except Exception as e: return {"ok":False,"errore":str(e)[:300]}
 @app.get("/api/ollama/up")
 def ollama_up():
  try:
   r = requests.get("http://127.0.0.1:11434/api/tags", timeout=2)
   return {"up": True, "models": len(r.json().get("models", []))}
  except Exception:
   return {"up": False}
 @app.post("/api/ollama/accendi")
 def ollama_accendi():
  t0 = time.time()
  r = _run("svc_ollama", ["/mnt/ainabox/engine_zone/runtime/bin/ollama_accendi.sh"], 300)
  if not r["ok"]:
   _log("Ollama ACCENDI: fallito " + (r.get("stderr") or "")[:200])
   return {"ok": False, "errore": (r.get("stderr") or r.get("stdout") or "")[:300]}
  for _ in range(15):
   time.sleep(2)
   try:
    requests.get("http://127.0.0.1:11434/api/tags", timeout=2)
    _t = round(time.time() - t0)
    _log("Ollama ACCENDI: UP in " + str(_t) + "s")
    return {"ok": True, "tempo": str(_t) + "s"}
   except Exception:
    pass
  _log("Ollama ACCENDI: timeout 30s")
  return {"ok": False, "errore": "Ollama non risponde dopo 30s."}
 @app.post("/api/ollama/spegni")
 def ollama_spegni():
  r = _run("svc_ollama", ["/mnt/ainabox/engine_zone/runtime/bin/ollama_spegni.sh"], 30)
  if not r["ok"]:
   _log("Ollama SPEGNI: fallito " + (r.get("stderr") or "")[:200])
   return {"ok": False, "errore": (r.get("stderr") or "")[:300]}
  _log("Ollama SPEGNI: OK")
  return {"ok": True}

 @app.get("/api/ollama/installati")
 def ollama_installati():
  try:
   r = requests.get("http://127.0.0.1:11434/api/tags", timeout=2)
   models = r.json().get("models", [])
  except Exception:
   return {"ok": True, "up": False, "count": 0, "modelli": []}
  out = []
  for m in models:
   det = m.get("details") or {}
   out.append({"name": m.get("name", ""), "size": m.get("size", 0), "params": det.get("parameter_size", ""), "quant": det.get("quantization_level", "")})
  _log("Ollama INSTALLATI: " + str(len(out)) + " modelli")
  return {"ok": True, "up": True, "count": len(out), "modelli": out}

 @app.post("/api/ollama/rimuovi")
 def ollama_rimuovi(nome: str):
  if not nome or not all(c.isalnum() or c in '_.:-' for c in nome) or not nome[0].isalnum():
   return {"ok": False, "errore": "nome non valido."}
  r = _run("svc_ollama", ["/mnt/ainabox/engine_zone/runtime/bin/ollama_rimuovi.sh", nome], 60)
  if not r["ok"]:
   _log("Ollama RIMUOVI: fallito " + (r.get("stderr") or r.get("stdout") or "")[:200])
   return {"ok": False, "errore": (r.get("stderr") or r.get("stdout") or "")[:300]}
  _log("Ollama RIMUOVI: " + nome + " rimosso")
  return {"ok": True}
 # ── AGGIORNA SERVIZI (Colpo 5a) ──
 VERZ="/mnt/ainabox/engine_zone/VERSIONI.json"
 SVC_MAP={"ollama":{"u":"svc_ollama","repo":"docker.io/ollama/ollama","porta":"11434","cont":"ollama"},
 "owu":{"u":"svc_owu","repo":"ghcr.io/open-webui/open-webui","porta":"3000","cont":"open-webui"}}
 AGG="/mnt/ainabox/engine_zone/runtime/bin/agg_servizi.sh"
 RUNC="/mnt/ainabox/engine_zone/runtime/bin/runc"
 def _verz_leggi():
  with open(VERZ) as f: return json.load(f)
 def _verz_scrivi(d):
  with open(VERZ,"w") as f: json.dump(d,f,indent=2)
 def _host_ip():
  try:
   r=subprocess.run(["hostname","-I"],capture_output=True,text=True,timeout=5)
   return r.stdout.strip().split()[0]
  except Exception: return "127.0.0.1"
 def _verify(porta,timeout=30):
  t0=time.time()
  while time.time()-t0<timeout:
   try:
    requests.get("http://127.0.0.1:"+porta,timeout=3)
    return True
   except Exception:
    time.sleep(2)
  return False
 def _stop_rm(motore):
  s=SVC_MAP[motore]
  _run(s["u"],[AGG,"stop",s["cont"]],30)
  _run(s["u"],[AGG,"rm","-f",s["cont"]],30)
 def _run_servizio(motore,tag):
  s=SVC_MAP[motore]
  if motore=="ollama":
   cmd=[AGG,"run","-d","--name","ollama","--runtime",RUNC,
    "-p","11434:11434","--gpus","all","-e","OLLAMA_HOST=0.0.0.0",
    "-v","/mnt/ainabox/ollama_zone:/root/.ollama",
    "-v","/mnt/ainabox/modelli/ollama_modelli:/opt/ingest:ro",
    s["repo"]+":"+tag,"serve"]
  else:
   hip=_host_ip()
   cmd=[AGG,"run","-d","--pull","never","--name","open-webui","--runtime",RUNC,
    "-p","127.0.0.1:3000:8080",
    "-v","/mnt/ainabox/owu_zone:/app/backend/data",
    "-e","OLLAMA_BASE_URL=http://"+hip+":11434",
    "-e","SPEACHES_URL=http://"+hip+":8000/v1",
    "-e","VETRINA_URL=https://"+hip+":8765",
    "-e","HF_HUB_OFFLINE=1","-e","TRANSFORMERS_OFFLINE=1",
    s["repo"]+":"+tag]
  return _run(s["u"],cmd,60)
 def _tag_disponibile(motore):
  if motore=="ollama":
   try:
    data=requests.get("https://hub.docker.com/v2/repositories/ollama/ollama/tags?page_size=50",timeout=10).json()
    versions=[]
    for t in data.get("results",[]):
     if re.match(r"^\d+\.\d+\.\d+$",t["name"]): versions.append(t["name"])
    if versions:
     versions.sort(key=lambda x:[int(p) for p in x.split(".")])
     return versions[-1]
    return None
   except Exception: return None
  else:
   try:
    data=requests.get("https://api.github.com/repos/open-webui/open-webui/releases/latest",timeout=10).json()
    return data.get("tag_name")
   except Exception: return None
 def _check_rete():
  try:
   return open("/mnt/ainabox/network_zone/MODE_NET").read().strip() != "offline"
  except Exception:
   return True
 @app.get("/api/servizi/stato")
 def servizi_stato():
  try:
   v=_verz_leggi()
  except Exception:
   return {"ok":False,"errore":"Registro versioni non leggibile."}
  out=[]
  for motore in ("ollama","owu"):
   m=v.get(motore,{})
   out.append({"motore":motore,"attuale":m.get("attuale","?"),
    "disponibile":_tag_disponibile(motore),
    "data":m.get("data","?"),
    "precedente":m.get("precedente")})
  return {"ok":True,"motori":out}
 @app.post("/api/servizi/aggiorna")
 def servizi_aggiorna(motore: str):
  if motore not in ("ollama","owu"):
   return {"ok":False,"errore":"Motore sconosciuto."}
  if not _check_rete():
   return {"ok":False,"errore":"Rete offline. Non posso aggiornare."}
  v=_verz_leggi()
  attuale=v.get(motore,{}).get("attuale","?")
  disp=_tag_disponibile(motore)
  if not disp:
   return {"ok":False,"errore":"Registro remoto non raggiungibile."}
  if disp==attuale:
   return {"ok":True,"messaggio":"Già aggiornato."}
  _log("AGGIORNA "+motore+": "+attuale+" → "+disp)
  s=SVC_MAP[motore]
  r=_run(s["u"],[AGG,"pull",s["repo"]+":"+disp],300)
  if not r["ok"]:
   _log("AGGIORNA "+motore+": PULL FALLITO exit="+str(r.get("exit")))
   return {"ok":False,"fase":"pull","errore":"Download non riuscito."}
  _stop_rm(motore)
  r=_run_servizio(motore,disp)
  if not r["ok"]:
   _log("AGGIORNA "+motore+": RUN FALLITO")
   _stop_rm(motore)
   prec=v.get(motore,{}).get("precedente")
   if prec: _run_servizio(motore,prec)
   return {"ok":False,"fase":"run","errore":"Avvio non riuscito."}
  if not _verify(s["porta"]):
   _log("AGGIORNA "+motore+": VERIFY FALLITO")
   _stop_rm(motore)
   prec=v.get(motore,{}).get("precedente")
   if prec: _run_servizio(motore,prec)
   return {"ok":False,"fase":"verify","errore":"Servizio non risponde."}
  v[motore]["precedente"]=attuale
  v[motore]["attuale"]=disp
  v[motore]["data"]=time.strftime("%Y-%m-%d")
  _verz_scrivi(v)
  _log("AGGIORNA "+motore+": OK "+disp)
  return {"ok":True,"motore":motore,"nuova":disp,"precedente":attuale}
 @app.post("/api/servizi/rollback")
 def servizi_rollback(motore: str):
  if motore not in ("ollama","owu"):
   return {"ok":False,"errore":"Motore sconosciuto."}
  v=_verz_leggi()
  prec=v.get(motore,{}).get("precedente")
  if not prec:
   return {"ok":False,"errore":"Nessun precedente disponibile."}
  _log("ROLLBACK "+motore+" → "+prec)
  s=SVC_MAP[motore]
  _stop_rm(motore)
  r=_run_servizio(motore,prec)
  if not r["ok"]:
   _log("ROLLBACK "+motore+": RUN FALLITO")
   return {"ok":False,"errore":"Rollback fallito."}
  if not _verify(s["porta"]):
   _log("ROLLBACK "+motore+": VERIFY FALLITO")
   return {"ok":False,"errore":"Servizio non risponde."}
  v[motore]["precedente"]=v[motore]["attuale"]
  v[motore]["attuale"]=prec
  v[motore]["data"]=time.strftime("%Y-%m-%d")
  _verz_scrivi(v)
  _log("ROLLBACK "+motore+": OK → "+prec)
  return {"ok":True,"motore":motore,"versione":prec}
