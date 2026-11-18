#!/usr/bin/env bash
# AINABOX — Installatore
# Copyright (C) 2026 Michele Canova bastian@ainabox.it
# Licensed under GPL-3.0-or-later
# Made by Bastian & Aina
set -uo pipefail

CURRENT_USER="$(whoami)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST=""
MODE="cartella"
DISCO=""
TARBALL=""
PASS1=""
PASS2=""
DISCO_UUID=""

# ── FUNZIONI ──
rileva_distro() { . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "$(uname -s)"; }
rileva_gpu() {
  if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1
  elif [ -e /dev/kfd ] && [ -e /dev/dri ]; then
    echo "GPU AMD (sperimentale)"
  else
    echo "CPU-only"
  fi
}
rileva_ram() { free -g | awk '/^Mem:/{print $2" GB"}'; }
rileva_dischi() {
  lsblk --bytes -P -d -n -o NAME,SIZE,MODEL,TYPE 2>/dev/null | while IFS= read -r line; do
    local name size model type
    name=$(echo "$line" | sed -n 's/.*NAME="\([^"]*\)".*/\1/p')
    size=$(echo "$line" | sed -n 's/.*SIZE="\([^"]*\)".*/\1/p')
    model=$(echo "$line" | sed -n 's/.*MODEL="\([^"]*\)".*/\1/p')
    type=$(echo "$line" | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
    [ "$type" != "disk" ] && continue
    local gb=$((size / 1073741824))
    [ "$gb" -le 0 ] && continue
    printf "%s (%s, %d GB)\n" "$name" "$model" "$gb"
  done
}

# ── PHASE 0: PREAMBOLO ──
PKG=""
command -v apt-get 2>/dev/null && PKG="apt-get"
command -v dnf 2>/dev/null && PKG="dnf"
command -v pacman 2>/dev/null && PKG="pacman"
command -v zypper 2>/dev/null && PKG="zypper"
if [ -z "$PKG" ]; then
    echo "ERRORE: Distro non supportata."
    exit 1
fi
pkg_install() {
    case "$PKG" in
        pacman) pkexec pacman -S --noconfirm "$@" ;;
        dnf)    pkexec dnf install -y "$@" ;;
        zypper) pkexec zypper install -y "$@" ;;
        *)      pkexec apt-get install -y "$@" ;;
    esac
}

# ── FASE 0: PREFLIGHT (bash-pure, idempotente) ──
_INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$_INSTALL_DIR/preflight.sh" ]; then
    bash "$_INSTALL_DIR/preflight.sh" || exit $?
fi

# --- GPU: rileva + opt-in toolkit (FIX MORSO 2: ls, non [ -d glob ]) ---
if ls /dev/nvidia* 2>/dev/null | grep -q . || command -v nvidia-smi &>/dev/null; then
    if command -v nvidia-ctk &>/dev/null; then
        [ -f /etc/cdi/nvidia.yaml ] || nvidia-ctk cdi generate --output /etc/cdi/nvidia.yaml 2>/dev/null || true
    else
        zenity --question --title="AINABOX" \
          --text="GPU NVIDIA rilevata.\n\nInstallare il toolkit GPU per abilitare l'accelerazione? (~50 MB)\nSe No, AINABOX funzionerà in CPU." \
          --ok-label="Installa GPU" --cancel-label="CPU-only" 2>/dev/null && {
            pkg_install nvidia-container-toolkit
            nvidia-ctk cdi generate --output /etc/cdi/nvidia.yaml 2>/dev/null || true
        }
    fi
fi

DISTRO="$(rileva_distro)"
GPU="$(rileva_gpu)"
RAM="$(rileva_ram)"

# ═══ FINESTRA 1: scelta modalità (FIX R2: --list --radiolist, zero RC 10) ═══
# ═══ FINESTRA 2: DOVE ═══
SELEZIONE=$(zenity --list --title="AINABOX — Dove" \
  --text="Vuoi installare AINABOX nel computer,\noppure su un disco esterno con cifratura dei dati?" \
  --column="Dove" \
  "COMPUTER" \
  "SSD ESTERNO" 2>/dev/null)
RC=$?
if [ $RC -ne 0 ]; then exit 0; fi
case "$SELEZIONE" in
  *SSD*|*esterno*|*ESTERNO*) MODE="luks" ;;
  *) MODE="cartella" ;;
esac
if [ "$MODE" = "cartella" ]; then
    PROT_RC=1
    zenity --question --title="AINABOX — Pannello" \
      --text="Installo in /opt/ainabox.\n\nVuoi una password per accedere al pannello?\n(Se NO, l'accesso è aperto in rete locale.)" \
      --ok-label="SÌ, PROTEGGI" --cancel-label="NO, VAI" 2>/dev/null || PROT_RC=$?
    if [ $PROT_RC -eq 0 ]; then
        PASS1="$(zenity --entry --title="Password" --hide-text --text="Digita una password. Scrivila su carta." --ok-label="OK" 2>/dev/null)"
        [ -z "$PASS1" ] && PASS1=""
        PASS2="$(zenity --entry --title="Conferma" --hide-text --text="Ripeti la password:" --ok-label="OK" 2>/dev/null)"
        [ -z "$PASS2" ] && PASS2=""
        [ "$PASS1" != "$PASS2" ] && { zenity --error --title="AINABOX" --text="Le password non coincidono."; exit 1; }
    else
        PASS1=""
    fi
    DEST="/opt/ainabox"
    AVAIL="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')"; AVAIL="${AVAIL:-0}"
    [ "$AVAIL" -lt 45 ] && { zenity --error --title="AINABOX — Spazio" --text="AINABOX ha bisogno di almeno 45 GB liberi.\nNe hai ${AVAIL} GB.\n\nLibera spazio e riprova."; exit 1; }
else
    DISCO_NAME="$(rileva_dischi | zenity --list --title="Disco" --text="Scegli un disco:" --column="Disco" --hide-header 2>/dev/null)"
    [ -z "$DISCO_NAME" ] && exit 0
    DISCO_NAME="${DISCO_NAME%% (*}"
    DISCO="/dev/$DISCO_NAME"
    DISCO_LABEL="$(lsblk -dno MODEL "/dev/$DISCO_NAME" 2>/dev/null | xargs || echo 'disco')"
    CONF_RC=1
    zenity --question --title="⚠️ FORMATTAZIONE" \
      --text="STAI PER FORMATTARE:\n/dev/$DISCO_NAME ($DISCO_LABEL)\n\nTutti i dati su questo disco saranno persi.\nQuesta operazione è IRREVERSIBILE." \
      --ok-label="SÌ, FORMATTA" --cancel-label="ANNULLA" 2>/dev/null ; CONF_RC=$?
    if [ $CONF_RC -ne 0 ]; then
        zenity --info --title="AINABOX" --text="Annullato. Nessun disco è stato toccato." 2>/dev/null || true
        exit 0
    fi
    DEST="/mnt/Data"
    AVAIL="$(lsblk --bytes -o SIZE -dn "/dev/$DISCO_NAME" 2>/dev/null | awk '{print int($1/1073741824)}')"; [ -z "$AVAIL" ] && AVAIL=0
    [ "${AVAIL:-0}" -lt 45 ] && { zenity --error --title="AINABOX" --text="Disco troppo piccolo (<45 GB)."; exit 1; }
    PASS1="$(zenity --entry --title="Password" --hide-text --text="Scegli una passphrase per proteggere il disco\ne l'accesso al pannello.\n\n⚠️ Questa è l'UNICA chiave.\nSe la perdi, i dati sono persi.\nScrivila su carta." --ok-label="OK" 2>/dev/null)"
    [ -z "$PASS1" ] && exit 0
    PASS2="$(zenity --entry --title="Conferma" --hide-text --text="Ripeti la passphrase:" --ok-label="OK" 2>/dev/null)"
    [ -z "$PASS2" ] && exit 0
    [ "$PASS1" != "$PASS2" ] && { zenity --error --title="AINABOX" --text="Le passphrase non coincidono."; exit 1; }
    DISCO_UUID="$(blkid -s UUID -o value "$DISCO" 2>/dev/null)"
fi

# ═══ FINESTRA 3: MODELLI ═══
MODELLI="no"
zenity --question --title="AINABOX — Modelli AI" \
  --text="Vuoi scaricare i modelli AI? (~15.5 GB)\nCHAT (Qwen) · GRAFICA (SD1.5) · VOCALE (Paola)\n\nSe NO, li scarichi quando vuoi dal pannello." \
  --ok-label="SÌ, TUTTI" --cancel-label="NO, DOPO" 2>/dev/null && MODELLI="si" || true

# ═══ IL FILM (1 finestra, testo cambia, 0 bottoni, X=annulla) [5 §1] ═══
FILM_PID=""
film() {
    [ -n "$FILM_PID" ] && kill "$FILM_PID" 2>/dev/null && wait "$FILM_PID" 2>/dev/null
    zenity --progress --title="AINABOX" --text="$1" --pulsate &
    FILM_PID=$!
}
film_end() {
    [ -n "$FILM_PID" ] && kill "$FILM_PID" 2>/dev/null && wait "$FILM_PID" 2>/dev/null
    FILM_PID=""
}
film "Scaricando AINABOX…"
# ── PHASE 2: TARBALL ──
TARBALL="$SCRIPT_DIR/ainabox-pkg.tar.gz"
if [ ! -f "$TARBALL" ]; then
    TARBALL="/tmp/ainabox-pkg.tar.gz"
    curl -fL --progress-bar -o "$TARBALL" "https://github.com/bastian-protopia/ainabox/releases/latest/download/ainabox-pkg.tar.gz" 2>/dev/null \
        || curl -fL --progress-bar -o "$TARBALL" "https://www.ainabox.it/ainabox-pkg.tar.gz" 2>/dev/null \
        || { zenity --error --title="AINABOX" --text="Download tarball fallito.\nVerifica la connessione e riprova."; exit 1; }
fi
SHA_FILE="${TARBALL}.sha256"
if [ -f "$SHA_FILE" ]; then
    echo "$(awk '{print $1}' "$SHA_FILE")  $(basename "$TARBALL")" | sha256sum --check - 2>/dev/null \
        || { zenity --error --title="AINABOX" --text="SHA256 non verificato.\nIl tarball potrebbe essere corrotto."; exit 1; }
fi



# ═══ PHASE 3: CONFIGURAZIONE (pkexec unico — R11) ═══
cat > /tmp/ainabox-root.sh << 'ROOTSCRIPT'
#!/bin/bash
set -euo pipefail
DEST="$1"; MODE="$2"; CUR="$3"; DISCO="${4:-}"; PASS1="${5:-}"; DISCO_UUID="${6:-}"; TARBALL="${7:?}"
if [ "$MODE" = "luks" ]; then
    printf '%s' "$PASS1" | cryptsetup luksFormat --type luks2 --hash sha256 --iter-time 2000 --batch-mode "$DISCO"
    printf '%s' "$PASS1" | cryptsetup luksOpen "$DISCO" ainabox --key-file=/dev/stdin
    mkfs.ext4 -F /dev/mapper/ainabox
    mkdir -p /etc/luks-keys
    dd if=/dev/urandom of=/etc/luks-keys/ainabox.key bs=512 count=1
    chmod 600 /etc/luks-keys/ainabox.key
    printf '%s' "$PASS1" | cryptsetup luksAddKey --batch-mode "$DISCO" /etc/luks-keys/ainabox.key
    mkdir -p /mnt/Data
    mount /dev/mapper/ainabox /mnt/Data
fi
mkdir -p "$DEST"
tar xzf "$TARBALL" -C "$DEST"
[ -d "$DEST/engine_zone" ] || { echo "ESTRAZIONE_INCOMPLETA"; exit 1; }
if [ "$MODE" = "cartella" ]; then
    if [ ! -e /mnt/Data ] || [ -L /mnt/Data ]; then
        rm -f /mnt/Data 2>/dev/null || true
        ln -sfn "$DEST" /mnt/Data
    fi
fi
mkdir -p /etc/ainabox
echo "$MODE" > /etc/ainabox/mode
echo "$DEST" > /etc/ainabox/dest
chmod 644 /etc/ainabox/dest
if [ "$MODE" = "luks" ]; then
    printf "UUID=%s\nMAPPER=ainabox\nKEYFILE=/etc/luks-keys/ainabox.key\n" "${DISCO_UUID:-$(blkid -s UUID -o value "$DISCO" 2>/dev/null)}" > /etc/ainabox/luks
fi
cat > /etc/sudoers.d/ainabox << SUDO
${CUR} ALL=(root) NOPASSWD: /usr/bin/bash /usr/local/bin/apri_ainabox
${CUR} ALL=(root) NOPASSWD: /usr/bin/bash /usr/local/bin/disconnetti_ainabox
${CUR} ALL=(root) NOPASSWD: /usr/bin/bash /usr/local/bin/avvia_servizio.sh *
${CUR} ALL=(root) NOPASSWD: /usr/bin/bash /usr/local/bin/ainabox_fase37 *
${CUR} ALL=(root) NOPASSWD: /usr/bin/bash /usr/local/bin/ainabox_hermes_link *
${CUR} ALL=(root) NOPASSWD: /usr/bin/bash /usr/local/bin/ainabox_placement *
SUDO
chmod 440 /etc/sudoers.d/ainabox
visudo -cf /etc/sudoers.d/ainabox
ln -sfn "$DEST/engine_zone/apri_ainabox" /usr/local/bin/apri_ainabox
ln -sfn "$DEST/engine_zone/disconnetti_ainabox" /usr/local/bin/disconnetti_ainabox
ln -sfn "$DEST/installer/ainabox-uninstall.sh" /usr/local/bin/ainabox-uninstall
ln -sfn "$DEST/engine_zone/bin/avvia_servizio.sh" /usr/local/bin/avvia_servizio.sh
ln -sfn "$DEST/installer/ainabox_fase37.sh" /usr/local/bin/ainabox_fase37
cat > /usr/local/bin/ainabox_hermes_link << 'HL'
#!/bin/bash
DEST="${1:-/opt/ainabox}"
if id svc_hermes &>/dev/null; then
    mkdir -p /home/svc_hermes/.hermes
    ln -sf "$DEST/hermes_zone/config.yaml" /home/svc_hermes/.hermes/config.yaml
    chown svc_hermes:ai_services /home/svc_hermes/.hermes/config.yaml
fi
HL
chmod 755 /usr/local/bin/ainabox_hermes_link
cat > /usr/local/bin/ainabox_placement << 'PL'
#!/bin/bash
SD_FILE="$1"; SD_OK="$2"
PAOLA_DIR="$3"; PAOLA_HASH="$4"; PAOLA_OK="$5"
[ "$SD_OK" = "1" ] && { mkdir -p "$(dirname "$SD_FILE")" && cp /tmp/SD1.5.safetensors "$SD_FILE" && echo "SD1.5: ✅"; }
[ "$PAOLA_OK" = "1" ] && {
    mkdir -p "$PAOLA_DIR/blobs" "$PAOLA_DIR/snapshots/$PAOLA_HASH" "$PAOLA_DIR/refs"
    for _f in model.onnx config.json README.md .gitattributes; do
        _b=$(sha256sum "/tmp/paola_$_f" | awk '{print $1}')
        cp "/tmp/paola_$_f" "$PAOLA_DIR/blobs/$_b"
        ln -sf "../../blobs/$_b" "$PAOLA_DIR/snapshots/$PAOLA_HASH/$_f"
    done
    printf '%s' "$PAOLA_HASH" > "$PAOLA_DIR/refs/main"
    echo "Paola: ✅"
}
PL
chmod 755 /usr/local/bin/ainabox_placement
if [ -n "$PASS1" ]; then
    TOKEN=$(echo -n "$PASS1" | openssl dgst -sha256 -hmac "ainabox_vetrina_v1" | awk '{print $NF}')
    mkdir -p "$DEST/updater_zone/.secrets"
    echo -n "$TOKEN" > "$DEST/updater_zone/.secrets/VETRINA_TOKEN"
    chmod 600 "$DEST/updater_zone/.secrets/VETRINA_TOKEN"
# FASE 3.7b: HERMES (app + config) — sandbox/chown delegati a apri_ainabox (root)
# ═══════════════════════════════════════════════
echo ""
echo "── FASE 3.7b: Hermes ──"
film "Configurando Hermes…" 2>/dev/null || true
_HLOG="/tmp/ainabox-hermes-install.log"
FAILURES="${FAILURES:-0}"
# ── 1. Download app Python (~400 MB) ──
echo "  Scarico Hermes app (~400 MB)…"
curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o /tmp/hermes_install.sh >> "$_HLOG" 2>&1
RC_CURL=$?
if [ $RC_CURL -ne 0 ]; then
    echo "  [ERRORE] curl install.sh fallito (exit $RC_CURL)."
    FAILURES=$((FAILURES + 1))
else
    # stdin chiuso: install.sh non aspetta input umano. App si scarica comunque.
    HERMES_HOME="$DEST/hermes_zone/.hermes" HOME="$DEST/hermes_zone" bash /tmp/hermes_install.sh < /dev/null >> "$_HLOG" 2>&1
    RC_HERMES=$?
    rm -f /tmp/hermes_install.sh
    if [ $RC_HERMES -ne 0 ]; then
        echo "  [ERRORE] install.sh fallito (exit $RC_HERMES)."
        FAILURES=$((FAILURES + 1))
    else
        echo "  [ok] Hermes app installata."
    fi
fi
# ── 2. Config yaml (6 valori, 7 righe) ──
mkdir -p "$DEST/hermes_zone/.hermes"
cat > "$DEST/hermes_zone/.hermes/config.yaml" << 'YAML'
model:
  default: hermes3-8b-64k
  provider: custom
  base_url: http://127.0.0.1:11434/v1
  context_length: 65536
terminal:
  backend: docker
streaming: false
YAML
echo "  [ok] Config yaml (6 valori)."
# ── 3. Sandbox + chown: delegati a apri_ainabox (FASE 4.2 root + FASE 2 root) ──
echo "  [ok] Sandbox + chown: delegati a apri_ainabox (root)."
# ── 4. Verifica ──
echo "  Verifica:"
echo "    yaml: $(grep -c 'hermes3-8b-64k\|provider: custom\|127.0.0.1:11434\|backend: docker\|streaming: false' "$DEST/hermes_zone/.hermes/config.yaml" 2>/dev/null) / 5 valori"
echo "    hermes bin: $(ls "$DEST/hermes_zone/.hermes/hermes-agent/.hermes/bin/hermes" 2>/dev/null && echo presente || echo assente)"
film_end 2>/dev/null || true
echo "  ✅ Hermes app + yaml pronti."
fi
chown -R "$CUR" "$DEST"
# --- VENV GUARD (universale: Python 3.10, 3.11, 3.12, 3.13) ---
VENV="$DEST/vetrina_zone/venv"
if ! $VENV/bin/python3 -c "import fastapi, uvicorn, requests" 2>/dev/null; then
  echo "[Install] Venv non compatibile con Python locale. Ricreo..."
  rm -rf "$VENV"
  /usr/bin/python3 -m venv "$VENV"
  $VENV/bin/pip install --quiet -r "$DEST/vetrina_zone/requirements.txt"
  chown -R "$CUR" "$VENV"
  echo "[Install] Venv riparato."
fi
echo "$CUR" > "$DEST/vetrina_zone/.current_user"
ROOTSCRIPT
chmod +x /tmp/ainabox-root.sh
film "Configurando…" 2>/dev/null || true
pkexec bash -x /tmp/ainabox-root.sh 2>/tmp/ainabox-root.log "$DEST" "$MODE" "$CURRENT_USER" "${DISCO:-}" "${PASS1:-}" "${DISCO_UUID:-}" "$TARBALL" \
    || { zenity --error --title="AINABOX" --text="Configurazione fallita.\nControlla i permessi e riprova."; exit 1; }
rm -f /tmp/ainabox-root.sh

# --- ICONE (anylinux: rileva la cartella desktop vera) ---
if [ -f "$HOME/.config/user-dirs.dirs" ]; then
  . "$HOME/.config/user-dirs.dirs"
  DESK="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
else
  DESK="$HOME/Desktop"
fi
mkdir -p "$DESK"
cp "$DEST/ainabox-apri.desktop" "$DESK/" 2>/dev/null
cp "$DEST/ainabox-disconnetti.desktop" "$DESK/" 2>/dev/null
chmod +x "$DESK"/ainabox-*.desktop 2>/dev/null
install -m 755 "$DEST/engine_zone/bin/apri_ainabox_icon" /usr/local/bin/apri_ainabox_icon 2>/dev/null || true
# Icon= nei .desktop desktop
for f in "$DESK"/ainabox-*.desktop; do
  [ -f "$f" ] && grep -q '^Icon=' "$f" || echo "Icon=ainabox" >> "$f"
done
mkdir -p "$HOME/.local/share/applications"
cp "$DEST/ainabox-apri.desktop" "$HOME/.local/share/applications/" 2>/dev/null
cp "$DEST/ainabox-disconnetti.desktop" "$HOME/.local/share/applications/" 2>/dev/null
cp "$DEST/ainabox-uninstall.desktop" "$HOME/.local/share/applications/" 2>/dev/null
for f in "$HOME/.local/share/applications"/ainabox-*.desktop; do
    [ -f "$f" ] && { grep -q "Categories=" "$f" || echo "Categories=Office;" >> "$f"; }
done
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$ICON_DIR"
cp "$DEST/AINABOX_logo.svg" "$ICON_DIR/ainabox.svg" 2>/dev/null
for f in "$DESK"/ainabox-*.desktop; do
    gio set "$f" metadata::trusted true 2>/dev/null || true
done
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true

# --- Obsidian XDG (O1) ---
OBSIDIAN="$DEST/Obsidian/Obsidian.AppImage"
if [ -f "$OBSIDIAN" ]; then
    chmod +x "$OBSIDIAN"
    mkdir -p "$HOME/.local/share/applications" "$HOME/.config/obsidian"
    printf '[Desktop Entry]\nType=Application\nName=Obsidian\nExec=%s %%u\nTerminal=false\nMimeType=x-scheme-handler/obsidian;\n' "$OBSIDIAN" > "$HOME/.local/share/applications/obsidian.desktop"
    xdg-mime default obsidian.desktop x-scheme-handler/obsidian 2>/dev/null || true
    chown "$CURRENT_USER":"$CURRENT_USER" "$HOME/.config/obsidian" 2>/dev/null || true
fi
film "Accensione…" 2>/dev/null || true

# ═══ PHASE 3.5: ACCENSIONE (obbligatoria) ═══
sudo bash /usr/local/bin/apri_ainabox 2>/dev/null \
    || { zenity --error --title="AINABOX" --text="Accensione fallita."; exit 1; }
sleep 5

echo "$CURRENT_USER" > "$DEST/vetrina_zone/.current_user" 2>/dev/null || true
# ── FASE 3.6: CHECK sandbox (caricata da apri_ainabox FASE 4.2) ──
if [ -f $DEST/.sandbox_loaded ]; then
    echo "  [ok] Immagine sandbox caricata."
else
    echo "  [!] Immagine sandbox non caricata."
    zenity --error --title="AINABOX" --text="Immagine sandbox non caricata." 2>/dev/null
fi
film "Scaricando servizi… (Ollama, WebUI, ComfyUI, Voce)" 2>/dev/null || true
# ── FASE 3.7: SCARICANDO SERVIZI (1 pkexec root, 0 drop, 0 band-aid) ──
echo ""
echo "══ FASE 3.7: Scaricando servizi ══"
sudo bash /usr/local/bin/ainabox_fase37 "$DEST"
_F37_RC=$?
if [ $_F37_RC -ne 0 ]; then
    zenity --error --title="AINABOX" --text="⚠️ FASE 3.7: download falliti.
Log: /tmp/ainabox-install.log
Rilancia l'installer per riprovare.
I download già completati verranno saltati." 2>/dev/null || true
    exit 1
fi
echo ""
echo "  ✅ Servizi pronti."

# ═══════════════════════════════════════════════
echo "  ✅ Hermes pronto."
# ═══ PHASE 4: MODELLI (se FINESTRA 3 = SÌ) ═══
if [ "$MODELLI" = "si" ]; then
    film "Scaricando modelli… (Qwen, SD1.5, Paola)" 2>/dev/null || true

        # FIX: accendi Ollama+OWU (bootstrap crea infra, non li avvia)
        sudo bash /usr/local/bin/avvia_servizio.sh testuale 2>/dev/null || true
        sleep 12

        # Polling oracolo (C16: "✅" ≠ UP)
        OLLAMA_UP=0
        for i in $(seq 1 45); do
            curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1 && OLLAMA_UP=1 && break
            sleep 2
        done
        [ "$OLLAMA_UP" -eq 0 ] && { zenity --error --title="AINABOX" --text="Ollama non si è avviato."; exit 1; }

        # ═══ MODELLI (log + polling + permessi) ═══
        LOG="$DEST/vetrina_zone/ainabox.log"
        _mlog() { echo "[$(date +%H:%M:%S)] [Modelli] $1" >> "$LOG" 2>/dev/null || true; }

        # 1/4: hermes3 (AGENTE) — polling oracolo
        if curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q "hermes3"; then
            _mlog "hermes3: già presente"
        else
            _mlog "hermes3: pull avviato (~4.6 GB)"
            curl -s -X POST http://127.0.0.1:11434/api/pull \
              -H "Content-Type: application/json" -d '{"name":"hermes3:8b"}' 2>/dev/null
            _up=0; for _i in $(seq 1 120); do
                curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q "hermes3" && _up=1 && break
                sleep 5
            done
            if [ "$_up" -eq 1 ]; then _mlog "hermes3: ✅ OK"
            else _mlog "hermes3: ❌ FALLITO"
                 zenity --error --title="AINABOX" --text="Modello AGENTE (hermes3) non scaricato.\nScaricalo dal cockpit: Accendi AGENTE." 2>/dev/null; fi
        fi

        # 1b/4: variante 64k (condivide pesi, zero GB extra)
        if curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q "hermes3-8b-64k"; then
            _mlog "hermes3-8b-64k: già presente"
        else
            _mlog "hermes3-8b-64k: creazione variante 64k"
            curl -s http://127.0.0.1:11434/api/create \
              -d '{"name":"hermes3-8b-64k","from":"hermes3:8b","parameters":{"num_ctx":65536}}' 2>/dev/null
            _mlog "hermes3-8b-64k: ✅ creata"
        fi
        # Symlink config Hermes → single source of truth
        if id svc_hermes &>/dev/null; then
            sudo bash /usr/local/bin/ainabox_hermes_link "$DEST" 2>/dev/null
            _mlog "hermes config symlink: ✅"
        fi
        # 2/4: qwen25vl (CHAT) — polling oracolo (6.8 GB, max 15 min)
        if curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q "qwen2.5vl"; then
            _mlog "qwen25vl: già presente"
        else
            _mlog "qwen25vl: pull avviato (~6.8 GB)"
            curl -s -X POST http://127.0.0.1:11434/api/pull \
              -H "Content-Type: application/json" -d '{"name":"qwen2.5vl:7b"}' 2>/dev/null
            _up=0; for _i in $(seq 1 180); do
                curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q "qwen2.5vl" && _up=1 && break
                sleep 5
            done
            if [ "$_up" -eq 1 ]; then _mlog "qwen25vl: ✅ OK"
            else _mlog "qwen25vl: ❌ FALLITO"
                 zenity --error --title="AINABOX" --text="Modello CHAT (qwen25vl) non scaricato.\nScaricalo dal cockpit: Accendi CHAT." 2>/dev/null; fi
        fi

        # 3/4 + 4/4: SD1.5 + Paola (download → placement pkexec)
        SD_OK=0; PAOLA_OK=0
        SD_FILE="$DEST/comfy_zone/ComfyUI/models/checkpoints/v1-5-pruned-emaonly.safetensors"
        PAOLA_DIR="$DEST/speaches_zone/models/hub/models--speaches-ai--piper-it_IT-paola-medium"
        PAOLA_HASH="a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"

        # 3/4: SD1.5 download (~4 GB)
        if [ ! -f "$SD_FILE" ]; then
            _mlog "SD1.5: download (~4 GB)"
            if curl -L --retry 2 -o /tmp/SD1.5.safetensors \
              "https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors" 2>/dev/null; then
                SD_OK=1; _mlog "SD1.5: download ok"
            else
                _mlog "SD1.5: ❌ download fallito"
                zenity --error --title="AINABOX" --text="Modelli GRAFICA (SD1.5) download fallito.\nScaricalo dal cockpit: Accendi GRAFICA." 2>/dev/null
            fi
        else
            _mlog "SD1.5: già presente"
        fi

        # 4/4: Paola download (61 MB)
        if [ ! -f "$PAOLA_DIR/refs/main" ]; then
            _mlog "Paola: download (61 MB)"
            PAOLA_DL_OK=1
            for _f in model.onnx config.json README.md .gitattributes; do
                curl -sL --retry 2 -o "/tmp/paola_$_f" \
                  "https://huggingface.co/speaches-ai/piper-it_IT-paola-medium/resolve/main/$_f" 2>/dev/null || PAOLA_DL_OK=0
            done
            if [ "$PAOLA_DL_OK" -eq 1 ]; then PAOLA_OK=1; _mlog "Paola: download ok"
            else _mlog "Paola: ❌ download fallito"
                 zenity --error --title="AINABOX" --text="Voce IT (Paola) download fallito.\nScaricala dal cockpit." 2>/dev/null; fi
        else
            _mlog "Paola: già presente"
        fi

        # Placement (UNO pkexec — permessi svc_comfy + svc_speaches)
        if [ "$SD_OK" -eq 1 ] || [ "$PAOLA_OK" -eq 1 ]; then
            _PL=$(mktemp /tmp/ainabox-place-XXXXXX)
            cat > "$_PL" << 'PLC'
#!/bin/bash
SD_FILE="$1"; SD_OK="$2"
PAOLA_DIR="$3"; PAOLA_HASH="$4"; PAOLA_OK="$5"
[ "$SD_OK" = "1" ] && { mkdir -p "$(dirname "$SD_FILE")" && cp /tmp/SD1.5.safetensors "$SD_FILE" && echo "SD1.5: ✅"; }
[ "$PAOLA_OK" = "1" ] && {
    mkdir -p "$PAOLA_DIR/blobs" "$PAOLA_DIR/snapshots/$PAOLA_HASH" "$PAOLA_DIR/refs"
    for _f in model.onnx config.json README.md .gitattributes; do
        _b=$(sha256sum "/tmp/paola_$_f" | awk '{print $1}')
        cp "/tmp/paola_$_f" "$PAOLA_DIR/blobs/$_b"
        ln -sf "../../blobs/$_b" "$PAOLA_DIR/snapshots/$PAOLA_HASH/$_f"
    done
    printf '%s' "$PAOLA_HASH" > "$PAOLA_DIR/refs/main"
    echo "Paola: ✅"
}
PLC
            chmod 700 "$_PL"
            sudo bash /usr/local/bin/ainabox_placement "$SD_FILE" "$SD_OK" "$PAOLA_DIR" "$PAOLA_HASH" "$PAOLA_OK" 2>/dev/null
            _mlog "Placement: $( [ $? -eq 0 ] && echo "✅ OK" || echo "❌ FALLITO" )"
            rm -f "$_PL" /tmp/SD1.5.safetensors /tmp/paola_* 2>/dev/null
        fi

fi

# ═══ PHASE 5: FINESTRA 5 ═══
MSG="AINABOX INSTALLATA
Apri: http://127.0.0.1:8765
Le icone sono sul desktop e nel menu."
[ "$MODE" = "luks" ] && MSG="$MSG
La passphrase è l'unica chiave.
Scrivila su carta."

film_end 2>/dev/null || true
RC5=$(zenity --info --title="Fatto" --text="$MSG" \
  --ok-label="APRI AINABOX" --extra-button="CHIUDI" 2>/dev/null)
RC5=$?

if [ $RC5 -eq 0 ]; then
    if ! curl -s http://127.0.0.1:8765/ > /dev/null 2>&1; then
        sudo bash /usr/local/bin/apri_ainabox &
        sleep 15
    fi
    xdg-open "http://127.0.0.1:8765" 2>/dev/null || true
fi

exit 0
