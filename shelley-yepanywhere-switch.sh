#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# shelley-yepanywhere-switch.sh
#
# Purpose:
#   - Install/update yepanywhere
#   - On -start:
#       * stop shelley and shelley.socket (via sudo systemctl)
#       * verify port is free
#       * start yepanywhere on port 9999 as the regular user
#       * if needed, bootstrap a new Codex conversation for the current project
#         from the latest relevant Shelley conversation
#   - On -stop:
#       * stop yepanywhere as the regular user
#       * start shelley (via sudo systemctl)
#
# Design:
#   - Shelley conversation discovery is project-aware via conversations.cwd
#   - Bootstrap is idempotent via a project-local marker file
#   - Bootstrap uses a generated handoff file + codex exec prompt
#   - We do NOT try to mutate Codex session files directly
#   - Only systemctl operations use sudo
###############################################################################

PORT="${PORT:-9999}"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/shelley-yepanywhere-switch"
PIDFILE="${PIDFILE:-${CACHE_DIR}/yepanywhere.pid}"
LOGFILE="${LOGFILE:-${CACHE_DIR}/yepanywhere.log}"

PROJECT_DIR="${PROJECT_DIR:-$(pwd -P)}"
SHELLEY_DB="${SHELLEY_DB:-}"

BOOTSTRAP_MODE="exec"          # exec | interactive | none
FORCE_BOOTSTRAP="false"
MAX_MESSAGES="${MAX_MESSAGES:-80}"

STATE_DIR_REL=".codex-handoff"
STATE_DIR=""
HANDOFF_MD=""
HANDOFF_JSONL=""
BOOTSTRAP_OUTPUT=""
BOOTSTRAP_MARKER=""
BOOTSTRAP_META=""

usage() {
  cat <<EOF
Usage:
  $0 -start [options]
  $0 -stop  [options]

Actions:
  -start                  Stop shelley/shelley.socket, install/update yepanywhere, start yepanywhere on port ${PORT},
                          and bootstrap a Codex session from Shelley if needed.
  -stop                   Stop yepanywhere and start shelley.

Options:
  --project-dir PATH      Project directory to use (default: current directory)
  --shelley-db PATH       Path to Shelley sqlite database
  --force-bootstrap       Recreate Shelley->Codex bootstrap even if already done
  --bootstrap-mode MODE   exec | interactive | none   (default: exec)
  --max-messages N        Number of recent Shelley messages to include (default: ${MAX_MESSAGES})
  --port N                yepanywhere port (default: ${PORT})
  -h, --help              Show this help

Examples:
  $0 -start --project-dir /workspace/myrepo --shelley-db /path/to/shelley.db
  $0 -start --project-dir /workspace/myrepo --shelley-db /path/to/shelley.db --force-bootstrap
  $0 -start --bootstrap-mode none
  $0 -stop
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

canon_path() {
  python3 - <<'PY' "$1"
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
}

setup_paths() {
  PROJECT_DIR="$(canon_path "${PROJECT_DIR}")"
  STATE_DIR="${PROJECT_DIR}/${STATE_DIR_REL}"
  HANDOFF_MD="${STATE_DIR}/shelley-bootstrap.md"
  HANDOFF_JSONL="${STATE_DIR}/shelley-bootstrap.jsonl"
  BOOTSTRAP_OUTPUT="${STATE_DIR}/codex-bootstrap-output.txt"
  BOOTSTRAP_MARKER="${STATE_DIR}/shelley-bootstrap.done"
  BOOTSTRAP_META="${STATE_DIR}/shelley-bootstrap.meta"
}

parse_args() {
  [[ $# -ge 1 ]] || { usage; exit 1; }

  ACTION=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -start)
        ACTION="-start"
        shift
        ;;
      -stop)
        ACTION="-stop"
        shift
        ;;
      --project-dir)
        PROJECT_DIR="$2"
        shift 2
        ;;
      --shelley-db)
        SHELLEY_DB="$2"
        shift 2
        ;;
      --force-bootstrap)
        FORCE_BOOTSTRAP="true"
        shift
        ;;
      --bootstrap-mode)
        BOOTSTRAP_MODE="$2"
        shift 2
        ;;
      --max-messages)
        MAX_MESSAGES="$2"
        shift 2
        ;;
      --port)
        PORT="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  [[ -n "${ACTION}" ]] || die "You must specify -start or -stop."
  [[ "${BOOTSTRAP_MODE}" =~ ^(exec|interactive|none)$ ]] || die "--bootstrap-mode must be exec, interactive, or none"

  setup_paths
}

ensure_cache_dir() {
  mkdir -p "${CACHE_DIR}"
}

require_sudo_for_systemctl() {
  if ! sudo -n true 2>/dev/null; then
    cat >&2 <<'EOF'
ERROR: sudo access is required for controlling the shelley service.

This script only uses sudo for:
  - systemctl stop shelley shelley.socket
  - systemctl start shelley

Run a sudo command manually first to refresh your sudo timestamp,
or configure sudo access for this user.
EOF
    exit 1
  fi
}

require_codex_auth_if_needed() {
  if [[ "${BOOTSTRAP_MODE}" == "none" ]]; then
    return 0
  fi

  if ! codex login status >/dev/null 2>&1; then
    cat >&2 <<'EOF'
ERROR: Codex CLI is not authenticated.

Shelley->Codex bootstrap requires a logged-in Codex CLI session.

Authenticate first with one of:
  codex login
  codex login --device-auth
  printenv OPENAI_API_KEY | codex login --with-api-key

Then rerun the script.
EOF
    exit 1
  fi
}

install_or_update_yepanywhere() {
  log "Installing/updating yepanywhere..."
  require_cmd npm
  npm i -g yepanywhere
}

stop_shelley() {
  if systemctl is-active --quiet shelley; then
    log "Stopping shelley..."
    sudo systemctl stop shelley shelley.socket
  else
    log "shelley already stopped"
  fi
}

start_shelley() {
  log "Starting shelley..."
  sudo systemctl start shelley
}

stop_yepanywhere() {
  log "Stopping yepanywhere if running..."

  if [[ -f "${PIDFILE}" ]]; then
    local pid
    pid="$(cat "${PIDFILE}" || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" || true
      sleep 2
      if kill -0 "${pid}" 2>/dev/null; then
        log "Force killing yepanywhere PID ${pid}..."
        kill -9 "${pid}" || true
      fi
    fi
    rm -f "${PIDFILE}"
  fi

  pkill -f '(^|/)(node .*)?yepanywhere($| )' 2>/dev/null || true
}

port_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :${PORT} )" | awk 'NR > 1 {found=1} END {exit !found}'
    return
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"${PORT}" -sTCP:LISTEN -Pn >/dev/null 2>&1
    return
  fi

  die "Neither ss nor lsof is available for port checking."
}

describe_port_holder() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN || true
    return
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "( sport = :${PORT} )" || true
    return
  fi
}

ensure_port_free_for_yepanywhere() {
  if port_in_use; then
    echo >&2
    echo "ERROR: port ${PORT} is still in use." >&2
    echo "Listener details:" >&2
    describe_port_holder >&2 || true
    echo >&2

    if systemctl is-active --quiet shelley; then
      echo "shelley still appears to be active and may still be holding port ${PORT}." >&2
    else
      echo "Another process appears to be holding port ${PORT}." >&2
    fi

    echo "Stop the conflicting process and rerun the script." >&2
    exit 1
  fi
}

start_yepanywhere() {
  log "Starting yepanywhere on port ${PORT} as user ${USER}..."
  require_cmd yepanywhere
  ensure_cache_dir
  ensure_port_free_for_yepanywhere

  touch "${LOGFILE}"

  nohup env PORT="${PORT}" yepanywhere >> "${LOGFILE}" 2>&1 &
  echo $! > "${PIDFILE}"
  sleep 3

  if kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
    if port_in_use; then
      log "yepanywhere started successfully (PID $(cat "${PIDFILE}"))"
      log "Logs: ${LOGFILE}"
    else
      die "yepanywhere process started but port ${PORT} is not listening. Check ${LOGFILE}"
    fi
  else
    die "Failed to start yepanywhere. Check ${LOGFILE}"
  fi
}

validate_start_requirements() {
  require_cmd sqlite3
  require_cmd python3
  require_cmd jq

  [[ -d "${PROJECT_DIR}" ]] || die "Project directory does not exist: ${PROJECT_DIR}"

  if [[ "${BOOTSTRAP_MODE}" != "none" ]]; then
    require_cmd codex
    [[ -n "${SHELLEY_DB}" ]] || die "--shelley-db is required for bootstrap mode ${BOOTSTRAP_MODE}"
    [[ -f "${SHELLEY_DB}" ]] || die "Shelley DB not found: ${SHELLEY_DB}"
  fi
}

bootstrap_already_done() {
  [[ -f "${BOOTSTRAP_MARKER}" ]]
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

latest_shelley_conversation_id_for_project() {
  sqlite3 -noheader -batch "${SHELLEY_DB}" "
    SELECT conversation_id
    FROM conversations
    WHERE cwd = '$(sql_escape "${PROJECT_DIR}")'
      AND COALESCE(parent_conversation_id, '') = ''
      AND COALESCE(archived, 0) = 0
    ORDER BY updated_at DESC
    LIMIT 1;
  "
}

write_handoff_from_shelley() {
  local conv_id
  conv_id="$(latest_shelley_conversation_id_for_project)"

  if [[ -z "${conv_id}" ]]; then
    log "No Shelley conversation found for project: ${PROJECT_DIR}"
    return 1
  fi

  log "Found latest Shelley conversation: ${conv_id}"
  mkdir -p "${STATE_DIR}"

  local conv_meta
  conv_meta="$(
    sqlite3 -json "${SHELLEY_DB}" "
      SELECT
        conversation_id,
        slug,
        cwd,
        created_at,
        updated_at,
        COALESCE(parent_conversation_id, '') AS parent_conversation_id,
        COALESCE(archived, 0) AS archived
      FROM conversations
      WHERE conversation_id = '$(sql_escape "${conv_id}")'
      LIMIT 1;
    "
  )"

  local messages_json
  messages_json="$(
    sqlite3 -json "${SHELLEY_DB}" "
      SELECT
        sequence_id,
        message_id,
        type,
        created_at,
        COALESCE(excluded_from_context, 0) AS excluded_from_context,
        COALESCE(llm_data, '{}') AS llm_data,
        COALESCE(user_data, '{}') AS user_data,
        COALESCE(usage_data, '{}') AS usage_data
      FROM messages
      WHERE conversation_id = '$(sql_escape "${conv_id}")'
        AND COALESCE(excluded_from_context, 0) = 0
      ORDER BY sequence_id DESC
      LIMIT ${MAX_MESSAGES};
    " | jq 'reverse'
  )"

  jq -c '.[]' <<<"${messages_json}" > "${HANDOFF_JSONL}"

  local rendered_transcript
  rendered_transcript="$(
    jq -r '
      def parse_json:
        if type == "string" then
          (try fromjson catch .)
        else .
        end;

      def gather_strings:
        [
          .text?,
          .content?,
          .message?,
          .prompt?,
          .output_text?,
          .input_text?,
          .display_text?,
          .title?,
          .body?,
          .summary?,
          .error?,
          .stderr?,
          .stdout?
        ]
        | map(select(type == "string" and length > 0));

      def smart_text:
        (
          (.user_data | parse_json | gather_strings) +
          (.llm_data  | parse_json | gather_strings)
        ) as $s
        | if ($s|length) > 0
          then ($s | join("\n") | gsub("\r"; "") | gsub("\n{3,}"; "\n\n"))
          else "(No simple text extract found; see shelley-bootstrap.jsonl)"
          end;

      .[]
      | "### [" + (.sequence_id|tostring) + "] " + .type + " @ " + .created_at + "\n\n"
        + smart_text + "\n"
    ' <<<"${messages_json}"
  )"

  cat > "${HANDOFF_MD}" <<EOF
# Shelley → Codex bootstrap handoff

This file was generated automatically from Shelley's SQLite database.

## Project
- Project directory: \`${PROJECT_DIR}\`
- Generated at: \`$(date -Is)\`

## Source Shelley conversation
\`\`\`json
$(jq '.' <<<"${conv_meta}")
\`\`\`

## How to use this handoff
Read this file first, then also inspect:
- \`${STATE_DIR_REL}/shelley-bootstrap.jsonl\`

Treat the Shelley conversation as prior project context.
Your goals:
1. Reconstruct the important project state from the prior Shelley conversation.
2. Identify decisions already made, constraints, blockers, and immediate next steps.
3. Continue the work from there without repeating already-resolved exploration.
4. If any detail is ambiguous, say so explicitly and use the repository state to verify it.

## Approximate extracted transcript
${rendered_transcript}
EOF

  cat > "${BOOTSTRAP_META}" <<EOF
conversation_id=${conv_id}
project_dir=${PROJECT_DIR}
generated_at=$(date -Is)
max_messages=${MAX_MESSAGES}
EOF

  log "Wrote handoff markdown: ${HANDOFF_MD}"
  log "Wrote raw handoff JSONL: ${HANDOFF_JSONL}"
  return 0
}

run_codex_bootstrap_exec() {
  log "Creating bootstrap Codex session with codex exec..."

  local prompt
  prompt=$(
    cat <<EOF
Read ${STATE_DIR_REL}/shelley-bootstrap.md completely, and inspect ${STATE_DIR_REL}/shelley-bootstrap.jsonl if needed.

This repository was previously worked on in Shelley. The handoff file contains the prior conversation context for this same project.

Your task:
- absorb the prior Shelley context
- restate the current project state
- list unresolved issues or next steps
- propose the single best immediate next action
- do not make code changes yet unless they are strictly necessary for understanding the repo

Write a concise but useful continuation summary.
EOF
  )

  (
    cd "${PROJECT_DIR}"
    codex exec "${prompt}"
  ) | tee "${BOOTSTRAP_OUTPUT}"

  touch "${BOOTSTRAP_MARKER}"
  log "Bootstrap Codex session created."
  log "Output saved to ${BOOTSTRAP_OUTPUT}"
}

run_codex_bootstrap_interactive() {
  log "Starting interactive Codex bootstrap session..."

  local prompt
  prompt=$(
    cat <<EOF
Read ${STATE_DIR_REL}/shelley-bootstrap.md completely, and inspect ${STATE_DIR_REL}/shelley-bootstrap.jsonl if needed.

This repository was previously worked on in Shelley. The handoff file contains the prior conversation context for this same project.

Please:
- absorb the prior Shelley context
- restate current project state
- identify unresolved issues and immediate next steps
- continue from there without repeating settled work
EOF
  )

  touch "${BOOTSTRAP_MARKER}"
  (
    cd "${PROJECT_DIR}"
    exec codex "${prompt}"
  )
}

maybe_bootstrap_codex_from_shelley() {
  if [[ "${BOOTSTRAP_MODE}" == "none" ]]; then
    log "Bootstrap mode is 'none'; skipping Shelley -> Codex handoff."
    return 0
  fi

  if [[ "${FORCE_BOOTSTRAP}" != "true" ]] && bootstrap_already_done; then
    log "Bootstrap marker already exists; skipping Shelley -> Codex bootstrap."
    log "Marker: ${BOOTSTRAP_MARKER}"
    return 0
  fi

  if ! write_handoff_from_shelley; then
    log "No matching Shelley conversation found for this project; skipping bootstrap."
    return 0
  fi

  case "${BOOTSTRAP_MODE}" in
    exec)
      run_codex_bootstrap_exec
      ;;
    interactive)
      run_codex_bootstrap_interactive
      ;;
    *)
      die "Unsupported bootstrap mode: ${BOOTSTRAP_MODE}"
      ;;
  esac
}

main() {
  parse_args "$@"

  case "${ACTION}" in
    -start)
      validate_start_requirements
      require_sudo_for_systemctl
      require_codex_auth_if_needed
      install_or_update_yepanywhere
      stop_yepanywhere
      stop_shelley
      ensure_port_free_for_yepanywhere
      start_yepanywhere
      maybe_bootstrap_codex_from_shelley
      ;;
    -stop)
      require_sudo_for_systemctl
      stop_yepanywhere
      start_shelley
      ;;
    *)
      die "Unknown action: ${ACTION}"
      ;;
  esac
}

main "$@"
