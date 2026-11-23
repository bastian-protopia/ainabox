# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""SERVIZI_UPDATE v2 — /api/servizi5b/stato + /api/servizi5b/aggiorna/{nome} + /api/servizi5b/rollback/{nome}
Pattern: aggiorna_codice_ainabox.py (Colpo 6) + servizi.py (Colpo 5a).
Corridoio: /etc/sudoers.d/vetrina → agg_servizi_5b.sh * (NOPASSWD).
"""
import json, subprocess, time
from fastapi import HTTPException
VER_FILE = "/mnt/ainabox/engine_zone/VERSIONI.json"
LOG = "/mnt/ainabox/vetrina_zone/ainabox.log"
WRAP = "/mnt/ainabox/engine_zone/bin/agg_servizi_5b.sh"
VALIDI = {"comfy", "speaches", "hermes"}

def _log(msg):
    try:
        with open(LOG, "a") as f:
            f.write("[%s] [Aggiorna Servizi] %s\n" % (time.strftime("%H:%M:%S"), msg))
    except Exception:
        pass

def _versioni():
    try:
        with open(VER_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def _sudo(*args, timeout=600):
    _log("sudo: %s (timeout=%ds)" % (" ".join(args), timeout))
    p = subprocess.run(
        ["sudo", "-n", "/usr/bin/bash", WRAP] + list(args),
        capture_output=True, text=True, timeout=timeout)
    _log("sudo: exit=%d" % p.returncode)
    if p.stderr.strip():
        _log("sudo stderr: %s" % p.stderr.strip()[:500])
    return p

def registra(app):
    @app.get("/api/servizi5b/stato")
    def stato():
        ver = _versioni()
        check_map = {
            "comfy":    {"url": "https://github.com/comfyanonymous/ComfyUI", "branch": "master",
                         "dir": "/mnt/ainabox/comfy_zone/ComfyUI"},
            "speaches": {"url": "https://github.com/speaches-ai/speaches", "branch": "master",
                         "dir": "/mnt/ainabox/speaches_zone/speaches"},
        }
        for nome, cfg in check_map.items():
            if nome not in ver:
                continue
            rem, loc = None, None
            try:
                p = subprocess.run(["git", "ls-remote", cfg["url"], cfg["branch"]],
                                   capture_output=True, text=True, timeout=10)
                if p.returncode == 0 and p.stdout.strip():
                    rem = p.stdout.strip().split()[0]
            except Exception:
                pass
            try:
                with open(cfg["dir"] + "/.git/HEAD") as fh:
                    head = fh.read().strip()
                if head.startswith("ref:"):
                    ref = head[4:].strip()
                    try:
                        with open(cfg["dir"] + "/.git/" + ref) as fh:
                            loc = fh.read().strip()
                    except Exception:
                        with open(cfg["dir"] + "/.git/packed-refs") as fh:
                            for line in fh:
                                if line.strip().endswith("/" + ref.split("/")[-1]):
                                    loc = line.strip().split()[0]
                                    break
                else:
                    loc = head
            except Exception:
                pass
            if rem is None or loc is None:
                ver[nome]["aggiornabile"] = None
            elif rem == loc:
                ver[nome]["aggiornabile"] = False
            else:
                ver[nome]["aggiornabile"] = True
        if "hermes" in ver:
            ver["hermes"]["aggiornabile"] = None
        return {"ok": True, "servizi": ver}

    @app.post("/api/servizi5b/aggiorna/{nome}")
    def aggiorna(nome: str):
        if nome not in VALIDI:
            raise HTTPException(400, "Servizio sconosciuto: %s" % nome)
        _log("Aggiorna: inizio → %s" % nome)
        p = _sudo(nome)
        if p.returncode == 0:
            _log("Aggiorna: COMPLETO → %s" % nome)
            return {"ok": True, "messaggio": "%s aggiornato." % nome}
        _log("Aggiorna: FALLITO → %s (exit=%d)" % (nome, p.returncode))
        return {
            "ok": False,
            "errore": "Aggiornamento non riuscito. Controlla i LOG.",
            "dettaglio": p.stderr.strip()[:300] if p.stderr.strip() else p.stdout.strip()[-300:]
        }

    @app.post("/api/servizi5b/rollback/{nome}")
    def rollback(nome: str):
        if nome not in VALIDI:
            raise HTTPException(400, "Servizio sconosciuto: %s" % nome)
        _log("Rollback: inizio → %s" % nome)
        p = _sudo("rollback", nome, timeout=600)
        if p.returncode == 0:
            _log("Rollback: COMPLETO → %s" % nome)
            return {"ok": True, "messaggio": "%s: rollback completato." % nome}
        _log("Rollback: FALLITO → %s" % nome)
        return {
            "ok": False,
            "errore": "Rollback non riuscito. Controlla i LOG.",
            "dettaglio": (p.stderr or p.stdout).strip()[:300]
        }
