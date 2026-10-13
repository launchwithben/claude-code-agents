#!/usr/bin/env bash
# Fixtures for role-handback-check.sh.   bash scripts/hooks/role-handback-check.test.sh
set -uo pipefail
cd "$(dirname "$0")"
H=./role-handback-check.sh
fails=0
rm -rf ../../tmp/role-handback
run() { # <role> <agent_id> <message>  -> exit code
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"SubagentStop","agent_type":sys.argv[1],"agent_id":sys.argv[2],"last_assistant_message":sys.argv[3]}))' "$1" "$2" "$3" | "$H" "$1" >/dev/null 2>&1
  return $?
}
t() { # <want> <label> <role> <id> <msg>
  run "$3" "$4" "$5"; local got=$?
  if [ "$got" = "$1" ]; then printf '  ok   %s\n' "$2"; else printf '  FAIL %s (want %s got %s)\n' "$2" "$1" "$got"; fails=$((fails+1)); fi
}
UI_OK=$'done\nGATE: npm run check -> PASS\nSCREENSHOTS: tmp/qa-shots/\nCOMMIT: abc'
t 2 "ui: no evidence -> BLOCK"            role-ui a1 "All done, looks great."
t 2 "ui: gate but no screenshots -> BLOCK" role-ui a2 $'GATE: npm run check -> PASS'
t 2 "ui: gate FAIL -> BLOCK"              role-ui a3 $'GATE: npm run check -> FAIL\nSCREENSHOTS: x'
t 0 "ui: full evidence -> ALLOW"          role-ui a4 "$UI_OK"
t 0 "ui: GATE-SKIPPED -> ALLOW"           role-ui a5 $'GATE-SKIPPED: preflight needs network, unavailable'
t 2 "ui: GATE-SKIPPED with no reason -> BLOCK" role-ui a6 $'GATE-SKIPPED:'
t 2 "dev: no gate -> BLOCK"               role-dev b1 "finished"
t 0 "dev: gate line -> ALLOW"             role-dev b2 $'GATE: npm run check -> exit 0'
t 2 "concept: shots only -> BLOCK"        role-concept c1 $'SCREENSHOTS: tmp/qa-shots'
t 0 "concept: shots + note -> ALLOW"      role-concept c2 $'SCREENSHOTS: tmp/qa-shots\nCONCEPT-NOTE: docs/concepts/x.md'
# 2 consecutive blocks then release
t 2 "release: block 1" role-dev r1 "nope"
t 2 "release: block 2" role-dev r1 "nope"
t 0 "release: 3rd attempt allowed" role-dev r1 "nope"
# fail-open cases
printf 'not json' | "$H" role-ui >/dev/null 2>&1; [ $? = 0 ] && echo "  ok   garbage stdin fails open" || { echo "  FAIL garbage stdin"; fails=$((fails+1)); }
printf '' | "$H" role-ui >/dev/null 2>&1; [ $? = 0 ] && echo "  ok   empty stdin fails open" || { echo "  FAIL empty stdin"; fails=$((fails+1)); }
printf '{"agent_type":"role-ui"}' | "$H" bogus-role >/dev/null 2>&1; [ $? = 0 ] && echo "  ok   unknown role fails open" || { echo "  FAIL unknown role"; fails=$((fails+1)); }
python3 -c 'import json;print(json.dumps({"agent_type":"bulk-worker","last_assistant_message":"x"}))' | "$H" role-ui >/dev/null 2>&1; [ $? = 0 ] && echo "  ok   other agent_type not judged" || { echo "  FAIL other agent"; fails=$((fails+1)); }
rm -rf ../../tmp/role-handback
[ "$fails" = 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
