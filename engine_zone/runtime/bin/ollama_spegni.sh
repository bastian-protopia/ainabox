#!/usr/bin/env bash
# AINABOX — Ollama Spegnimento (v0.1a)
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
set -euo pipefail
export HOME=/home/svc_ollama
export XDG_RUNTIME_DIR=/run/user/$(id -u svc_ollama)
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null || true)
[ -z "$AIBOX" ] && { echo "ERRORE: /etc/ainabox/dest assente o vuoto" >&2; exit 1; }
export PATH="$AIBOX/engine_zone/runtime/bin:$AIBOX/engine_zone/runtime:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
cd "$AIBOX/ollama_zone"
nerdctl stop --time 5 ollama 2>/dev/null || true
nerdctl rm -f ollama 2>/dev/null || true
echo "OK"
