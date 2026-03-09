# shelley-yepanywhere-switch

A Bash controller script for switching an [exe.dev](https://exe.dev) VM between [Shelley](https://github.com/boldsoftware/shelley) and [yepanywhere](https://github.com/kzahel/yepanywhere) + Codex CLI on the same port.

---

# Known Issue: Bootstrap session not visible in YepAnywhere Sessions tab

> **Status: Upstream bug in yepanywhere — workaround available**

The bootstrap Codex session launched by this script is visible as an artifact in the YepAnywhere web UI, but clicking into the Sessions tab shows nothing. This appears to affect even yepanywhere-native Codex sessions (not just ones launched via this script), so it is likely a bug in yepanywhere itself. [A related issue has been reopened in the yepanywhere repo](https://github.com/kzahel/yepanywhere/issues).

The yepanywhere developer has indicated a new npm release is expected shortly that should fix the Codex sessions not showing up.

## Workaround

Until a fixed yepanywhere release is available:

1. In the YepAnywhere web UI, open the **Project** that corresponds to your repo
2. Start a **new yepanywhere/Codex chat** inside that Project
3. In the chat, prompt Codex to examine the files in `.codex-handoff/` to get up to speed on the current state of the project

This gives you a functional Codex session with full project context, even without being able to click directly into the bootstrap session.

> **⚠️ Save the session URL immediately after opening it**
>
> Due to this bug, once you navigate away from the session, you will **not be able to find it again** through the YepAnywhere web UI or the standard Sessions listing. As soon as the new chat session opens in your browser, copy and save the full URL somewhere (a note, your terminal, etc.) so you can return to it directly if needed.

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

> **TIP: Configure Codex project trust before running**
>
> When the script launches a Codex bootstrap session inside tmux, Codex may pause and wait for you to manually approve the project directory as trusted — which means you'd have to attach to the tmux session yourself just to nudge it along.
>
> To avoid this, add your project path to Codex's trusted projects list **before** running the script.
> Edit `~/.codex/config.toml` and add the project path under `approved_api_base_urls` — or more specifically, add it to the `trusted_projects` list:
>
> ```toml
> # ~/.codex/config.toml
> trusted_projects = [
>   "/home/exedev/myproject"
> ]
> ```
>
> Replace `/home/exedev/myproject` with the actual path you will pass to `--project-dir`. This allows Codex to start unattended inside the tmux session without requiring manual confirmation.

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

> **TIP: Delete `.codex-handoff/` after significant progress**
>
> After you have made a lot of changes in your yepanywhere/Codex session, delete the `.codex-handoff/` directory before starting a new conversation. The handoff files reflect the state of the project at the time of the original Shelley bootstrap — if left in place, they may provide stale or misleading context to subsequent Codex sessions.
>
> ```bash
> rm -rf /home/exedev/myproject/.codex-handoff
> ```
>
> Replace `/home/exedev/myproject` with your actual project path. The directory will be recreated fresh the next time you run the script with bootstrap enabled.

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