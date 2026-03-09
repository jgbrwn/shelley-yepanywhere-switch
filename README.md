# shelley-yepanywhere-switch

A Bash controller script for switching an exe.dev VM between Shelley and yepanywhere on the same port.

This repository contains a small Shell-based controller that automates switching a running VM between the Shelley build and the yepanywhere build on the same port. Below are brief usage notes and a few screenshots that show the bootstrap output and the yepanywhere UI after the bootstrap completes.

## Quick overview

- Language: Shell
- Purpose: Start / stop / switch an exe.dev VM between two projects (Shelley and yepanywhere) while keeping the same network port.

## Prerequisites

- A running exe.dev VM environment where both Shelley and yepanywhere are available.
- Necessary permissions to stop/start services or containers on the VM.
- Bash available (this repo is 100% Shell).

## Usage

1. Place this script on the target VM or machine that controls the exe.dev VM.
2. Make it executable: `chmod +x switch.sh` (or the actual script name in this repo).
3. Run with the appropriate arguments to switch to `shelley` or `yepanywhere` (see the script header / comments for exact flags).

(If you want, I can add a thorough usage section with flags and examples if you provide the script filename and how you normally invoke it.)

## Screenshots

The repository owner provided three screenshots showing the bootstrap console output and the yepanywhere UI after a successful bootstrap. These images are included in this PR under `screenshots/` and referenced below.

Bootstrap / handoff output (initial steps) — these show the codex/bootstrap output and the session handoff text:
- screenshots/bootstrap-1.png (bootstrap part 1)
- screenshots/bootstrap-2.png (bootstrap part 2)

Yepanywhere web UI after bootstrap — the running session in the yepanywhere web UI:
- screenshots/session-after-bootstrap.png

### Bootstrap output (initial validation & handoff)

![Bootstrap output — part 1](./screenshots/bootstrap-1.png)
*Screenshot: bootstrap/codex handoff output and immediate session summary.*  

![Bootstrap output — part 2](./screenshots/bootstrap-2.png)
*Screenshot: continued bootstrap/handoff summary and next-steps.*  

### Yepanywhere web UI after bootstrap

![Yepanywhere session after bootstrap](./screenshots/session-after-bootstrap.png)
*Screenshot: yepanywhere web UI showing an active session after the bootstrap completed.*  