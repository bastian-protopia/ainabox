#!/usr/bin/env bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina

# avvia_servizio.sh — Accende la combinazione richiesta (pattern rm -f + run)
# Uso: sudo bash /usr/local/bin/avvia_servizio.sh <nome>
# <nome> ∈ testuale | vocale | testuale_img | vocale_img | assistente
# Chiede al chiamante (servizi.py) di aver già chiamato chiudi_tutto.
# Qui solo APRI. (Regola 16: apri = violento, chiudi = dolce [2])

AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest non trovato" >&2; exit 1; }
set -euo pipefail

SVC="${1:-}"

AINABOX_LOG="$AIBOX/vetrina_zone/ainabox.log"
log() { echo "[$(date +%H:%M:%S)] [$1] $2" >> "$AINABOX_LOG" 2>/dev/null || true; }

# ── Helper: avvia Ollama ──
avvia_ollama() {
  local _t0=$SECONDS
  local _out
  local _gpu=""
  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    _gpu="--gpus all"
  elif [ -e /dev/kfd ] && [ -d /dev/dri ]; then
    _gpu="--device /dev/kfd --device /dev/dri"
  fi
  # GPU LIBS: gestite da CDI (nvidia-container-toolkit) — zero mount manuali
  # GUARD D-11: containerd socket
  pgrep -u svc_ollama -f containerd >/dev/null 2>&1 || { echo "❌ Daemon containerd (svc_ollama) non attivo. Clicca APRI prima di avviare i servizi." >&2; log "Ollama" "FALSO → daemon containerd non attivo." 2>/dev/null; return 1; }
  if _out=$(sudo -u svc_ollama GPU_ARGS="$_gpu" XDG_RUNTIME_DIR="/run/user/$(id -u svc_ollama)" AIBOX="$AIBOX" bash -c '
    export HOME=/home/svc_ollama
    export PATH=$AIBOX/engine_zone/runtime/bin:$AIBOX/engine_zone/runtime:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    cd "$AIBOX/ollama_zone"
    nerdctl rm -f ollama 2>/dev/null || true
    nerdctl run -d --name ollama --runtime $AIBOX/engine_zone/runtime/bin/runc \
      -p 11434:11434 \
      $GPU_ARGS \
      -e OLLAMA_HOST=0.0.0.0 \
      -v $AIBOX/ollama_zone:/root/.ollama \
      -v $AIBOX/modelli/ollama_modelli:/opt/ingest:ro \
      docker.io/ollama/ollama:0.40.5 serve
  ' 2>&1); then
    local _el=$((SECONDS - _t0))
    log "Ollama" "AVVIO → 127.0.0.1:11434 UP (${_el}s)"
    echo "✅ Ollama → 11434"
  else
    log "Ollama" "AVVIO → FALSO → 127.0.0.1:11434 non risponde dopo 90s"
    echo "❌ Ollama non partito" >&2
    return 1
  fi
}

# ── Helper: avvia OWU ──
avvia_owu() {
  local HOST_IP
  HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -z "$HOST_IP" ] && HOST_IP=$(ip -4 -o addr show | grep -v ' lo ' | awk '{print $4}' | cut -d/ -f1 | head -1)
  echo "  OWU → Ollama via ${HOST_IP}:11434"
  local _t0=$SECONDS
  local _out
  # GUARD D-11: containerd socket
  pgrep -u svc_owu -f containerd >/dev/null 2>&1 || { echo "❌ Daemon containerd (svc_owu) non attivo. Clicca APRI prima di avviare i servizi." >&2; log "Open WebUI" "FALSO → daemon containerd non attivo." 2>/dev/null; return 1; }
  if _out=$(sudo -u svc_owu XDG_RUNTIME_DIR="/run/user/$(id -u svc_owu)" AIBOX="$AIBOX" bash -c '
    export HOME=/home/svc_owu
    export PATH=$AIBOX/engine_zone/runtime/bin:$AIBOX/engine_zone/runtime:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    cd "$AIBOX/owu_zone"
    nerdctl rm -f open-webui 2>/dev/null || true
    nerdctl run -d --pull missing --name open-webui --runtime $AIBOX/engine_zone/runtime/bin/runc \
      -p 127.0.0.1:3000:8080 \
      -v $AIBOX/owu_zone:/app/backend/data \
      -e OLLAMA_BASE_URL=http://'"${HOST_IP}"':11434 \
      -e SPEACHES_URL=http://'"${HOST_IP}"':8000/v1 \
      -e VETRINA_URL=https://'"${HOST_IP}"':8765 \
      -e HF_HUB_OFFLINE=1 \
      -e TRANSFORMERS_OFFLINE=1 \
      -e HF_HOME=/app/backend/data/hf_cache \
      ghcr.io/open-webui/open-webui:v0.12.2
  ' 2>&1); then
    local _el=$((SECONDS - _t0))
    log "Open WebUI" "AVVIO → nerdctl run → 127.0.0.1:3000 UP (${_el}s)"
    echo "✅ OWU → 127.0.0.1:3000"
  else
    log "Open WebUI" "AVVIO → FALSO → nerdctl exit=1"
    echo "❌ OWU non partito" >&2
    return 1
  fi
}

# ── Helper: avvia ComfyUI ──
avvia_comfy() {
  local _t0=$SECONDS
  local _out
  if _out=$(sudo -u svc_comfy AIBOX="$AIBOX" bash -c '
    export HOME=/home/svc_comfy
    export PATH=$AIBOX/engine_zone/runtime/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    cd "$AIBOX/comfy_zone/ComfyUI"
    nohup ./venv/bin/python3 main.py --port 8188 --tls-keyfile $AIBOX/comfy_zone/certs/comfy.key --tls-certfile $AIBOX/comfy_zone/certs/comfy.crt --enable-cors-header  > $AIBOX/comfy_zone/comfyui.log 2>&1 &
  ' 2>&1); then
    local _el=$((SECONDS - _t0))
    log "ComfyUI" "AVVIO → 127.0.0.1:8188 UP (${_el}s)"
    echo "✅ ComfyUI → 127.0.0.1:8188"
  else
    log "ComfyUI" "AVVIO → FALSO → 127.0.0.1:8188 non risponde dopo 90s"
    echo "❌ ComfyUI non partito" >&2
    return 1
  fi
}

# ── Helper: avvia Speaches ──
avvia_speaches() {
  local _t0=$SECONDS
  local _out
  if _out=$(sudo -u svc_speaches AIBOX="$AIBOX" bash -c '
    export HOME=/home/svc_speaches
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    cd "$AIBOX/speaches_zone/speaches"
    export PYTHONPATH=src:.venv/lib/python3.12/site-packages
    export HF_HOME=$AIBOX/speaches_zone/models
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1
  export CUDA_VISIBLE_DEVICES=-1
    nohup $AIBOX/speaches_zone/.python/cpython-3.12.15-linux-x86_64-gnu/bin/python3.12 -m uvicorn speaches.main:create_app --factory --host 0.0.0.0 --port 8000 > $AIBOX/speaches_zone/speaches.log 2>&1 &
  ' 2>&1); then
    local _ok=0
    for _i in $(seq 1 15); do ss -tlnp 2>/dev/null | grep -q ':8000 ' && { _ok=1; break; }; sleep 1; done
    local _el=$((SECONDS - _t0))
    if [ $_ok -eq 0 ]; then log "Speaches" "FALSO → 8000 non UP dopo ${_el}s"; echo "❌ Speaches non partito" >&2; return 1; fi
    log "Speaches" "AVVIO → 8000 UP (${_el}s)"; echo "✅ Speaches → 8000"
  else
    log "Speaches" "AVVIO → FALSO → 127.0.0.1:8000 non risponde dopo 60s"
    echo "❌ Speaches non partito" >&2
    return 1
  fi
}

# ── Helper: avvia Hermes (5° motore, processo Python, pattern ComfyUI/Speaches) ──
avvia_hermes() {
  local _t0=$SECONDS
  local _out
  if _out=$(sudo -u svc_hermes AIBOX="$AIBOX" bash -c '
    export HOME=$AIBOX/hermes_zone
    export HERMES_WRITE_SAFE_ROOT=$AIBOX/hermes_zone
    export WIKI_PATH=$AIBOX/hermes_zone/wiki
    export PATH=$AIBOX/hermes_zone/.hermes/hermes-agent/.hermes/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    cd "$AIBOX/hermes_zone"
    [ -d $AIBOX/hermes_zone/.hermes ] || hermes pm install 2>&1
    if [ -f $AIBOX/hermes_zone/config.yaml ] && [ -d $AIBOX/hermes_zone/.hermes ]; then
      cp $AIBOX/hermes_zone/config.yaml $AIBOX/hermes_zone/.hermes/config.yaml
      chmod 644 $AIBOX/hermes_zone/.hermes/config.yaml
    fi
    # ── Guard sandbox podman ──
    if ! command -v podman >/dev/null 2>&1; then
      echo "ERRORE: podman non trovato. Il sandbox non può girare." >> $AIBOX/vetrina_zone/ainabox.log
      echo "ERRORE: podman assente." >&2
      exit 1
    fi
    if ! podman images 2>/dev/null | grep -q "hermes-agent"; then
      echo "ERRORE: immagine hermes-agent assente." >> $AIBOX/vetrina_zone/ainabox.log
      echo "ERRORE: immagine sandbox assente." >&2
      exit 1
    fi
    nohup hermes dashboard >$AIBOX/hermes_zone/hermes.log 2>&1 &
  ' 2>&1); then
    local _el=$((SECONDS - _t0))
    log "HERMES" "AVVIO → processo Python UP (${_el}s)"
    echo "✅ HERMES → agente attivo"
  else
    log "HERMES" "AVVIO → FALSO → hermes non partito"
    echo "❌ Hermes non partito" >&2
    return 1
  fi
}

# ── Combinazioni (estendere qui) ──
case "$SVC" in
  testuale)
    avvia_ollama
    avvia_owu
    echo "🗨️ Chat testuale pronta → http://localhost:3000"
    ;;
  vocale)
    avvia_speaches
    sudo python3 $AIBOX/engine_zone/bin/inietta_vocale.py --lang ${2:-it}
    echo "🎧 Vocale pronta → http://localhost:8000"
    ;;
  ascolto)
    avvia_speaches
    echo "🗣️ Ascolto pronto → http://localhost:8000"
    ;;
  spegni_vocale)
    pkill -u svc_speaches -f "uvicorn speaches.main" 2>/dev/null || true
    echo "🔇 Speaches spento."
    ;;
  testuale_img)
    avvia_ollama
    avvia_owu
    # ComfyUI (quando pronto):
    # avvia_comfy
    echo "NON_ANCORI: ComfyUI in standby"
    ;;
  vocale_img)
    avvia_ollama
    avvia_owu
    # Speaches + ComfyUI:
    echo "NON_ANCORI: Speaches + ComfyUI in standby"
    ;;
  agente)
    avvia_ollama
    avvia_hermes
    echo "🤖 AGENTE pronto → Hermes attivo"
    ;;
  assistente)
    # alias per compatibilità (stesso di agente)
    avvia_ollama
    avvia_hermes
    echo "🤖 AGENTE pronto → Hermes attivo"
    ;;
  grafica)
    avvia_comfy
    echo "🎨 GRAFICA pronta → http://localhost:8188"
    ;;
  *)
    echo "ERRORE: servizio sconosciuto '$SVC'"
    echo "Validi: testuale | vocale | ascolto | testuale_img | vocale_img | agente | grafica"
    exit 1
    ;;
esac
