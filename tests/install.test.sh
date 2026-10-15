#!/usr/bin/env bash
# Fixtures for install.sh: a real install into scratch repos with the sample overlay in examples/.
#   bash tests/install.test.sh
kit="$(cd "$(dirname "$0")/.." && pwd)"
source "$kit/core/hooks/_testlib.sh"
t_syntax "$kit/install.sh" "$kit/lib/install.py"
I="$kit/install.sh"
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT
export HOME="$S/home"; mkdir -p "$HOME"        # never touch the real ~/.claude
unset CLAUDE_PROJECT_DIR

mkrepo() { # <dir>: a git repo with the sample overlay and a .claude/ that is gitignored, plus the territory file
  mkdir -p "$1"; git init -q -b main "$1" 2>/dev/null
  cp "$kit/examples/roles.config.json" "$1/"; cp -R "$kit/examples/roles" "$kit/examples/docs" "$1/"
  printf '.claude/\n' > "$1/.gitignore"
}
jget() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2]))' "$1" "$2"; }

echo "-- install into a repo that already has a settings.json with unrelated hooks"
P="$S/proj"; mkrepo "$P"
mkdir -p "$P/.claude"
cat > "$P/.claude/settings.json" <<'EOF'
{
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo their-bash-hook"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "echo their-stop-hook"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "echo their-prompt-hook"}]}]
  }
}
EOF
out="$(bash "$I" --target "$P" 2>&1)"; t_eq 0 "$?" "install exits 0"
for f in .claude/agents/acme-lead.md .claude/agents/acme-pm.md .claude/agents/acme-dev.md .claude/agents/acme-ui.md \
         .claude/agents/acme-concept.md .claude/agents/acme-docs.md .claude/skills/roles/SKILL.md \
         .claude/skills/acme-lead-rules/SKILL.md .claude/skills/acme-build-rules/SKILL.md .claude/skills/acme-design-rules/SKILL.md \
         scripts/roles-kit/VERSION scripts/roles-kit/hooks/role-territory-guard.py scripts/roles-kit/bin/inflight.mjs \
         scripts/roles-kit/bin/ask.sh scripts/roles-kit/bin/kit-check scripts/roles-kit/bin/roles-pulse.mjs; do
  [ -f "$P/$f" ] && t_pass "installed $f" || t_fail "installed $f"
done
t_eq 0.2.1 "$(cat "$P/scripts/roles-kit/VERSION")" "the kit version is recorded"
echo "-- settings.json was MERGED, not overwritten"
SJ="$P/.claude/settings.json"
t_eq '["Bash(ls:*)"]' "$(jget "$SJ" 'json.dumps(d["permissions"]["allow"])')" "unrelated top-level keys survive"
grep -q their-bash-hook "$SJ" && grep -q their-stop-hook "$SJ" && grep -q their-prompt-hook "$SJ" && t_pass "all three of their hooks survive" || t_fail "their hooks survive"
t_eq echo "$(jget "$SJ" 'd["hooks"]["PreToolUse"][0]["hooks"][0]["command"].split()[0]')" "their entries stay first"
grep -q 'role-territory-guard.sh' "$SJ" && grep -q 'role-routing-guard.sh' "$SJ" && grep -q 'role-picker.sh' "$SJ" && t_pass "routing, territory and picker hooks registered" || t_fail "kit hooks registered"
grep -q 'lead-inflight-record.sh' "$SJ" && grep -q 'SubagentStop' "$SJ" && t_pass "the in-flight recorder is registered (PostToolUse + SubagentStop)" || t_fail "in-flight recorder registered"
cp "$SJ" "$S/settings.after1"
echo "-- agents render with the overlay's prefix, gate and hook paths"
D="$P/.claude/agents/acme-dev.md"
grep -q '^name: acme-dev$' "$D" && grep -q 'npm run check' "$D" && grep -q 'bash scripts/preflight.sh' "$D" && grep -q 'role-handback-check.sh\\" acme-dev' "$D" && t_pass "dev agent: name, gate, extra gate, handback hook" || t_fail "dev agent rendering"
grep -q 'CLAUDE_PROJECT_DIR/scripts/roles-kit/hooks' "$D" && t_pass "hook path points at the installed kit" || t_fail "hook path"
grep -rq '{{' "$P/.claude" && t_fail "an unresolved {{placeholder}} is left in .claude/" || t_pass "no unresolved placeholders"
grep -q 'claude --agent acme-lead' "$P/.claude/agents/acme-lead.md" && grep -q 'node $CLAUDE_PROJECT_DIR/scripts/roles-kit/bin/inflight.mjs' "$P/.claude/agents/acme-lead.md" && t_pass "lead agent: start line and ledger reader" || t_fail "lead agent rendering"
grep -q 'lead-heartbeat-check.sh' "$P/.claude/agents/acme-lead.md" && t_pass "lead carries the heartbeat as an agent-scoped Stop hook" || t_fail "heartbeat on lead"
grep -q 'docs/board-notes.md' "$P/.claude/agents/acme-pm.md" && grep -q 'Never set the Priority field' "$P/.claude/agents/acme-pm.md" && t_pass "pm agent: overlay board rules and read-first doc" || t_fail "pm overlay"
grep -q 'acme-docs' "$P/.claude/agents/acme-lead.md" && t_pass "the extra role is in the lead's routing" || t_fail "extra role routing"
grep -q '^name: acme-docs$' "$P/.claude/agents/acme-docs.md" && grep -q 'isolation: worktree' "$P/.claude/agents/acme-docs.md" && t_pass "extra role rendered" || t_fail "extra role"
echo "-- generated skill built from the docs, starters written once"
grep -q 'GENERATED' "$P/.claude/skills/acme-build-rules/SKILL.md" && t_pass "acme-build-rules is generated from docs/rules.md (replaces the starter)" || t_fail "generated skill"
grep -q 'HOW TO FILL' "$P/.claude/skills/acme-design-rules/SKILL.md" && t_pass "design-rules is a starter" || t_fail "design starter"
echo "my own rules" >> "$P/.claude/skills/acme-design-rules/SKILL.md"
echo "-- the installer's follow-up notes"
case "$out" in *"git add -f"*) t_pass "tells you to git add -f when .claude/ is ignored";; *) t_fail "git add -f hint";; esac
case "$out" in *"kit-check"*"build_skills.sh --check"*) t_pass "prints the lines to add to the project gate";; *) t_fail "gate lines";; esac
case "$out" in *"restart Claude Code"*) t_pass "says to restart for a new agents folder";; *) t_fail "restart note";; esac
case "$out" in *"claude --agent acme-lead"*) t_pass "says how to start the lead";; *) t_fail "lead start note";; esac

echo "-- re-install is idempotent and keeps edits to starters"
bash "$I" --target "$P" >/dev/null 2>&1; t_eq 0 "$?" "second install exits 0"
cmp -s "$SJ" "$S/settings.after1" && t_pass "settings.json is byte-identical (no duplicate hooks)" || t_fail "settings.json changed on re-install"
grep -q "my own rules" "$P/.claude/skills/acme-design-rules/SKILL.md" && t_pass "an edited starter rules skill is never overwritten" || t_fail "starter overwritten"

echo "-- --check: clean, then drift"
bash "$I" --target "$P" --check >/dev/null 2>&1; t_eq 0 "$?" "--check is clean after install"
out="$(cd "$P" && bash scripts/roles-kit/bin/kit-check 2>&1)"; t_eq 0 "$?" "the installed copy of kit-check passes inside the project"
echo "# local edit" >> "$P/scripts/roles-kit/hooks/role-picker.py"
out="$(bash "$I" --target "$P" --check 2>&1)"; t_eq 1 "$?" "--check fails after a core file is edited"
case "$out" in *"DRIFT"*"role-picker.py"*) t_pass "and names the drifted file";; *) t_fail "names the file: $out";; esac
bash "$I" --target "$P" >/dev/null 2>&1; bash "$I" --target "$P" --check >/dev/null 2>&1; t_eq 0 "$?" "re-install heals it"
echo "x" >> "$P/.claude/agents/acme-dev.md"
bash "$I" --target "$P" --check >/dev/null 2>&1; t_eq 1 "$?" "an edited rendered agent is drift too"
bash "$I" --target "$P" >/dev/null 2>&1
rm "$P/scripts/roles-kit/hooks/role-picker.sh"
out="$(bash "$I" --target "$P" --check 2>&1)"; case "$out" in *"MISSING"*"role-picker.sh"*) t_pass "a deleted core file is MISSING";; *) t_fail "missing: $out";; esac
bash "$I" --target "$P" >/dev/null 2>&1
printf '# Rules\n\n## The check\n1. changed upstream\n\n## Git\n2. pathspec\n' > "$P/docs/rules.md"
out="$(bash "$I" --target "$P" --check 2>&1)"; t_eq 1 "$?" "--check fails when a doc behind a generated skill changed"
case "$out" in *"generated skill"*"acme-build-rules"*) t_pass "and names the generated skill";; *) t_fail "names generated skill: $out";; esac
python3 - "$SJ" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
d["hooks"]["UserPromptSubmit"]=[e for e in d["hooks"]["UserPromptSubmit"] if "roles-kit" not in json.dumps(e)]
json.dump(d,open(sys.argv[1],"w"))
PY
out="$(bash "$I" --target "$P" --check 2>&1)"; case "$out" in *"MISSING"*"settings hook"*"role-picker"*) t_pass "a removed settings hook is reported";; *) t_fail "settings hook: $out";; esac

echo "-- the installed hooks work from the settings.json commands"
bash "$I" --target "$P" >/dev/null 2>&1
cmd="$(jget "$SJ" '[h["command"] for e in d["hooks"]["UserPromptSubmit"] for h in e["hooks"] if "roles-kit" in h["command"]][0]')"
out="$(printf '%s' '{"prompt":"@agent-acme"}' | CLAUDE_PROJECT_DIR="$P" bash -c "$cmd")"
case "$out" in *"acme-dev"*"acme-lead (main-session seat"*) t_pass "the registered picker command runs and lists the roles";; *) t_fail "picker via settings command: $out";; esac
tcmd="$(jget "$SJ" '[h["command"] for e in d["hooks"]["PreToolUse"] for h in e["hooks"] if "role-territory-guard" in h["command"]][0]')"
out="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]+"/scripts/x.sh"},"agent_type":"","cwd":sys.argv[1]}))' "$P" | CLAUDE_PROJECT_DIR="$P" bash -c "$tcmd")"
case "$out" in *'"permissionDecision": "deny"'*acme-dev*) t_pass "the registered territory guard denies a lead edit of a dev file";; *) t_fail "territory guard via settings command: $out";; esac

echo "-- refusals leave the project untouched"
B="$S/bad"; mkrepo "$B"; mkdir -p "$B/.claude"; printf '{ not json' > "$B/.claude/settings.json"
bash "$I" --target "$B" >/dev/null 2>&1; t_eq 1 "$?" "a settings.json that does not parse is refused"
[ "$(cat "$B/.claude/settings.json")" = "{ not json" ] && [ ! -d "$B/.claude/agents" ] && [ ! -d "$B/scripts/roles-kit" ] && t_pass "and nothing was written" || t_fail "partial write after refusal"
N="$S/noprefix"; mkrepo "$N"; printf '{"gate":"x"}' > "$N/roles.config.json"
bash "$I" --target "$N" >/dev/null 2>&1; t_eq 1 "$?" "an overlay with no prefix is refused"
printf '{"prefix":"a","roles":["dev","wizard"]}' > "$N/roles.config.json"
bash "$I" --target "$N" >/dev/null 2>&1; t_eq 1 "$?" "an unknown role is refused"
printf '{"prefix":"a","kit":"9.9.9"}' > "$N/roles.config.json"
out="$(bash "$I" --target "$N" 2>&1)"; t_eq 1 "$?" "an overlay pinning another kit version is refused"
case "$out" in *"pins kit 9.9.9"*) t_pass "and says which version it wants";; *) t_fail "pin message: $out";; esac
bash "$I" --target "$S/does-not-exist" >/dev/null 2>&1; t_eq 1 "$?" "no overlay at all is refused"

echo "-- a minimal overlay: no territory, no lead; --init"
M="$S/mini"; mkdir -p "$M"; git init -q -b main "$M" 2>/dev/null
printf '{"prefix":"mini","roles":["dev"],"gate":"make test"}' > "$M/roles.config.json"
bash "$I" --target "$M" >/dev/null 2>&1; t_eq 0 "$?" "installs"
[ -f "$M/.claude/agents/mini-dev.md" ] && [ ! -f "$M/.claude/agents/mini-lead.md" ] && [ ! -f "$M/.claude/skills/mini-design-rules/SKILL.md" ] && t_pass "only the chosen role (and only the rules skills it needs)" || t_fail "minimal roles"
grep -q 'role-territory-guard' "$M/.claude/settings.json" && t_fail "territory guard registered without a territory file" || t_pass "no territory key -> territory guard not registered"
grep -q 'lead-inflight-record' "$M/.claude/settings.json" && t_fail "in-flight recorder registered without a lead" || t_pass "no lead -> no recorder"
bash "$I" --target "$M" --check >/dev/null 2>&1; t_eq 0 "$?" "--check clean"
E="$S/empty"; mkdir -p "$E"; bash "$I" --target "$E" --init >/dev/null 2>&1; t_eq 0 "$?" "--init writes a starter overlay"
[ -f "$E/roles.config.json" ] && t_pass "the starter overlay exists" || t_fail "starter overlay"
bash "$I" --target "$E" --init >/dev/null 2>&1; t_eq 1 "$?" "--init never overwrites"

echo "-- user-level install (scope: user)"
U="$S/userproj"; mkrepo "$U"
python3 - "$U/roles.config.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1])); c["scope"]="user"; c.pop("extraRoles",None); json.dump(c,open(sys.argv[1],"w"))
PY
bash "$I" --target "$U" >/dev/null 2>&1; t_eq 0 "$?" "user-scope install exits 0"
[ -f "$HOME/.claude/agents/acme-dev.md" ] && [ -f "$HOME/.claude/roles-kit/hooks/role-picker.sh" ] && [ -f "$HOME/.claude/settings.json" ] && t_pass "files land in ~/.claude, not in the project" || t_fail "user-scope locations"
[ ! -d "$U/scripts/roles-kit" ] && [ ! -f "$U/.claude/agents/acme-dev.md" ] && t_pass "the project itself is not touched" || t_fail "project touched"
grep -q 'HOME/.claude/roles-kit/hooks' "$HOME/.claude/settings.json" && t_pass "hooks point at the user-level kit" || t_fail "user-level hook path"
bash "$I" --target "$U" --check >/dev/null 2>&1; t_eq 0 "$?" "--check clean at user scope"
echo "-- the untouched starter overlay warns (it used to install silently with a fake gate and a fake PM repo)"
W="$S/starter"; mkdir -p "$W"; git init -q -b main "$W" 2>/dev/null
bash "$I" --target "$W" --init >/dev/null 2>&1
warn="$(bash "$I" --target "$W" 2>&1 >/dev/null)"; t_eq 0 "$?" "installing the starter still exits 0 (warnings, not errors)"
echo "$warn" | grep -q '"prefix" is still "acme"' && t_pass "warns about the example prefix" || t_fail "no prefix warning"
echo "$warn" | grep -q 'acme/widgets' && t_pass "warns about the example PM repo" || t_fail "no pm.repo warning"
echo "$warn" | grep -q 'scripts/preflight.sh' && t_pass "warns about the gate script that does not exist" || t_fail "no extraGates warning"
echo "$warn" | grep -q 'territory' && t_pass "warns about the missing territory file" || t_fail "no territory warning"
echo "$warn" | grep -q 'example "docs" role' && t_pass "warns about the example docs role" || t_fail "no docs-role warning"
clean="$(bash "$I" --target "$P" --check 2>&1)"; echo "$clean" | grep -q WARNING && t_fail "--check must not warn" || t_pass "a finished overlay (and --check) does not warn about the starter"

t_done
