#!/usr/bin/env bash
# ask.sh <role> "<brief>"   hand ONE task to a role, headless, and print its handback.
# ask.sh --list             one line per role (read live from the agent files)
#
# <role> is the full name (acme-dev) or just the suffix (dev). Why headless: roles load at process start, so a long
# chat cannot spawn one it did not start with, and /clear does not reload them. A fresh `claude -p --agent` is also
# the cheap shape: a small context that exits, instead of loading a subsystem into the lead's long-lived chat.
# Logs one line per call to <root>/tmp/roles/roles.jsonl (role, secs, cost, turns): the measurement for whether
# roles pay. <root> = $CLAUDE_PROJECT_DIR, else the current directory.
# Env: ROLE_TIMEOUT_SECS (default 1800), ROLE_PERMISSION_MODE (default acceptEdits), CLAUDE_BIN (default claude).
# Limit: hooks in agent files do not run under `claude -p`; the territory guard registered in settings still does
# (ROLE_KIT_ROLE tells it who is calling).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" && pwd)"
helper="$here/ask_helper.py"
prefix="$(python3 "$here/../hooks/_kit.py" cfg "$root" prefix role)"
role="${1:-}"; brief="${2:-}"
agents="$root/.claude/agents"; [ -d "$agents" ] || agents="$HOME/.claude/agents"
if [ "$role" = "--list" ]; then python3 "$helper" list "$agents" "$prefix"; exit 0; fi
case "$role" in "$prefix"-*) ;; *) role="$prefix-$role" ;; esac
if [ ! -f "$agents/$role.md" ] || [ -z "$brief" ]; then
  echo "usage: ask.sh <role> \"<brief>\"   roles: $(cd "$agents" 2>/dev/null && ls "$prefix"-*.md 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')" >&2
  exit 2
fi
log="$root/tmp/roles/roles.jsonl"
mkdir -p "$root/tmp/roles"
start=$(date +%s)
tcmd=""; command -v timeout >/dev/null 2>&1 && tcmd="timeout ${ROLE_TIMEOUT_SECS:-1800}"
out=$(cd "$root" && ROLE_KIT_ROLE="$role" $tcmd "${CLAUDE_BIN:-claude}" -p --agent "$role" \
        --permission-mode "${ROLE_PERMISSION_MODE:-acceptEdits}" --output-format json "$brief" 2>>"$root/tmp/roles/roles.log")
rc=$?
secs=$(( $(date +%s) - start ))
printf '%s' "$out" | python3 "$helper" log "$log" "$role" "$rc" "$secs" "$brief" 2>/dev/null
result="$(printf '%s' "$out" | python3 "$helper" field result 2>/dev/null)"
[ -n "$result" ] || result="$out"
# Global Stop hooks can make a headless role keep talking after its handback, and -p returns only the LAST message.
# So if the result carries no handback line, print the last message in the role's transcript that does.
if ! printf '%s\n' "$result" | grep -qE '^(ANSWER|COMMIT|GATE|GATE-SKIPPED|OUT-OF-SCOPE|CURSOR):'; then
  sid="$(printf '%s' "$out" | python3 "$helper" field session_id 2>/dev/null)"
  if [ -n "$sid" ]; then
    hb="$(python3 "$helper" recover "$sid" 2>/dev/null)"
    [ -n "$hb" ] && result="$hb"$'\n\n'"(handback recovered from the transcript; the final message was: ${result:0:200})"
  fi
fi
printf '%s\n' "$result"
exit $rc
