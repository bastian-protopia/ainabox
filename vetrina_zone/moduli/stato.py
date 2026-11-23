# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""STATO — cosa dice la catena adesso. Sola lettura."""
import os

def _n(p, suff=".json"):
    try: return len([f for f in os.listdir(p) if f.endswith(suff)])
    except OSError: return 0

def _file(p):
    try: return sorted(os.listdir(p))
    except OSError: return []

def rapido():
    return {
        "manifesti_in_coda": _n("/mnt/ainabox/updater_zone/manifesti"),
        "inbox_pacchetti":  _n("/mnt/ainabox/updater_zone/inbox"),
        "pianerottolo_gguf": [f for f in _file("/mnt/ainabox/modelli/ollama_modelli")
                              if f.lower().endswith(".gguf")],
    }
