#!/usr/bin/env python3
# AINABOX — Iniezione Vocale (v0.1a)
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
"""Iniezione OWU: 6 IP host-dipendenti + modello TTS per lingua.
   C14: ogni stringa → json.dumps. Numeri → nudi."""
import sqlite3, json, subprocess, argparse

AIBOX = open("/etc/ainabox/dest").read().strip()
DB = f"{AIBOX}/owu_zone/webui.db"

VOCI = {
    "it": ("speaches-ai/piper-it_IT-paola-medium", "it_IT-paola-medium"),
    "en": ("speaches-ai/piper-en_US-amy-medium",   "en_US-amy-medium"),
}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--lang", default="it", choices=["it", "en"])
    a = p.parse_args()

    h = subprocess.check_output(["hostname", "-I"], text=True).strip().split()[0]
    model, voice = VOCI[a.lang]

    db  = sqlite3.connect(DB)
    cur = db.cursor()
    up = [
        ("ollama.base_urls",                    json.dumps([f"http://{h}:11434"])),
        ("audio.tts.openai.api_base_url",       json.dumps(f"http://{h}:8000/v1")),
        ("audio.stt.openai.api_base_url",       json.dumps(f"http://{h}:8000/v1")),
        ("openai.api_base_urls",                json.dumps([f"http://{h}:8000/v1"])),
        ("image_generation.comfyui.base_url",   json.dumps(f"http://{h}:8188")),
        ("image_generation.openai.api_base_url",json.dumps(f"http://{h}:8765/v1")),
        ("audio.tts.model",                     json.dumps(model)),
        ("audio.tts.voice",                     json.dumps(voice)),
        ("audio.tts.openai.params",         json.dumps({"model": model, "response_format": "wav"})),
        ("audio.tts.engine",                json.dumps("openai")),
        ("audio.stt.engine",                json.dumps("openai")),
        ("audio.stt.model",               json.dumps("Systran/faster-whisper-small")),
    ]
    for k, v in up:
        cur.execute("UPDATE config SET value=? WHERE key=?", (v, k))
    db.commit()
    print(f"[vocale] {len(up)} campi → {h} | lang={a.lang} | {model}")
    db.close()
    print("[vocale] ✅ iniezione completata")

if __name__ == "__main__":
    main()
