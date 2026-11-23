#!/usr/bin/env bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

# agg_servizi_5b.sh — Aggiorna Servizi (ComfyUI + Speaches + Hermes)
# v2: readiness post-update + rollback automatico + case rollback manuale
# Chiamato da: servizi_update.py via sudo (svc_vetrina → root)
# Log: /mnt/Data/vetrina_zone/ainabox.log
set -euo pipefail
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest assente" >&2; exit 1; }
LOG="$AIBOX/vetrina_zone/ainabox.log"
VERZ="$AIBOX/engine_zone/VERSIONI.json"
UV="$AIBOX/engine_zone/bin/uv"
COMFY_DIR="$AIBOX/comfy_zone/ComfyUI"
SPE_DIR="$AIBOX/speaches_zone/speaches"
HERMES_DIR="$AIBOX/hermes_zone/hermes-agent"

log() { echo "[$(date +%H:%M:%S)] [Aggiorna Servizi] $1" >> "$LOG"; }

# ── Readiness: HTTP 200 entro 30s ──
_readiness() {
    local nome="$1"
    local url method timeout=30
    case "$nome" in
        comfy)
            url="https://127.0.0.1:8188/system_stats"
            method="-ks"
            ;;
        speaches)
            url="http://127.0.0.1:8000/v1/models"
            method="-s"
            ;;
        hermes)
            url="http://127.0.0.1:9119"
            method="-s"
            ;;
        *)
            log "readiness: nome sconosciuto: $nome"
            return 1
            ;;
    esac
    local t0
    t0=$(date +%s)
    while true; do
        local now
        now=$(date +%s)
        if (( now - t0 >= timeout )); then
            log "readiness $nome: TIMEOUT ${timeout}s"
            return 1
        fi
        local code
        code=$(curl -o /dev/null -w "%{http_code}" $method "$url" 2>/dev/null) || code="000"
        if [[ "$code" =~ ^[23] ]]; then
            log "readiness $nome: OK (HTTP $code, $(( now - t0 ))s)"
            return 0
        fi
        sleep 2
    done
}

# ── Aggiorna VERSIONI.json ──
_verz_update() {
    local nome="$1" attuale="$2" precedente="$3"
    python3 -c "
import json, sys
verz = '$VERZ'
with open(verz) as f: d = json.load(f)
d['$nome']['attuale'] = '$attuale'
d['$nome']['precedente'] = '$precedente'
d['$nome']['data'] = '$(date +%Y-%m-%d)'
with open(verz, 'w') as f: json.dump(d, f, indent=2)
" 2>/dev/null || log "VERZ update: fallito per $nome"
}

# ── ComfyUI ──
agg_comfy() {
    log "ComfyUI: inizio update"
    local prev
    prev=$(sudo -u svc_comfy git -C "$COMFY_DIR" rev-parse HEAD) || { log "ComfyUI: ERR non posso leggere HEAD"; return 1; }
    log "ComfyUI: commit precedente = $prev"

    log "ComfyUI: spegni"
    pkill -u svc_comfy -f "main.py" 2>/dev/null || true
    sleep 2

    log "ComfyUI: git pull"
    sudo -u svc_comfy git -C "$COMFY_DIR" pull || { log "ComfyUI: git pull FALLITO → rollback"; _rollback_comfy "$prev"; return 1; }

    local nuovo
    nuovo=$(sudo -u svc_comfy git -C "$COMFY_DIR" rev-parse HEAD)

    log "ComfyUI: pip install -r requirements.txt"
    sudo -u svc_comfy "$COMFY_DIR/venv/bin/python3" -m pip install -r "$COMFY_DIR/requirements.txt" 2>&1 | tail -5 >> "$LOG" || { log "ComfyUI: pip install FALLITO → rollback"; _rollback_comfy "$prev"; return 1; }

    log "ComfyUI: riaccendi"
    /usr/local/bin/avvia_servizio.sh grafica

    log "ComfyUI: readiness check"
    if _readiness comfy; then
        _verz_update comfy "$nuovo" "$prev"
        log "ComfyUI: ✅ AGGIORNATO ($prev → $nuovo)"
    else
        log "ComfyUI: readiness FALLITO → rollback"
        _rollback_comfy "$prev"
    fi
}

_rollback_comfy() {
    local prev="$1"
    log "ROLLBACK ComfyUI → $prev"
    pkill -u svc_comfy -f "main.py" 2>/dev/null || true
    sleep 2
    sudo -u svc_comfy git -C "$COMFY_DIR" checkout "$prev"
    sudo -u svc_comfy "$COMFY_DIR/venv/bin/python3" -m pip install -r "$COMFY_DIR/requirements.txt" 2>&1 | tail -3 >> "$LOG" || true
    /usr/local/bin/avvia_servizio.sh grafica
    if _readiness comfy; then
        _verz_update comfy "$prev" "$prev"
        log "ROLLBACK ComfyUI: ✅ OK (tornato a $prev)"
    else
        log "ROLLBACK ComfyUI: 🚨 FALLITO — intervento manuale"
        return 1
    fi
}

# ── Speaches ──
agg_speaches() {
    log "Speaches: inizio update"
    local prev
    prev=$(sudo -u svc_speaches git -C "$SPE_DIR" rev-parse HEAD) || { log "Speaches: ERR non posso leggere HEAD"; return 1; }
    log "Speaches: commit precedente = $prev"

    log "Speaches: spegni"
    pkill -u svc_speaches -f "uvicorn speaches" 2>/dev/null || true
    sleep 2

    log "Speaches: git pull"
    sudo -u svc_speaches git -C "$SPE_DIR" pull || { log "Speaches: git pull FALLITO → rollback"; _rollback_speaches "$prev"; return 1; }

    local nuovo
    nuovo=$(sudo -u svc_speaches git -C "$SPE_DIR" rev-parse HEAD)

    log "Speaches: uv sync"
    sudo -u svc_speaches bash -c "cd $SPE_DIR && $UV sync" 2>&1 | tail -5 >> "$LOG" || { log "Speaches: uv sync FALLITO → rollback"; _rollback_speaches "$prev"; return 1; }

    log "Speaches: riaccendi"
    /usr/local/bin/avvia_servizio.sh vocale

    log "Speaches: readiness check"
    if _readiness speaches; then
        _verz_update speaches "$nuovo" "$prev"
        log "Speaches: ✅ AGGIORNATO ($prev → $nuovo)"
    else
        log "Speaches: readiness FALLITO → rollback"
        _rollback_speaches "$prev"
    fi
}

_rollback_speaches() {
    local prev="$1"
    log "ROLLBACK Speaches → $prev"
    pkill -u svc_speaches -f "uvicorn speaches" 2>/dev/null || true
    sleep 2
    sudo -u svc_speaches git -C "$SPE_DIR" checkout "$prev"
    sudo -u svc_speaches bash -c "cd $SPE_DIR && $UV sync" 2>&1 | tail -3 >> "$LOG" || true
    /usr/local/bin/avvia_servizio.sh vocale
    if _readiness speaches; then
        _verz_update speaches "$prev" "$prev"
        log "ROLLBACK Speaches: ✅ OK (tornato a $prev)"
    else
        log "ROLLBACK Speaches: 🚨 FALLITO — intervento manuale"
        return 1
    fi
}

# ── Hermes ──
agg_hermes() {
    log "Hermes: inizio update"
    local prev
    prev=$(sudo -u svc_hermes git -C "$HERMES_DIR" rev-parse HEAD) || { log "Hermes: ERR non posso leggere HEAD"; return 1; }
    log "Hermes: commit precedente = $prev"

    log "Hermes: hermes update"
    sudo -u svc_hermes "$HERMES_DIR/.hermes/bin/hermes" update 2>&1 | tail -10 >> "$LOG" || { log "Hermes: hermes update FALLITO → rollback"; _rollback_hermes "$prev"; return 1; }

    local nuovo
    nuovo=$(sudo -u svc_hermes git -C "$HERMES_DIR" rev-parse HEAD)

    log "Hermes: riaccendi"
    pkill -u svc_hermes -f "hermes" 2>/dev/null || true
    sleep 2
    /usr/local/bin/avvia_servizio.sh agente

    log "Hermes: readiness check"
    if _readiness hermes; then
        _verz_update hermes "$nuovo" "$prev"
        log "Hermes: ✅ AGGIORNATO ($prev → $nuovo)"
    else
        log "Hermes: readiness FALLITO → rollback"
        _rollback_hermes "$prev"
    fi
}

_rollback_hermes() {
    local prev="$1"
    log "ROLLBACK Hermes → $prev"
    pkill -u svc_hermes -f "hermes" 2>/dev/null || true
    sleep 2
    sudo -u svc_hermes git -C "$HERMES_DIR" checkout "$prev"
    sudo -u svc_hermes bash -c "cd $HERMES_DIR && pip install -e ." 2>&1 | tail -3 >> "$LOG" || true
    /usr/local/bin/avvia_servizio.sh agente
    if _readiness hermes; then
        _verz_update hermes "$prev" "$prev"
        log "ROLLBACK Hermes: ✅ OK (tornato a $prev)"
    else
        log "ROLLBACK Hermes: 🚨 FALLITO — intervento manuale"
        return 1
    fi
}

# ── Case ──
case "${1:-}" in
    comfy)       agg_comfy ;;
    speaches)    agg_speaches ;;
    hermes)      agg_hermes ;;
    rollback)
        nome="${2:-}"
        if [[ ! "$nome" =~ ^(comfy|speaches|hermes)$ ]]; then
            log "rollback: nome invalido: $nome"
            echo "Uso: $0 rollback {comfy|speaches|hermes}" >&2
            exit 1
        fi
        log "Rollback manuale: $nome"
        prev=$(python3 -c "import json; d=json.load(open('$VERZ')); print(d['$nome'].get('precedente',''))" 2>/dev/null)
        if [[ -z "$prev" || "$prev" == "null" ]]; then
            log "rollback $nome: nessun precedente in VERSIONI.json"
            echo "Nessun precedente disponibile per $nome." >&2
            exit 1
        fi
        case "$nome" in
            comfy)    _rollback_comfy "$prev" ;;
            speaches) _rollback_speaches "$prev" ;;
            hermes)   _rollback_hermes "$prev" ;;
        esac
        ;;
    *)
        echo "Uso: $0 {comfy|speaches|hermes|rollback <nome>}" >&2
        exit 1
        ;;
esac
