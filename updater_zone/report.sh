#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

# ==============================================================================
# UPDATER — REPORT (solo lettura, zero uscite cloud)
# Uso: bash $AIBOX/updater_zone/report.sh
# ==============================================================================
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null) || { echo "ERRORE: /etc/ainabox/dest assente" >&2; exit 1; }
WATCH="$AIBOX/updater_zone/watchlist.json"
INBOX="$AIBOX/updater_zone/inbox"
API="http://127.0.0.1:11434"

echo "═══ UPDATER REPORT ═══"
echo ""

# 1. Modelli locali (via API)
echo "📦 MODELLI LOCALI:"
curl -s "$API/api/tags" 2>/dev/null | python3 -c "
import sys,json
try:
    data=json.load(sys.stdin)
    for m in data.get('models',[]):
        name=m['name']
        size=round(m.get('details',{}).get('size',0)/1e9,2)
        print(f'   ✅ {name:40s} {size} GB')
except:
    print('   ❌ API non raggiungibile')
"
echo ""

# 2. Watchlist
echo "📋 WATCHLIST:"
python3 -c "
import json
with open('$WATCH') as f:
    items=json.load(f)
for item in items:
    print(f'   👁️  {item[\"model\"]:40s} {item.get(\"note\",\"\")}')
"
echo ""

# 3. Inbox (download attesi)
echo "📥 INBOX:"
if [ "$(ls -A "$INBOX" 2>/dev/null)" ]; then
    ls -lh "$INBOX" | tail -n +2 | sed 's/^/   /'
else
    echo "   (vuota)"
fi
echo ""

# 4. Stato Ollama
echo "🔋 OLLAMA:"
if curl -s "$API/api/version" >/dev/null 2>&1; then
    curl -s "$API/api/version" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'   v{d.get(\"version\",\"?\")}')"
else
    echo "   ❌ non raggiungibile"
fi
echo ""
echo "═══ FINE ═══"
