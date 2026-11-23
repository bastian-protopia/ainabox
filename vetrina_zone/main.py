# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""
VETRINA — centro di comando T7 (v1.1, 4 bottoni)
Regola 13: binding 0.0.0.0 (UFW deny IN + token Bearer). 127.0.0.1 era la v1.
In divenire: ogni sezione = un modulo in /moduli.
"""
from pathlib import Path
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from moduli import sistema, stato, pacchetti, servizi, aggiorna_codice_ainabox, config, backup, collegamenti, naso, servizi_update

app = FastAPI(title="VETRINA T7", version="0.1.1")
from fastapi.staticfiles import StaticFiles
app.mount("/fonts", StaticFiles(directory="/mnt/ainabox/vetrina_zone/fonts"), name="fonts")
app.mount("/i18n", StaticFiles(directory="/mnt/ainabox/vetrina_zone/i18n"), name="i18n")
from fastapi.responses import FileResponse

@app.get("/app.css")
def serve_css():
    return FileResponse("/mnt/ainabox/vetrina_zone/app.css", media_type="text/css")

@app.get("/app.js")
def serve_js():
    return FileResponse("/mnt/ainabox/vetrina_zone/app.js", media_type="application/javascript")

import os
from fastapi import Request
from fastapi.responses import JSONResponse

TOKEN_PATH = "/mnt/ainabox/updater_zone/.secrets/VETRINA_TOKEN"
try:
    TOKEN = open(TOKEN_PATH).read().strip()
except (FileNotFoundError, PermissionError):
    TOKEN = None
PAGINA_PATH = Path(__file__).parent / "pagina.html"

@app.get("/")
def index():
    html = PAGINA_PATH.read_text()
    try:
        _u = open("/mnt/ainabox/vetrina_zone/.current_user").read().strip()
    except (FileNotFoundError, OSError):
        _u = ""
    if _u:
        html = html.replace('<span id="header-user"></span>', '<span id="header-user">' + _u + '</span>')
    else:
        html = html.replace('<span id="header-user"></span>', '<span id="header-user" style="display:none"></span>')
    if TOKEN:
        html = html.replace('</head>',
            '<script>localStorage.setItem("vetrina_token","' + TOKEN + '")</script></head>', 1)
    return HTMLResponse(
        html,
        headers={
            "Cache-Control": "no-store, no-cache, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0",
        },
    )

@app.get("/api/sistema")
def api_sistema():
    return sistema.scan()

@app.get("/api/stato")
def api_stato():
    return stato.rapido()

pacchetti.registra(app)
servizi.registra(app)
aggiorna_codice_ainabox.registra(app)
config.registra(app)
backup.registra(app)
collegamenti.registra(app)
servizi_update.registra(app)

@app.middleware("http")
async def auth_guard(request: Request, call_next):
    path = request.url.path
    if path == "/" or not path.startswith("/api/"):
        return await call_next(request)
    if TOKEN is None:
        return JSONResponse(status_code=503, content={"error": "Token non configurato"})
    auth = request.headers.get("authorization", "")
    if not (auth.startswith("Bearer ") and auth[7:] == TOKEN):
        # Fallback: token come query-param (per EventSource/SSE)
        q_tok = request.query_params.get("token", "")
        if q_tok != TOKEN:
            return JSONResponse(status_code=401, content={"detail": "Unauthorized"})
    return await call_next(request)

@app.get("/api/naso/ps")
async def naso_ps():
    raw = naso._ollama_ps()
    if not raw or isinstance(raw, list):
        return {"ok": True, "models": []}
    models = raw.get("models", [])
    if not models:
        return {"ok": True, "models": []}
    out = []
    for m in models:
        total = m.get("size", 0)
        vram = m.get("size_vram", 0)
        out.append({
            "name": m.get("name", "unknown"),
            "vram_gb": round(vram / (1024**3), 1),
            "ram_gb": round(max(total - vram, 0) / (1024**3), 1)
        })
    return {"ok": True, "models": out}


@app.get("/api/naso/classifica")
async def naso_classifica(vocale: int = 0):
    silo = naso._ollama_tags()
    if not silo:
        return {"ok": True, "stato": "vuoto", "modelli": []}
    hw = servizi._vram()
    ram = servizi._ram()
    vram_lib = hw["total_gb"] - hw["used_gb"]
    ram_lib = ram["total_gb"] - ram["used_gb"]
    classif = naso._classifica(silo, vram_lib, ram_lib, vocale=bool(vocale))
    return {"ok": True, "modelli": classif}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8765)
