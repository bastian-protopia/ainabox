#!/usr/bin/env bash
# AINABOX — Ollama Accensione (v0.1a)
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
nerdctl rm -f ollama 2>/dev/null || true
nerdctl run -d --name ollama --runtime "$AIBOX/engine_zone/runtime/bin/runc" \
  -p 11434:11434 \
  --gpus all \
  -e OLLAMA_HOST=0.0.0.0 \
  -v "$AIBOX/ollama_zone:/root/.ollama" \
  -v "$AIBOX/modelli/ollama_modelli:/opt/ingest:ro" \
  docker.io/ollama/ollama:latest serve
echo "OK"
