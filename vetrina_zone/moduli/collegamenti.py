# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""Toggle Connessioni — base GPL.
Pattern: registra(app), come tutti gli altri moduli.
Minimo privilegio: scrive solo MODE_NET. Nessun sudo. Nessun nft.
scout/updater leggono MODE_NET e si auto-bloccano se offline.
"""
from fastapi import Request
from fastapi.responses import JSONResponse

MODE_NET_FILE = "/mnt/ainabox/network_zone/MODE_NET"


def _leggi_mode():
    try:
        return open(MODE_NET_FILE).read().strip()
    except Exception:
        return "offline"


def _scrivi_mode(m: str):
    with open(MODE_NET_FILE, "w") as f:
        f.write(m)


def registra(app):
    @app.get("/api/collegamenti/stato")
    async def stato():
        m = _leggi_mode()
        return {"mode": m, "internet": m == "casa"}

    @app.post("/api/collegamenti/toggle")
    async def toggle(request: Request):
        body = await request.json()
        nuovo = body.get("mode", "offline")
        if nuovo not in ("offline", "casa"):
            return JSONResponse(status_code=400, content={"errore": "mode non valido"})
        _scrivi_mode(nuovo)
        return {"ok": True, "mode": nuovo, "internet": nuovo == "casa"}
