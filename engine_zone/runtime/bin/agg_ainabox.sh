#!/usr/bin/env bash
# AINABOX — Aggiorna Codice (v0.1a)
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
# agg_ainabox.sh — Wrapper AINABOX (codice): snapshot / pull / reset / extract / restart / verify
# Chiamato da aggiorna_codice_ainabox.py via sudo (svc_vetrina → root)
# Log: $AIBOX/vetrina_zone/ainabox.log
set -euo pipefail

AIBOX=$(cat /etc/ainabox/dest 2>/dev/null || true)
[ -z "$AIBOX" ] && { echo "ERRORE: /etc/ainabox/dest assente o vuoto" >&2; exit 1; }
DATA_DIR="$AIBOX"
BACKUP_DIR="$DATA_DIR/update_backup"
VETRINA_PORT="8765"
LOG="$DATA_DIR/vetrina_zone/ainabox.log"

log() {
    local ts; ts=$(date +%H:%M:%S)
    echo "[$ts] [Aggiorna AINABOX] $1" | tee -a "$LOG"
}

cmd_snapshot() {
    local ver="$1"
    local hash; hash=$(cd "$DATA_DIR" && git log --format=%h -1)
    mkdir -p "$BACKUP_DIR"
    local bf="$BACKUP_DIR/ainabox-${ver}-${hash}.tar.gz"
    log "Snapshot: inizio → $(basename "$bf")"
    tar czf "$bf" -C "$DATA_DIR" \
        --exclude='vetrina_zone/venv' \
        --exclude='engine_zone/runtime' \
        --exclude='updater_zone/.secrets' \
        --exclude='updater_zone/inbox' \
        --exclude='*.bkp-*' \
        vetrina_zone/ engine_zone/ updater_zone/ network_zone/ 2>/dev/null
    local sz; sz=$(du -sh "$bf" | cut -f1)
    log "Snapshot: fatto ($sz)"
    # D13: max 3 (golden escluso)
    local count=0 oldest=""
    for f in $(ls -1t "$BACKUP_DIR"/ainabox-*.tar.gz 2>/dev/null | grep -v 'golden'); do
        count=$((count+1)); oldest="$f"
    done
    if [ "$count" -gt 2 ]; then
        log "Pulizia: rimo $(basename "$oldest") (oltre max 3)"
        rm -f "$oldest"
    fi
}

cmd_pull() {
    log "Pull: inizio"
    cd "$DATA_DIR" && git pull origin main
    log "Pull: fatto"
}

cmd_reset() {
    local commit="$1"
    log "Reset: inizio → $commit"
    cd "$DATA_DIR" && git reset --hard "$commit"
    log "Reset: fatto → $commit"
}

cmd_extract() {
    local tb="$1"
    log "Extract: inizio → $(basename "$tb")"
    tar xzf "$tb" -C "$DATA_DIR/" 2>/dev/null
    log "Extract: fatto"
}

cmd_restart() {
    log "Restart: stop vetrina"
    systemctl stop vetrina
    sleep 3
    log "Restart: start vetrina"
    systemctl start vetrina
    sleep 2
    log "Restart: fatto"
}

cmd_verify() {
    local resp
    if resp=$(curl -sk "https://127.0.0.1:$VETRINA_PORT/api/sistema" 2>/dev/null | head -5); then
        log "Verify: OK (200)"
        echo "$resp"
    else
        log "Verify: FAIL"
        echo "FAIL"
        return 1
    fi
}

case "${1:-}" in
    snapshot)  cmd_snapshot "${2:?uso: snapshot <versione>}" ;;
    pull)      cmd_pull ;;
    reset)     cmd_reset "${2:?uso: reset <commit>}" ;;
    extract)   cmd_extract "${2:?uso: extract <tarball>}" ;;
    restart)   cmd_restart ;;
    verify)    cmd_verify ;;
    *) echo "Uso: agg_ainabox.sh {snapshot|pull|reset|extract|restart|verify} [args]" >&2; exit 1 ;;
esac
