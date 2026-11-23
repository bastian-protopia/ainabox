#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

# post_check.sh — MASTERMAP §13.5
# Torna 0 se tutto OK, 1 se qualcosa è down.
ok=0
curl -s -o /dev/null http://127.0.0.1:11434 || { echo "FAIL: Ollama"; ok=1; }
curl -s -o /dev/null http://127.0.0.1:3000  || { echo "FAIL: OWU"; ok=1; }
curl -s -o /dev/null http://127.0.0.1:8765  || { echo "FAIL: Vetrina"; ok=1; }
[ $ok -eq 0 ] && echo "POST-CHECK OK"
exit $ok
