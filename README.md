# @imandel/pi-zellij

A [pi](https://github.com/badlogic/pi-mono) skill for programmatic [zellij](https://zellij.dev) terminal workspace control. Requires zellij 0.44+.

## Install

```bash
pi install npm:@imandel/pi-zellij
```

## What it does

Gives pi the ability to:

- **Create and manage background zellij sessions** — headless workspaces the user can attach to
- **Target panes by stable ID** — `terminal_0`, `terminal_1`, etc.
- **Send input** — `write-chars` (typed), `paste` (multi-line), `write` (raw bytes / Ctrl-C)
- **Read output** — `dump-screen` (snapshot) and `subscribe` (real-time streaming)
- **Run blocking commands** — `--block-until-exit` waits for completion without polling
- **Apply layouts** — generate KDL layout files for complex workspaces (editor + terminal + logs, etc.)
- **Wait for patterns** — `wait-for-text.sh` uses `subscribe` (event-driven, not polling)
- **Detect idle** — `wait-idle.sh` detects when output settles

## Why not tmux?

Zellij 0.44+ has features that make agent control significantly better:

| | tmux | zellij |
|---|---|---|
| Read output | `capture-pane` (snapshot, poll) | `subscribe --json` (streaming) |
| Wait for done | poll loop + grep | `--block-until-exit` or `subscribe` |
| Create pane | no ID returned | returns stable pane ID |
| Multi-line input | send line by line | `paste` (bracketed) |
| Session state | text parsing | `list-panes --json` |
| Layouts | manual splits | KDL layout files, `override-layout` |
| Session recovery | manual | built-in resurrection |

## License

MIT
