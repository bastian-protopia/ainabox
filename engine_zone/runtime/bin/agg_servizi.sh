#!/bin/bash
# AINABOX — Nerdctl Wrapper (v0.1a)
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
# agg_servizi.sh — nerdctl wrapper (Colpo 5a)
export HOME=/home/$(whoami)
export XDG_RUNTIME_DIR=/run/user/$(id -u)
AIBOX=$(cat /etc/ainabox/dest 2>/dev/null || true)
[ -z "$AIBOX" ] && { echo "ERRORE: /etc/ainabox/dest assente o vuoto" >&2; exit 1; }
export PATH="$AIBOX/engine_zone/runtime/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
cd "$AIBOX"
exec "$AIBOX/engine_zone/runtime/bin/nerdctl" "$@"
