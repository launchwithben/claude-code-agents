#!/usr/bin/env bash
# Fixtures for lead-heartbeat-check.   bash core/hooks/lead-heartbeat-check.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/_testlib.sh"
t_syntax "$here/lead-heartbeat-check.sh" "$here/lead-heartbeat-check.py"
command -v node >/dev/null 2>&1 || { echo "  skip node is not installed (the lead hooks need node 18+)"; echo "ALL PASS"; exit 0; }
H="$here/lead-heartbeat-check.sh"
t_proj '{"prefix":"acme","mainBranch":"main","chains":"docs/pm/chains.md"}'
export LEAD_PROJECTS_DIR="$T_ROOT/projects"; mkdir -p "$LEAD_PROJECTS_DIR" "$T_ROOT/tmp/lead" "$T_ROOT/docs/pm"
L="$T_ROOT/tmp/lead/inflight.jsonl"; C="$T_ROOT/docs/pm/chains.md"
git init -q -b main "$T_ROOT" 2>/dev/null
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; SHA=deadbee0000000000000000000000000000000
hb() { # <session> [stop_hook_active]
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"Stop","session_id":sys.argv[1],"stop_hook_active":sys.argv[2]=="1","last_assistant_message":"x"}))' "$1" "${2:-0}" | bash "$H" >"$T_ROOT/err" 2>&1
  return $?
}
row() { # <session> <agent> [done-commit]
  printf '{"ev":"dispatch","time":"%s","agent_id":"%s","subagent_type":"acme-dev","description":"d","issue":6,"session_id":"%s"}\n' "$NOW" "$2" "$1"
  [ -n "${3:-}" ] && printf '{"ev":"done","time":"%s","agent_id":"%s","commit":"%s","branch":"b"}\n' "$NOW" "$2" "$3"; return 0
}
printf '# Chains\n\n## Ready chains\n\n### 1. Drift gates\n- x\n\n## Blocked chains\n\n### A. not launchable\n' > "$C"

: > "$L"
hb s1;                       t_eq 0 "$?" "a session that never dispatched + a launchable chain => ALLOW (ordinary sessions untouched)"
row s1 d0 $SHA > "$L"
hb s1;                       t_eq 2 "$?" "this session dispatched, none running, chain launchable => BLOCK"
grep -q "Drift gates" "$T_ROOT/err" && t_pass "the message names the chain" || t_fail "the message names the chain"
grep -qi "not launchable" "$T_ROOT/err" && t_fail "a chain under Blocked leaked into the message" || t_pass "chains under Blocked are not launchable"
hb s1;                       t_eq 0 "$?" "same state, same session => released (block once)"
hb s2 1;                     t_eq 0 "$?" "stop_hook_active => ALLOW"

printf '# Chains\n\n## Ready chains\n\n## Blocked chains\n' > "$C"
hb s3;                       t_eq 0 "$?" "nothing to do => ALLOW"

row s4 r1 > "$L"
printf '# C\n\n## Ready chains\n\n### 1. X\n' > "$C"
hb s4;                       t_eq 0 "$?" "a role is running => ALLOW (the lead is correctly waiting)"

row s5 r2 $SHA > "$L"
printf '# C\n\n## Ready chains\n' > "$C"
hb s5;                       t_eq 2 "$?" "finished-not-landed work, no chain => BLOCK"
grep -q "LAND acme-dev #6" "$T_ROOT/err" && t_pass "the message says LAND #6" || t_fail "the message says LAND #6"
hb s5;                       t_eq 0 "$?" "released on the second attempt"
hb s7;                       t_eq 0 "$?" "another session's finished-unlanded rows are ignored"
printf '{"ev":"dispatch","time":"%s","agent_id":"r9","subagent_type":"acme-dev","description":"d","issue":6}\n{"ev":"done","time":"%s","agent_id":"r9","commit":"%s","branch":"b"}\n' "$NOW" "$NOW" "$SHA" > "$L"
hb s8;                       t_eq 0 "$?" "rows without a session_id are ignored"
echo '{"hook_event_name":"Stop"}' | bash "$H" >/dev/null 2>&1; t_eq 0 "$?" "no session_id in the payload => ALLOW"
printf 'garbage' | bash "$H" >/dev/null 2>&1;  t_eq 0 "$?" "garbage stdin fails open"
printf '' | bash "$H" >/dev/null 2>&1;         t_eq 0 "$?" "empty stdin fails open"
printf '{"session_id":' | bash "$H" >/dev/null 2>&1; t_eq 0 "$?" "truncated JSON fails open"
t_done
