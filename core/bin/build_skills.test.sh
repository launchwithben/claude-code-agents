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
printf 'acme-rules | Acme rules | docs/rules.md#Git | user-invocable: true; disable-model-invocation: false\n' > "$T_ROOT/roles/skills.txt"
bash "$B" >/dev/null;               t_eq 0 "$?" "a 4th column builds"
sed -n 1,6p "$S" | grep -q '^user-invocable: true$' && sed -n 1,6p "$S" | grep -q '^disable-model-invocation: false$' && t_pass "declared frontmatter fields are written (user-invocable survives)" || t_fail "declared frontmatter written"
t_eq "---" "$(sed -n 6p "$S")" "frontmatter is still closed by --- after the extra fields"
bash "$B" --check >/dev/null;       t_eq 0 "$?" "--check is clean with extra frontmatter"
sed -i.b 's/^user-invocable: true$/user-invocable: false/' "$S"; rm -f "$S.b"
bash "$B" --check >/dev/null 2>&1;  t_eq 1 "$?" "--check fails when a frontmatter field was changed by hand"
printf 'acme-rules | Acme rules | docs/rules.md#Git\n' > "$T_ROOT/roles/skills.txt"
bash "$B" >/dev/null; ! grep -q 'user-invocable' "$S" && t_pass "without a 4th column no extra fields are written"
printf 'acme-rules | d | docs/rules.md#Nope\n' > "$T_ROOT/roles/skills.txt"
bash "$B" >/dev/null 2>&1;          t_eq 1 "$?" "a missing section is an error, not an empty skill"
printf 'acme-rules | d | docs/missing.md#Git\n' > "$T_ROOT/roles/skills.txt"
bash "$B" >/dev/null 2>&1;          t_eq 1 "$?" "a missing doc is an error"
rm "$T_ROOT/roles/skills.txt"
bash "$B" >/dev/null 2>&1;          t_eq 0 "$?" "no skills file -> nothing to build, exit 0"
# #14: a skill over the ~900-word guidance warns (stderr) and still builds; --check warns too, never fails on size
printf '# Rules\n\n## Big\n' > "$T_ROOT/docs/big.md"
for i in $(seq 1 120); do printf 'word%s alpha beta gamma delta epsilon zeta eta theta.\n' "$i" >> "$T_ROOT/docs/big.md"; done
printf '# Rules\n\n## Git\n2. pathspec\n' > "$T_ROOT/docs/rules.md"
printf 'acme-big | Big | docs/big.md#Big\nacme-rules | Rules | docs/rules.md#Git\n' > "$T_ROOT/roles/skills.txt"
out="$(bash "$B" 2>&1 >/dev/null)"; rc=$?
t_eq 0 "$rc" "an oversize skill still builds (warning, not error)"
case "$out" in *WARNING*acme-big*words*) t_pass "an oversize skill warns, naming it and its word count";; *) t_fail "oversize warning: $out";; esac
case "$out" in *acme-rules*) t_fail "a small skill must not warn: $out";; *) t_pass "a small skill does not warn";; esac
out="$(bash "$B" --check 2>&1)"; rc=$?
t_eq 0 "$rc" "--check stays clean for an oversize but current skill"
case "$out" in *WARNING*acme-big*) t_pass "--check repeats the warning";; *) t_fail "--check warning: $out";; esac
out="$(ROLE_KIT_SKILL_MAX_WORDS=5000 bash "$B" 2>&1 >/dev/null)"
case "$out" in *WARNING*) t_fail "ROLE_KIT_SKILL_MAX_WORDS raises the threshold: $out";; *) t_pass "ROLE_KIT_SKILL_MAX_WORDS raises the threshold";; esac
rm "$T_ROOT/roles/skills.txt"
t_done
