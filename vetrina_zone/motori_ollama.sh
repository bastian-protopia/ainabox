#!/bin/bash
# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
BIN_DIR="/mnt/ainabox/engine_zone/runtime"
export PATH="$BIN_DIR/bin:$BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/home/svc_ollama"
export XDG_RUNTIME_DIR="/run/user/$(id -u svc_ollama)"
cd /mnt/ainabox/ollama_zone
case "$1" in
  on)
    systemctl --user start containerd-rootless.service 2>/dev/null || true
    for _i in $(seq 1 10); do nerdctl version >/dev/null 2>&1 && break; sleep 1; done
    nerdctl rm -f ollama 2>/dev/null
    nerdctl run -d --name ollama -e OLLAMA_HOST=0.0.0.0 --gpus all \
      -p 11434:11434 \
      -v /mnt/ainabox/ollama_zone:/root/.ollama \
      -v /mnt/ainabox/modelli/ollama_modelli:/opt/ingest:ro \
      ollama/ollama
    echo "✅ Ollama on"
    ;;
  off)
    nerdctl stop ollama 2>/dev/null
    nerdctl rm ollama 2>/dev/null
    echo "✅ OWU off"
    ;;
  *)
    echo "Uso: $0 {on|off}"; exit 1 ;;
esac
