#!/usr/bin/env bash
# Remove the Start/Stop Bird Stream dock launchers installed by install-launchers.sh:
# unpins them from the GNOME dock and deletes the .desktop files and icons. Safe to re-run.
set -euo pipefail

ICON_DIR=~/.local/share/icons/hicolor/scalable/apps
APP_DIR=~/.local/share/applications

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "Unpinning launchers from the dock..."
favorites=$(gsettings get org.gnome.shell favorite-apps)
for app in bird-stream.desktop bird-stream-stop.desktop; do
  favorites=${favorites//", '$app'"/}
  favorites=${favorites//"'$app', "/}
  favorites=${favorites//"'$app'"/}
done
[[ $favorites == "[]" ]] && favorites="@as []"
gsettings set org.gnome.shell favorite-apps "$favorites"

log "Removing launchers from $APP_DIR..."
rm -f "$APP_DIR/bird-stream.desktop" "$APP_DIR/bird-stream-stop.desktop"

log "Removing icons from $ICON_DIR..."
rm -f "$ICON_DIR/carolina-wren.svg" "$ICON_DIR/carolina-wren-stop.svg"

gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor >/dev/null 2>&1 || true
update-desktop-database "$APP_DIR" 2>/dev/null || true

log "Done. The scripts in this directory are untouched; run ./install-launchers.sh to reinstall."
