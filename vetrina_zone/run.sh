#!/bin/bash

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

set -euo pipefail
cd /mnt/ainabox/vetrina_zone
exec ./venv/bin/python main.py
