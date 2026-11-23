#!/bin/bash
# AINABOX — Ingest Modelli (v0.1a)
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
# VETRINA — wrapper ingest (v2).
# Uso: vetrina_ingest.sh <nome_modello> [file.gguf]
set -euo pipefail
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null || true)
[ -z "$AIBOX" ] && { echo "ERRORE: /etc/ainabox/dest assente o vuoto" >&2; exit 1; }
LOG="$AIBOX/vetrina_zone/ainabox.log"
NOME="${1:?manca il nome del modello}"
[[ "$NOME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || { echo "nome non valido: $NOME"; exit 2; }
if [ -n "${2:-}" ]; then
    BASE="${2##*/}"
    FILE="$AIBOX/modelli/ollama_modelli/$BASE"
    [ -f "$FILE" ] || { echo "file non trovato: $BASE"; exit 3; }
else
    FILE="$(ls -t $AIBOX/modelli/ollama_modelli/*.gguf 2>/dev/null | head -1)"
    [ -n "$FILE" ] || { echo "niente GGUF nel pianerottolo"; exit 3; }
    BASE="$(basename "$FILE")"
fi
export XDG_RUNTIME_DIR=/run/user/$(id -u svc_ollama)
cd /
echo "🧪 ingest: $BASE -> modello $NOME"
echo "[$(date +%H:%M:%S)] [INGEST] avvio: $BASE → $NOME" >> "$LOG"
# Guard 2: Ollama su 11434
if ! curl -s --max-time 2 http://127.0.0.1:11434/api/version > /dev/null 2>&1; then
  echo "  ⚡ Ollama non attivo → accendo…"
  echo "[$(date +%H:%M:%S)] [INGEST] guard: Ollama non attivo → accendo" >> "$LOG"
  "$AIBOX/engine_zone/runtime/bin/ollama_accendi.sh"
  for i in $(seq 1 30); do
    curl -s --max-time 1 http://127.0.0.1:11434/api/version > /dev/null 2>&1 && break
    sleep 1
  done
fi
NE="$AIBOX/engine_zone/runtime/bin/nerdctl"
$NE exec ollama sh -c 'echo FROM $1 > /root/.ollama/Modelfile.vetrina' _ "/opt/ingest/$BASE"
$NE exec ollama sh -c 'ollama create "$1" -f /root/.ollama/Modelfile.vetrina' _ "$NOME"
$NE exec ollama sh -c 'rm -f /root/.ollama/Modelfile.vetrina'
echo "✅ done"
echo "[$(date +%H:%M:%S)] [INGEST] done: $NOME" >> "$LOG"
rm -f "$FILE"
echo "[$(date +%H:%M:%S)] [INGEST] pulito: $BASE rimosso da pianerottolo" >> "$LOG"
