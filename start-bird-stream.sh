#!/usr/bin/env bash
# Start the bird cam stream: mediamtx on the rpi, YouTube in Chrome, OBS streaming.
set -euo pipefail

RPI=bill@192.168.3.76
RPI_HOST=${RPI#*@}
MEDIAMTX_DIR=software/mediamtx_v1.12.0
RTSP_PORT=8554
YOUTUBE_URL=https://www.youtube.com/live_dashboard  # same page as Create -> Go Live
YOUTUBE_WAIT=15  # seconds to let the live dashboard load before OBS starts
# Dedicated Chrome profile, so remote debugging (needed to list tabs) is allowed.
CHROME_PROFILE=~/.config/google-chrome-birdcam
CHROME_PORT=9222
OBS_WAIT=30  # seconds to wait for OBS to report the stream as live
OBS_WS="$(dirname "$(readlink -f "$0")")/obs-ws.py"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --pause (used by the desktop launcher) keeps the terminal open so output can be read, even on failure.
if [[ ${1:-} == --pause ]]; then
  trap 'echo; read -n1 -s -t 30 -p "Press any key to close (auto-closes in 30s)" || true' EXIT
fi

# 1+2. Start mediamtx on the rpi (detached, so it survives the ssh session ending).
log "Starting mediamtx on $RPI..."
ssh -o BatchMode=yes -o ConnectTimeout=10 "$RPI" "
  if pgrep -x mediamtx >/dev/null; then
    echo 'mediamtx already running'
  else
    # Non-interactive ssh lacks /sbin, but the rpiCamera source needs ldconfig.
    export PATH=\$PATH:/usr/sbin:/sbin
    # A killed mediamtx can orphan its camera helper, which keeps the camera busy.
    pkill -x mtxrpicam && sleep 1
    cd $MEDIAMTX_DIR || exit 1
    setsid nohup ./mediamtx > mediamtx.log 2>&1 < /dev/null &
    echo 'mediamtx started'
  fi
"

log "Waiting for RTSP port $RTSP_PORT on $RPI_HOST..."
for _ in $(seq 30); do
  if timeout 1 bash -c "</dev/tcp/$RPI_HOST/$RTSP_PORT" 2>/dev/null; then
    log "RTSP server is up"
    break
  fi
  sleep 1
done
timeout 1 bash -c "</dev/tcp/$RPI_HOST/$RTSP_PORT" 2>/dev/null \
  || { log "mediamtx never came up; check ~/$MEDIAMTX_DIR/mediamtx.log on the rpi"; exit 1; }
sleep 3  # give the camera a moment to start publishing

# 3. Open the YouTube live dashboard in the bird cam Chrome profile. Wayland won't let us
# raise a minimized window, so close any dashboard tab already open and open it again
# in a new window, which always appears.
dashboard_tab_ids() {
  curl -sf "http://127.0.0.1:$CHROME_PORT/json/list" | python3 -c '
import json, sys
for t in json.load(sys.stdin):
    url = t.get("url", "")
    if t.get("type") == "page" and ("live_dashboard" in url or
                                    ("studio.youtube.com" in url and "/livestreaming" in url)):
        print(t["id"])
'
}
if ids=$(dashboard_tab_ids 2>/dev/null) && [[ -n $ids ]]; then
  log "Live dashboard already open; reopening it in a new window..."
  for id in $ids; do curl -sf "http://127.0.0.1:$CHROME_PORT/json/close/$id" >/dev/null || true; done
else
  log "Opening YouTube live dashboard in Chrome..."
fi
setsid nohup google-chrome --user-data-dir="$CHROME_PROFILE" --remote-debugging-port="$CHROME_PORT" \
  --no-first-run --no-default-browser-check --new-window "$YOUTUBE_URL" >/dev/null 2>&1 &
sleep "$YOUTUBE_WAIT"

# 4+5. Launch OBS and start streaming, controlled through obs-websocket.
obs_ws() { python3 "$OBS_WS" "$@"; }  # exit 0 = yes/ok, 1 = not streaming, 3 = can't reach OBS
WS_HINT="enable it in OBS: Tools -> WebSocket Server Settings -> Enable WebSocket server"
if pgrep -x obs >/dev/null; then
  rc=0; obs_ws streaming || rc=$?
  case $rc in
    0) log "OBS is already streaming; leaving it alone." ;;
    1) log "OBS is running but not streaming; starting the stream..."
       obs_ws start-stream ;;
    *) log "Can't reach OBS's WebSocket server; $WS_HINT"; exit 1 ;;
  esac
else
  log "Launching OBS and starting the stream..."
  setsid nohup obs --startstreaming --disable-shutdown-check >/dev/null 2>&1 &
fi

log "Waiting for OBS to report the stream as live..."
for _ in $(seq "$OBS_WAIT"); do
  rc=0; obs_ws streaming 2>/dev/null || rc=$?
  [[ $rc == 0 ]] && break
  sleep 1
done
case $rc in
  0) log "OBS is streaming." ;;
  1) log "OBS didn't start streaming within ${OBS_WAIT}s; check OBS for an error."; exit 1 ;;
  *) log "Can't reach OBS's WebSocket server; $WS_HINT"; exit 1 ;;
esac

log "Done."
