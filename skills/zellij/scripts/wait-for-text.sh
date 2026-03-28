#!/usr/bin/env bash
set -euo pipefail

# wait-for-text.sh — watch a zellij pane for a pattern using subscribe (event-driven)

usage() {
  cat <<'USAGE'
Usage: wait-for-text.sh --session NAME --pane-id ID --pattern PATTERN [options]

Watch a zellij pane for text and exit when found.
Uses `zellij subscribe` — event-driven, no polling.

Options:
  --session    Zellij session name (required)
  --pane-id    Pane ID, e.g. terminal_0 (required)
  --pattern    Regex pattern to match (required)
  --fixed      Treat pattern as a fixed string (grep -F)
  --timeout    Seconds to wait (default: 15)
  -h, --help   Show this help
USAGE
}

session=""
pane_id=""
pattern=""
grep_flag="-E"
timeout_secs=15

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)  session="${2-}"; shift 2 ;;
    --pane-id)  pane_id="${2-}"; shift 2 ;;
    --pattern)  pattern="${2-}"; shift 2 ;;
    --fixed)    grep_flag="-F"; shift ;;
    --timeout)  timeout_secs="${2-}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$session" || -z "$pane_id" || -z "$pattern" ]]; then
  echo "session, pane-id, and pattern are required" >&2
  usage
  exit 1
fi

for cmd in zellij jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd not found in PATH" >&2; exit 1; }
done

# Use a FIFO + background subscribe so we can kill it cleanly from the main process.
FIFO=$(mktemp -u /tmp/zellij-wait.XXXXXX)
mkfifo "$FIFO"
trap 'rm -f "$FIFO"; kill "$SUB_PID" 2>/dev/null; kill "$TIMER_PID" 2>/dev/null; wait 2>/dev/null' EXIT

# Start subscribe in background, writing to FIFO
zellij --session "$session" subscribe \
    --pane-id "$pane_id" \
    --format json \
    --scrollback 200 > "$FIFO" 2>/dev/null &
SUB_PID=$!

# Start timeout killer in background
(
  sleep "$timeout_secs"
  echo "TIMEOUT" > "$FIFO" 2>/dev/null || true
) &
TIMER_PID=$!

# Read from FIFO in the main process (no subshell — exit works correctly)
while IFS= read -r line; do
  # Check for timeout sentinel
  if [[ "$line" == "TIMEOUT" ]]; then
    echo "Timed out after ${timeout_secs}s waiting for pattern: $pattern" >&2
    # Dump current viewport for debugging
    zellij --session "$session" action dump-screen --pane-id "$pane_id" >&2 2>/dev/null || true
    exit 1
  fi

  # Extract viewport lines from JSON
  viewport=$(echo "$line" | jq -r '
    select(.event == "pane_update") |
    (.viewport // []) | join("\n")
  ' 2>/dev/null) || continue

  [[ -z "$viewport" ]] && continue

  # Also check scrollback from initial delivery
  scrollback=$(echo "$line" | jq -r '
    select(.event == "pane_update") |
    (.scrollback // []) | join("\n")
  ' 2>/dev/null) || true

  combined="${scrollback:+$scrollback
}$viewport"

  if echo "$combined" | grep $grep_flag -- "$pattern" >/dev/null 2>&1; then
    exit 0
  fi
done < "$FIFO"

# Subscribe ended without finding pattern
echo "subscribe ended without finding pattern: $pattern" >&2
exit 1
