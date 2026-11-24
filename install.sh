#!/usr/bin/env bash
# Sofabox - turns an old Debian/Ubuntu/Mint laptop into a TV streaming box:
#   - Kodi starts full screen at boot (no desktop needed)
#   - qBittorrent runs in the background with a web UI you open from your phone
#   - the torrent download folder shows up in Kodi under Videos
#   - closing the laptop lid does not suspend it
#
# Usage:  sudo bash install.sh [username]
#   or:   curl -fsSL https://raw.githubusercontent.com/DjNysa/sofabox/main/install.sh | sudo bash
#   username defaults to the user who ran sudo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this with sudo:  sudo bash $0" >&2
  exit 1
fi

BOX_USER="${1:-${SUDO_USER:-}}"
if [[ -z "$BOX_USER" || "$BOX_USER" == "root" ]]; then
  echo "Give the normal (non-root) user that should run Kodi:  sudo bash $0 pedro" >&2
  exit 1
fi
id "$BOX_USER" >/dev/null 2>&1 || { echo "User $BOX_USER does not exist." >&2; exit 1; }

BOX_HOME="$(getent passwd "$BOX_USER" | cut -d: -f6)"
DL_DIR="$BOX_HOME/Downloads/Torrents"
WEBUI_PORT="${WEBUI_PORT:-8080}"
WEBUI_USER="${WEBUI_USER:-admin}"

if ! command -v apt-get >/dev/null; then
  echo "This script needs a Debian/Ubuntu-based system (apt)." >&2
  exit 1
fi

# --- Web UI password -------------------------------------------------------
if [[ -z "${WEBUI_PASS:-}" ]]; then
  while true; do
    read -rsp "Choose a password for the torrent web UI (min 6 chars): " WEBUI_PASS </dev/tty; echo
    read -rsp "Repeat it: " p2 </dev/tty; echo
    [[ "$WEBUI_PASS" == "$p2" && ${#WEBUI_PASS} -ge 6 ]] && break
    echo "Passwords did not match or were too short, try again."
  done
fi

echo "==> Installing packages (Kodi, qBittorrent-nox, minimal X server)"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  kodi qbittorrent-nox \
  xserver-xorg xinit x11-xserver-utils dbus-x11 \
  alsa-utils pulseaudio python3

usermod -aG audio,video,input,render "$BOX_USER" 2>/dev/null || usermod -aG audio,video,input "$BOX_USER"

# --- Download folder -------------------------------------------------------
echo "==> Creating download folder $DL_DIR"
install -d -o "$BOX_USER" -g "$BOX_USER" "$BOX_HOME/Downloads" "$DL_DIR" "$DL_DIR/.incomplete"

# --- qBittorrent config ----------------------------------------------------
echo "==> Configuring qBittorrent (web UI on port $WEBUI_PORT)"
QB_DIR="$BOX_HOME/.config/qBittorrent"
install -d -o "$BOX_USER" -g "$BOX_USER" "$BOX_HOME/.config" "$QB_DIR"
[[ -f "$QB_DIR/qBittorrent.conf" ]] && cp "$QB_DIR/qBittorrent.conf" "$QB_DIR/qBittorrent.conf.bak.$(date +%s)"

PBKDF2="$(WEBUI_PASS="$WEBUI_PASS" python3 -I -c '
import base64, hashlib, os
salt = os.urandom(16)
key = hashlib.pbkdf2_hmac("sha512", os.environ["WEBUI_PASS"].encode(), salt, 100000)
print("@ByteArray(%s:%s)" % (base64.b64encode(salt).decode(), base64.b64encode(key).decode()))
')"

cat > "$QB_DIR/qBittorrent.conf" <<CONF
[LegalNotice]
Accepted=true

[BitTorrent]
Session\\DefaultSavePath=$DL_DIR
Session\\TempPath=$DL_DIR/.incomplete
Session\\TempPathEnabled=true
Session\\AddExtensionToIncompleteFiles=true

[Preferences]
Downloads\\SavePath=$DL_DIR/
Downloads\\TempPath=$DL_DIR/.incomplete/
Downloads\\TempPathEnabled=true
WebUI\\Enabled=true
WebUI\\Port=$WEBUI_PORT
WebUI\\Username=$WEBUI_USER
WebUI\\Password_PBKDF2="$PBKDF2"
WebUI\\LocalHostAuth=true
WebUI\\CSRFProtection=true
CONF
chown "$BOX_USER:$BOX_USER" "$QB_DIR/qBittorrent.conf"
chmod 600 "$QB_DIR/qBittorrent.conf"

cat > /etc/systemd/system/sofabox-torrent.service <<UNIT
[Unit]
Description=qBittorrent (headless, web UI on port $WEBUI_PORT)
After=network-online.target
Wants=network-online.target

[Service]
User=$BOX_USER
Group=$BOX_USER
UMask=0002
ExecStart=/usr/bin/qbittorrent-nox --webui-port=$WEBUI_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

# --- Kodi: add the download folder as a video source -----------------------
echo "==> Adding $DL_DIR to Kodi as a video source"
KODI_DATA="$BOX_HOME/.kodi/userdata"
install -d -o "$BOX_USER" -g "$BOX_USER" "$BOX_HOME/.kodi" "$KODI_DATA"
if [[ -f "$KODI_DATA/sources.xml" ]]; then
  if ! grep -q "$DL_DIR" "$KODI_DATA/sources.xml"; then
    cp "$KODI_DATA/sources.xml" "$KODI_DATA/sources.xml.bak.$(date +%s)"
    python3 -I - "$KODI_DATA/sources.xml" "$DL_DIR/" <<'PY'
import sys, xml.etree.ElementTree as ET
path, dl = sys.argv[1], sys.argv[2]
tree = ET.parse(path); root = tree.getroot()
video = root.find("video")
if video is None:
    video = ET.SubElement(root, "video")
src = ET.SubElement(video, "source")
ET.SubElement(src, "name").text = "Torrent Downloads"
p = ET.SubElement(src, "path", pathversion="1"); p.text = dl
ET.SubElement(src, "allowsharing").text = "true"
tree.write(path, encoding="utf-8", xml_declaration=True)
PY
  fi
else
  cat > "$KODI_DATA/sources.xml" <<XML
<sources>
    <programs><default pathversion="1"></default></programs>
    <video>
        <default pathversion="1"></default>
        <source>
            <name>Torrent Downloads</name>
            <path pathversion="1">$DL_DIR/</path>
            <allowsharing>true</allowsharing>
        </source>
    </video>
    <music><default pathversion="1"></default></music>
    <pictures><default pathversion="1"></default></pictures>
    <files><default pathversion="1"></default></files>
</sources>
XML
fi
chown -R "$BOX_USER:$BOX_USER" "$BOX_HOME/.kodi"

# --- Kodi: start full screen at boot ---------------------------------------
echo "==> Making Kodi start at boot"
# Allow a non-console service to start the X server.
cat > /etc/X11/Xwrapper.config <<'XW'
allowed_users=anybody
needs_root_rights=yes
XW

cat > /etc/systemd/system/sofabox-kodi.service <<UNIT
[Unit]
Description=Kodi full screen on the TV
After=systemd-user-sessions.service network-online.target sound.target
Wants=network-online.target
Conflicts=getty@tty7.service

[Service]
User=$BOX_USER
Group=$BOX_USER
PAMName=login
TTYPath=/dev/tty7
StandardInput=tty
StandardOutput=journal
Environment=HOME=$BOX_HOME
ExecStart=/usr/bin/xinit /usr/bin/dbus-launch --exit-with-session /usr/bin/kodi-standalone -- :0 -nolisten tcp vt7 -nocursor
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

# Boot to console (no desktop) so Kodi owns the screen. Undo with:
#   sudo systemctl set-default graphical.target
systemctl set-default multi-user.target

# --- Laptop: keep running with the lid closed ------------------------------
echo "==> Ignoring the lid switch so the laptop keeps running when closed"
install -d /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-sofabox.conf <<'LID'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
LID

systemctl daemon-reload
systemctl enable sofabox-torrent.service sofabox-kodi.service
systemctl restart sofabox-torrent.service

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
cat <<DONE

All set.
  Torrent web UI (open on your phone, same Wi-Fi):  http://${IP:-<laptop-ip>}:$WEBUI_PORT
  Login: $WEBUI_USER / (the password you chose)
  Downloads land in: $DL_DIR  -> Kodi: Videos > Files > Torrent Downloads

Reboot now to start Kodi on the TV:  sudo reboot
DONE
