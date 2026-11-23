# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""
config.py — Vetrina: gestione segreti (token HF).
Regola 58: X non sa path, URL, permessi. Vede solo "Token salvato ✅".
Il valore entra via POST body → stdout del micro-script → file 600.
"""
import subprocess
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

SCRIPT = "/mnt/ainabox/updater_zone/imposta_token_hf"

class TokenBody(BaseModel):
    token: str

@router.post("/api/config/hf_token")
def salva_token_hf(body: TokenBody):
    tok = body.token.strip()
    if not tok:
        raise HTTPException(400, "Token vuoto.")
    try:
        r = subprocess.run(
            ["sudo", "-n", "-u", "root", SCRIPT],
            input=tok.encode(),
            capture_output=True,
            timeout=10,
        )
        out = r.stdout.decode().strip()
        err = r.stderr.decode().strip()
        if r.returncode == 0:
            return {"ok": True, "msg_key": "srv.hf_salvato"}
        else:
            raise HTTPException(500, err or "Errore imprevisto.")
    except FileNotFoundError:
        raise HTTPException(500, "Micro-script non trovato.")
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Timeout.")

def registra(app):
    app.include_router(router)
