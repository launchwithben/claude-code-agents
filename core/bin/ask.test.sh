#!/usr/bin/env bash
# Fixtures for ask.sh (headless dispatch) with a stub `claude`.   bash core/bin/ask.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../hooks/_testlib.sh"
t_syntax "$here/ask.sh" "$here/ask_helper.py"
A="$here/ask.sh"
t_proj '{"prefix":"acme"}'
export HOME="$T_ROOT/home"; mkdir -p "$HOME/.claude/projects/p" "$T_ROOT/.claude/agents" "$T_ROOT/stub"
printf -- '---\nname: acme-dev\ndescription: >-\n  Developer for non-UI work. Second sentence.\n---\nbody\n' > "$T_ROOT/.claude/agents/acme-dev.md"
printf -- '---\nname: acme-ui\ndescription: UI builder.\n---\nbody\n' > "$T_ROOT/.claude/agents/acme-ui.md"
# a stub claude: records its argv and the role env, prints a fixed -p JSON result chosen by $STUB_MODE
cat > "$T_ROOT/stub/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_ARGV"; printf '%s\n' "${ROLE_KIT_ROLE:-}" > "$STUB_ROLE"
case "$STUB_MODE" in
  ok)     echo '{"result":"done\nGATE: make test -> PASS\nCOMMIT: abc1234 on branch b","session_id":"sess1","total_cost_usd":0.5,"num_turns":4}' ;;
  buried) echo '{"result":"capture skipped","session_id":"sess2","total_cost_usd":1.25,"num_turns":9}' ;;
  fail)   echo 'not json at all'; exit 3 ;;
esac
EOF
chmod +x "$T_ROOT/stub/claude"
export CLAUDE_BIN="$T_ROOT/stub/claude" STUB_ARGV="$T_ROOT/argv" STUB_ROLE="$T_ROOT/role"
echo "-- --list and usage"
out="$(bash "$A" --list)"
case "$out" in *$'acme-dev\tDeveloper for non-UI work.'*) t_pass "--list prints name and description";; *) t_fail "--list prints name and description: $out";; esac
case "$out" in *acme-ui*) t_pass "--list shows every role";; *) t_fail "--list shows every role";; esac
bash "$A" dev >/dev/null 2>&1;            t_eq 2 "$?" "no brief -> usage, exit 2"
bash "$A" nosuch "x" >/dev/null 2>&1;     t_eq 2 "$?" "unknown role -> usage, exit 2"
echo "-- a normal run"
out="$(STUB_MODE=ok bash "$A" dev "fix #3")"; rc=$?
t_eq 0 "$rc" "exit code of the role run is returned"
case "$out" in *"GATE: make test -> PASS"*"COMMIT: abc1234"*) t_pass "the handback is printed";; *) t_fail "the handback is printed: $out";; esac
case "$(cat "$T_ROOT/argv")" in *"-p --agent acme-dev"*"--output-format json"*"fix #3"*) t_pass "claude -p --agent <full role name> <brief>";; *) t_fail "argv: $(cat "$T_ROOT/argv")";; esac
t_eq acme-dev "$(cat "$T_ROOT/role")" "ROLE_KIT_ROLE tells the territory guard who is calling"
t_eq 0.5 "$(python3 -c 'import json;print(json.loads(open("'"$T_ROOT"'/tmp/roles/roles.jsonl").readlines()[0])["cost_usd"])')" "cost is logged"
echo "-- a handback buried under later chatter is recovered from the transcript"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"real report\nGATE: make test -> PASS\nCOMMIT: def5678 on branch b"}]}}' '{"type":"assistant","message":{"content":[{"type":"text","text":"capture skipped"}]}}' > "$HOME/.claude/projects/p/sess2.jsonl"
out="$(STUB_MODE=buried bash "$A" acme-dev "go")"
case "$out" in *"COMMIT: def5678"*"recovered from the transcript"*) t_pass "buried handback recovered";; *) t_fail "buried handback recovered: $out";; esac
echo "-- failure"
STUB_MODE=fail bash "$A" dev "go" >/dev/null 2>&1; t_eq 3 "$?" "a failing run returns its exit code"
t_eq 3 "$(python3 -c 'import json;print(json.loads(open("'"$T_ROOT"'/tmp/roles/roles.jsonl").readlines()[-1])["rc"])')" "and logs it"
t_done
