#!/usr/bin/env bash
# Fixtures for pm-delta.mjs with a stub `gh`.   bash core/bin/pm-delta.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../hooks/_testlib.sh"
command -v node >/dev/null 2>&1 || { echo "  skip node is not installed"; echo "ALL PASS"; exit 0; }
P="$here/pm-delta.mjs"
t_proj '{"prefix":"acme","pm":{"repo":"acme/widgets","cursor":"docs/pm/state.json"}}'
mkdir -p "$T_ROOT/stub"
cat > "$T_ROOT/stub/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
if [ "$GH_FAIL" = 1 ]; then echo boom >&2; exit 1; fi
echo '[{"number":12,"title":"Fix login","state":"open","updated_at":"2026-10-14T09:00:00Z","comments":2,"labels":[{"name":"bug"}]},{"number":13,"title":"A PR","state":"open","updated_at":"2026-10-14T09:00:00Z","comments":0,"labels":[],"pull_request":{}}]'
EOF
chmod +x "$T_ROOT/stub/gh"
export PATH="$T_ROOT/stub:$PATH" STUB_LOG="$T_ROOT/gh.log"
out="$(node "$P")"; t_eq 0 "$?" "first run succeeds"
case "$out" in *"#12 [open] Fix login"*"bug"*) t_pass "an issue is listed with its labels";; *) t_fail "issue listed: $out";; esac
case "$out" in *"#13"*) t_fail "a pull request leaked into the delta";; *) t_pass "pull requests are filtered out";; esac
case "$out" in *"no cursor yet"*) t_pass "first run says there is no cursor";; *) t_fail "first-run note";; esac
grep -q 'repos/acme/widgets/issues' "$T_ROOT/gh.log" && t_pass "reads the repo from the overlay over REST" || t_fail "REST call"
[ -f "$T_ROOT/tmp/pm/delta.json" ] && t_pass "details land in tmp/pm/delta.json" || t_fail "delta.json"
node "$P" --ack --at 2026-10-14T10:00:00Z >/dev/null;  t_eq 0 "$?" "--ack --at writes the cursor"
t_eq 2026-10-14T10:00:00Z "$(python3 -c 'import json;print(json.load(open("'"$T_ROOT"'/docs/pm/state.json"))["cursor"])')" "the cursor file holds it"
: > "$T_ROOT/gh.log"; node "$P" >/dev/null
grep -q 'since=2026-10-14T10:00:00Z' "$T_ROOT/gh.log" && t_pass "the next delta asks only for what changed since the cursor" || t_fail "since= cursor"
node "$P" --ack --at nonsense >/dev/null 2>&1; t_eq 2 "$?" "a bad --at is refused"
GH_FAIL=1 node "$P" >/dev/null 2>&1;            t_eq 1 "$?" "a failing gh is an error, and the cursor is untouched"
t_eq 2026-10-14T10:00:00Z "$(python3 -c 'import json;print(json.load(open("'"$T_ROOT"'/docs/pm/state.json"))["cursor"])')" "cursor unchanged after the failure"
t_done
