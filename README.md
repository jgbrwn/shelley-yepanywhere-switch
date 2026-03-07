# shelley-yepanywhere-switch

A Bash controller script for switching an exe.dev VM between **Shelley** and **yepanywhere + Codex CLI** on the same port.

---

# Purpose

This script supports a workflow where:

- `shelley` normally runs on port `9999`
- when exe.dev credits are exhausted, you temporarily stop `shelley`
- you start `yepanywhere` on the same port
- you bootstrap a **Codex session using the latest Shelley conversation** for that project
- when finished, you switch back to Shelley

The goal is a **clean transition between Shelley and Codex** without losing project context.

---

# Architecture

```
Shelley
   │
   │ (extract latest conversation from SQLite)
   ▼
.codex-handoff/
   │
   │ generates bootstrap context
   ▼
tmux → codex session
   │
   │ detected automatically
   ▼
YepAnywhere Web UI
```

Explanation:

1. The script extracts the **latest Shelley conversation tied to the project directory**
2. It generates **handoff files inside the repository**
3. It launches **Codex in a detached `tmux` session**
4. YepAnywhere detects that Codex session and exposes it in the web UI

This allows work to continue in Codex with **minimal context loss**.

---

# Features

- installs or updates `yepanywhere`
- stops `shelley` **and `shelley.socket`**
- starts `yepanywhere` on port `9999`
- stops `yepanywhere` and restores Shelley
- only uses `sudo` for `systemctl`
- runs yepanywhere and Codex as the **regular user**
- verifies port `9999` is free before starting yepanywhere
- checks Codex CLI authentication before bootstrap
- reads the Shelley SQLite DB for the **latest conversation tied to the project directory**
- generates a **Shelley → Codex handoff artifact**
- launches Codex inside a **detached `tmux` session**
- avoids repeating bootstrap unless forced

---

# Why tmux is used

Bootstrap no longer uses `codex exec`.

Instead the script launches:

```bash
codex
```

inside a **detached `tmux` session**.

This has two important advantages:

1. The Codex session remains **alive and resumable**
2. YepAnywhere can **detect and display the session correctly**

Short-lived `codex exec` runs can complete before YepAnywhere detects them, which causes the session to not appear in the UI.

Running Codex inside tmux solves this problem.

---

# Files created in each project

When bootstrap runs, the script creates a project-local directory:

```
.codex-handoff/
```

Containing:

```
.codex-handoff/
 ├─ shelley-bootstrap.md
 ├─ shelley-bootstrap.jsonl
 ├─ bootstrap-prompt.txt
 ├─ codex-bootstrap-output.txt
 ├─ shelley-bootstrap.done
 └─ shelley-bootstrap.meta
```

### shelley-bootstrap.md

Human-readable reconstruction of the Shelley conversation.

### shelley-bootstrap.jsonl

Raw extracted messages from the Shelley database.

### bootstrap-prompt.txt

The prompt used to initialize the Codex session.

### codex-bootstrap-output.txt

Output captured from the initial Codex bootstrap.

### shelley-bootstrap.done

Marker file preventing duplicate bootstrap.

### shelley-bootstrap.meta

Metadata about the bootstrap session, including:

```
tmux_session_name=<session>
project_dir=<path>
generated_at=<timestamp>
```

---

# Usage

TIP: install `nodeenv` (only needs done once) and then source it before running the script:

```bash
uvx nodeenv -n lts ./node_env
source ./node_env/bin/activate
```

---

## Start yepanywhere and bootstrap from Shelley

```bash
./shelley-yepanywhere-switch.sh \
  -start \
  --project-dir /path/to/repo \
  --shelley-db /path/to/shelley.db
```

---

## Start yepanywhere without bootstrap

```bash
./shelley-yepanywhere-switch.sh -start --bootstrap-mode none
```

---

## Force a fresh bootstrap

```bash
./shelley-yepanywhere-switch.sh \
  -start \
  --project-dir /path/to/repo \
  --shelley-db /path/to/shelley.db \
  --force-bootstrap
```

---

## Return to Shelley

```bash
./shelley-yepanywhere-switch.sh -stop
```

---

# Inspecting the Codex bootstrap session

The Codex session is launched inside a **detached tmux session**.

List sessions:

```bash
tmux ls
```

Attach to the bootstrap session:

```bash
tmux attach -t <session-name>
```

The session name is stored in:

```
.codex-handoff/shelley-bootstrap.meta
```

---

# Requirements

- bash
- sudo
- systemctl
- npm
- sqlite3
- python3
- jq
- codex CLI
- tmux
- yepanywhere (installable via npm)

For port checks, at least one of:

- ss
- lsof

---

# Notes

- The systemd service name must be **`shelley`**
- The script stops/starts **both `shelley` and `shelley.socket`**
- YepAnywhere logs and PID files live in:

```
~/.cache/shelley-yepanywhere-switch/
```

- The shared port between Shelley and yepanywhere is:

```
9999
```

---

# Future ideas

Possible improvements:

- smarter Shelley conversation parsing
- automatic Codex → Codex context distillation when context windows get large
- improved yepanywhere process management
- automatic repo detection for bootstrap without needing `--project-dir`
