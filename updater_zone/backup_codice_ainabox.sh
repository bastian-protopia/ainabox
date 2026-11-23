#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

# backup_ainabox.sh — snapshot pre-aggiornamento (Regola 55)
# $AIBOX/update_backup/<ts>/ = SOLO CODICE NOSTRO + VERSION
# retention: 3 ultimi + golden
set -uo pipefail
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest assente" >&2; exit 1; }
BASE="$AIBOX/update_backup"
TS=$(date +%Y%m%d_%H%M%S)
DEST="$BASE/$TS"
mkdir -p "$DEST"
ver=$(tr -d '[:space:]' < $AIBOX/ollama_zone/VERSION 2>/dev/null || echo "0.0.0")
tar -czf "$DEST/ollama_${ver}.tar.gz" -C $AIBOX --exclude='ollama_zone/models' --exclude='ollama_zone/cache' ollama_zone 2>/dev/null || echo "WARN: ollama non archiviato"
ver=$(tr -d '[:space:]' < $AIBOX/owu_zone/VERSION 2>/dev/null || echo "0.0.0")
tar -czf "$DEST/owu_${ver}.tar.gz" -C $AIBOX --exclude='owu_zone/cache' --exclude='owu_zone/uploads' --exclude='owu_zone/vector_db' owu_zone 2>/dev/null || echo "WARN: owu non archiviato"
ver=$(tr -d '[:space:]' < $AIBOX/comfy_zone/VERSION 2>/dev/null || echo "0.0.0")
tar -czf "$DEST/comfy_${ver}.tar.gz" -C $AIBOX --exclude='comfy_zone/ComfyUI' --exclude='comfy_zone/models' comfy_zone 2>/dev/null || echo "WARN: comfy non archiviato"
ver=$(tr -d '[:space:]' < $AIBOX/speaches_zone/VERSION 2>/dev/null || echo "0.0.0")
tar -czf "$DEST/speaches_${ver}.tar.gz" -C $AIBOX --exclude='speaches_zone/speaches' --exclude='speaches_zone/models' --exclude='speaches_zone/hf_cache' speaches_zone 2>/dev/null || echo "WARN: speaches non archiviato"
ver=$(tr -d '[:space:]' < $AIBOX/vetrina_zone/VERSION 2>/dev/null || echo "0.0.0")
tar -czf "$DEST/vetrina_${ver}.tar.gz" -C $AIBOX --exclude='vetrina_zone/venv' --exclude='vetrina_zone/vetrina.log' --exclude='*/__pycache__' --exclude='*.bak' --exclude='*.bak_*' --exclude='*.pre-fix' vetrina_zone 2>/dev/null || echo "WARN: vetrina non archiviato"
ls -1d "$BASE"/2* 2>/dev/null | sort | head -n -3 | xargs -r rm -rf
if [ ! -d "$BASE/golden" ]; then cp -a "$DEST" "$BASE/golden"; echo "GOLDEN creato da $(basename "$DEST")"; fi
echo "BACKUP OK: $DEST"
