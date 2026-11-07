#!/usr/bin/env bash
# Stop the bird cam stream: quit OBS, then stop mediamtx and its camera helper on the rpi.
set -euo pipefail

RPI=bill@192.168.3.76

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --pause (used by the desktop launcher) keeps the terminal open so output can be read, even on failure.
if [[ ${1:-} == --pause ]]; then
  trap 'echo; read -n1 -s -t 30 -p "Press any key to close (auto-closes in 30s)" || true' EXIT
fi

# 1. Quit OBS (ends the YouTube stream once it stops receiving video).
if pgrep -x obs >/dev/null; then
  log "Quitting OBS..."
  pkill -TERM -x obs
  for _ in $(seq 15); do pgrep -x obs >/dev/null || break; sleep 1; done
  if pgrep -x obs >/dev/null; then
    log "OBS didn't quit (it may be showing a dialog); close it by hand."
  else
    log "OBS stopped."
  fi
else
  log "OBS isn't running."
fi

# 2. Stop mediamtx and its camera helper, so the camera is free for next time.
log "Stopping mediamtx on $RPI..."
ssh -o BatchMode=yes -o ConnectTimeout=10 "$RPI" '
  pkill -x mediamtx && echo "mediamtx stopped" || echo "mediamtx was not running"
  sleep 2
  pkill -x mtxrpicam && echo "stray camera helper stopped" || true
'

log "Done."
