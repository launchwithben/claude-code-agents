# claude-code-roles

Dedicated agents for Claude Code, all in one chat: a **developer**, a **UI builder** and a **concept designer** that know your project's rules before they start, and have to show their evidence before they're allowed to finish.

You keep talking to one Claude session (the lead). It sends the work to the right role, each role works in its own git worktree, and the lead reviews the diff and merges. No extra windows and no extra subscriptions.

```
you ──► lead session ──► role-dev      (scripts, data, config)       ──┐
                     ├─► role-ui       (components, styles)            ├─► lead reviews the diff ──► merge
                     └─► role-concept  ("show me 3 ways")              ──┘
```

Written up in full at **launchwithben.com/learn** (the post explains why each part exists and what it cost to run for real).

## What's in the box

| File | What it does |
|---|---|
| `.claude/agents/role-dev.md` | Non-UI developer. Sonnet, own worktree, preloads `build-rules`. |
| `.claude/agents/role-ui.md` | Designs and builds UI in one pass. Sonnet, own worktree, preloads `design-rules` + `build-rules`. |
| `.claude/agents/role-concept.md` | Answers direction questions with 2-3 rendered concepts. Never touches production components. |
| `.claude/skills/build-rules/` | Your project's build rules, injected into every role at start. **Template: fill it in.** |
| `.claude/skills/design-rules/` | Your design system's rules. **Template: fill it in.** |
| `.claude/skills/roles/` | `/roles` command: a menu, so nobody memorises role names. |
| `scripts/hooks/role-handback-check.sh` | Blocks a role from finishing until its report has the evidence (`GATE: ... -> PASS`, `SCREENSHOTS:`). Fails open; gives up after 2 blocks so it can never trap an agent. |
| `scripts/hooks/role-routing-guard.sh` | Stops the lead sending an edit to a generic worker instead of a role. Read-only work passes. Logs every denial to `tmp/role-routing/denials.jsonl`. |
| `scripts/hooks/role-picker.sh` | Typing a bare `@agent-role` shows the role menu instead of guessing. |
| `scripts/roles-pulse.mjs` | Reads Claude Code's own transcripts and tells you whether the roles are used, whether they hand back evidence, and what each run cost. |
| `scripts/hooks/*.test.sh` | Fixtures for every hook. |

## Install (5 minutes)

Requirements: Claude Code, `bash`, `python3` (hooks), `node` 18+ (pulse script only), a git repo.

```bash
# from your project root
git clone https://github.com/launchwithben/claude-code-roles /tmp/claude-code-roles
mkdir -p .claude/agents .claude/skills scripts/hooks
cp    /tmp/claude-code-roles/.claude/agents/*.md        .claude/agents/
cp -R /tmp/claude-code-roles/.claude/skills/*           .claude/skills/
cp    /tmp/claude-code-roles/scripts/hooks/role-*       scripts/hooks/
cp    /tmp/claude-code-roles/scripts/roles-pulse.mjs    scripts/
```

**Merge** the two hooks from `.claude/settings.json` into your own `.claude/settings.json` (do not overwrite it if you already have one).

Then:

1. **Fill in `.claude/skills/build-rules/SKILL.md`.** Your real check command, and the rules an agent would otherwise break. Keep it under ~900 words: it is pasted into every role on every run.
2. **Fill in `.claude/skills/design-rules/SKILL.md`** if you have a UI.
3. If your check is not `npm run check`, change the `GATE:` line in the three agent files.
4. **Restart Claude Code.** Agents load at session start; `/clear` is not enough.
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
- **Model.** Roles run on `sonnet`. In our runs the same UI task cost about $4 on Sonnet and $10-26 on the top model; keep the expensive model for single decisions, not whole builds.

## Known limits

- Roles load at process start. After adding or editing one, restart the session.
- Under `claude -p --agent <role>` (headless, the role IS the session) the Stop hook does not fire, so check the handback lines yourself.
- The routing guard is a regex on the prompt. It can miss an oddly worded edit. Saying "read-only, do not edit" lets analysis through on purpose.
- The rules skills are distilled copies of your real docs. When a rule changes at its source, change the skill in the same commit.

## License

MIT
