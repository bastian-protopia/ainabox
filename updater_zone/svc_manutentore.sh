#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

set -euo pipefail
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest assente" >&2; exit 1; }
LOG="$AIBOX/vetrina_zone/ainabox.log"
echo "[$(date +%H:%M:%S)] [MANUT] avvio" >> "$LOG"

INBOX="$AIBOX/updater_zone/inbox"

shopt -s nullglob
MANFALIST=( "$INBOX"/*.json )

if [ ${#MANFALIST[@]} -eq 0 ]; then
    echo "Nessun pacchetto in inbox. Niente da fare."
    echo "[$(date +%H:%M:%S)] [MANUT] nessun pacchetto — esito" >> "$LOG"
    exit 0
fi

for MAN in "${MANFALIST[@]}"; do
    echo "═══════════════════════════════════════════"
    echo "📋 $(basename "$MAN")"

    DEST=$(python3 -c "import json; print(json.load(open('$MAN')).get('destinazione',''))" 2>/dev/null || echo "")
    [ -z "$DEST" ] && { echo "  ⏭️  non è un manifesto — rimosso"; rm -f "$MAN"; continue; }
    LISTA=$(python3 -c "
import json
with open('$MAN') as f:
    m = json.load(f)
for e in m['file']:
    fn = e.get('file','') or e['url'].split('/')[-1]
    print(f\"{fn}|{e['sha256']}\")
")

    case "$DEST" in
        ollama_zone) DESTDIR="$AIBOX/modelli/ollama_modelli" ;;
        comfy_zone)
            DESTDIR="$AIBOX/comfy_zone/ComfyUI/models"
            SUB=$(python3 -c "import json; print(json.load(open('$MAN')).get('sottocartella',''))" 2>/dev/null || echo "")
            [ -n "$SUB" ] && DESTDIR="$DESTDIR/$SUB"
            mkdir -p "$DESTDIR"
            ;;
        engine_zone) DESTDIR="$AIBOX/engine_zone" ;;
        *)
            echo "  ❌ Destinazione sconosciuta: $DEST"
            rm -f "$MAN"
            continue
            ;;
    esac

    FAILED=0
    while IFS='|' read -r FILENAME SHA256; do
        [ -z "$FILENAME" ] && continue
        echo "  📦 $FILENAME"

        SRC="$INBOX/$FILENAME"
        if [ ! -f "$SRC" ]; then
            echo "  ❌ file non in inbox: $FILENAME"
            FAILED=1
            continue
        fi

        REAL=$(sha256sum "$SRC" | awk '{print $1}')
        if [ "$REAL" != "$SHA256" ]; then
            echo "  ❌ HASH DIVERSO — non installo"
            FAILED=1
            continue
        fi

        if [ -f "$DESTDIR/$FILENAME" ]; then
            ES=$(sha256sum "$DESTDIR/$FILENAME" | awk '{print $1}')
            if [ "$ES" = "$SHA256" ]; then
                echo "  ⏭️  già presente — skip"
                continue
            fi
        fi

        cp "$SRC" "$DESTDIR/$FILENAME"
        echo "  ✅ → $DESTDIR/$FILENAME"
        echo "[$(date +%H:%M:%S)] [MANUT] cp: $FILENAME → $DESTDIR" >> "$LOG"

    done <<< "$LISTA"

    if [ $FAILED -eq 1 ]; then
        echo "  ═══ FALLO — pacchetto resta in inbox ═══"
        continue
    fi

    while IFS='|' read -r FILENAME SHA256; do
        [ -z "$FILENAME" ] && continue
        rm -f "$INBOX/$FILENAME"
    done <<< "$LISTA"
    rm -f "$MAN"
    echo "  🗑️  inbox svuotata"
    echo "  ═══ OK ═══"
    echo "[$(date +%H:%M:%S)] [MANUT] ok: $(basename "$MAN")" >> "$LOG"
done

echo ""
echo "═══ STATO INBOX ═══"
ls -lh "$INBOX" 2>&1 || echo "(vuota)"
