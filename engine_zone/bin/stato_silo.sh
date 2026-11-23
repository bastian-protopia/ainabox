#!/usr/bin/env bash
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest assente" >&2; exit 1; }
# AINABOX — Stato Silo (v0.1a)
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
# Licensed under GPL-3.0-or-later

# stato_silo.sh — read-only: nerdctl ps nel silo richiesto
# CORRETTO 9/9/2026: nerdctl rootless DEVE girare COME l'utente svc_* (non come root):
# con euid 0 il client entra in rootful mode → socket sbagliato → exit=1 in silenzio.
# Percorsi già T7 (engine_zone/runtime/bin) — il bug era l'identità, non la sede.
# AGGIUNTO 16/9: check daemon containerd-rootless (exit 2 = daemon down)
SVC="${1:-}"
LOG="$AIBOX/vetrina_zone/ainabox.log"
declare -A UID_MAP=( [ollama]=$(id -u svc_ollama) [owu]=$(id -u svc_owu) [comfy]=$(id -u svc_comfy) [speaches]=$(id -u svc_speaches) [hermes]=$(id -u svc_hermes) )
UID_NUM="${UID_MAP[$SVC]:-}"
if [[ -z "$UID_NUM" ]]; then
  echo "ERRORE: silo sconosciuto '$SVC' (validi: ollama owu comfy speaches)"
  exit 1
fi
# --- Check daemon (nuovo 16/9) ---
if ! sudo -u "svc_$SVC" env XDG_RUNTIME_DIR="/run/user/$UID_NUM" \
     systemctl --user is-active containerd-rootless >/dev/null 2>&1; then
  echo "DAEMON_DOWN"
  echo "[$(date +%H:%M:%S)] [SILO] daemon_down: $SVC" >> "$LOG"
  exit 2
fi
# --- Container (come prima) ---
sudo -u "svc_$SVC" env XDG_RUNTIME_DIR="/run/user/$UID_NUM" \
  PATH=$AIBOX/engine_zone/runtime/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  bash -c 'cd / && nerdctl ps'
echo "[$(date +%H:%M:%S)] [SILO] ok: $SVC" >> "$LOG"
