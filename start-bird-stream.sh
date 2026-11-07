#!/usr/bin/env bash
# Start the bird cam stream: mediamtx on the rpi, YouTube in Chrome, OBS streaming.
set -euo pipefail

RPI=bill@192.168.3.76
RPI_HOST=${RPI#*@}
MEDIAMTX_DIR=software/mediamtx_v1.12.0
RTSP_PORT=8554
YOUTUBE_URL=https://www.youtube.com/live_dashboard  # same page as Create -> Go Live
YOUTUBE_WAIT=15  # seconds to let the live dashboard load before OBS starts

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

# 3. Open the YouTube live dashboard in a new Chrome window. Wayland won't let us
# raise a minimized existing window, but a new one always appears.
log "Opening YouTube live dashboard in Chrome..."
setsid nohup google-chrome --new-window "$YOUTUBE_URL" >/dev/null 2>&1 &
sleep "$YOUTUBE_WAIT"

# 4+5. Launch OBS and start streaming.
obs_streaming() {
  ss -tnpH state established '( dport = :443 or dport = :1935 )' 2>/dev/null | grep -q '"obs"'
}
if obs_streaming; then
  log "OBS is already streaming; leaving it alone."
else
  if pgrep -x obs >/dev/null; then
    # Can't raise a minimized window on Wayland, so restart OBS to get a visible one.
    log "OBS is running but not streaming; restarting it..."
    pkill -TERM -x obs
    for _ in $(seq 15); do pgrep -x obs >/dev/null || break; sleep 1; done
    pgrep -x obs >/dev/null && { log "OBS didn't quit; close it and run this again."; exit 1; }
  fi
  log "Launching OBS and starting the stream..."
  setsid nohup obs --startstreaming --disable-shutdown-check >/dev/null 2>&1 &
fi

log "Done."
