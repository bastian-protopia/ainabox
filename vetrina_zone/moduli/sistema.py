# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""
NASO — rileva hardware e cartelle che crescono.
Sola lettura. Zero scrittura. stdlib solo.
"""
import os, platform, shutil, subprocess

CARTELLE = [
    ("Silo Ollama",      "/mnt/ainabox/ollama_zone"),
    ("Silo OWU",         "/mnt/ainabox/owu_zone"),
    ("Silo ComfyUI",     "/mnt/ainabox/comfy_zone"),
    ("Pianerottolo",     "/mnt/ainabox/modelli/ollama_modelli"),
    ("Coda manifesti",   "/mnt/ainabox/updater_zone/manifesti"),
    ("Inbox",            "/mnt/ainabox/updater_zone/inbox"),
]

def _gpu():
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,memory.used,memory.free,driver_version",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5)
        if out.returncode != 0:
            return {"presente": False}
        nome, tot, used, free, driver = [x.strip() for x in out.stdout.split(",")]
        return {"presente": True, "nome": nome, "driver": driver,
                "vram_tot_gb": round(float(tot)/1024,1),"vram_libera_gb": round(float(free)/1024,1)}
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return {"presente": False}

def _ram():
    kb = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            kb[k] = int(v.strip().split()[0])
    return {"ram_tot_gb": round(kb.get("MemTotal",0)/1e6,1),
            "ram_libera_gb": round(kb.get("MemAvailable",0)/1e6,1)}

def _cpu():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    return {"nome": line.split(":",1)[1].strip().split("@")[0].strip()}
    except OSError:
        pass
    return {"nome": platform.processor() or "sconosciuto"}

def _cartella(path):
    try:
        total, used, free = shutil.disk_usage(path)
        dim = 0
        for root, dirs, files in os.walk(path, onerror=lambda e: None):
            for f in files:
                try: dim += os.lstat(os.path.join(root, f)).st_size
                except OSError: pass
        return {"gb": round(dim/1e9,2), "disco_libero_gb": round(free/1e9,0)}
    except OSError:
        return {"gb": None}

def scan():
    return {"gpu": _gpu(), "cpu": _cpu(), "ram": _ram(),
            "cartelle": {k: _cartella(p) for k, p in CARTELLE}}
