#!/usr/bin/env bash
# Fixtures for build_skills.sh.   bash core/bin/build_skills.test.sh
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../hooks/_testlib.sh"
t_syntax "$here/build_skills.sh"
B="$here/build_skills.sh"
t_proj '{"prefix":"acme","skills":"roles/skills.txt"}'
mkdir -p "$T_ROOT/roles" "$T_ROOT/docs"
printf '# Rules\n\n## The check\n1. run it\n\n## Git\n2. pathspec\n\n## Other\n3. unrelated\n' > "$T_ROOT/docs/rules.md"
printf '# comment\nacme-rules | Acme rules | docs/rules.md#The check; docs/rules.md#Git\n' > "$T_ROOT/roles/skills.txt"
S="$T_ROOT/.claude/skills/acme-rules/SKILL.md"
bash "$B" >/dev/null;               t_eq 0 "$?" "build writes the skill"
grep -q '^name: acme-rules' "$S" && grep -q '1. run it' "$S" && grep -q '2. pathspec' "$S" && ! grep -q 'unrelated' "$S" && t_pass "only the named sections are in it" || t_fail "only the named sections are in it"
grep -q 'GENERATED' "$S" && t_pass "it says it is generated" || t_fail "it says it is generated"
bash "$B" --check >/dev/null;       t_eq 0 "$?" "--check is clean right after a build"
echo "tamper" >> "$S"
out="$(bash "$B" --check 2>&1)";    t_eq 1 "$?" "--check fails when the skill was edited by hand"
case "$out" in *"STALE"*"acme-rules"*) t_pass "and names the skill";; *) t_fail "names the skill: $out";; esac
bash "$B" >/dev/null
printf '# Rules\n\n## The check\n1. run it twice\n\n## Git\n2. pathspec\n' > "$T_ROOT/docs/rules.md"
bash "$B" --check >/dev/null 2>&1;  t_eq 1 "$?" "--check fails when the source doc changed"
bash "$B" >/dev/null;               bash "$B" --check >/dev/null 2>&1; t_eq 0 "$?" "rebuild makes it clean again"
printf 'acme-rules | d | docs/rules.md#Nope\n' > "$T_ROOT/roles/skills.txt"
bash "$B" >/dev/null 2>&1;          t_eq 1 "$?" "a missing section is an error, not an empty skill"
printf 'acme-rules | d | docs/missing.md#Git\n' > "$T_ROOT/roles/skills.txt"
bash "$B" >/dev/null 2>&1;          t_eq 1 "$?" "a missing doc is an error"
rm "$T_ROOT/roles/skills.txt"
bash "$B" >/dev/null 2>&1;          t_eq 0 "$?" "no skills file -> nothing to build, exit 0"
t_done
