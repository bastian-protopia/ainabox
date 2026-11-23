#!/usr/bin/env bash
# AINABOX — Tarball di produzione (UNIVERSALE)
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
# 2026-11-07 · D-TB chiuso
set -uo pipefail

# ── ARGUMENTO ──
SHIP_DIR="${1:?Uso: make_tarball.sh /path/to/ship_dir}"

# ── PRECONDIZIONI ──
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo 'ERRORE: /etc/ainabox/dest assente' >&2; exit 1; }
[ -d "$AIBOX" ] || { echo "ERRORE: $AIBOX non esiste." ; exit 1; }
[ -d "$SHIP_DIR" ] || mkdir -p "$SHIP_DIR" || { echo "ERRORE: $SHIP_DIR non creabile."; exit 1; }
[ -w "$SHIP_DIR" ] || { echo "ERRORE: $SHIP_DIR non scrivibile."; exit 1; }

cd "$AIBOX"

EXCLUDES=(
  --exclude='/.git/'
  --exclude='bastian_zone/'
  --exclude='_legacy/'
  --exclude='lost+found/'
  --exclude='modelli/'
  --exclude='**/*.log'
  --exclude='**/*.bak*'
  --exclude='**/*.bkp*'
  --exclude='**/__pycache__/'
  --exclude='*.gguf'
  --exclude='network_zone/reti.sh'
  --exclude='engine_zone/backups/'
  --exclude='updater_zone/inbox'
  --exclude='updater_zone/.secrets'
  --exclude='updater_zone/__pycache__'
  --exclude='vetrina_zone/.lock_seriale'
  --exclude='vetrina_zone/.env'
  --exclude='vetrina_zone/venv/'
  --exclude='hermes_zone/state.db'
  --exclude='hermes_zone/models_dev_cache.json'
  --exclude='hermes_zone/memories/'
  --exclude='hermes_zone/sandboxes/'
  --exclude='hermes_zone/work'
  --exclude='hermes_zone/terminal-sessions'
  --exclude='hermes_zone/.local/share/containers'
  --exclude='hermes_zone/cache/scratch'
  --exclude='hermes_zone/.hermes/cache/scratch'
  --exclude='hermes_zone/.local/bin'
  --exclude='hermes_zone/.hermes/tools'
  --exclude='hermes_zone/.hermes/tools'
  --exclude='comfy_zone/ComfyUI'
  --exclude='owu_zone/webui.db'
  --exclude='owu_zone/webui.db-shm'
  --exclude='owu_zone/webui.db-wal'
  --exclude='speaches_zone/speaches'
  --exclude='speaches_zone/models'
  --exclude='ollama_zone/models'
  --exclude='ollama_zone/cache'
  --exclude='nerdctl_root/svc_ollama/containerd'
  --exclude='nerdctl_root/svc_owu/containerd'
  --exclude='hermes_zone/.hermes/shared-state.db'
  --exclude='hermes_zone/.hermes/runtime'
  --exclude='hermes_zone/.hermes_history'
)
SOURCES=(
  engine_zone/
  owu_zone/
  vetrina_zone/
  network_zone/
  ollama_zone/
  comfy_zone/
  speaches_zone/
  updater_zone/
  Obsidian/
  nerdctl_root/
  installer/
  README.md LICENSE NOTICE AINABOX_logo.svg .gitignore
  ainabox-apri.desktop ainabox-disconnetti.desktop ainabox-uninstall.desktop
)

# ── DRY-RUN ──
if [ "${DRY:-0}" == "1" ]; then
  echo "DRY-RUN: validazione path (no output)"
  tar czf /dev/null "${EXCLUDES[@]}" "${SOURCES[@]}"
  echo "DRY-RUN: exit=$?"
  exit 0
fi

# ── PRODUZIONE ──
echo "=== AINABOX TARBALL → $SHIP_DIR ==="
echo "  Sources:  ${#SOURCES[@]} voci"
echo "  Excludes: ${#EXCLUDES[@]} voci"
echo "  Dest:     $SHIP_DIR/ainabox-pkg.tar.gz"
echo ""

# 1. Tar + Gzip direttamente in SHIP_DIR
echo "  [1/4] tar czf (27 GB, ~10 min)…"
tar czf "$SHIP_DIR/ainabox-pkg.tar.gz" "${EXCLUDES[@]}" "${SOURCES[@]}" || { echo "ERRORE: tar fallito."; exit 1; }
echo "  [ok] tarball creato"

# 2. SHA256
echo "  [2/4] sha256sum…"
sha256sum "$SHIP_DIR/ainabox-pkg.tar.gz" > "$SHIP_DIR/ainabox-pkg.tar.gz.sha256"
echo "  [ok] $(awk '{print $1}' $SHIP_DIR/ainabox-pkg.tar.gz.sha256 | cut -c1-16)…"

# 3. Installer in ship
echo "  [3/4] cp installer…"
cp installer/ainabox-install.sh "$SHIP_DIR/" || { echo "ERRORE: cp installer fallito."; exit 1; }
echo "  [ok] installer copiato"
cp installer/dependencies.json "$SHIP_DIR/" || { echo "ERRORE: cp dependencies fallito."; exit 1; }
echo "  [ok] dependencies.json copiato"

# 4. Conferma
echo "  [4/4] Contenuto ship:"
ls -lh "$SHIP_DIR/"
echo ""
echo "=== FINE ==="
