#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

# svc_updater.sh — IL corriere
# Legge manifesti, scarica, verifica hash, deposita in inbox.
# Non sa da dove viene. Non sceglie. Non installa.
set -euo pipefail
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest assente" >&2; exit 1; }
LOG="$AIBOX/vetrina_zone/ainabox.log"
echo "[$(date +%H:%M:%S)] [UPDATER] avvio" >> "$LOG"
# ── Self-check connessioni (minimo privilegio) ──
MODE_NET_FILE="$AIBOX/network_zone/MODE_NET"
MODE=$(cat "$MODE_NET_FILE" 2>/dev/null || echo "offline")
if [ "$MODE" = "offline" ]; then
    echo "OFFLINE — non scarico. Toggle: Vetrina > Connessioni."
    exit 0
fi


MANIFESTI="$AIBOX/updater_zone/manifesti"
INBOX="$AIBOX/updater_zone/inbox"

cleanup() { find "$INBOX" -maxdepth 1 -name '.tmp_*' -delete 2>/dev/null; }
trap cleanup EXIT

shopt -s nullglob
MANFALIST=( "$MANIFESTI"/*.json )
if [ ${#MANFALIST[@]} -eq 0 ]; then
    echo "Nessun manifesto in coda. Niente da fare."
    echo "[$(date +%H:%M:%S)] [UPDATER] nessun manifesto — esito" >> "$LOG"
    exit 0
fi

for MAN in "${MANFALIST[@]}"; do
    echo "═══════════════════════════════════════════"
    echo "📦 $(basename "$MAN")"

    LISTA=$(python3 -c "
import json
with open('$MAN') as f:
    m = json.load(f)
for e in m['file']:
    print(f\"{e['url']}|{e['sha256']}|{e['size']}\")
")

    FAILED=0
    HF_TOK=""
    if [ -f $AIBOX/updater_zone/.secrets/HF_TOKEN ]; then HF_TOK=$(cat $AIBOX/updater_zone/.secrets/HF_TOKEN); fi
    if [ -n "$HF_TOK" ]; then AUTH=(-H "Authorization: Bearer $HF_TOK"); else AUTH=(); fi
    while IFS='|' read -r URL SHA256 SIZE; do
        [ -z "$URL" ] && continue
        FILENAME=$(basename "$URL")
        echo "  ⬇️  $FILENAME"
        echo "[$(date +%H:%M:%S)] [UPDATER] download: $FILENAME" >> "$LOG"

        if [ -f "$INBOX/$FILENAME" ]; then
            ES=$(sha256sum "$INBOX/$FILENAME" | awk '{print $1}')
            if [ "$ES" = "$SHA256" ]; then
                echo "  ⏭️  già presente, hash ok — skip"
                continue
            fi
        fi

        TMP="$INBOX/.tmp_$$_$FILENAME"
        curl "${AUTH[@]}" -sS -fL --retry 5 --retry-delay 10 -C - --connect-timeout 30 -o "$TMP" "$URL"

        REAL=$(sha256sum "$TMP" | awk '{print $1}')
        if [ "$REAL" = "$SHA256" ]; then
            echo "  ✅ hash ok"
            echo "[$(date +%H:%M:%S)] [UPDATER] hash ok: $FILENAME" >> "$LOG"
            mv "$TMP" "$INBOX/$FILENAME"
        else
            echo "  ❌ HASH DIVERSO — rimosso"
            echo "[$(date +%H:%M:%S)] [UPDATER] HASH FAIL: $FILENAME atteso=$SHA256 reale=$REAL" >> "$LOG"
            echo "     atteso: $SHA256"
            echo "     reale : $REAL"
            rm -f "$TMP"
            FAILED=1
        fi
    done <<< "$LISTA"

    if [ $FAILED -eq 1 ]; then
        echo "  ═══ FALLO — manifesto resta in coda ═══"
        continue
    fi

    mv "$MAN" "$INBOX/"
    echo "  📋 manifesto → inbox"
    echo "  ═══ OK ═══"
    echo "[$(date +%H:%M:%S)] [UPDATER] ok: $(basename "$MAN") → inbox" >> "$LOG"
done

echo ""
echo "═══ STATO INBOX ═══"
ls -lh "$INBOX"
