#!/usr/bin/env bash
# ============================================================
# cache-keepalive-stamp.sh  --  Stop + UserPromptSubmit (+ SessionStart --bind)
# ============================================================
# Fast, non-blocking. Records "this session was active now" so the
# background monitor can measure how long *this session* has been idle.
#
# It also records which session this Claude Code process is showing
# (host.<CLAUDE_PID>), so the monitor can follow /resume and /clear. With
# --bind (the SessionStart hook) it does only that; the monitor decides how
# a started or resumed session's heartbeat begins.
#
# With --prompt (the UserPromptSubmit hook) it also records a human prompt in
# last_prompt.<session>, which the monitor's max-idle cap measures from. The
# hook also fires for task notifications -- including the keepalive's own
# pings -- so a prompt that is a <task-notification> is not counted.
#
# Per-session: the heartbeat is keyed by the Claude Code session id
# (CLAUDE_SESSION_ID, falling back to the stdin session_id), so multiple
# concurrent sessions keep independent idle timers. A global last_stop
# is also written as a fallback for a monitor that cannot see a session id.
# ============================================================
set -uo pipefail

BIND_ONLY=0
PROMPT=0
case "${1:-}" in
  --bind)   BIND_ONLY=1 ;;
  --prompt) PROMPT=1 ;;
esac

STATE_DIR="${CCKA_STATE_DIR:-$HOME/.claude/cache-keepalive}"
mkdir -p "$STATE_DIR" 2>/dev/null || true

input="$(cat 2>/dev/null || true)"
now="$(date +%s)"

# key preference must match the monitor: env first, then the hook's stdin
key="${CLAUDE_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -z "$key" ]; then
  key="$(printf '%s' "$input" \
    | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
[ -n "$key" ] || key="default"
safe="$(printf '%s' "$key" | tr -c 'A-Za-z0-9._-' '_')"

case "${CLAUDE_PID:-}" in
  ''|*[!0-9]*) : ;;
  *)
    hostfile="$STATE_DIR/host.$CLAUDE_PID"
    prev="$(cat "$hostfile" 2>/dev/null || true)"
    if [ "$prev" != "$safe" ]; then
      printf '%s' "$safe" > "$hostfile" 2>/dev/null || true
      # hand the running monitor's pid file to the new session, so the
      # SessionEnd cleanup and the ctl script find it under the current id
      if [ -n "$prev" ] && [ -f "$STATE_DIR/monitor.$prev.pid" ]; then
        mv -f "$STATE_DIR/monitor.$prev.pid" "$STATE_DIR/monitor.$safe.pid" 2>/dev/null || true
      fi
    fi
    ;;
esac
[ "$BIND_ONLY" = 1 ] && exit 0

printf '%s' "$now" > "$STATE_DIR/last_stop.$safe" 2>/dev/null || true
printf '%s' "$now" > "$STATE_DIR/last_stop"       2>/dev/null || true   # fallback
printf '%s' "$safe" > "$STATE_DIR/last_session"   2>/dev/null || true

if [ "$PROMPT" = 1 ] && ! printf '%s' "$input" \
     | grep -q '"prompt"[[:space:]]*:[[:space:]]*"[[:space:]]*<task-notification>'; then
  printf '%s' "$now" > "$STATE_DIR/last_prompt.$safe" 2>/dev/null || true
  printf '%s' "$now" > "$STATE_DIR/last_prompt"       2>/dev/null || true   # fallback
fi

exit 0
