#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

# rollback_t7.sh — Rollback a cascata (MASTERMAP §13.5)
# Sequenza: ultimo → penultimo → terz'ultimo → golden
# Post-check dopo ogni step.
set -uo pipefail
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest assente" >&2; exit 1; }
BASE="$AIBOX/update_backup"
ZONES=(ollama owu comfy speaches vetrina)
STATO="$AIBOX/updater_zone/post_check.sh"

post_check() {
  bash "$STATO" >/dev/null 2>&1
}

try_restore() {
  local ts_dir="$1"
  local z
  for z in "${ZONES[@]}"; do
    local tar
    tar=$(ls "$ts_dir"/${z}_*.tar.gz 2>/dev/null | head -1)
    if [ -n "$tar" ]; then
      sudo tar -xzf "$tar" -C $AIBOX
    fi
  done
  # riavvia servizi attivi
  [ -f /usr/local/bin/avvia_servizio.sh ] && bash /usr/local/bin/avvia_servizio.sh 2>/dev/null || true
  if post_check; then
    return 0
  fi
  return 1
}

# elenca backup in ordine cronologico (vecchio → nuovo)
MAPPA=()
while IFS= read -r d; do MAPPA+=("$d"); done < <(ls -1d "$BASE"/2* 2>/dev/null | sort)

GOLDEN="$BASE/golden"
[ -d "$GOLDEN" ] && MAPPA+=("$GOLDEN")

# ripercorro dall'ultimo al primo
for (( i=${#MAPPA[@]}-1; i>=0; i-- )); do
  ts="${MAPPA[$i]}"
  echo "🔄 Rollback → $(basename "$ts")"
  if try_restore "$ts"; then
    echo "✅ POST-CHECK OK con $(basename "$ts")"
    exit 0
  else
    echo "⚠️ $(basename "$ts") non basta. Scendo."
  fi
done

echo "❌ ROLLBACK ESAURITO. Nessun backup ha superato il post-check."
exit 1
