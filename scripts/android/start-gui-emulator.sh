#!/usr/bin/env bash
set -euo pipefail

readonly DISPLAY_NUMBER="${DISPLAY_NUMBER:-:0}"
readonly NOVNC_PORT="${NOVNC_PORT:-6080}"
readonly SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1440x900x24}"

[[ "$DISPLAY_NUMBER" =~ ^:[0-9]{1,3}$ ]] || {
  printf 'DISPLAY_NUMBER must match :0 through :999.\n' >&2
  exit 2
}
[[ "$NOVNC_PORT" =~ ^[1-9][0-9]{0,4}$ ]] && (( NOVNC_PORT <= 65535 )) || {
  printf 'NOVNC_PORT must be an integer from 1 through 65535.\n' >&2
  exit 2
}
[[ "$SCREEN_GEOMETRY" =~ ^[1-9][0-9]{2,4}x[1-9][0-9]{2,4}x(16|24|32)$ ]] || {
  printf 'SCREEN_GEOMETRY must use WIDTHxHEIGHTxDEPTH format.\n' >&2
  exit 2
}

export DISPLAY="$DISPLAY_NUMBER"
export EMULATOR_WINDOW_MODE=window

Xvfb "$DISPLAY" -screen 0 "$SCREEN_GEOMETRY" -ac -nolisten tcp \
  >/tmp/xvfb.log 2>&1 &
xvfb_pid=$!

for _ in {1..50}; do
  [[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]] && break
  kill -0 "$xvfb_pid" 2>/dev/null || {
    printf 'Xvfb exited before its display became ready.\n' >&2
    cat /tmp/xvfb.log >&2 || true
    exit 1
  }
  sleep 0.1
done
[[ -S "/tmp/.X11-unix/X${DISPLAY#:}" ]] || {
  printf 'Timed out waiting for Xvfb display %s.\n' "$DISPLAY" >&2
  exit 1
}

openbox-session >/tmp/openbox.log 2>&1 &
x11vnc -display "$DISPLAY" -forever -shared -nopw -rfbport 5900 \
  >/tmp/x11vnc.log 2>&1 &
websockify --web=/usr/share/novnc "$NOVNC_PORT" localhost:5900 \
  >/tmp/websockify.log 2>&1 &

"$(dirname "$0")/start-emulator.sh"
exec tail -f /dev/null
