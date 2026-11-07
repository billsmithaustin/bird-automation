# Bird Cam Stream Automation

One-click start and stop for the bird cam livestream: a Raspberry Pi camera, served by
mediamtx, pulled into OBS Studio on the Ubuntu box, and streamed to YouTube.

## Setup

| Machine | Address | Role |
|---|---|---|
| Ubuntu desktop | whatever it is | Runs OBS Studio and Chrome, streams to YouTube |
| Raspberry Pi | `bill@192.168.3.76` | Camera (imx477) served by mediamtx at `rtsp://192.168.3.76:8554/stream` |

mediamtx lives on the Pi in `~/software/mediamtx_v1.12.0`, with the `stream` path set to
`source: rpiCamera` in `mediamtx.yml`.

## Usage

Click the wren icons pinned to the dock:

- **Start Bird Stream** (wren): starts everything and goes live.
- **Stop Bird Stream** (wren with red stop badge): quits OBS and shuts down the camera.

Each opens a terminal showing progress. It stays open for 30 seconds afterward (or until a
key is pressed) so you can read any errors.

You can also run the scripts from a terminal:

```
./start-bird-stream.sh
./stop-bird-stream.sh
```

## What the scripts do

### `start-bird-stream.sh`

1. SSHes to the Pi and starts mediamtx in the background, unless it is already running.
   Before starting, it kills any leftover `mtxrpicam` camera helper.
2. Waits up to 30 seconds for the RTSP port (8554) to open.
3. Opens the YouTube live dashboard (`https://www.youtube.com/live_dashboard`, the same page
   as Create → Go Live) in a new Chrome window, then waits 15 seconds for it to load.
4. Starts OBS with `--startstreaming`:
   - If OBS is already streaming, it is left alone.
   - If OBS is running but not streaming, it is restarted, because Wayland doesn't allow
     raising a minimized window.

### `stop-bird-stream.sh`

1. Quits OBS gracefully.
2. SSHes to the Pi and stops mediamtx and any leftover `mtxrpicam` camera helper.

YouTube ends the broadcast on its own once OBS stops sending video (see Auto-stop below).

## One-time requirements

- **Passwordless SSH to the Pi.** The key `~/.ssh/id_ed25519` was installed with
  `ssh-copy-id bill@192.168.3.76`. The scripts use `BatchMode`, so they fail instead of
  prompting for a password.
- **YouTube Auto-stop enabled** in the stream's settings (Create → Go Live → Edit →
  Additional settings). Auto-start should also be on, so the broadcast begins when OBS
  connects.
- **OBS scene** with a Media Source pointing at `rtsp://192.168.3.76:8554/stream`, and the
  YouTube stream key set in OBS → Settings → Stream.

## Installed files outside this directory

`./install-launchers.sh` creates all of these and pins both launchers to the dock. It is safe
to re-run, for example after moving this directory, since the launchers point at wherever
the scripts are. `./uninstall-launchers.sh` unpins and deletes them, leaving the rest of the
dock and this directory untouched.

| File | Purpose |
|---|---|
| `~/.local/share/applications/bird-stream.desktop` | Start launcher |
| `~/.local/share/applications/bird-stream-stop.desktop` | Stop launcher |
| `~/.local/share/icons/hicolor/scalable/apps/carolina-wren.svg` | Start icon |
| `~/.local/share/icons/hicolor/scalable/apps/carolina-wren-stop.svg` | Stop icon |

The launchers are pinned to the dock via `gsettings` (`org.gnome.shell favorite-apps`).
To change an icon, edit its SVG in `icons/` and re-run `./install-launchers.sh`.

## Troubleshooting

The mediamtx log on the Pi is `~/software/mediamtx_v1.12.0/mediamtx.log`. It is
overwritten each time the start script launches mediamtx.

| Symptom | Log message | Cause / fix |
|---|---|---|
| OBS shows no video | `ldconfig failed: executable file not found in $PATH` | A non-interactive SSH session has no `/sbin` on its PATH. The start script adds it; keep that line if you edit the script. |
| OBS shows no video | `Camera.acquire() failed` / `Pipeline handler in use by another process` | An orphaned `mtxrpicam` from an earlier mediamtx holds the camera. Run the stop script, or `ssh bill@192.168.3.76 pkill -x mtxrpicam`, then start again. |
| OBS shows no video | `no stream is available on path 'stream'` | The camera hasn't started publishing yet. Check the log for one of the errors above. |
| Start script stops with "mediamtx never came up" | — | Check the log on the Pi, and that the Pi is reachable. |
| Stop script says "OBS didn't quit" | — | OBS is probably showing a confirmation dialog. Close it by hand. |
| Dock shows the old icon | — | Unpin and re-pin the launcher, or log out and back in. |
