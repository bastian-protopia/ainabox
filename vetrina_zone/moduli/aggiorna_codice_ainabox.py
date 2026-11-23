# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""AGGIORNA AINABOX v1 — /api/ainabox/stato + /api/ainabox/aggiorna + /api/ainabox/rollback
Regola: solo root tocca internet (git pull). svc_vetrina chiede a root via sudo.
Flusso: Stato → Aggiorna (snapshot + pull + restart + verify) → Rollback auto se fail
(Per i modelli → pacchetti.py. Per i servizi → servizi.py.)
"""
import subprocess, time
from fastapi import HTTPException

VER_FILE = "/mnt/ainabox/engine_zone/VERSION_AINABOX"
MODE_NET = "/mnt/ainabox/network_zone/MODE_NET"
LOG = "/mnt/ainabox/vetrina_zone/ainabox.log"
DATA_DIR = "/mnt/ainabox"
WRAP = "/mnt/ainabox/engine_zone/runtime/bin/agg_ainabox.sh"

def _log(msg):
    try:
        with open(LOG, "a") as f:
            f.write("[%s] [Aggiorna AINABOX] %s\n" % (time.strftime("%H:%M:%S"), msg))
    except Exception:
        pass

def _run(cmd, timeout=120):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=DATA_DIR)
    return p

def _sudo(*args, timeout=120):
    return _run(["sudo", "/usr/bin/bash", WRAP] + list(args), timeout=timeout)

def _versione():
    try:
        with open(VER_FILE) as f:
            return f.read().strip()
    except Exception:
        return "sconosciuta"

def _mode_net():
    try:
        with open(MODE_NET) as f:
            return f.read().strip()
    except Exception:
        return "casa"

def _check_rete():
    return _mode_net() != "offline"

def registra(app):
    @app.get("/api/ainabox/stato")
    def stato():
        if not _check_rete():
            return {"ok": False, "errore": "Rete offline."}
        ver = _versione()
        disp = None
        try:
            fetch = _run(["git", "fetch", "--dry-run", "origin", "main"], timeout=10)
            if fetch.returncode == 0:
                remote = _run(["git", "log", "--format=%h", "origin/main", "-1"], timeout=5)
                local = _run(["git", "log", "--format=%h", "-1"], timeout=5)
                if remote.stdout.strip() != local.stdout.strip():
                    disp = "nuova"
        except Exception:
            pass
        return {"ok": True, "versione": ver, "disponibile": disp}

    @app.post("/api/ainabox/aggiorna")
    def aggiorna():
        if not _check_rete():
            return {"ok": False, "errore": "Rete offline."}
        ver = _versione()
        _log("Aggiorna: inizio (v=%s)" % ver)
        ante = _run(["git", "log", "--format=%h", "-1"], timeout=5)
        ante_hash = ante.stdout.strip()
        snap = _sudo("snapshot", ver, timeout=120)
        if snap.returncode != 0:
            _log("Aggiorna: snapshot FALLITO")
            return {"ok": False, "fase": "snapshot", "errore": snap.stderr.strip()[:200]}
        _log("Aggiorna: snapshot OK")
        pull = _sudo("pull", timeout=300)
        if pull.returncode != 0:
            _log("Aggiorna: pull FALLITO → rollback automatico")
            _sudo("reset", ante_hash, timeout=30)
            _sudo("restart", timeout=30)
            _log("Aggiorna: ROLLBACK fatto → v=%s" % ver)
            return {"ok": False, "fase": "pull", "errore": pull.stderr.strip()[:200], "rollback": True}
        _log("Aggiorna: pull OK")
        _sudo("restart", timeout=30)
        vf = _sudo("verify", timeout=15)
        if vf.returncode != 0:
            _log("Aggiorna: verify FALLITO → rollback automatico")
            _sudo("reset", ante_hash, timeout=30)
            _sudo("restart", timeout=30)
            return {"ok": False, "fase": "verify", "errore": "vetrina non risponde", "rollback": True}
        _log("Aggiorna: COMPLETO")
        return {"ok": True, "messaggio": "Aggiornata."}

    @app.post("/api/ainabox/rollback")
    def rollback():
        _log("Rollback: chiamato (manuale)")
        return {"ok": True, "messaggio": "Rollback manuale: usa terminale (git reset --hard + restart)."}
