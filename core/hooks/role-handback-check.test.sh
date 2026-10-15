#!/usr/bin/env bash
# Fixtures for role-handback-check.   bash core/hooks/role-handback-check.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/_testlib.sh"
t_syntax "$here/role-handback-check.sh" "$here/role-handback-check.py" "$here/_kit.py"
H="$here/role-handback-check.sh"
t_proj '{"prefix":"acme","handback":{"audit":["gate","line:REPORT"],"ackpm":["line:CURSOR~\\S+ -> ACKED"],"badre":["line:X~("]},"extraRoles":[{"name":"docs","description":"d","contract":["gate"]}]}'
run() { # <role> <agent_id> <message> -> exit code
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"SubagentStop","agent_type":sys.argv[1],"agent_id":sys.argv[2],"last_assistant_message":sys.argv[3]}))' "$1" "$2" "$3" | "$H" "$1" >/dev/null 2>&1
}
t() { run "$3" "$4" "$5"; t_eq "$1" "$?" "$2"; }
UI_OK=$'done\nGATE: npm run check -> PASS\nSCREENSHOTS: tmp/qa-shots/\nCOMMIT: abc1234'
t 2 "ui: no evidence -> BLOCK"                  acme-ui a1 "All done, looks great."
t 2 "ui: gate but no screenshots -> BLOCK"      acme-ui a2 $'GATE: npm run check -> PASS'
t 2 "ui: gate FAIL -> BLOCK"                    acme-ui a3 $'GATE: npm run check -> FAIL\nSCREENSHOTS: x'
t 0 "ui: full evidence -> ALLOW"                acme-ui a4 "$UI_OK"
t 0 "ui: GATE-SKIPPED -> ALLOW"                 acme-ui a5 $'GATE-SKIPPED: preflight needs network, unavailable'
t 2 "ui: GATE-SKIPPED with no reason -> BLOCK"  acme-ui a6 $'GATE-SKIPPED:'
t 2 "dev: no gate -> BLOCK"                     acme-dev b1 "finished"
t 0 "dev: gate line -> ALLOW"                   acme-dev b2 $'GATE: npm run check -> exit 0'
t 2 "concept: shots only -> BLOCK"              acme-concept c1 $'SCREENSHOTS: tmp/qa-shots'
t 0 "concept: shots + note -> ALLOW"            acme-concept c2 $'SCREENSHOTS: tmp/qa-shots\nCONCEPT-NOTE: docs/concepts/x.md'
t 2 "pm: no cursor line -> BLOCK"               acme-pm p1 "triaged 4 issues"
t 0 "pm: cursor line -> ALLOW"                  acme-pm p2 $'CURSOR: 2026-10-14T10:00:00Z -> ACKED'
t 0 "pm: skipped run, no ack -> ALLOW"          acme-pm p3 $'GATE-SKIPPED: board API rate limited'
# contracts from the overlay: a custom line, an extra role
t 2 "overlay: custom role missing REPORT line"  acme-audit au1 $'GATE: make test -> PASS'
t 0 "overlay: custom role with both"            acme-audit au2 $'GATE: make test -> PASS\nREPORT: docs/audit.md'
t 2 "overlay: extra role needs a gate"          acme-docs e1 "docs updated"
t 0 "overlay: extra role with gate"             acme-docs e2 $'GATE: make docs -> PASS'
# pattern evidence: line:NAME~REGEX
t 2 "pattern: cursor not acked -> BLOCK"          acme-ackpm k1 $'CURSOR: 2026-10-14T10:00:00Z'
t 2 "pattern: cursor with a different ending -> BLOCK" acme-ackpm k2 $'CURSOR: 2026-10-14T10:00:00Z -> PENDING'
t 2 "pattern: no cursor line at all -> BLOCK"     acme-ackpm k3 "done"
t 0 "pattern: cursor acked -> ALLOW"              acme-ackpm k4 $'CURSOR: 2026-10-14T10:00:00Z -> ACKED'
t 0 "pattern: GATE-SKIPPED still releases"        acme-ackpm k5 $'GATE-SKIPPED: rate limited'
t 0 "pattern: a regex that does not compile fails open" acme-badre k6 "anything"
# suffix match: a differently prefixed role still gets the contract of its suffix
t 2 "suffix: other-prefix ui needs evidence"    other-ui f1 "done"
t 0 "no contract for the role -> ALLOW"         acme-unknown g1 "whatever"
# 2 consecutive blocks then release
t 2 "release: block 1"                          acme-dev r1 "nope"
t 2 "release: block 2"                          acme-dev r1 "nope"
t 0 "release: 3rd attempt allowed"              acme-dev r1 "nope"
# fail-open cases
printf 'not json' | "$H" acme-ui >/dev/null 2>&1;            t_eq 0 "$?" "garbage stdin fails open"
printf '{"agent_type": ' | "$H" acme-ui >/dev/null 2>&1;     t_eq 0 "$?" "truncated JSON fails open"
printf '' | "$H" acme-ui >/dev/null 2>&1;                    t_eq 0 "$?" "empty stdin fails open"
printf '{"agent_type":"acme-ui"}' | "$H" bogus-role >/dev/null 2>&1; t_eq 0 "$?" "unknown role fails open"
python3 -c 'import json;print(json.dumps({"agent_type":"bulk-worker","last_assistant_message":"x"}))' | "$H" acme-ui >/dev/null 2>&1
t_eq 0 "$?" "another agent_type is not judged"
printf 'garbage' > "$T_ROOT/roles.config.json"
python3 -c 'import json;print(json.dumps({"agent_type":"acme-dev","agent_id":"z","last_assistant_message":"x"}))' | "$H" acme-dev >/dev/null 2>&1
t_eq 2 "$?" "unparseable overlay falls back to default contracts (still judges)"
t_done
