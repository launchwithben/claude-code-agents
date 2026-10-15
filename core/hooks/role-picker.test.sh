#!/usr/bin/env bash
# Fixtures for role-picker.   bash core/hooks/role-picker.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/_testlib.sh"
t_syntax "$here/role-picker.sh" "$here/role-picker.py"
H="$here/role-picker.sh"
t_proj '{"prefix":"acme"}'
export HOME="$T_ROOT/home"; mkdir -p "$HOME"   # never read the real ~/.claude/agents
mkdir -p "$T_ROOT/.claude/agents"
for r in lead dev ui; do
  printf -- '---\nname: acme-%s\ndescription: >-\n  The %s role. Does %s work. Third sentence.\n---\nbody\n' "$r" "$r" "$r" > "$T_ROOT/.claude/agents/acme-$r.md"
done
p() { python3 -c 'import json,sys;print(json.dumps({"prompt":sys.argv[1]}))' "$1" | bash "$H"; }
want() { # <menu|none> <label> <prompt>
  out="$(p "$3")"; got=none; case "$out" in *"<role-picker>"*) got=menu;; esac
  t_eq "$1" "$got" "$2"
}
want menu "bare @agent-acme"              "@agent-acme"
want menu "bare with text"               "@agent-acme fix the failing test"
want menu "unknown role"                 "@agent-acme-pmm run it"
want none "valid role"                   "@agent-acme-dev fix the failing test"
want none "valid ui"                     "@agent-acme-ui add a pricing toggle"
want none "no mention"                   "how do roles work"
want none "other agent"                  "@agent-bulk-worker list files"
want none "other prefix"                 "@agent-role fix it"
want menu "main-session role named: prints how to start it" "@agent-acme-lead plan the week"
out="$(p '@agent-acme')"
case "$out" in *"- acme-dev:"*"- acme-ui:"*) t_pass "menu lists the dispatchable roles";; *) t_fail "menu lists the dispatchable roles";; esac
case "$out" in *"acme-lead (main-session seat, never dispatched)"*"claude --agent acme-lead"*) t_pass "lead is shown as a chat seat with the CLI start line";; *) t_fail "lead start line";; esac
case "$out" in *"/acme-lead-rules"*) t_pass "desktop start hint names the lead rules skill";; *) t_fail "desktop start hint";; esac
printf 'garbage' | bash "$H" >/dev/null 2>&1;  t_eq 0 "$?" "garbage stdin exits 0"
out="$(printf 'garbage' | bash "$H" 2>&1)"; t_eq "" "$out" "garbage stdin is silent"
printf '{"prompt":' | bash "$H" >/dev/null 2>&1; t_eq 0 "$?" "truncated JSON exits 0"
t_done
