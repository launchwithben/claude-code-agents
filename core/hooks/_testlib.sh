#!/usr/bin/env bash
# _testlib.sh - tiny helpers sourced by the kit's fixtures (hooks/*.test.sh, bin/*.test.sh). Not a test itself.
T_FAILS=0
t_pass() { printf '  ok   %s\n' "$1"; }
t_fail() { printf '  FAIL %s\n' "$1"; T_FAILS=$((T_FAILS+1)); }
t_eq() { # <want> <got> <label>
  if [ "$1" = "$2" ]; then t_pass "$3"; else t_fail "$3 (want $1 got $2)"; fi
}
# t_syntax <file>...: a bash syntax error exits 2 = BLOCK in Claude Code, so a fail-open hook would fail CLOSED.
# Every fixture file starts here. Python files are parsed, not run.
t_syntax() {
  local f
  for f in "$@"; do
    case "$f" in
      *.py) python3 -c 'import ast,sys;ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null || { echo "FAIL $f has a python syntax error"; exit 1; } ;;
      *) bash -n "$f" || { echo "FAIL $f has a bash syntax error"; exit 1; } ;;
    esac
  done
}
# t_proj '<roles.config.json content>': a scratch project root; exports CLAUDE_PROJECT_DIR; removed on exit.
t_proj() {
  T_ROOT="$(mktemp -d)"
  trap 'rm -rf "$T_ROOT"' EXIT
  export CLAUDE_PROJECT_DIR="$T_ROOT"
  printf '%s\n' "$1" > "$T_ROOT/roles.config.json"
}
t_json() { # <key=value>...: a JSON object from string pairs on stdout (values are plain strings)
  python3 -c 'import json,sys;print(json.dumps(dict(a.split("=",1) for a in sys.argv[1:])))' "$@"
}
t_done() {
  if [ "$T_FAILS" = 0 ]; then echo "ALL PASS"; else echo "$T_FAILS FAILED"; exit 1; fi
}
