#!/usr/bin/env bash
set -euo pipefail

# wait-idle.sh — wait until a zellij pane has no new output for a given period

usage() {
  cat <<'USAGE'
Usage: wait-idle.sh --session NAME --pane-id ID [options]

Wait until a pane has no new output for --idle-time seconds.
Uses `zellij subscribe` — event-driven, no polling.

Options:
  --session    Zellij session name (required)
  --pane-id    Pane ID, e.g. terminal_0 (required)
  --idle-time  Seconds of silence before considering idle (default: 2)
  --timeout    Maximum seconds to wait (default: 30)
  -h, --help   Show this help
USAGE
}

session=""
pane_id=""
idle_time=2
timeout_secs=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)    session="${2-}"; shift 2 ;;
    --pane-id)    pane_id="${2-}"; shift 2 ;;
    --idle-time)  idle_time="${2-}"; shift 2 ;;
    --timeout)    timeout_secs="${2-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$session" || -z "$pane_id" ]]; then
  echo "session and pane-id are required" >&2
  usage
  exit 1
fi

command -v zellij >/dev/null 2>&1 || { echo "zellij not found in PATH" >&2; exit 1; }

# Use a FIFO + background subscribe so we control the main process.
FIFO=$(mktemp -u /tmp/zellij-idle.XXXXXX)
mkfifo "$FIFO"
trap 'rm -f "$FIFO"; kill "$SUB_PID" 2>/dev/null; kill "$TIMER_PID" 2>/dev/null; wait 2>/dev/null' EXIT

# Start subscribe in background
zellij --session "$session" subscribe \
    --pane-id "$pane_id" \
    --format json > "$FIFO" 2>/dev/null &
SUB_PID=$!

# Global timeout
(
  sleep "$timeout_secs"
  echo "TIMEOUT" > "$FIFO" 2>/dev/null || true
) &
TIMER_PID=$!

# Read with per-read timeout. Skip the initial event, then if read times out
# (no new event for idle_time seconds), the pane is idle.
FIRST=true
while IFS= read -t "$idle_time" -r line; do
  if [[ "$line" == "TIMEOUT" ]]; then
    echo "Timed out after ${timeout_secs}s waiting for idle" >&2
    exit 1
  fi
  if [[ "$FIRST" == true ]]; then
    FIRST=false
  fi
done < "$FIFO"

# read timed out — no output for idle_time seconds = idle
exit 0
