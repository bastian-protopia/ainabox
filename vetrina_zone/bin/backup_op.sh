#!/usr/bin/env bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

# backup_op.sh v2 — wrapper validato (Colpo 2 FASE 3)
# Sostituisce: rsync *, du *, find *, rm -rf /mnt/ainabox/*, rm -rf /mnt/Datadisk/*
# Gira già come root (concesso da sudoers). Nessun sudo interno.
set -euo pipefail

# ALLOWED rimosso — valid_dest ora dinamica (universale)
SOURCE="/mnt/ainabox"

valid_dest() {
  local d="$1"
  [[ "$d" == "$SOURCE" || "$d" == "$SOURCE"/* ]] && { echo "DENIED: è la fonte" >&2; return 1; }
  [[ "$d" == *".."* || "$d" == "" ]] && { echo "DENIED: path non valido" >&2; return 1; }
  case "$d" in
    /mnt/*|/media/*|/run/media/*|/srv/*|/opt/*|/home/*|/tmp/*|/var/*) return 0 ;;
    *) echo "DENIED: destinazione non consentita: $d" >&2; return 1 ;;
  esac
}

valid_name() {
  local n="$1"
  if [[ ! "$n" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "DENIED: nome non valido: $n" >&2; return 1
  fi
  if [[ "$n" == "." || "$n" == ".." || "$n" == */* ]]; then
    echo "DENIED: path in nome: $n" >&2; return 1
  fi
}

LOG="/mnt/ainabox/vetrina_zone/ainabox.log"
log() { echo "[$(date '+%H:%M:%S')] [backup_op] $*" >> "$LOG" 2>/dev/null || true; }

OP="${1:?uso: backup_op.sh <rsync|cp|du|rm> ...}"
shift

case "$OP" in

  rsync)
    DEST="${1:?dest mancante}"
    NAME="${2:?nome mancante}"
    DRY="${3:-}"
    shift 2
    if [[ "$1" == "dry" ]]; then shift; fi
    valid_dest "$DEST"
    valid_name "$NAME"
    mkdir -p "$DEST"
    log "rsync → $DEST/$NAME${DRY:+ (dry-run)}"
    if [[ "$DRY" == "dry" ]]; then
      exec rsync -anv "$@" "$SOURCE/" "$DEST/$NAME/"
    else
      exec rsync -av --info=progress2 "$@" "$SOURCE/" "$DEST/$NAME/"
    fi
    ;;

  cp)
    DEST_DIR="${1:?dest mancante}"
    SRC_DIR="${2:?src mancante}"
    valid_dest "$DEST_DIR"
    log "cp $SRC_DIR → $DEST_DIR/"
    cp -a "$SRC_DIR/" "$DEST_DIR/"
    ;;

  ls)
    TARGET="${1:?path mancante}"
    valid_dest "$TARGET"
    log "ls $TARGET"
    exec ls -1 "$TARGET"
    ;;
  du)
    FLAG="${1:-}"
    TARGET="${2:?path mancante}"
    if [[ "$TARGET" == "$SOURCE" || "$TARGET" == "$SOURCE"/* ]]; then
      :
    else
      valid_dest "$TARGET"
    fi
    log "du $FLAG $TARGET"
    exec du "$FLAG" "$TARGET"
    ;;

  rm)
    DEST="${1:?dest mancante}"
    NAME="${2:?nome mancante}"
    valid_dest "$DEST"
    valid_name "$NAME"
    TARGET="$DEST/$NAME"
    if [[ ! -d "$TARGET" ]]; then
      echo "404: $TARGET non esiste" >&2
      log "DENIED rm (non esiste) $TARGET"
      exit 404
    fi
    log "rm $TARGET"
    rm -rf "$TARGET"
    ;;

  *)
    echo "Operazione sconosciuta: $OP" >&2
    exit 1
    ;;

esac
