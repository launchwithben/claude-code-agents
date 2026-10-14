# claude-code-agents

**Turn one Claude Code chat into a team of specialists.**

> **Status: Active.** Maintained by [Launch With Ben](https://launchwithben.com). See [MAINTENANCE.md](MAINTENANCE.md) for what that means, how to hear about updates, and what happens if it is ever sunset. Changes are in [CHANGELOG.md](CHANGELOG.md).

A developer, a UI builder and a concept designer, each with its own scope, its own rules and (for the roles that edit code) its own copy of the repo. You talk to one chat. It sends every job to the right specialist, reads the diff that comes back and merges it. A role cannot hand back without showing its check result, or the reason it had none.

No extra windows and no extra subscriptions: the roles are subagents of the Claude Code you already run, and the session you talk to becomes the lead.

```
you ──► lead session ──► role-dev      (scripts, data, config)       ──┐
                     ├─► role-ui       (components, styles)            ├─► lead reviews the diff ──► merge
                     └─► role-concept  ("show me 3 ways")              ──┘
```

Written up in full at **launchwithben.com/notes/claude-code-agents** (the post explains why each part exists and what it cost to run for real).

## What's in the box

| File | What it does |
|---|---|
| `.claude/agents/role-dev.md` | Non-UI developer. Sonnet, own worktree, preloads `build-rules`. |
| `.claude/agents/role-ui.md` | Designs and builds UI in one pass. Sonnet, own worktree, preloads `design-rules` + `build-rules`. |
| `.claude/agents/role-concept.md` | Answers direction questions with 2-3 rendered concepts. Never touches production components. |
| `.claude/skills/build-rules/` | Your project's build rules, injected into every role at start. **Template: fill it in.** |
| `.claude/skills/design-rules/` | Your design system's rules. **Template: fill it in.** |
| `.claude/skills/roles/` | `/roles` command: a menu, so nobody memorises role names. |
| `scripts/hooks/role-handback-check.sh` | Blocks a role from finishing until its report has the evidence (`GATE: ... -> PASS`, `SCREENSHOTS:`) or an explicit `GATE-SKIPPED: <reason>`. It checks what the role REPORTS, not that the command ran. Fails open on its own runtime errors and lets the agent through after 2 blocks. |
| `scripts/hooks/role-routing-guard.sh` | Stops the lead sending an edit to a generic worker instead of a role. Read-only work passes. Logs every denial to `tmp/role-routing/denials.jsonl`. |
| `scripts/hooks/role-picker.sh` | Typing a bare `@agent-role` shows the role menu instead of guessing. |
| `scripts/roles-pulse.mjs` | Reads Claude Code's own transcripts and tells you whether the roles are used, whether they hand back evidence, and what each run cost. |
| `scripts/hooks/*.test.sh` | Fixtures for every hook. |

**Installing with an agent?** Point it at this repo and tell it to follow `AGENTS.md`: it detects your check command, merges (never overwrites) `settings.json`, runs the hook tests, and tells you the two steps only you can do (restart, trust prompt).

## Install (5 minutes)

Requirements: Claude Code, `bash`, `python3` (hooks), `node` 18+ (pulse script only), a git repo.

```bash
# from your project root
git clone https://github.com/launchwithben/claude-code-agents /tmp/claude-code-agents
mkdir -p .claude/agents .claude/skills scripts/hooks
cp    /tmp/claude-code-agents/.claude/agents/*.md        .claude/agents/
cp -R /tmp/claude-code-agents/.claude/skills/*           .claude/skills/
cp    /tmp/claude-code-agents/scripts/hooks/role-*       scripts/hooks/
cp    /tmp/claude-code-agents/scripts/roles-pulse.mjs    scripts/
```

Then the two project hooks (routing guard + role picker) live in `.claude/settings.json`:

```bash
# no settings file yet: copy it
[ -f .claude/settings.json ] || cp /tmp/claude-code-agents/.claude/settings.json .claude/settings.json
```

If you already have a `.claude/settings.json`, merge its `PreToolUse` and `UserPromptSubmit` entries into yours by hand instead of overwriting.

Then:

1. **Fill in `.claude/skills/build-rules/SKILL.md`.** Your real check command, and the rules an agent would otherwise break. Keep it under ~900 words: it is pasted into every role on every run.
2. **Fill in `.claude/skills/design-rules/SKILL.md`** if you have a UI.
3. **Restart Claude Code if `.claude/agents/` did not exist when the session started.** An existing agents folder is watched and edits apply live; a brand-new one is not picked up until restart (`/clear` is not enough).
4. **Accept the workspace trust prompt.** Hooks in an agent file only run in a trusted project.
5. Prove the hooks work in your repo:
   ```bash
   for t in scripts/hooks/*.test.sh; do bash "$t" | tail -1; done
   ```

If `.claude/` is in your `.gitignore`, commit the files with `git add -f`, or a fresh worktree will not have the roles.

## Use it

Talk to your normal session. Any of these work:

```
/roles                                   # menu
@agent-role-ui add a monthly/yearly toggle to the pricing table
Have role-dev fix the failing date test and add a regression case.
```

A follow-up on the same work should go to the **same** agent (Claude does this with SendMessage) so it keeps its context. A new task gets a fresh agent.

## Check it's working

```bash
node scripts/roles-pulse.mjs                 # last 7 days, this project
node scripts/roles-pulse.mjs --since 2026-10-01 --json
```

You get one row per role run (model, tool calls, how often the handback hook blocked it, the `GATE:` line it reported, rounds on the same issue, cost) plus per-role and per-issue totals. Cost is a floor: transcripts under-count output tokens.

## Customising

- **Rename the roles.** Keep the suffix (`-dev`, `-ui`, `-concept`): the handback hook picks the contract by suffix. Change the `role-` prefix in `role-picker.sh` and set `ROLE_PREFIX` for the pulse script.
- **Add a role.** Copy an agent file, give it a new suffix, and add a branch for that suffix in `role-handback-check.sh`.
- **Model.** Roles run on `sonnet`. In our runs, the four finished UI jobs on Sonnet cost $3.58 to $4.33 each, and the two on the top model cost $9.47 and $25.73 (different jobs, so not a like-for-like comparison). Keep the expensive model for single decisions, not whole builds.

## Known limits

- A brand-new `.claude/agents/` folder needs a session restart before its roles exist.
- **The two-block limit is shared, not per agent.** `role-handback-check.sh` keys its counter on `agent_id`, falling back to `session_id`. In real runs two jobs were blocked with "attempt 2 of 2" as their first block, so the counter was shared across agents of the same role in a session. Treat it as two blocks per role per session.
- **Headless runs skip the handback hook.** Under `claude -p` (whether the role is dispatched or started with `--agent`), hooks in agent files did not fire in our tests: a `-p` session does not count as a trusted workspace. The routing guard in `settings.json` still runs. Check the handback lines yourself.
- **A hook with a bash syntax error fails CLOSED.** Bash exits 2 on a syntax error, and 2 is the code Claude Code reads as "block", so the fail-open logic never runs. That is why every test file starts with `bash -n`. Keep apostrophes, backticks and unbalanced parens out of the `$( ... <<'PY' ... )` heredocs, comments included.
- The handback check reads what the role reports. A role could write `GATE: ... -> PASS` without running anything; the lead still reviews the diff.
- `role-concept` has no worktree on purpose: it works on throwaway routes or a preview branch.
- The routing guard is a regex on the prompt. It can miss an oddly worded edit. Saying "read-only, do not edit" lets analysis through on purpose.
- The rules skills are distilled copies of your real docs. When a rule changes at its source, change the skill in the same commit.

## Support and updates

- **Updates:** Watch → Custom → Releases, or the free [AI Boss newsletter](https://launchwithben.com/newsletter).
- **Problems:** open an issue. **Using it:** open a "Report a result" issue. The kit has no telemetry, so that is how I learn it is being used.
- **Security:** read the scripts before you install them, and report vulnerabilities privately (see [SECURITY.md](SECURITY.md)).
- **If it is ever sunset,** the top of this README will say so, the repo will be archived, and a final release will say what to use instead.

## License

MIT
