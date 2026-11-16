#!/usr/bin/env bash
# Stop the bird cam stream: quit OBS, then stop mediamtx and its camera helper on the rpi.
set -euo pipefail

RPI=bill@192.168.3.76
OBS_WS="$(dirname "$(readlink -f "$0")")/obs-ws.py"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --pause (used by the desktop launcher) keeps the terminal open so output can be read, even on failure.
if [[ ${1:-} == --pause ]]; then
  trap 'echo; read -n1 -s -t 30 -p "Press any key to close (auto-closes in 30s)" || true' EXIT
fi

# 1. Stop the stream through obs-websocket (YouTube auto-stop then ends the broadcast),
# then quit OBS. Stopping first avoids OBS's "stream is active, really quit?" dialog.
obs_ws() { python3 "$OBS_WS" "$@"; }  # exit 0 = yes/ok, 1 = not streaming, 3 = can't reach OBS
if pgrep -x obs >/dev/null; then
  log "Stopping the stream..."
  if obs_ws stop-stream; then
    for _ in $(seq 10); do obs_ws streaming 2>/dev/null || break; sleep 1; done
    obs_ws streaming 2>/dev/null && log "OBS still reports streaming; quitting anyway." || log "Stream stopped."
  else
    log "Couldn't stop it through OBS's WebSocket server; quitting OBS anyway."
  fi
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
