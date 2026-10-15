#!/usr/bin/env bash
# Fixtures for role-territory-guard.   bash core/hooks/role-territory-guard.test.sh
# The three misroutes reproduced in the first version are named M1-M3 below; every other case is a true positive
# (a write the owner must do) or a true negative (a read, a run, a mention).
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/_testlib.sh"
t_syntax "$here/role-territory-guard.sh" "$here/role-territory-guard.py" "$here/_kit.py"
G="$here/role-territory-guard.sh"
t_proj '{"prefix":"acme","territory":"roles/territory.txt","gate":"npm run check"}'
mkdir -p "$T_ROOT/roles" "$T_ROOT/tmp"
cat > "$T_ROOT/roles/territory.txt" <<'EOF'
# role mode path
-     edit roles/
-     edit tmp/
-     edit .claude/
docs  edit docs/
ui    edit src/components/
ui    edit src/styles/
dev   edit scripts/
dev   edit package.json
dev   all  billing/
dev   edit re:^migrations/.*\.sql$
EOF
R="$T_ROOT"
# call <agent_type|-> <tool> <tool_input json> -> prints "deny" or "allow"
call() {
  local who="$1"; [ "$who" = "-" ] && who=""
  local out
  out="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[2],"tool_input":json.loads(sys.argv[3]),"agent_type":sys.argv[1],"cwd":sys.argv[4]}))' "$who" "$2" "$3" "$R" | bash "$G" 2>/dev/null)"
  case "$out" in *'"permissionDecision": "deny"'*) echo deny;; *) echo allow;; esac
}
bashc() { # <agent|-> <command>
  call "$1" Bash "$(python3 -c 'import json,sys;print(json.dumps({"command":sys.argv[1]}))' "$2")"
}
brief() { # <agent|-> <subagent_type> <prompt>
  call "$1" Agent "$(python3 -c 'import json,sys;print(json.dumps({"subagent_type":sys.argv[1],"prompt":sys.argv[2],"description":"d"}))' "$2" "$3")"
}
file_tool() { # <agent|-> <tool> <path>
  call "$1" "$2" "$(python3 -c 'import json,sys;print(json.dumps({"file_path":sys.argv[1]}))' "$3")"
}
t() { t_eq "$1" "$2" "$3"; }

echo "-- M1: a redirect to somewhere else is not a write to the script it runs"
t allow "$(bashc - 'bash scripts/x.sh > /tmp/out.txt')"                         "M1 run a dev script, output to /tmp"
t allow "$(bashc - 'node scripts/x.mjs --flag 2>&1 > /tmp/o.log')"              "M1 run with 2>&1 and a /tmp redirect"
t allow "$(bashc - 'bash scripts/x.sh >/dev/null 2>&1')"                        "M1 >/dev/null 2>&1"
t allow "$(bashc acme-ui 'bash scripts/x.sh | tee /tmp/o.log')"                 "M1 tee to /tmp from another role"
t allow "$(bashc - 'npm run check > /tmp/gate.txt')"                            "M1 the gate with a redirect"
echo "-- M2: copying FROM another territory to somewhere else only reads it"
t allow "$(bashc acme-dev 'cp src/components/Hero.astro /tmp/Hero.astro')"      "M2 dev copies a ui file to /tmp"
t allow "$(bashc - 'cp src/components/Hero.astro /tmp/Hero.astro')"             "M2 lead copies a ui file to /tmp"
t allow "$(bashc - 'cat src/styles/a.css scripts/x.sh > /tmp/both.txt')"        "M2 concatenating two territories into /tmp"
echo "-- M3: a brief that only MENTIONS another role's file"
t allow "$(brief - acme-dev 'Fix the off-by-one in scripts/build.mjs. For context, src/components/Hero.astro calls it.')" "M3 dev brief names a ui file as context"
t allow "$(brief - acme-ui 'Add a toggle to src/components/Hero.astro; the data comes from scripts/build.mjs')"         "M3 ui brief mentions a dev file"
t allow "$(brief - acme-dev 'Write the changelog entry, nothing under scripts/ changes. Reference: src/components/Hero.astro')" "M3 only context cues for the other file"
t allow "$(brief - acme-dev 'Fix scripts/build.mjs and update docs/guide.md')" "M3 owns one of two named territories"
echo "-- true positives: writes to a territory you do not own"
t deny "$(bashc - "sed -i 's/a/b/' scripts/x.sh")"                               "lead sed -i on a dev file"
t deny "$(bashc - "sed -i.bak -e 's/a/b/' scripts/x.sh")"                       "lead sed -i.bak -e"
t deny "$(bashc - 'echo hi > scripts/x.sh')"                                    "lead redirect into a dev file"
t deny "$(bashc - 'echo hi >> scripts/x.sh')"                                   "lead append into a dev file"
t deny "$(bashc - 'printf x | tee scripts/x.sh')"                               "lead tee into a dev file"
t deny "$(bashc - 'cp /tmp/a scripts/x.sh')"                                    "lead cp INTO a dev file"
t deny "$(bashc - 'mv /tmp/a scripts/x.sh')"                                    "lead mv INTO a dev file"
t deny "$(bashc - 'mv scripts/x.sh /tmp/x.sh')"                                 "lead mv a dev file AWAY"
t deny "$(bashc - 'rm scripts/x.sh')"                                           "lead rm a dev file"
t deny "$(bashc - 'touch package.json')"                                        "lead touch a dev file"
t deny "$(bashc - 'cd scripts && echo x > y.sh')"                               "cd into a territory then redirect"
t deny "$(bashc - "python3 -c \"open('scripts/x.py','w').write('x')\"")"        "python -c opening a dev file for write"
t deny "$(bashc - $'python3 - <<\'PY\'\nopen("scripts/x.py","w").write("x")\nPY')" "python heredoc writing a dev file"
t deny "$(bashc - "sed -i 's/a/b/' scripts/x.sh; npm run check")"               "an edit chained before the gate is still an edit"
t deny "$(bashc acme-dev 'echo x > src/components/a.astro')"                    "dev writes a ui file"
t deny "$(bashc acme-dev "sed -i 's/a/b/' src/styles/a.css")"                   "dev sed -i on a ui file"
t deny "$(bashc acme-ui 'echo x > scripts/x.sh')"                               "ui writes a dev file"
echo "-- true negatives: reads, runs, git, the owner"
t allow "$(bashc - 'ls scripts/ && git add scripts/x.sh')"                      "git add"
t allow "$(bashc - 'git commit -m "fix scripts/x.sh" -- scripts/x.sh')"         "git commit naming the path"
t allow "$(bashc - 'cat scripts/x.sh | grep foo')"                              "read a dev file"
t allow "$(bashc - 'grep -r foo scripts/')"                                     "search an edit-mode territory"
t allow "$(bashc acme-dev "sed -i 's/a/b/' scripts/x.sh")"                      "the owner edits its own file"
t allow "$(bashc acme-ui 'echo x > src/styles/a.css')"                          "ui edits a ui file"
t allow "$(bashc - 'echo notes > roles/notes.txt')"                             "nobody-owned path (-)"
t allow "$(bashc - 'echo "abc > scripts/x.sh')"                                 "unbalanced quote fails open"
t allow "$(bashc - 'bash scripts/roles-kit/bin/ask.sh dev "Fix billing/x.py in scripts/y.sh"')" "a role dispatch script is exempt"
echo "-- mode all: a whole subsystem is the owner's, even to read"
t deny  "$(bashc - 'cat billing/x.py')"                                         "lead reads an all-territory file"
t deny  "$(bashc - 'grep -r foo billing/')"                                     "lead searches an all-territory dir"
t allow "$(bashc acme-dev 'cat billing/x.py')"                                  "owner reads its all-territory file"
t deny  "$(file_tool - Read "$R/billing/x.py")"                                 "Read tool on an all-territory file"
t allow "$(file_tool acme-dev Read "$R/billing/x.py")"                          "owner Read"
t deny  "$(call - Grep '{"path":"billing"}')"                                   "Grep path inside an all-territory dir"
t allow "$(file_tool - Read "$R/scripts/x.sh")"                                 "Read of an edit-mode file is open to all"
t allow "$(call - Grep '{"path":"scripts"}')"                                   "Grep of an edit-mode dir is open to all"
echo "-- file tools"
t deny  "$(file_tool - Edit "$R/scripts/x.sh")"                                 "lead Edit a dev file"
t deny  "$(file_tool - Write "$R/docs/a.md")"                                   "lead Write a docs file"
t allow "$(file_tool - Write "$R/roles/territory.txt")"                         "lead Write the territory file ('-')"
t allow "$(file_tool acme-dev Edit "$R/scripts/x.sh")"                          "dev Edit a dev file"
t deny  "$(file_tool acme-dev Edit "$R/src/components/Hero.astro")"             "dev Edit a ui file"
t allow "$(file_tool - Edit "/tmp/elsewhere.txt")"                              "Edit outside the project"
t deny  "$(file_tool - Edit "$R/.claude/worktrees/w1/scripts/x.sh")"            "a worktree path is judged as if at the root (lead)"
t allow "$(file_tool acme-dev Edit "$R/.claude/worktrees/w1/scripts/x.sh")"     "a worktree path is judged as if at the root (owner)"
t deny  "$(file_tool - Edit "$R/migrations/001_init.sql")"                      "re: row matches"
t allow "$(file_tool - Read "$R/migrations/001_init.sql")"                      "re: row, read-only"
t allow "$(file_tool - Edit "$R/migrations/README.md")"                         "re: row does not match a non-sql file"
echo "-- briefs to agents"
t deny  "$(brief - bulk-worker 'Fix the bug in scripts/x.sh and commit')"       "generic worker told to edit a dev file"
t allow "$(brief - acme-dev 'Fix the bug in scripts/x.sh and commit')"          "the owner role gets the same brief"
t allow "$(brief - bulk-worker 'Read-only: summarise scripts/x.sh, do not edit')" "read-only brief to a generic worker"
t allow "$(brief - bulk-worker 'Explain how scripts/x.sh works')"               "no edit verb"
t deny  "$(brief - bulk-worker 'Summarise billing/x.py')"                       "brief about an all-territory subsystem to a non-owner"
t allow "$(brief - acme-dev 'Summarise billing/x.py')"                          "same brief to the owner"
t deny  "$(brief - acme-ui 'Fix the rounding in billing/x.py')"                 "ui told to edit a dev subsystem (owns none of what is named)"
t allow "$(brief - acme-ui 'Fix src/components/A.astro and the helper in scripts/x.sh')" "ui owns one of two named"
t allow "$(brief - bulk-worker 'Fix the typo in README.md')"                    "no territory named"
echo "-- identity and overrides"
t allow "$(ROLE_KIT_ROLE=acme-dev file_tool - Edit "$R/scripts/x.sh")"          "headless: ROLE_KIT_ROLE names the caller"
t deny  "$(ROLE_KIT_ROLE=acme-ui file_tool - Edit "$R/scripts/x.sh")"           "headless: ROLE_KIT_ROLE of another role"
touch "$R/tmp/role-override"
t allow "$(file_tool - Edit "$R/scripts/x.sh")"                                 "override file < 30 min allows"
touch -t 202001010000 "$R/tmp/role-override"
t deny  "$(file_tool - Edit "$R/scripts/x.sh")"                                 "an old override file does not"
rm -f "$R/tmp/role-override"
echo "-- no territory file, or a broken one: the guard stands down"
printf '{"prefix":"acme"}' > "$R/roles.config.json"
t allow "$(file_tool - Edit "$R/scripts/x.sh")"                                 "no territory key"
printf '{"prefix":"acme","territory":"roles/missing.txt"}' > "$R/roles.config.json"
t allow "$(file_tool - Edit "$R/scripts/x.sh")"                                 "territory file missing"
printf 'garbage' > "$R/roles.config.json"
t allow "$(file_tool - Edit "$R/scripts/x.sh")"                                 "unparseable overlay"
echo "-- fail open on bad input"
printf 'not json' | bash "$G" >/dev/null 2>&1;          t_eq 0 "$?" "garbage stdin"
printf '' | bash "$G" >/dev/null 2>&1;                  t_eq 0 "$?" "empty stdin"
printf '{"tool_name":"Bash","tool_input":' | bash "$G" >/dev/null 2>&1; t_eq 0 "$?" "truncated JSON"
printf '{"tool_name":"Bash","tool_input":{"command":null}}' | bash "$G" >/dev/null 2>&1; t_eq 0 "$?" "null command"
t_done
