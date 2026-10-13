#!/usr/bin/env bash
# Fixtures for role-picker.sh. Run: bash scripts/hooks/role-picker.test.sh
H="$(dirname "$0")/role-picker.sh"; fails=0
t() { # expect(menu|none) label prompt
  out="$(printf '%s' "{\"prompt\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$3")}" | bash "$H")"
  got=none; case "$out" in *"<role-picker>"*) got=menu;; esac
  [ "$got" = "$1" ] && echo "  ok   $2" || { echo "  FAIL $2 (got $got)"; fails=$((fails+1)); }
}
t menu "bare @agent-role"            "@agent-role"
t menu "bare with text"             "@agent-role fix the failing test"
t menu "unknown role"               "@agent-role-pmm run it"
t none "valid role"                 "@agent-role-dev fix the failing test"
t none "valid ui"                   "@agent-role-ui add a pricing toggle"
t none "no mention"                 "how do roles work"
t none "other agent"                "@agent-bulk-worker list files"
out="$(printf 'garbage' | bash "$H")"; [ -z "$out" ] && echo "  ok   garbage stdin is silent" || { echo "  FAIL garbage"; fails=$((fails+1)); }
printf '%s' '{"prompt":"@agent-role"}' | bash "$H" | grep -c '^- role-' | xargs -I{} echo "  info roles listed: {}"
[ $fails = 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
