#!/usr/bin/env bash
# Install the Start/Stop Bird Stream dock launchers: copies the Carolina Wren icons
# from icons/, writes the .desktop files, and pins both to the GNOME dock. Safe to re-run.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ICON_DIR=~/.local/share/icons/hicolor/scalable/apps
APP_DIR=~/.local/share/applications

log() { echo "[$(date +%H:%M:%S)] $*"; }

mkdir -p "$ICON_DIR" "$APP_DIR"

# desktop_entry <name> <comment> <script> <icon>
desktop_entry() {
  cat <<EOF
[Desktop Entry]
Type=Application
Name=$1
Comment=$2
Exec=$SCRIPT_DIR/$3 --pause
Icon=$4
Terminal=true
Categories=AudioVideo;
EOF
}

log "Installing icons to $ICON_DIR..."
cp "$SCRIPT_DIR/icons/carolina-wren.svg" "$SCRIPT_DIR/icons/carolina-wren-stop.svg" "$ICON_DIR/"

log "Writing launchers to $APP_DIR..."
desktop_entry "Start Bird Stream" \
  "Start mediamtx on the rpi, open YouTube Go Live, and stream with OBS" \
  start-bird-stream.sh carolina-wren > "$APP_DIR/bird-stream.desktop"
desktop_entry "Stop Bird Stream" \
  "Quit OBS and stop mediamtx and the camera on the rpi" \
  stop-bird-stream.sh carolina-wren-stop > "$APP_DIR/bird-stream-stop.desktop"
chmod +x "$SCRIPT_DIR/start-bird-stream.sh" "$SCRIPT_DIR/stop-bird-stream.sh"

if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$APP_DIR/bird-stream.desktop" "$APP_DIR/bird-stream-stop.desktop"
fi
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor >/dev/null 2>&1 || true
update-desktop-database "$APP_DIR" 2>/dev/null || true

log "Pinning launchers to the dock..."
favorites=$(gsettings get org.gnome.shell favorite-apps)
for app in bird-stream.desktop bird-stream-stop.desktop; do
  if [[ $favorites != *"'$app'"* ]]; then
    if [[ $favorites == "@as []" ]]; then
      favorites="['$app']"
    else
      favorites=${favorites%]}", '$app']"
    fi
  fi
done
gsettings set org.gnome.shell favorite-apps "$favorites"

log "Done. If the dock shows an old icon, unpin and re-pin it, or log out and back in."
