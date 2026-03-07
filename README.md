# shelley-yepanywhere-switch

A Bash controller script for switching an exe.dev VM between Shelley and yepanywhere on the same port.

## Purpose

This script is for the workflow where:

- `shelley` is your normal service on port `9999`
- when you run out of exe.dev credits, you stop `shelley`
- you start `yepanywhere` on the same port
- you optionally bootstrap a new Codex conversation using the latest Shelley conversation for the same project

## Features

- installs or updates `yepanywhere`
- stops `shelley` and starts `yepanywhere` on port `9999`
- stops `yepanywhere` and starts `shelley` again
- only uses `sudo` for `systemctl`
- runs yepanywhere and Codex as the regular user
- checks that port `9999` is free before starting yepanywhere
- checks Codex CLI auth before bootstrap
- reads the Shelley SQLite DB for the latest project conversation
- creates `.codex-handoff/` files inside the repo
- avoids repeating bootstrap unless forced

## Files created in each project

When bootstrap runs, the script creates:

- `.codex-handoff/shelley-bootstrap.md`
- `.codex-handoff/shelley-bootstrap.jsonl`
- `.codex-handoff/codex-bootstrap-output.txt`
- `.codex-handoff/shelley-bootstrap.done`
- `.codex-handoff/shelley-bootstrap.meta`

## Usage

TIP: install nodeenv (only needs done once) and then source it before running the script:

```uvx nodeenv -n lts ./node_env
source ./node_env/bin/activate
```

Start yepanywhere and bootstrap from Shelley:

```bash
./shelley-yepanywhere-switch.sh   -start   --project-dir /path/to/repo   --shelley-db /path/to/shelley.db
```

Start yepanywhere without bootstrap:

```bash
./shelley-yepanywhere-switch.sh -start --bootstrap-mode none
```

Force a fresh bootstrap:

```bash
./shelley-yepanywhere-switch.sh   -start   --project-dir /path/to/repo   --shelley-db /path/to/shelley.db   --force-bootstrap
```

Return to Shelley:

```bash
./shelley-yepanywhere-switch.sh -stop
```

## Requirements

- bash
- sudo
- systemctl
- npm
- sqlite3
- python3
- jq
- codex
- yepanywhere installable via npm

For port checks, at least one of these:

- ss
- lsof

## Notes

- the systemd service name is expected to be `shelley`
- yepanywhere logs and pid files live under `~/.cache/shelley-yepanywhere-switch/`
- the default shared port is `9999`
