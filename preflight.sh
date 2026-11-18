#!/usr/bin/env bash
# AINABOX — Pre-flight Sistemi (v0.1a)
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
# ═══════════════════════════════════════════════════════════════
# preflight.sh — AINABOX v0.1a
# Bash-pure. No python nella logica. Primo respiro.
# Idempotente: 2ª chiamata → "Tutto presente." → exit 0.
# Chiamato da: ainabox-install (FASE 0) · apri_ainabox (FASE 0)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

MIN_SPACE_GB=45

# ─── 2 RAMI: root / non-root ───
if [ "$(id -u)" -eq 0 ]; then
    IPREFIX=""        # già root, installa diretto
else
    IPREFIX="pkexec"  # polkit dialog (non zenity)
fi

# ─── PACKAGE MANAGER ───
detect_pm() {
    if command -v apt-get  &>/dev/null; then echo "apt";    return 0; fi
    if command -v dnf      &>/dev/null; then echo "dnf";    return 0; fi
    if command -v pacman   &>/dev/null; then echo "pacman"; return 0; fi
    if command -v zypper   &>/dev/null; then echo "zypper"; return 0; fi
    return 1
}

# ─── SPAZIO ───
SPAZIO_GB=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
SPAZIO_GB="${SPAZIO_GB:-0}"

# ─── CHECK 6 SATELLITI (strato: sistema) ───
MISSING=()
EFFECTS=()

command -v zenity &>/dev/null || { MISSING+=("zenity");    EFFECTS+=("AINABOX non si apre"); }
command -v podman &>/dev/null || { MISSING+=("podman");    EFFECTS+=("Hermes non esegue comandi"); }
command -v ffmpeg &>/dev/null || { MISSING+=("ffmpeg");    EFFECTS+=("La voce non funziona"); }
command -v nft    &>/dev/null || { MISSING+=("nftables");  EFFECTS+=("Cintura rete non si applica"); }
python3 -c 'import sys; sys.exit(0 if sys.version_info>=(3,10) else 1)' 2>/dev/null \
    || { MISSING+=("python3");   EFFECTS+=("Cockpit + Hermes non partono"); }
detect_pm &>/dev/null          || { MISSING+=("package manager"); EFFECTS+=("Non si installa nulla"); }

# ─── DECISION TREE ───

# 1) SPAZIO INSUFFICIENTE → HARD STOP
if [ "$SPAZIO_GB" -lt "$MIN_SPACE_GB" ]; then
    if command -v zenity &>/dev/null; then
        zenity --error --title="AINABOX — Spazio" \
            --text="AINABOX ha bisogno di almeno ${MIN_SPACE_GB} GB liberi.\nNe hai ${SPAZIO_GB} GB.\n\nLibera spazio e riprova." \
            2>/dev/null || true
    fi
    echo "ERRORE: spazio insufficiente (${SPAZIO_GB} GB < ${MIN_SPACE_GB} GB)" >&2
    exit 1
fi

# 2) TUTTO PRESENTE → exit 0, ZERO finestre (idempotente)
if [ "${#MISSING[@]}" -eq 0 ]; then
    echo "Tutto presente."
    exit 0
fi

# 3) BOOTSTRAP ZENITY (fuori finestra: polkit, non zenity)
if ! command -v zenity &>/dev/null; then
    PM=$(detect_pm || true)
    if [ -z "$PM" ]; then
        echo "ERRORE: nessun package manager. Non posso installare zenity." >&2
        exit 1
    fi
    case "$PM" in
        apt)    $IPREFIX apt-get install -y zenity ;;
        dnf)    $IPREFIX dnf install -y zenity ;;
        pacman) $IPREFIX pacman -S --noconfirm zenity ;;
        zypper) $IPREFIX zypper install -y zenity ;;
    esac
    # Rimuovi zenity da MISSING (ora è installato)
    _m=() _e=()
    for i in "${!MISSING[@]}"; do
        if [ "${MISSING[$i]}" != "zenity" ]; then
            _m+=("${MISSING[$i]}")
            _e+=("${EFFECTS[$i]}")
        fi
    done
    MISSING=("${_m[@]:-}")
    EFFECTS=("${_e[@]:-}")
fi

# 4) ANCORA QUALCOSA MANCA → FINESTRA SÌ/NO
if [ "${#MISSING[@]}" -gt 0 ]; then
    TXT="Senza di esse AINABOX NON FUNZIONA:\n\n"
    for i in "${!MISSING[@]}"; do
        TXT="${TXT}  • ${MISSING[$i]} → ${EFFECTS[$i]}\n"
    done
    TXT="${TXT}\nTutti i satelliti sono obbligatori.\nNO = annulla l'installazione intera."

    RC=1
    zenity --question \
        --title="AINABOX — Verifica" \
        --text="$TXT" \
        --ok-label="SÌ, INSTALLA" \
        --cancel-label="ANNULLA" \
        2>/dev/null || RC=$?

    if [ "$RC" -ne 0 ]; then
        zenity --info --title="AINABOX" \
            --text="Installazione annullata. AINABOX non è installata." \
            2>/dev/null || true
        exit 0
    fi

    # SÌ → installa i mancanti
    PM=$(detect_pm || true)
    if [ -z "$PM" ]; then
        zenity --error --title="AINABOX" \
            --text="Errore: nessun package manager." 2>/dev/null || true
        exit 1
    fi
    PKGS=()
    for m in "${MISSING[@]}"; do
        case "$m" in
            podman)          PKGS+=("podman") ;;
            ffmpeg)          PKGS+=("ffmpeg") ;;
            nftables)        PKGS+=("nftables") ;;
            python3)
                case "$PM" in
                    pacman) PKGS+=("python" "python-pip") ;;
                    *)      PKGS+=("python3" "python3-pip") ;;
                esac ;;
            "package manager") : ;;
        esac
    done
    if [ "${#PKGS[@]}" -gt 0 ]; then
        case "$PM" in
            apt)    $IPREFIX apt-get install -y "${PKGS[@]}" ;;
            dnf)    $IPREFIX dnf install -y "${PKGS[@]}" ;;
            pacman) $IPREFIX pacman -S --noconfirm "${PKGS[@]}" ;;
            zypper) $IPREFIX zypper install -y "${PKGS[@]}" ;;
        esac
    fi
fi

echo "Preflight OK."
exit 0
