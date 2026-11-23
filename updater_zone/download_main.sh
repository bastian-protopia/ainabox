#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest assente" >&2; exit 1; }
INBOX="$AIBOX/updater_zone/inbox"
FILE="Qwen2.5-VL-7B-Instruct-Q5_K_M.gguf"
URL="https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/$FILE"
EXPECTED="793abbb5069da0ca9e11fbcb26352fda62391dace0ad13924db3d0dc57ee819c"
sudo -u svc_updater curl -sL -o "$INBOX/$FILE" "$URL"
REAL=$(sha256sum "$INBOX/$FILE" | awk '{print $1}')
SIZE=$(stat -c%s "$INBOX/$FILE")
echo "size:   $SIZE"
echo "atteso: $EXPECTED"
echo "reale : $REAL"
if [ "$REAL" = "$EXPECTED" ]; then
  echo "OK — veritiero"
  echo "{\"file\":\"$FILE\",\"sha256\":\"$REAL\",\"size\":$SIZE,\"ok\":true}" >> "$INBOX/manifest.json"
else
  echo "HASH NON CORRISPONDENTE — rimosso"
  sudo -u svc_updater rm -f "$INBOX/$FILE"
  exit 1
fi
