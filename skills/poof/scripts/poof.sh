#!/bin/bash
# poof: delete the agent session that runs this script, once that session is done.
#
#   poof.sh "<one-line result headline>"   arm it (the session's last tool call)
#   poof.sh --cancel                        disarm it for the current session
#   poof.sh --status                        say whether it is armed
#
# Works in Claude Code and OpenAI Codex. Arming returns at once; a detached
# worker waits for the session to finish, deletes it with the agent's own CLI,
# and appends one line to $POOF_STATE_DIR/log (default ~/.local/state/poof/log).
#
# Claude Code, background session: waits until `claude agents` shows it idle
#   and done, then `claude stop`, `claude rm` (refuses on unpushed worktree
#   work, and then nothing is deleted), and deletes the transcript files.
# Claude Code, interactive: waits for the person to exit, then deletes the
#   transcript files.
# Codex, `codex exec` or the TUI: waits for the codex process to exit, then
#   `codex delete --force`.
# Codex, app-server thread (desktop app, `codex agents`): waits for the turn's
#   task_complete event and a quiet rollout file, then `codex delete --force`.
set -u

STATE_DIR="${POOF_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/poof}"
LOG="$STATE_DIR/log"
UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"

log() {
  printf '%s %s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${AGENT:-?}" \
    "${SHORT:-????????}" "$*" >>"$LOG"
}

die() {
  echo "poof: $*" >&2
  exit 1
}

# The agent that ran this script is the nearest one up the process tree. Both
# agents' variables can be in the environment when one was started from the
# other (codex run from a Claude Code session), so the environment alone can't
# say which session to delete.
# Prints "claude <pid>", "codex <pid>", or "none"; fails if ps is blocked.
nearest_agent() {
  local p=$PPID comm
  while [ "${p:-0}" -gt 1 ]; do
    if [ "$p" = "${CLAUDE_PID:-}" ]; then
      echo "claude $p"
      return 0
    fi
    comm="$(ps -o comm= -p "$p" 2>/dev/null)" || return 1
    case "$(basename "$comm")" in
      codex | codex-*)
        echo "codex $p"
        return 0
        ;;
    esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  done
  echo none
}

if [ "${1:-}" != "--worker" ]; then
  CODEX_SID="${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-}}"
  if ! found="$(nearest_agent)"; then
    [[ "$CODEX_SID" =~ $UUID_RE ]] &&
      die "can't inspect processes. Inside the Codex sandbox, rerun this exact command with escalated permissions (outside the sandbox)."
    die "can't inspect processes (ps failed)"
  fi
  read -r AGENT OWNER <<<"$found"
  case "$AGENT" in
    claude) SID="${CLAUDE_CODE_SESSION_ID:-}" ;;
    codex) SID="$CODEX_SID" ;;
    *) die "not running inside a Claude Code or Codex session" ;;
  esac
  [[ "$SID" =~ $UUID_RE ]] || die "found a $AGENT process but no $AGENT session id in the environment"
  SHORT="${SID:0:8}"

  if ! mkdir -p "$STATE_DIR" 2>/dev/null || ! touch "$LOG" 2>/dev/null; then
    die "can't write $STATE_DIR. Inside the Codex sandbox, rerun this exact command with escalated permissions (outside the sandbox)."
  fi
  chmod 700 "$STATE_DIR"
  PIDFILE="$STATE_DIR/$SID.pid"

  armed_pid() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && cat "$PIDFILE"
  }

  case "${1:-}" in
    --cancel)
      if pid="$(armed_pid)" && kill "$pid" 2>/dev/null; then
        rm -f "$PIDFILE"
        log "cancelled"
        echo "poof cancelled for $SHORT; the session stays."
      else
        rm -f "$PIDFILE"
        echo "poof was not armed for $SHORT."
      fi
      exit 0
      ;;
    --status)
      if armed_pid >/dev/null; then echo "poof is armed for $SHORT."; else echo "poof is not armed for $SHORT."; fi
      exit 0
      ;;
    -*) die "unknown option $1" ;;
  esac

  if armed_pid >/dev/null; then
    echo "poof is already armed for $SHORT."
    exit 0
  fi
  command -v jq >/dev/null || die "jq is required (brew install jq, or apt install jq)"

  if [ "$AGENT" = claude ]; then
    CLI="$(command -v claude)" || die "the claude CLI is not on PATH"
    MODE=interactive
    if [ -n "${CLAUDE_JOB_DIR:-}" ] && [ "$(basename "$CLAUDE_JOB_DIR")" = "$SHORT" ]; then
      MODE=background
    fi
  else
    CLI="$(command -v codex)" || die "the codex CLI is not on PATH"
    case "$(ps -o command= -p "$OWNER")" in
      *" app-server"*) MODE="app-server" ;;
      *" exec"* | *" e "*) MODE="exec" ;;
      *) MODE="tui" ;;
    esac
  fi

  export POOF_AGENT="$AGENT" POOF_SID="$SID" POOF_OWNER="$OWNER" POOF_MODE="$MODE" \
    POOF_CLI="$CLI" POOF_RESULT="${1:-}" POOF_PIDFILE="$PIDFILE" POOF_STATE_DIR="$STATE_DIR"
  # A new session and process group, so stopping the agent can't take the worker with it.
  nohup /usr/bin/perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' "$0" --worker \
    </dev/null >>"$LOG" 2>&1 &
  echo "$!" >"$PIDFILE"
  echo "poof armed for $SHORT ($AGENT, $MODE). Cancel with: $0 --cancel"
  exit 0
fi

# ---- worker ----
AGENT="$POOF_AGENT"
SID="$POOF_SID"
SHORT="${SID:0:8}"
OWNER="$POOF_OWNER"
CLI="$POOF_CLI"
RESULT="$POOF_RESULT"
echo $$ >"$POOF_PIDFILE"
trap 'rm -f "$POOF_PIDFILE"' EXIT

# Call the CLIs as a plain shell would, not as a child of the session being deleted.
for v in $(env | sed -nE 's/^((CLAUDE|CODEX_)[A-Za-z0-9_]*)=.*/\1/p') AI_AGENT; do
  [ "$v" = CODEX_HOME ] || unset "$v"
done

wait_for_exit() {
  while kill -0 "$OWNER" 2>/dev/null; do sleep 5; done
}

# Claude Code: prints "<status> <state> <name>", "gone gone", or "unknown unknown".
claude_info() {
  local json
  json="$("$CLI" agents --json --all 2>/dev/null)" || {
    echo "unknown unknown"
    return
  }
  printf '%s' "$json" | jq -r --arg id "$SHORT" '
    [.[] | select(.id == $id)][0]
    | if . == null then "gone gone"
      else "\(.status // "none") \(.state // "none") \(.name // "")" end
  ' 2>/dev/null || echo "unknown unknown"
}

claude_wait_done() {
  local start=$SECONDS done_polls=0 stuck_since="" status state name
  while :; do
    [ $((SECONDS - start)) -gt 21600 ] && {
      log "aborted: not done after 6h; nothing deleted | $RESULT"
      exit 1
    }
    read -r status state name <<<"$(claude_info)"
    [ -n "${name:-}" ] && NAME="$name"
    case "$status/$state" in
      busy/*)
        done_polls=0
        stuck_since=""
        ;;
      */done)
        done_polls=$((done_polls + 1))
        [ "$done_polls" -ge 2 ] && return 0
        ;;
      */blocked | */failed)
        done_polls=0
        : "${stuck_since:=$SECONDS}"
        [ $((SECONDS - stuck_since)) -ge 180 ] && {
          log "aborted: session ended $state, not done; nothing deleted | $NAME | $RESULT"
          exit 1
        }
        ;;
      gone/gone)
        log "aborted: session no longer listed; nothing deleted | $RESULT"
        exit 1
        ;;
      *) done_polls=0 ;;
    esac
    sleep 5
  done
}

claude_purge_files() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rm -f "$f"
    rm -rf "${f%.jsonl}"
    rmdir "$(dirname "$f")" 2>/dev/null
  done < <(find "$HOME/.claude/projects" -maxdepth 2 -name "$SID.jsonl" 2>/dev/null)
  rm -rf "$HOME/.claude/session-env/$SID" \
    "$HOME/.claude/file-history/$SID" \
    "$HOME/.claude/tasks/session-$SHORT" \
    "$HOME/.claude/teams/session-$SHORT" \
    "$HOME/.claude/jobs/$SHORT" \
    "$HOME/.claude/debug/$SID.txt"
  rm -f "$HOME/.claude/todos/$SID"*.json
  find "${TMPDIR:-/tmp}" /private/tmp -maxdepth 3 -type d -path "*/claude-*/*/$SID" \
    -exec rm -rf {} + 2>/dev/null
}

# Codex app-server threads outlive their turns; wait for task_complete and a quiet file.
codex_wait_turn_done() {
  local rollout start=$SECONDS last prev_mtime="" mtime quiet=0
  rollout="$(find "$CODEX_DIR/sessions" -name "rollout-*-$SID.jsonl" 2>/dev/null | head -1)"
  [ -n "$rollout" ] || {
    log "aborted: rollout file for this thread not found; nothing deleted | $RESULT"
    exit 1
  }
  while :; do
    [ $((SECONDS - start)) -gt 21600 ] && {
      log "aborted: turn not finished after 6h; nothing deleted | $RESULT"
      exit 1
    }
    last="$(tail -n 1 "$rollout" | jq -r '.payload.type // ""' 2>/dev/null)"
    mtime="$(stat -f %m "$rollout" 2>/dev/null || stat -c %Y "$rollout")"
    if [ "$last" = task_complete ] && [ "$mtime" = "$prev_mtime" ]; then
      quiet=$((quiet + 5))
      [ "$quiet" -ge 15 ] && return 0
    else
      quiet=0
    fi
    prev_mtime="$mtime"
    sleep 5
  done
}

NAME=""
if [ "$AGENT" = claude ]; then
  if [ "$POOF_MODE" = background ]; then
    claude_wait_done
    "$CLI" stop "$SHORT" >/dev/null 2>&1
    for _ in $(seq 60); do
      kill -0 "$OWNER" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$OWNER" 2>/dev/null; then
      log "aborted: process $OWNER still running after stop; nothing deleted | $NAME | $RESULT"
      exit 1
    fi
    if ! out="$("$CLI" rm "$SHORT" 2>&1)"; then
      log "aborted: claude rm refused, transcript kept: $(printf '%s' "$out" | tr '\n' ' ') | $NAME | $RESULT"
      exit 1
    fi
  else
    read -r _ _ NAME <<<"$(claude_info)"
    wait_for_exit
  fi
  claude_purge_files
else
  if [ "$POOF_MODE" = app-server ]; then
    codex_wait_turn_done
  else
    wait_for_exit
  fi
  if ! out="$("$CLI" delete --force "$SID" 2>&1)"; then
    log "aborted: codex delete failed: $(printf '%s' "$out" | tail -n 3 | tr '\n' ' ') | $RESULT"
    exit 1
  fi
fi

log "deleted: ${NAME:-session} | $RESULT"
