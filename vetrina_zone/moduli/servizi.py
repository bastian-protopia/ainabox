# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina

"""SERVIZI v1 — 5 Switch + Spegni AINABOX
Pattern: stesso di chat.py (lock + subprocess + registra).
Corridoio: /etc/sudoers.d/servizi (NOPASSWD, 2 comandi stretti).
"""
import os, subprocess, socket, time
import urllib.request
import subprocess
from fastapi import Request, HTTPException

import fcntl, time
import asyncio
from fastapi.responses import StreamingResponse
from fastapi import Request

_sse_queues = set()

def sse_broadcast(msg=None, color="", msg_key=None, msg_args=None):
    import json as _json
    data = _json.dumps({"msg": msg, "color": color, "msg_key": msg_key, "msg_args": msg_args})
    for q in _sse_queues:
        q.put_nowait(data)

_LOCK_SERIALE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".lock_seriale")
_LOCK_VOCALE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".lock_vocale")

def _lock(kind="seriale"):
    fd = os.open(_LOCK_SERIALE if kind=="seriale" else _LOCK_VOCALE, os.O_CREAT | os.O_WRONLY)
    deadline = time.time() + 30
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except (IOError, OSError):
            if time.time() >= deadline:
                os.close(fd)
                fd = None
                raise HTTPException(409, "⏳ Transizione in corso. Riprova tra un momento.")
            time.sleep(1)

def _unlock(fd):
    if fd is not None:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
        except OSError:
            pass
        fd = None

def _sudo(cmd, timeout=30):
    p = subprocess.run(
        ["sudo", "-n"] + cmd,
        capture_output=True, text=True, timeout=timeout)
    return {"ok": p.returncode == 0,
            "exit": p.returncode,
            "stdout": p.stdout[-4000:],
            "stderr": p.stderr[-4000:]}

def _silo_up(silo, timeout=15):
    """Read-only: stato silo. Ritorna: 'up' | 'ready' | 'daemon_down'
    Corridoio: /etc/sudoers.d/stato_silo (NOPASSWD, read-only)."""
    uid = "svc_" + silo
    try:
        p = subprocess.run(
            ["sudo", "-n", "-u", uid,
             "bash", "/usr/local/bin/stato_silo.sh", silo],
            capture_output=True, text=True, timeout=timeout)
        if p.returncode == 2 or "DAEMON_DOWN" in p.stdout:
            return "daemon_down"
        if "Up" in p.stdout:
            return "up"
        return "ready"
    except Exception:
        return "daemon_down"

def _stato():
    ollama_st = _silo_up("ollama")
    owu_st = _silo_up("owu")
    attivo = ("testuale" if (ollama_st == "up" and owu_st == "up") else
        "assistente" if (_port_up("127.0.0.1", 9119) and ollama_st == "up") else
        "transizione" if (ollama_st == "up" or owu_st == "up") else None)
    return {
        "attivo": attivo,
        "leds": {
            "ollama": ollama_st,
            "owu": owu_st,
            "comfy": "up" if _port_up("127.0.0.1", 8188) else "daemon_down",
            "speaches": "up" if _port_up("127.0.0.1", 8000) else "daemon_down",
            "hermes": "up" if _port_up("127.0.0.1", 9119) else "daemon_down",
        }
    }

def registra(app):
    @app.get("/api/events")
    async def sse_events(request: Request):
        q = asyncio.Queue()
        _sse_queues.add(q)
        async def gen():
            try:
                while True:
                    try:
                        data = await asyncio.wait_for(q.get(), timeout=15)
                        yield f"data: {data}\n\n"
                    except asyncio.TimeoutError:
                        yield ": keepalive\n\n"
            finally:
                _sse_queues.discard(q)
        return StreamingResponse(gen(), media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


    @app.get("/api/servizio/stato")
    def servizio_stato():
        return _stato()

    def _owu_ready(timeout=5):
        """True se OWU risponde HTTP 2xx/3xx sulla 3000."""
        try:
            import requests
            r = requests.get("http://127.0.0.1:3000", timeout=timeout)
            return r.status_code < 400
        except Exception:
            return False

    @app.post("/api/servizio/{nome}")
    async def servizio_avvia(nome: str, request: Request):
        try:
            _b = await request.json()
            _lang = _b.get("lang", "it") if isinstance(_b, dict) else "it"
        except Exception:
            _lang = "it"
        validi = {"testuale", "grafica", "vocale", "ascolto",
                  "testuale_img", "vocale_img", "assistente"}
        if nome not in validi:
            raise HTTPException(
                400, f"Servizio sconosciuto: {nome}")
        # GIÀ ATTIVO: pre-lock, ~1ms
        if nome == "testuale" and _port_up("127.0.0.1", 11434) and _port_up("127.0.0.1", 3000):
            from . import naso
            _tags = naso._ollama_tags()
            _vr = _vram()
            _rm = _ram()
            _vram_lib = _vr["total_gb"] - _vr["used_gb"]
            _ram_lib = _rm["total_gb"] - _rm["used_gb"]
            classif = naso._classifica(_tags, _vram_lib, _ram_lib)
            resp = {"ok": True, "gia_attivo": True, "modelli": classif}
            non_ok = [m for m in classif if m["grado"] != "ok"]
            if non_ok:
                resp["avvertenze"] = non_ok
            return resp
        if nome == "grafica" and _port_up("127.0.0.1", 8188) and not _port_up("127.0.0.1", 3000):
            from . import naso
            _vr = _vram()
            _rm = _ram()
            _vl = _vr["total_gb"] - _vr["used_gb"]
            _rl = _rm["total_gb"] - _rm["used_gb"]
            _sc = naso._silo_comfy()
            classif = naso._classifica(_sc, _vl, _rl)
            resp = {"ok": True, "gia_attivo": True, "modelli": classif}
            non_ok = [m for m in classif if m["grado"] != "ok"]
            if non_ok:
                resp["avvertenze"] = non_ok
            return resp
        if nome in ("ascolto", "vocale") and _port_up("127.0.0.1", 8000):
            if nome == "vocale":
                import subprocess
                subprocess.run(["sudo", "bash", "/usr/local/bin/avvia_servizio.sh", "vocale", _lang], timeout=30, capture_output=True)
            return {"ok": True, "gia_attivo": True}
        if nome == "assistente" and _port_up("127.0.0.1", 9119):
            return {"ok": True, "gia_attivo": True}

        fd = _lock("vocale" if nome in ("vocale","ascolto") else "seriale")
        try:
            from . import naso
            if nome == "testuale":
                return naso.accendi_chat(_vram, _ram, _sudo, _owu_ready, _port_up, sse_broadcast)
            elif nome == "grafica":
                return naso.accendi_grafica(_vram, _ram, _sudo, _port_up, sse_broadcast)
            elif nome == "ascolto":
                return naso.accendi_ascolto(_sudo, _port_up, sse_broadcast)
            elif nome == "vocale":
                return naso.accendi_vocale(_vram, _sudo, _port_up, sse_broadcast, lang=_lang)
            elif nome == "assistente":
                return naso.accendi_assistente(_sudo, _port_up, sse_broadcast)
            else:
                return {"ok": False, "errore": "Non ancora disponibile."}
        finally:
            _unlock(fd)

    @app.post("/api/servizio/{nome}/off")
    def servizio_spegni(nome: str):
        validi = {"vocale", "ascolto"}
        if nome not in validi:
            raise HTTPException(400, f"Spegnimento non supportato per: {nome}")
        from . import naso
        if nome == "vocale":
            r = naso.rilascia_vocale(); _sudo(["/usr/bin/bash", "/usr/local/bin/avvia_servizio.sh", "spegni_vocale"], 10); return r
        elif nome == "ascolto":
            import subprocess
            try:
                subprocess.run(
                    ["pkill", "-u", "svc_speaches", "-f", "uvicorn speaches.main"],
                    timeout=5
                )
            except Exception:
                pass
            return {"ok": True, "msg": "Ascolto spento."}
    @app.post("/api/spegni")
    def spegni():
        fd = _lock()
        try:
            r = _sudo(
                ["/usr/bin/bash",
                 "/usr/local/bin/chiudi_tutto"], 60)
            return r
        except subprocess.TimeoutExpired:
            return {"ok": False,
                    "errore": "timeout dopo 60s"}
        finally:
            _unlock(fd)
    @app.get("/api/cockpit")
    def stato_ricco():
        """FASE A — stato ricco (porte + hardware)."""
        return _health()

    @app.get("/api/log")
    def get_log():
        LOG_PATH = "/mnt/ainabox/vetrina_zone/ainabox.log"
        if not os.path.exists(LOG_PATH):
            return {"lines": []}
        try:
            with open(LOG_PATH, "r", errors="replace") as f:
                lines = f.readlines()[-300:]
            return {"lines": [l.rstrip(chr(10)) for l in lines]}
        except Exception:
            return {"lines": []}


# ═══════ FASE A — SENSORI (18/9) ═══════

def _port_up(host, port, timeout=2):
    """1 TCP handshake. True se la porta risponde."""
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except (OSError, socket.timeout):
        return False

def _owu_http(timeout=3):
    """HTTP 200 su 127.0.0.1:3000. True se OWU risponde davvero."""
    try:
        import urllib.request
        r = urllib.request.urlopen("http://127.0.0.1:3000", timeout=timeout)
        return r.status < 400
    except Exception:
        return False

def _vram():
    try:
        p = subprocess.run(
            ["nvidia-smi","--query-gpu=memory.used,memory.free",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5)
        lines = [l for l in p.stdout.strip().split("\n") if l.strip()]
        if not lines:
            return {"used_gb":0, "total_gb":0}
        total = sum(int(l.split(",")[0].strip())+int(l.split(",")[1].strip())
                    for l in lines)
        used = sum(int(l.split(",")[0].strip()) for l in lines)
        return {"used_gb": round(used/1024,1), "total_gb": round(total/1024,1)}
    except Exception:
        return {"used_gb":0, "total_gb":0}

def _ram():
    try:
        info = {}
        with open("/proc/meminfo") as f:
            for line in f:
                k, v = line.split(":", 1)
                info[k.strip()] = int(v.strip().split()[0])
        total = info.get("MemTotal", 0)
        avail = info.get("MemAvailable", 0)
        return {"used_gb": round((total-avail)/1024/1024, 1),
                "total_gb": round(total/1024/1024, 1)}
    except Exception:
        return {"used_gb":0, "total_gb":0}

_proc_stat_prev=None

def _cpu():
    global _proc_stat_prev
    try:
        with open("/proc/stat") as fh:
            line=fh.readline()
        parts=line.split()
        vals=[int(x) for x in parts[1:8]]
        total=sum(vals)
        idle=vals[3]+vals[4]
        if _proc_stat_prev is not None:
            pt,pi=_proc_stat_prev
            dt=total-pt; di=idle-pi
            pct=max(0,(dt-di)/dt*100) if dt>0 else 0
        else:
            pct=0
        _proc_stat_prev=(total,idle)
        return {"percent":round(pct),"cores":os.cpu_count() or 1}
    except Exception:
        return {"percent":0,"cores":os.cpu_count() or 1}

def _ssd():
    try:
        p = subprocess.run(["df","--output=size,avail","/mnt/ainabox"],
                          capture_output=True, text=True, timeout=5)
        parts = p.stdout.strip().split("\n")[1].split()
        size, avail = int(parts[0]), int(parts[1])
        return {"used_gb": round((size-avail)/1024/1024, 1),
                "total_gb": round(size/1024/1024, 1)}
    except Exception:
        return {"used_gb":0, "total_gb":0}

def _health():
    return {
        "attivo": ("testuale" if (_port_up("127.0.0.1",11434) and _port_up("127.0.0.1",3000))
                   else "assistente" if (_port_up("127.0.0.1",9119) and _port_up("127.0.0.1",11434))
                   else "grafica" if _port_up("127.0.0.1",8188) else None),
        "servizi": {
            "ollama":   _port_up("127.0.0.1", 11434),
            "owu":      _port_up("127.0.0.1", 3000),
            "comfy":    _port_up("127.0.0.1", 8188),
            "speaches": _port_up("127.0.0.1", 8000),
        "owu_http": _owu_http(3),
            "hermes":   _port_up("127.0.0.1", 9119),
        },
        "hardware": {"vram": _vram(), "ram": _ram(), "ssd": _ssd(), "cpu": _cpu()},
        "modello": None,
        "transizione": False,
    }

