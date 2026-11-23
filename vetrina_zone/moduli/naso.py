# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""naso.py — Il Naso: cervello orchestratore. C1-C4."""
import time
import os

def silo_vuoto(path_silo: str) -> bool:
    """True se il silo non ha NESSUN modello (o il path non esiste)."""
    try:
        if not os.path.isdir(path_silo):
            return True
        for _root, _dirs, _files in os.walk(path_silo):
            for _f in _files:
                if not _f.startswith("."):
                    return False
        return True
    except OSError:
        return True

# ── Tabella tier CHAT (Ollama) ──
# (min_gpu_libera_gb, min_ram_libera_gb, nome_ollama, label_per_X)
TIER_CHAT = [
    (10, 16, "qwen25vl", "Qwen 2.5 VL 7B (vision)"),
    (6,  8,  "llama3.1", "Llama 3.1 8B"),
]


def scegli_modello(gpu_libera_gb: float, ram_libera_gb: float) -> dict:
    """C2: il più pesante che sta in GPU+RAM. Se nessuno → errore."""
    for min_g, min_r, nome, label in TIER_CHAT:
        if gpu_libera_gb >= min_g and ram_libera_gb >= min_r:
            return {"ok": True, "modello": nome, "label": label}
    return {"ok": False, "errore": "GPU insufficiente per CHAT. Serve min 6 GB libera.", "errore_key": "errore.gpu_insufficiente"}


def accendi_chat(vram_fn, ram_fn, sudo_fn, owu_ready_fn, port_up_fn, sse_fn) -> dict:
    """C3: leggi hardware → scegli modello → chiudi → avvia → health → SSE."""
    if silo_vuoto("/mnt/ainabox/ollama_zone/models"):
        sse_fn(msg_key="sse.nessun_modello_ollama", color="#FF9999")
        return {"ok": False, "errore": "Nessun modello Ollama installato. Vai su Aggiorna Modelli per scaricarne uno.", "errore_key": "errore.nessun_modello_ollama"}
    hw = vram_fn()
    ram = ram_fn()
    gpu_lib = hw["total_gb"] - hw["used_gb"]
    ram_lib = ram["total_gb"] - ram["used_gb"]

    scelta = scegli_modello(gpu_lib, ram_lib)
    if not scelta["ok"]:
        sse_fn(msg_key="sse.gpu_insuff", color="#FF9999")
        return {"ok": False, "errore": scelta["errore"]}

    sse_fn(msg_key="sse.chat_avvio", color="#FFFFFF")

    sudo_fn(["/usr/bin/bash", "/usr/local/bin/chiudi_tutto"], 60)
    for _ in range(20):
        if not port_up_fn("127.0.0.1", 11434) and not port_up_fn("127.0.0.1", 3000) and not port_up_fn("127.0.0.1", 8188):
            break
        time.sleep(1)
    r2 = sudo_fn(["/usr/bin/bash", "/usr/local/bin/avvia_servizio.sh", "testuale"], 90)

    if not r2.get("ok"):
        sse_fn(msg_key="sse.chat_fail", color="#FF9999")
        return {"ok": False, "errore": "Avvio fallito. Controlla i log.", "errore_key": "errore.avvio_generico"}

    sse_fn(msg_key="sse.chat_ok", color="#FFFFFF")
    return {"ok": True, "stato": "avviamento"}


def accendi_grafica(vram_fn, ram_fn, sudo_fn, port_up_fn, sse_fn) -> dict:
    """C4: chiudi CHAT → avvia ComfyUI → health → SSE."""
    if silo_vuoto("/mnt/ainabox/comfy_zone/ComfyUI/models"):
        sse_fn(msg_key="sse.nessun_modello_grafica", color="#FF9999")
        return {"ok": False, "errore": "Nessun modello per Grafica installato. Vai su Aggiorna Modelli per scaricarne uno.", "stato": "nessuno"}
    sse_fn(msg_key="sse.grafica_avvio", color="#FFFFFF")

    sudo_fn(["/usr/bin/bash", "/usr/local/bin/chiudi_tutto"], 60)
    for _ in range(20):
        if not port_up_fn("127.0.0.1", 11434) and not port_up_fn("127.0.0.1", 3000) and not port_up_fn("127.0.0.1", 8188):
            break
        time.sleep(1)
    sse_fn(msg_key="sse.grafica_avvio", color="#FFFFFF")

    r2 = sudo_fn(["/usr/bin/bash", "/usr/local/bin/avvia_servizio.sh", "grafica"], 90)

    if not r2.get("ok"):
        sse_fn(msg_key="sse.grafica_fail", color="#FF9999")
        return {"ok": False, "errore": "Avvio fallito. Controlla i log.", "errore_key": "errore.avvio_generico"}

    sse_fn(msg_key="sse.grafica_ok", color="#FFFFFF")
    return {"ok": True, "stato": "avviamento"}

def accendi_ascolto(sudo_fn, port_up_fn, sse_fn) -> dict:
    """C5: TTS (Piper). CPU. Sempre disponibile."""
    sse_fn(msg_key="sse.ascolto_avvio", color="#FFFFFF")
    r = sudo_fn(["/usr/bin/bash", "/usr/local/bin/avvia_servizio.sh", "ascolto"], 90)
    if not r.get("ok"):
        sse_fn(msg_key="sse.ascolto_fail", color="#FF9999")
        return {"ok": False, "errore": "Avvio TTS fallito.", "errore_key": "errore.avvio_tts"}
    sse_fn(msg_key="sse.ascolto_ok", color="#FFFFFF")
    return {"ok": True, "stato": "avviamento"}


def accendi_vocale(vram_fn, sudo_fn, port_up_fn, sse_fn, lang="it") -> dict:
    """C5: TTS/STT su CPU. VRAM non serve."""
    r = sudo_fn(["/usr/bin/bash", "/usr/local/bin/avvia_servizio.sh", "vocale", lang], 90)
    if not r.get("ok"):
        return {"ok": False, "errore": "Avvio STT fallito.", "errore_key": "errore.avvio_stt"}
    return {"ok": True, "stato": "avviamento"}


def accendi_assistente(sudo_fn, port_up_fn, sse_fn) -> dict:
    """H: chiudi tutto → avvia Hermes → verifica 9119 → SSE."""
    sse_fn(msg_key="sse.assistente_avvio", color="#FFFFFF")
    sudo_fn(["/usr/bin/bash", "/usr/local/bin/chiudi_tutto"], 60)
    for _ in range(20):
        if (not port_up_fn("127.0.0.1", 11434) and
            not port_up_fn("127.0.0.1", 3000) and
            not port_up_fn("127.0.0.1", 8188) and
            not port_up_fn("127.0.0.1", 8000) and
            not port_up_fn("127.0.0.1", 9119)):
            break
        time.sleep(1)
    r2 = sudo_fn(["/usr/bin/bash", "/usr/local/bin/avvia_servizio.sh", "assistente"], 90)
    if not r2.get("ok"):
        sse_fn(msg_key="sse.assistente_fail", color="#FF9999")
        return {"ok": False, "errore": "Avvio fallito. Controlla i log.", "errore_key": "errore.avvio_generico"}
    sse_fn(msg_key="sse.assistente_ok", color="#FFFFFF")
    return {"ok": True, "stato": "avviamento"}

# ═══ C6: SWAP LLM PER VOCALE ═══════════════════════════════════════════
import json as _json
import os as _os
import time as _time

_OLLAMA = "http://127.0.0.1:11434"
_SWAP_FILE = "/mnt/ainabox/vetrina_zone/state/swap_vocale.json"
_WHISPER_GB = 2  # small ≈ 2 GB VRAM (domani: tier selectable)


def _ollama_ps():
    """Modelli attivi in VRAM."""
    import requests
    try:
        return requests.get(f"{_OLLAMA}/api/ps", timeout=3).json()
    except Exception:
        return []


def _ollama_tags():
    """Tutti i modelli sul disco."""
    import requests
    try:
        return requests.get(f"{_OLLAMA}/api/tags", timeout=3).json().get("models", [])
    except Exception:
        return []


def _ollama_unload(nome):
    import requests
    try:
        requests.post(f"{_OLLAMA}/api/generate",
                      json={"model": nome, "prompt": "", "keep_alive": 0}, timeout=10)
    except Exception:
        pass


def _ollama_load(nome):
    import requests
    try:
        requests.post(f"{_OLLAMA}/api/generate",
                      json={"model": nome, "prompt": "ok", "keep_alive": -1}, timeout=30)
    except Exception:
        pass


def _silo_comfy():
    """Walk checkpoints + diffusion_models. Return [{name, size}] (bytes)."""
    base = "/mnt/ainabox/comfy_zone/ComfyUI/models"
    cats = [("checkpoints", "Checkpoint"), ("diffusion_models", "Diffusion")]
    out = []
    for subdir, label in cats:
        path = os.path.join(base, subdir)
        if not os.path.isdir(path):
            continue
        for root, _dirs, files in os.walk(path):
            for f in files:
                if f.startswith(".") or f.startswith("put_"):
                    continue
                fp = os.path.join(root, f)
                try:
                    sz = os.path.getsize(fp)
                except OSError:
                    continue
                if sz < 100 * 1024 * 1024:
                    continue
                name = os.path.splitext(f)[0]
                out.append({"name": f"{name} ({label})", "size": sz})
    return out

def _classifica(silo, vram_lib, ram_lib, vocale=False):
    """2b: classifica ogni modello nel silo. ok / warn / no."""
    budget_ram = max(ram_lib - (2.5 if vocale else 0), 0)
    out = []
    for m in silo:
        name = m.get("name", "unknown")
        size = m.get("size", 0) / (1024**3)
        if size <= vram_lib:
            grado = "ok"
        elif size <= vram_lib + budget_ram:
            grado = "warn"
        else:
            grado = "no"
        out.append({"nome": name, "grado": grado, "size_gb": round(size, 1)})
    return out


def valuta_vocale(vram, sse_fn):
    """
    C6 — Naso: Whisper sta in VRAM?
    SÌ  → ok, LLM intatto.
    NO  → swap al modello più grande disponibile che sta.
    Impossibile → errore onesto (Regola 50).
    """
    libera = vram["total_gb"] - vram["used_gb"]

    # ── VRAM basta: nessun swap ──
    if libera >= _WHISPER_GB:
        return {"ok": True, "swap": None,
                "msg_key": "srv.whisper_attivo"}

    # ── VRAM non basta: swap ──
    active = _ollama_ps()
    if not active:
        return {"ok": True, "swap": None,
                "msg_key": "srv.nessun_llm"}

    big = active[0]["name"]
    tutti = _ollama_tags()
    alternativi = sorted(
        [m for m in tutti if m["name"] != big],
        key=lambda m: m.get("size", 0), reverse=True
    )

    if not alternativi:
        return {"ok": False, "swap": None, "msg_key": "srv.nessun_alternativo"}

    # ── Swap: il più grande che sta ──
    small = alternativi[0]["name"]
    _ollama_unload(big)
    _time.sleep(2)
    _ollama_load(small)

    _os.makedirs(_os.path.dirname(_SWAP_FILE), exist_ok=True)
    with open(_SWAP_FILE, "w") as f:
        _json.dump({"active": True, "from": big, "to": small}, f)

    return {"ok": True, "swap": {"from": big, "to": small}, "msg_key": "srv.modello_riotto", "msg_args": {"big": big, "small": small}}


def rilascia_vocale():
    """
    X spegne VOCALE → restore LLM (se c'era swap).
    Chiamato da servizi.py nel path OFF.
    Ritorna: {ok, restored, msg}
    """
    swap = None
    if _os.path.exists(_SWAP_FILE):
        with open(_SWAP_FILE) as f:
            state = _json.load(f)
        if state.get("active"):
            swap = {"from": state["from"], "to": state["to"]}
        _os.remove(_SWAP_FILE)

    if swap:
        _ollama_unload(swap["to"])
        _time.sleep(2)
        _ollama_load(swap["from"])

    return {"ok": True, "restored": swap is not None,
            "msg_key": ("srv.voce_spenta_ripristinato" if swap else "srv.voce_spenta"), "msg_args": ({"from": swap["from"]} if swap else {})}


