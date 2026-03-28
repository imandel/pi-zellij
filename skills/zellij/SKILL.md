---
name: zellij
description: "Remote control zellij sessions for interactive CLIs, long-running commands, and workspace automation. Create panes, send input, stream output, run commands with blocking, and apply layouts — all programmatically."
---

# Zellij Skill

Use zellij as a programmable terminal workspace for interactive and long-running work. Requires zellij 0.44+.

## Quickstart

```bash
SESSION=pi-work

# Create a background session (no terminal needed)
zellij attach "$SESSION" --create-background

# Create a named pane, capture its ID
PANE_ID=$(zellij --session "$SESSION" action new-pane --name "python")

# Send text to a specific pane
zellij --session "$SESSION" action write-chars --pane-id "$PANE_ID" 'python3 -q'
zellij --session "$SESSION" action write --pane-id "$PANE_ID" 10   # Enter key

# Read pane output (viewport only, or --full for scrollback)
zellij --session "$SESSION" action dump-screen --pane-id "$PANE_ID"
zellij --session "$SESSION" action dump-screen --pane-id "$PANE_ID" --full

# Clean up
zellij kill-session "$SESSION"
```

After starting a session, ALWAYS tell the user how to attach:

```
To monitor this session yourself:
  zellij attach pi-work
```

This must ALWAYS be printed right after a session is started and once again at the end of the tool loop.

## Session management

```bash
# Create background session (headless, no terminal)
zellij attach my-session --create-background

# List sessions
zellij ls

# Kill a session
zellij kill-session my-session

# Kill all sessions
zellij delete-all-sessions
```

Background sessions are the primary pattern. The agent creates them headless, the user can attach at any time.

## Naming conventions

- Use short, slug-like names: `pi-python`, `pi-build`, `pi-debug`. Prefix with `pi-` to distinguish agent sessions from user sessions.
- Panes should be named descriptively with `--name`: `--name "tests"`, `--name "server"`, `--name "gpu-monitor"`.
- When creating sessions for a specific project, include the project name: `pi-myapp-dev`.
- Avoid spaces in session and pane names.

## Targeting panes

Every pane has a stable ID returned on creation: `terminal_0`, `terminal_1`, `plugin_2`, etc.
Bare numbers work too: `--pane-id 0` is equivalent to `--pane-id terminal_0`.

All commands that target panes use `--pane-id <ID>`. All commands that target sessions use `--session <NAME>` (or the shorthand `-s`).

```bash
# List all panes with metadata
zellij --session "$SESSION" action list-panes --json --all

# Filter to terminal panes only
zellij --session "$SESSION" action list-panes --json --all \
  | jq '[.[] | select(.is_plugin == false)]'
```

## Sending input

```bash
# Write characters (typed one at a time, triggers shell completion etc.)
zellij --session "$SESSION" action write-chars --pane-id "$PANE_ID" 'echo hello'

# Send Enter (byte 10 = newline)
zellij --session "$SESSION" action write --pane-id "$PANE_ID" 10

# Paste text (bracketed paste mode — multi-line safe, won't trigger shell completion)
zellij --session "$SESSION" action paste --pane-id "$PANE_ID" 'line 1
line 2
line 3'

# Send control keys (Ctrl-C = byte 3, Ctrl-D = byte 4, Ctrl-Z = byte 26)
zellij --session "$SESSION" action write --pane-id "$PANE_ID" 3   # Ctrl-C
zellij --session "$SESSION" action write --pane-id "$PANE_ID" 4   # Ctrl-D
```

### Input guidelines

- Use `write-chars` for short commands (single line).
- Use `paste` for multi-line input (code blocks, heredocs). It uses bracketed paste mode so shells handle it correctly.
- Use `write 10` to send Enter after `write-chars`.
- Use `write 3` to interrupt a running process (Ctrl-C).

## Reading output

### Snapshot (dump-screen)

```bash
# Current viewport
zellij --session "$SESSION" action dump-screen --pane-id "$PANE_ID"

# Full scrollback
zellij --session "$SESSION" action dump-screen --pane-id "$PANE_ID" --full

# With ANSI colors preserved
zellij --session "$SESSION" action dump-screen --pane-id "$PANE_ID" --full --ansi

# Save to file
zellij --session "$SESSION" action dump-screen --pane-id "$PANE_ID" --full --path /tmp/output.txt
```

### Streaming (subscribe)

Subscribe streams pane updates as JSON events in real-time. No polling needed.

```bash
# Stream updates from a pane (blocks until killed)
zellij --session "$SESSION" subscribe --pane-id "$PANE_ID" --format json

# Include scrollback in initial delivery
zellij --session "$SESSION" subscribe --pane-id "$PANE_ID" --format json --scrollback

# Subscribe to multiple panes
zellij --session "$SESSION" subscribe --pane-id terminal_0 --pane-id terminal_1 --format json
```

Event format:
```json
{
  "event": "pane_update",
  "is_initial": true,
  "pane_id": "terminal_0",
  "scrollback": null,
  "viewport": ["$ echo hello", "hello", "$ "]
}
```

## Running commands

### Fire-and-forget

```bash
# Run in a new pane, get pane ID back
PANE_ID=$(zellij --session "$SESSION" action new-pane --name "build" -- make)

# Or with zellij run
PANE_ID=$(zellij --session "$SESSION" run --name "tests" -- pytest -v)
```

### Blocking (wait for completion)

```bash
# Block until command finishes (any exit code)
zellij --session "$SESSION" run --block-until-exit -- pytest

# Block only until success (re-run interactively on failure)
zellij --session "$SESSION" run --block-until-exit-success -- cargo build

# Block until failure (useful for watch-style commands)
zellij --session "$SESSION" run --block-until-exit-failure -- ./health-check.sh

# Close pane automatically when command finishes
zellij --session "$SESSION" run --close-on-exit -- make clean
```

`--block-until-exit` is the primary way to run a command and wait for it. The agent's script blocks until the command finishes — no polling, no guessing.

## Synchronizing / waiting for prompts

Use the helper script to wait for specific output in a pane:

```bash
# Wait for Python prompt
./scripts/wait-for-text.sh --session "$SESSION" --pane-id "$PANE_ID" --pattern '>>>' --timeout 15

# Wait for a build to finish
./scripts/wait-for-text.sh --session "$SESSION" --pane-id "$PANE_ID" --pattern 'Build succeeded' --timeout 120

# Fixed string matching (not regex)
./scripts/wait-for-text.sh --session "$SESSION" --pane-id "$PANE_ID" --pattern 'error[E0308]' --fixed --timeout 30
```

The helper uses `zellij subscribe --format json` under the hood — event-driven, no polling.

For simple cases, `--block-until-exit` is better. Use `wait-for-text.sh` when you need to detect specific output from a long-running interactive process.

## Spawning processes

Special rules for processes:

- When asked to debug, use **lldb** by default.
- When starting a Python interactive shell, always set `PYTHON_BASIC_REPL=1`. The non-basic console interferes with `write-chars`.
  ```bash
  PANE_ID=$(zellij --session "$SESSION" action new-pane --name "python" -- env PYTHON_BASIC_REPL=1 python3 -q)
  ```

## Layouts

Generate a KDL layout file and apply it to create complex workspaces in one step.

```bash
# Write a layout
cat > /tmp/dev-layout.kdl << 'KDL'
layout {
    pane split_direction="vertical" {
        pane name="editor" size="60%"
        pane split_direction="horizontal" {
            pane name="terminal"
            pane name="logs" command="tail" {
                args "-f" "server.log"
            }
        }
    }
}
KDL

# Start a session with this layout
zellij --session dev --layout /tmp/dev-layout.kdl

# Or create a new tab with a layout in an existing session
zellij --session "$SESSION" action new-tab --layout /tmp/dev-layout.kdl --name "dev"

# Or rearrange the current tab without killing panes
zellij --session "$SESSION" action override-layout /tmp/dev-layout.kdl --retain-existing-terminal-panes
```

### Layout templates (reusable pane definitions)

```kdl
layout {
    pane_template name="tail-log" {
        command "tail"
        args "-f"
        start_suspended true
    }

    pane split_direction="vertical" {
        pane name="main"
        pane split_direction="horizontal" {
            tail-log name="app-log" { args "-f" "app.log" }
            tail-log name="err-log" { args "-f" "error.log" }
        }
    }
}
```

### Floating panes

```bash
# Quick floating pane for a one-off command
PANE_ID=$(zellij --session "$SESSION" action new-pane --floating --name "quick" -- bash)

# Positioned and sized floating pane
PANE_ID=$(zellij --session "$SESSION" action new-pane --floating \
    --x 10% --y 10% --width 80% --height 80% \
    --name "monitor" -- htop)
```

## Interactive tool recipes

- **Python REPL**: create pane with `env PYTHON_BASIC_REPL=1 python3 -q`; wait for `>>>` with `wait-for-text.sh`; send code with `write-chars` + `write 10`; interrupt with `write 3`.
- **lldb/gdb**: create pane with `lldb ./binary`; wait for `(lldb)` prompt; send commands with `write-chars`; exit via `write-chars 'quit'`.
- **psql/mysql/node/bash**: same pattern — start the program, wait for its prompt, then send literal text.
- **Long builds**: use `zellij run --block-until-exit -- make` to block the agent until done.
- **Watch commands**: use `subscribe` to stream output and detect patterns in real time.

## Session resurrection

Zellij automatically saves session state every second. If a session dies:

```bash
# List all sessions (including exited)
zellij ls

# Reattach — zellij resurrects the layout and commands
zellij attach my-session
```

Resurrected commands show a "Press ENTER to run" prompt for safety.

## Cleanup

```bash
# Kill a specific session
zellij kill-session "$SESSION"

# Kill all sessions
zellij delete-all-sessions

# List and clean up
zellij ls
```

## Helper: wait-for-text.sh

`./scripts/wait-for-text.sh` uses `zellij subscribe` to watch a pane for a pattern. Event-driven — no polling.

```bash
./scripts/wait-for-text.sh --session SESSION --pane-id PANE_ID --pattern PATTERN [--fixed] [--timeout 15]
```

- `--session` session name (required)
- `--pane-id` pane ID, e.g. `terminal_0` (required)
- `--pattern` regex to match (required); add `--fixed` for literal string
- `--timeout` seconds to wait (default: 15)
- Exits 0 on first match, 1 on timeout. On timeout, dumps the last viewport to stderr.

## Helper: wait-idle.sh

`./scripts/wait-idle.sh` waits until a pane has no new output for a given period. Useful for "wait until the command is done" when you don't know what the output will look like.

```bash
./scripts/wait-idle.sh --session SESSION --pane-id PANE_ID [--idle-time 2] [--timeout 30]
```

- `--idle-time` seconds of no output before considering idle (default: 2)
- `--timeout` maximum seconds to wait (default: 30)
