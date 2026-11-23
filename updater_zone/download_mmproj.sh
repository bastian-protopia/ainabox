#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

# ==============================================================================
# UPDATER — DOWNLOAD (test singolo: mmproj-BF16.gguf)
# Attori: svc_updater scarica in inbox → verifica → manifest
# Uso:  bash $AIBOX/updater_zone/download_mmproj.sh
# ==============================================================================
set -euo pipefail

AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo 'ERRORE: /etc/ainabox/dest assente' >&2; exit 1; }
INBOX="$AIBOX/updater_zone/inbox"
URL="https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-BF16.gguf"
FILE="mmproj-BF16.gguf"
EXPECTED="f0edf43c09b69d6e5dd24262f33b356a1e9dd978e7c3299b3e69141fcbb87553"

echo "═══ DOWNLOAD (svc_updater → inbox) ═══"

# 1. Download come svc_updater (curl -L segue il redirect CDN)
echo "⬇️  Scarico $FILE ..."
sudo -u svc_updater curl -sL -o "$INBOX/$FILE" "$URL"

# 2. Hash reale
REAL=$(sha256sum "$INBOX/$FILE" | awk '{print $1}')
SIZE=$(stat -c%s "$INBOX/$FILE")

echo "   size : $SIZE"
echo "   atteso: $EXPECTED"
echo "   reale : $REAL"

# 3. Confronto
if [ "$REAL" = "$EXPECTED" ]; then
    echo "✅ HASH OK — veritiero"
    python3 -c "
import json, datetime
m = {'file':'$FILE','url':'$URL','sha256':'$REAL','size':$SIZE,'ok':True,'ts':datetime.datetime.now().isoformat()}
open('$INBOX/manifest.json','a+').write(json.dumps(m,ensure_ascii=False)+'\n')
"
    echo "📝 manifest aggiornato"
else
    echo "❌ HASH DIVERSO — NON veritiero"
    echo "   ATTENZIONE: non installare. Verificare provenienza."
    echo "   (rimuovo il file per non lasciarlo in inbox)"
    sudo -u svc_updater rm -f "$INBOX/$FILE"
    exit 1
fi

echo "═══ FINE ═══"
echo "   inbox:"
ls -lh "$INBOX"
